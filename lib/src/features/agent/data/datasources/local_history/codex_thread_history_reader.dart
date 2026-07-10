part of '../app_server/codex_app_server_agent_provider.dart';

/// 负责读取远端 thread/read 与本地 session jsonl 两类历史来源。
class _CodexThreadHistoryReader {
  Future<AgentThreadHistorySnapshot?> threadHistoryFromSessionFile(
    String threadId,
    String? sessionPath,
  ) async {
    final path = sessionPath?.trim();
    if (path == null || path.isEmpty) {
      return null;
    }

    final file = File(path);
    if (!await file.exists()) {
      _log.fine('Session file missing for thread $threadId: $path');
      return null;
    }

    final parser = _JsonlHistoryParser(
      fallbackThreadId: threadId,
      sessionPath: path,
    );

    try {
      await for (final line
          in file
              .openRead()
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        parser.consumeLine(line);
      }
    } on FileSystemException catch (error, stackTrace) {
      _log.warning(
        'Could not read Codex session file for thread $threadId: $path',
        error,
        stackTrace,
      );
      return null;
    }

    final snapshot = parser.build();
    if (snapshot.turns.isEmpty) {
      _log.fine('Session file had no displayable history for thread $threadId');
      return null;
    }
    return snapshot;
  }

  AgentThreadHistorySnapshot threadHistoryFromReadResult(
    Object? value,
    String fallbackThreadId,
  ) {
    final map = _map(value);
    final thread = _map(map['thread']);
    final threadId = _string(thread['id']) ?? fallbackThreadId;
    final turns = <AgentHistoryTurn>[];
    AgentHistoryTurn? currentTurn;
    final turnsList = thread['turns'];

    if (turnsList is List<Object?>) {
      for (final turnValue in turnsList) {
        final turn = _map(turnValue);
        final turnId = _string(turn['id']) ?? threadId;
        final turnEntries = <AgentHistoryEntry>[];
        final items = turn['items'];
        if (items is List<Object?>) {
          for (final itemValue in items) {
            final entry = _historyEntryFromItem(itemValue, turnId: turnId);
            if (entry != null) {
              turnEntries.add(entry);
            }
          }
        }
        final startedAt = _dateTimeFromAny(
          turn['startedAt'] ?? turn['startedAtMs'],
        );
        final completedAt = _dateTimeFromAny(
          turn['completedAt'] ?? turn['completedAtMs'],
        );
        final error = _map(turn['error']);
        final historyTurn = AgentHistoryTurn(
          id: turnId,
          entries: List<AgentHistoryEntry>.unmodifiable(turnEntries),
          status: _historyTurnStatus(_string(turn['status']), completedAt),
          startedAt: startedAt,
          completedAt: completedAt,
          duration: _durationFromMilliseconds(turn['durationMs']),
          cwd: _string(turn['cwd']),
          model: _string(turn['model']),
          modelContextWindow:
              _numberToInt(turn['modelContextWindow']) ??
              _numberToInt(turn['model_context_window']),
          collaborationMode:
              _string(turn['collaborationMode']) ??
              _string(turn['collaboration_mode']),
          tokenUsage: _tokenUsageFromTurnPayload(turn),
          errorMessage: _string(error['message']),
          errorCode: _codexErrorCode(error['codexErrorInfo']),
          raw: turn,
        );
        turns.add(historyTurn);
        currentTurn = historyTurn;
      }
    }

    return AgentThreadHistorySnapshot(
      threadId: threadId,
      turns: List<AgentHistoryTurn>.unmodifiable(turns),
      currentTurn: currentTurn,
      raw: map,
    );
  }

  String? _codexErrorCode(Object? value) {
    if (value is String) {
      return value;
    }
    final map = _map(value);
    return map.isEmpty ? null : map.keys.first;
  }

  AgentHistoryEntry? _historyEntryFromItem(
    Object? value, {
    required String turnId,
  }) {
    final item = _map(value);
    final type = _string(item['type']);
    final normalizedType = _normalizedAgentItemType(type);
    final id = _string(item['id']) ?? '$turnId-${type ?? 'item'}';

    return switch (normalizedType) {
      'usermessage' => _historyMessage(
        id: id,
        role: AgentMessageRole.user,
        text: _userInputText(item['content']),
        localImagePaths: _userInputLocalImagePaths(item['content']),
        raw: item,
      ),
      'agentmessage' => _historyMessage(
        id: id,
        role: AgentMessageRole.agent,
        text: _string(item['text']),
        phase: _messagePhase(_string(item['phase'])),
        status: _messageStatus(_string(item['status'])),
        duration: _messageDuration(item),
        raw: item,
      ),
      'plan' => _historyMessage(
        id: id,
        role: AgentMessageRole.agent,
        text: _string(item['text']),
        status: AgentMessageStatus.completed,
        raw: item,
      ),
      final type when _isSystemThreadItemType(type) =>
        _systemHistoryEventFromThreadItem(item, id: id),
      _ => _historyToolEntryFromThreadItem(item, id: id),
    };
  }

  AgentHistoryToolEntry? _historyToolEntryFromThreadItem(
    Map<String, Object?> item, {
    required String id,
  }) {
    final toolCall = _toolCallFromThreadItem(
      item,
      id: id,
      status: _historyToolStatus(_string(item['status'])),
    );
    return toolCall == null ? null : _historyTool(toolCall);
  }

  AgentHistoryMessageEntry? _historyMessage({
    required String id,
    required AgentMessageRole role,
    required String? text,
    AgentMessagePhase? phase,
    AgentMessageStatus? status,
    Duration? duration,
    List<String> localImagePaths = const <String>[],
    required Map<String, Object?> raw,
  }) {
    final trimmed = text?.trim() ?? '';
    // 允许纯图片用户消息：无文本但有本地图片路径时仍保留条目。
    if (trimmed.isEmpty && localImagePaths.isEmpty) {
      return null;
    }
    return AgentHistoryMessageEntry(
      id: id,
      role: role,
      text: trimmed,
      phase: phase,
      status: status,
      duration: duration,
      localImagePaths: List<String>.unmodifiable(localImagePaths),
      raw: raw,
    );
  }

  AgentHistoryToolEntry _historyTool(AgentToolCall toolCall) {
    return AgentHistoryToolEntry(toolCall: toolCall);
  }

  AgentTokenUsage? _tokenUsageFromTurnPayload(Map<String, Object?> turn) {
    final container = _map(turn['tokenUsage']).isNotEmpty
        ? _map(turn['tokenUsage'])
        : _map(turn['token_usage']);

    // 当前协议：tokenUsage 内嵌 total/last 两个 breakdown。
    final nestedTotal = _map(container['total']);
    if (nestedTotal.isNotEmpty) {
      final nestedLast = _map(container['last']);
      return AgentTokenUsage(
        inputTokens: _breakdownInt(nestedTotal, 'inputTokens', 'input_tokens'),
        cachedInputTokens: _breakdownInt(
          nestedTotal,
          'cachedInputTokens',
          'cached_input_tokens',
        ),
        outputTokens: AgentTokenUsage.mergeOutputTokens(
          _breakdownInt(nestedTotal, 'outputTokens', 'output_tokens'),
          _breakdownInt(
            nestedTotal,
            'reasoningOutputTokens',
            'reasoning_output_tokens',
          ),
        ),
        totalTokens: _breakdownInt(nestedTotal, 'totalTokens', 'total_tokens'),
        lastInputTokens: _breakdownInt(
          nestedLast,
          'inputTokens',
          'input_tokens',
        ),
        lastCachedInputTokens: _breakdownInt(
          nestedLast,
          'cachedInputTokens',
          'cached_input_tokens',
        ),
        lastOutputTokens: AgentTokenUsage.mergeOutputTokens(
          _breakdownInt(nestedLast, 'outputTokens', 'output_tokens'),
          _breakdownInt(
            nestedLast,
            'reasoningOutputTokens',
            'reasoning_output_tokens',
          ),
        ),
        lastTotalTokens: _breakdownInt(
          nestedLast,
          'totalTokens',
          'total_tokens',
        ),
        modelContextWindow: _breakdownInt(
          container,
          'modelContextWindow',
          'model_context_window',
        ),
      );
    }

    // 旧结构：tokenUsage 本身就是 total breakdown 的平铺字段。
    final total = container.isNotEmpty
        ? container
        : _map(turn['total_token_usage']);
    if (total.isEmpty) {
      return null;
    }
    final last = _map(turn['last_token_usage']);
    return AgentTokenUsage(
      inputTokens: _breakdownInt(total, 'inputTokens', 'input_tokens'),
      cachedInputTokens: _breakdownInt(
        total,
        'cachedInputTokens',
        'cached_input_tokens',
      ),
      outputTokens: AgentTokenUsage.mergeOutputTokens(
        _breakdownInt(total, 'outputTokens', 'output_tokens'),
        _breakdownInt(
          total,
          'reasoningOutputTokens',
          'reasoning_output_tokens',
        ),
      ),
      totalTokens: _breakdownInt(total, 'totalTokens', 'total_tokens'),
      lastInputTokens: _breakdownInt(last, 'inputTokens', 'input_tokens'),
      lastCachedInputTokens: _breakdownInt(
        last,
        'cachedInputTokens',
        'cached_input_tokens',
      ),
      lastOutputTokens: AgentTokenUsage.mergeOutputTokens(
        _breakdownInt(last, 'outputTokens', 'output_tokens'),
        _breakdownInt(last, 'reasoningOutputTokens', 'reasoning_output_tokens'),
      ),
      lastTotalTokens: _breakdownInt(last, 'totalTokens', 'total_tokens'),
      modelContextWindow: _breakdownInt(
        turn,
        'modelContextWindow',
        'model_context_window',
      ),
    );
  }
}

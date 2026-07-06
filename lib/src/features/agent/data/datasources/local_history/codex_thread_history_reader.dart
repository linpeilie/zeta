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
      'reasoning' => _historyTool(
        AgentToolCall(
          id: id,
          title: 'Reasoning',
          kind: AgentToolKind.think,
          status: AgentToolStatus.completed,
          content:
              _joinedStrings(item['summary']) ??
              _joinedStrings(item['content']),
          raw: item,
        ),
      ),
      'commandexecution' => _historyTool(
        AgentToolCall(
          id: id,
          title: _string(item['command']) ?? 'Command',
          kind: AgentToolKind.execute,
          status: _historyToolStatus(_string(item['status'])),
          content:
              _string(item['aggregatedOutput']) ?? _string(item['command']),
          locations: _singleLocation(_string(item['cwd'])),
          raw: item,
        ),
      ),
      'filechange' => _historyTool(
        AgentToolCall(
          id: id,
          title: 'File change',
          kind: AgentToolKind.edit,
          status: _historyToolStatus(_string(item['status'])),
          content: _joinedStrings(_fileChangeLocations(item['changes'])),
          locations: _fileChangeLocations(item['changes']),
          raw: item,
        ),
      ),
      'mcptoolcall' => _historyTool(
        AgentToolCall(
          id: id,
          title: _toolPathTitle(
            prefix: 'MCP',
            first: _string(item['server']),
            second: _string(item['tool']),
          ),
          kind: AgentToolKind.other,
          status: _historyToolStatus(_string(item['status'])),
          content:
              _string(_map(item['error'])['message']) ??
              _joinedContentItems(item['result']) ??
              _objectPreview(item['arguments']),
          rawInput: _map(item['arguments']),
          rawOutput: _map(item['result']),
          raw: item,
        ),
      ),
      'dynamictoolcall' => _historyTool(
        AgentToolCall(
          id: id,
          title: _toolPathTitle(
            first: _string(item['namespace']),
            second: _string(item['tool']),
          ),
          kind: AgentToolKind.other,
          status: _historyToolStatus(_string(item['status'])),
          content:
              _joinedContentItems(item['contentItems']) ??
              _objectPreview(item['arguments']),
          rawInput: _map(item['arguments']),
          raw: item,
        ),
      ),
      _ => null,
    };
  }

  AgentHistoryMessageEntry? _historyMessage({
    required String id,
    required AgentMessageRole role,
    required String? text,
    AgentMessagePhase? phase,
    AgentMessageStatus? status,
    Duration? duration,
    required Map<String, Object?> raw,
  }) {
    final trimmed = text?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return AgentHistoryMessageEntry(
      id: id,
      role: role,
      text: trimmed,
      phase: phase,
      status: status,
      duration: duration,
      raw: raw,
    );
  }

  AgentHistoryToolEntry _historyTool(AgentToolCall toolCall) {
    return AgentHistoryToolEntry(toolCall: toolCall);
  }

  AgentTokenUsage? _tokenUsageFromTurnPayload(Map<String, Object?> turn) {
    final direct = _map(turn['tokenUsage']);
    final nested = direct.isNotEmpty ? direct : _map(turn['token_usage']);
    final total = nested.isNotEmpty ? nested : _map(turn['total_token_usage']);
    if (total.isEmpty) {
      return null;
    }
    final last = _map(turn['last_token_usage']);
    return AgentTokenUsage(
      inputTokens:
          _numberToInt(total['input_tokens']) ??
          _numberToInt(total['inputTokens']),
      cachedInputTokens:
          _numberToInt(total['cached_input_tokens']) ??
          _numberToInt(total['cachedInputTokens']),
      outputTokens:
          _numberToInt(total['output_tokens']) ??
          _numberToInt(total['outputTokens']),
      reasoningOutputTokens:
          _numberToInt(total['reasoning_output_tokens']) ??
          _numberToInt(total['reasoningOutputTokens']),
      totalTokens:
          _numberToInt(total['total_tokens']) ??
          _numberToInt(total['totalTokens']),
      lastInputTokens: _numberToInt(last['input_tokens']),
      lastCachedInputTokens: _numberToInt(last['cached_input_tokens']),
      lastOutputTokens: _numberToInt(last['output_tokens']),
      lastReasoningOutputTokens: _numberToInt(last['reasoning_output_tokens']),
      lastTotalTokens: _numberToInt(last['total_tokens']),
    );
  }
}

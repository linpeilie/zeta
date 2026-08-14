part of '../app_server/codex_app_server_agent_provider.dart';

/// 负责读取远端 thread/read 与本地 session jsonl 两类历史来源。
class _CodexThreadHistoryReader {
  static const _conversationModeCodec = _CodexConversationModeCodec();

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
      _log.t('Session file missing for thread $threadId: $path');
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
      _log.w(
        'Could not read Codex session file for thread $threadId: $path',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }

    final snapshot = parser.build();
    if (snapshot.turns.isEmpty) {
      _log.t('Session file had no displayable history for thread $threadId');
      return null;
    }
    return snapshot;
  }

  AgentThreadHistorySnapshot threadHistoryFromReadResult(
    Object? value,
    String fallbackThreadId,
  ) {
    final fileChangeTracker = CodexFileChangeTracker();
    try {
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
          fileChangeTracker.beginTurn(runtimeScope: null, sessionId: threadId);
          final turnEntries = <AgentHistoryEntry>[];
          final items = turn['items'];
          if (items is List<Object?>) {
            for (final itemValue in items) {
              final entry = _historyEntryFromItem(
                itemValue,
                sessionId: threadId,
                turnId: turnId,
                fileChangeTracker: fileChangeTracker,
              );
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
            reasoningEffort: _codexReadReasoningEffort(turn),
            modelContextWindow:
                _numberToInt(turn['modelContextWindow']) ??
                _numberToInt(turn['model_context_window']),
            collaborationMode:
                _conversationModeCodec.modeIdFromValue(
                  turn['collaborationMode'],
                ) ??
                _conversationModeCodec.modeIdFromValue(
                  turn['collaboration_mode'],
                ),
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
    } finally {
      fileChangeTracker.dispose();
    }
  }

  String? _codexErrorCode(Object? value) {
    if (value is String) {
      return value;
    }
    final map = _map(value);
    return map.isEmpty ? null : map.keys.first;
  }

  /// 将 thread/read 中的补充元数据与终态错误叠到本地 JSONL 历史上。
  ///
  /// Codex session JSONL 通常不持久化 `error` 通知；live 时 `serverOverloaded`
  /// 等失败只会经 JSON-RPC 到达客户端。优先使用内容更完整的本地条目，仅在
  /// 本地 turn 缺少 reasoning effort 或 error/failed 状态时用远端补齐。
  AgentThreadHistorySnapshot mergeRemoteTurnFailures({
    required AgentThreadHistorySnapshot local,
    required AgentThreadHistorySnapshot remote,
  }) {
    if (remote.turns.isEmpty) {
      return local;
    }
    final remoteById = <String, AgentHistoryTurn>{
      for (final turn in remote.turns) turn.id: turn,
    };
    var changed = false;
    final mergedTurns = <AgentHistoryTurn>[];
    for (final localTurn in local.turns) {
      final remoteTurn = remoteById[localTurn.id];
      if (remoteTurn == null) {
        mergedTurns.add(localTurn);
        continue;
      }
      final merged = _overlayRemoteTurn(localTurn, remoteTurn);
      if (!identical(merged, localTurn)) {
        changed = true;
      }
      mergedTurns.add(merged);
    }
    if (!changed) {
      return local;
    }
    AgentHistoryTurn? currentTurn;
    final currentId = local.currentTurn?.id;
    if (currentId != null) {
      for (final turn in mergedTurns) {
        if (turn.id == currentId) {
          currentTurn = turn;
          break;
        }
      }
    }
    currentTurn ??= mergedTurns.isEmpty ? null : mergedTurns.last;
    return AgentThreadHistorySnapshot(
      threadId: local.threadId,
      turns: List<AgentHistoryTurn>.unmodifiable(mergedTurns),
      currentTurn: currentTurn,
      raw: <String, Object?>{...local.raw, 'remoteFailureOverlay': true},
    );
  }

  AgentHistoryTurn _overlayRemoteTurn(
    AgentHistoryTurn local,
    AgentHistoryTurn remote,
  ) {
    final remoteError = remote.errorMessage?.trim();
    final hasRemoteFailure =
        remote.status == AgentHistoryTurnStatus.failed &&
        remoteError != null &&
        remoteError.isNotEmpty;
    final needsReasoningEffort =
        !local.reasoningEffort.isKnown && remote.reasoningEffort.isKnown;

    final localError = local.errorMessage?.trim();
    final needsStatus =
        hasRemoteFailure &&
        local.status != AgentHistoryTurnStatus.failed &&
        local.status != AgentHistoryTurnStatus.interrupted;
    final needsMessage =
        hasRemoteFailure && (localError == null || localError.isEmpty);
    final needsCode =
        hasRemoteFailure &&
        (local.errorCode == null || local.errorCode!.trim().isEmpty) &&
        remote.errorCode != null &&
        remote.errorCode!.trim().isNotEmpty;
    if (!needsReasoningEffort && !needsStatus && !needsMessage && !needsCode) {
      return local;
    }

    return AgentHistoryTurn(
      id: local.id,
      entries: local.entries,
      status: needsStatus ? AgentHistoryTurnStatus.failed : local.status,
      startedAt: local.startedAt ?? remote.startedAt,
      completedAt: local.completedAt ?? remote.completedAt,
      duration: local.duration ?? remote.duration,
      timeToFirstToken: local.timeToFirstToken ?? remote.timeToFirstToken,
      cwd: local.cwd ?? remote.cwd,
      model: local.model ?? remote.model,
      reasoningEffort: needsReasoningEffort
          ? remote.reasoningEffort
          : local.reasoningEffort,
      modelContextWindow: local.modelContextWindow ?? remote.modelContextWindow,
      collaborationMode: local.collaborationMode ?? remote.collaborationMode,
      tokenUsage: local.tokenUsage ?? remote.tokenUsage,
      tokenUsageIsSessionCumulative: local.tokenUsageIsSessionCumulative,
      errorMessage: needsMessage ? remote.errorMessage : local.errorMessage,
      errorCode: needsCode ? remote.errorCode : local.errorCode,
      raw: <String, Object?>{
        ...local.raw,
        if (needsReasoningEffort) 'remoteReasoningEffortOverlay': true,
        if (hasRemoteFailure)
          'remoteFailureOverlay': <String, Object?>{
            'status': remote.status.name,
            'errorMessage': remote.errorMessage,
            'errorCode': remote.errorCode,
          },
      },
    );
  }

  AgentHistoryReasoningEffort _codexReadReasoningEffort(
    Map<String, Object?> turn,
  ) {
    for (final key in const <String>[
      'effort',
      'reasoningEffort',
      'reasoning_effort',
    ]) {
      if (!turn.containsKey(key)) {
        continue;
      }
      final raw = turn[key];
      if (raw == null) {
        return const AgentHistoryReasoningEffort.providerDefault();
      }
      final effort = _string(raw);
      return effort == null
          ? const AgentHistoryReasoningEffort.unknown()
          : AgentHistoryReasoningEffort.explicit(effort);
    }
    return const AgentHistoryReasoningEffort.unknown();
  }

  AgentHistoryEntry? _historyEntryFromItem(
    Object? value, {
    required String sessionId,
    required String turnId,
    required CodexFileChangeTracker fileChangeTracker,
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
        kind: AgentMessageKind.plan,
        status: AgentMessageStatus.completed,
        raw: item,
      ),
      final type when _isSystemThreadItemType(type) =>
        _systemHistoryEventFromThreadItem(item, id: id),
      _ => _historyToolEntryFromThreadItem(
        item,
        id: id,
        sessionId: sessionId,
        turnId: turnId,
        fileChangeTracker: fileChangeTracker,
      ),
    };
  }

  AgentHistoryToolEntry? _historyToolEntryFromThreadItem(
    Map<String, Object?> item, {
    required String id,
    required String sessionId,
    required String turnId,
    required CodexFileChangeTracker fileChangeTracker,
  }) {
    final fileProjection =
        _normalizedAgentItemType(_string(item['type'])) == 'filechange'
        ? fileChangeTracker.projectTool(
            runtimeScope: null,
            sessionId: sessionId,
            turnId: turnId,
            toolCallId: id,
            hasStructuredChanges: item.containsKey('changes'),
            changes: item['changes'],
          )
        : null;
    final toolCall = _toolCallFromThreadItem(
      item,
      id: id,
      status: _historyToolStatus(_string(item['status'])),
      sessionId: sessionId,
      turnId: turnId,
      fileChanges: fileProjection?.snapshot,
      projectedLocations: fileProjection?.snapshot == null
          ? null
          : fileProjection!.locations,
    );
    return toolCall == null ? null : _historyTool(toolCall);
  }

  AgentHistoryMessageEntry? _historyMessage({
    required String id,
    required AgentMessageRole role,
    required String? text,
    AgentMessageKind kind = AgentMessageKind.regular,
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
      kind: kind,
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
        outputTokens: AgentTokenUsage.visibleOutputTokens(
          _breakdownInt(nestedTotal, 'outputTokens', 'output_tokens'),
          _breakdownInt(
            nestedTotal,
            'reasoningOutputTokens',
            'reasoning_output_tokens',
          ),
        ),
        reasoningOutputTokens: _breakdownInt(
          nestedTotal,
          'reasoningOutputTokens',
          'reasoning_output_tokens',
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
        lastOutputTokens: AgentTokenUsage.visibleOutputTokens(
          _breakdownInt(nestedLast, 'outputTokens', 'output_tokens'),
          _breakdownInt(
            nestedLast,
            'reasoningOutputTokens',
            'reasoning_output_tokens',
          ),
        ),
        lastReasoningOutputTokens: _breakdownInt(
          nestedLast,
          'reasoningOutputTokens',
          'reasoning_output_tokens',
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
      outputTokens: AgentTokenUsage.visibleOutputTokens(
        _breakdownInt(total, 'outputTokens', 'output_tokens'),
        _breakdownInt(
          total,
          'reasoningOutputTokens',
          'reasoning_output_tokens',
        ),
      ),
      reasoningOutputTokens: _breakdownInt(
        total,
        'reasoningOutputTokens',
        'reasoning_output_tokens',
      ),
      totalTokens: _breakdownInt(total, 'totalTokens', 'total_tokens'),
      lastInputTokens: _breakdownInt(last, 'inputTokens', 'input_tokens'),
      lastCachedInputTokens: _breakdownInt(
        last,
        'cachedInputTokens',
        'cached_input_tokens',
      ),
      lastOutputTokens: AgentTokenUsage.visibleOutputTokens(
        _breakdownInt(last, 'outputTokens', 'output_tokens'),
        _breakdownInt(last, 'reasoningOutputTokens', 'reasoning_output_tokens'),
      ),
      lastReasoningOutputTokens: _breakdownInt(
        last,
        'reasoningOutputTokens',
        'reasoning_output_tokens',
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

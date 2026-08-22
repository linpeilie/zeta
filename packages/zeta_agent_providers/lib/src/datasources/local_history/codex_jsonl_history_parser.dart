part of '../app_server/codex_app_server_agent_provider.dart';

/// 按 jsonl 日志顺序重建 thread 历史。
class _JsonlHistoryParser {
  _JsonlHistoryParser({
    required this.fallbackThreadId,
    required this.sessionPath,
    required this.textCatalog,
  });

  final String fallbackThreadId;
  final String sessionPath;
  final AgentUiTextCatalog textCatalog;
  static const _conversationModeCodec = _CodexConversationModeCodec();

  late final String _unscopedTurnId = '${fallbackThreadId}__unscoped__';
  late String _threadId = fallbackThreadId;

  final List<AgentHistoryEntry> _entries = <AgentHistoryEntry>[];
  final List<String?> _entryTurnIds = <String?>[];
  final Map<String, _JsonlTurnBuilder> _turnBuildersById =
      <String, _JsonlTurnBuilder>{};
  final Map<String, _JsonlPendingTool> _pendingToolsByCallId =
      <String, _JsonlPendingTool>{};
  final Map<String, _JsonlPendingHistoryEvent> _pendingEventsByCallId =
      <String, _JsonlPendingHistoryEvent>{};
  final CodexFileChangeTracker _fileChangeTracker = CodexFileChangeTracker();

  String? _currentTurnId;

  /// 当前 JSONL 记录的时间戳（记录级 metadata，不是原文内容）。
  DateTime? _currentRecordTimestamp;
  int _lineNumber = 0;

  void consumeLine(String line) {
    _lineNumber += 1;
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      return;
    }

    Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (_) {
      return;
    }

    final record = _map(decoded);
    if (record.isEmpty) {
      return;
    }

    final recordType = _string(record['type']);
    _currentRecordTimestamp = _dateTimeFromAny(record['timestamp']);
    final payload = _map(record['payload']);
    if (recordType == 'session_meta') {
      _consumeSessionMeta(payload);
      return;
    }
    if (payload.isEmpty) {
      return;
    }

    final turnId = _turnIdFromRecord(record, payload);
    if (turnId != null) {
      _currentTurnId = turnId;
      _ensureTurn(turnId);
    }

    switch (recordType) {
      case 'event_msg':
        _consumeEventMessage(payload, raw: wrapAgentProviderPayload(record));
        return;
      case 'turn_context':
        _consumeTurnContext(payload, raw: wrapAgentProviderPayload(record));
        return;
      case 'response_item':
        _consumeResponseItem(payload, raw: wrapAgentProviderPayload(record));
        return;
      case _:
        return;
    }
  }

  AgentThreadHistorySnapshot build() {
    final groupedEntriesByTurnId = <String, List<AgentHistoryEntry>>{};
    for (var index = 0; index < _entries.length; index += 1) {
      final turnId = _entryTurnIds[index];
      if (turnId == null) {
        continue;
      }
      groupedEntriesByTurnId
          .putIfAbsent(turnId, () => <AgentHistoryEntry>[])
          .add(_entries[index]);
    }

    final turns = <AgentHistoryTurn>[];
    for (final builder in _turnBuildersById.values) {
      turns.add(
        builder.build(
          groupedEntriesByTurnId[builder.id] ?? const <AgentHistoryEntry>[],
        ),
      );
    }

    AgentHistoryTurn? currentTurn;
    final currentTurnId = _currentTurnId;
    if (currentTurnId != null) {
      for (final turn in turns) {
        if (turn.id == currentTurnId) {
          currentTurn = turn;
          break;
        }
      }
    }

    return AgentThreadHistorySnapshot(
      threadId: _threadId,
      turns: List<AgentHistoryTurn>.unmodifiable(turns),
      currentTurn: currentTurn,
      sourceLabel: 'sessionFile',
      sessionPath: sessionPath,
    );
  }

  void _consumeSessionMeta(Map<String, Object?> payload) {
    final sessionId = _string(payload['session_id']) ?? _string(payload['id']);
    if (sessionId != null) {
      _threadId = sessionId;
    }
  }

  void _consumeEventMessage(
    Map<String, Object?> payload, {
    required AgentProviderRawPayload raw,
  }) {
    final type = _string(payload['type']);
    switch (type) {
      case 'task_started':
        _consumeTaskStarted(payload, raw: raw);
        return;
      case 'task_complete':
        _consumeTaskComplete(payload, raw: raw);
        return;
      case 'turn_aborted':
        _consumeTurnAborted(payload, raw: raw);
        return;
      case 'user_message':
        // 会话 JSONL 在 event_msg.user_message.local_images 携带本地绝对路径；
        // 必须写入 localImagePaths，UI 才能渲染历史缩略图（与 live 一致）。
        final localImagePaths = _jsonlUserMessageLocalImagePaths(payload);
        final text = _trimmedText(_jsonlUserMessageText(payload)) ?? '';
        // 允许纯图消息：无正文但有本地路径时仍保留条目。
        if (text.isEmpty && localImagePaths.isEmpty) {
          return;
        }
        _appendEntry(
          AgentHistoryMessageEntry(
            id: _string(payload['client_id']) ?? _nextHistoryId('history-user'),
            role: AgentMessageRole.user,
            text: text,
            localImagePaths: localImagePaths,
            raw: raw,
          ),
        );
        return;
      case 'agent_message':
        final text = _trimmedText(_string(payload['message']));
        if (text == null) {
          return;
        }
        _appendEntry(
          AgentHistoryMessageEntry(
            id: _string(payload['id']) ?? _nextHistoryId('history-agent'),
            role: AgentMessageRole.agent,
            text: text,
            phase: _messagePhase(_string(payload['phase'])),
            status: AgentMessageStatus.completed,
            raw: raw,
          ),
        );
        return;
      case 'patch_apply_end':
        _consumePatchApplyEnd(payload, raw: raw);
        return;
      case 'mcp_tool_call_end':
        _consumeMcpToolCallEnd(payload, raw: raw);
        return;
      case 'web_search_end':
        return;
      case 'token_count':
        _consumeTokenCount(payload, raw: raw);
        return;
      case 'item_completed':
        _consumeCompletedItem(payload, raw: raw);
        return;
      default:
        final historyEvent = _historyEventFromSpecialPayload(
          type: type,
          payload: payload,
          raw: raw,
          id: _nextHistoryId('history-event'),
        );
        if (historyEvent != null) {
          _appendEntry(historyEvent);
        }
        return;
    }
  }

  /// 消费 `event_msg.item_completed`（ThreadItem 流）里的**消息**。
  ///
  /// Codex 0.148 起的部分 rollout 不再写 `event_msg.user_message` /
  /// `agent_message`，整条会话改由 ThreadItem 流承载，`item.type` 是大驼峰
  /// （`UserMessage` / `AgentMessage` / `CommandExecution`…）。这条分支之前只
  /// 放行 `plan`，于是这类会话的每一条用户提问和 Agent 回复都被丢掉，历史里
  /// 只剩下从 `response_item` 单独重建出来的工具卡——看上去就是「没有历史」。
  ///
  /// 这里刻意**只接消息**，另外两类各有不接的理由：
  ///
  /// - **工具卡不接**。同一批调用在 `response_item.custom_tool_call` 里还会再
  ///   出现一次，两条流的 id 互不相同（`exec-…` vs `call_…`），都收就会渲染出
  ///   双份工具卡。工具的唯一来源仍然是 response_item。
  /// - **Reasoning 不接**。旧格式的 `agent_reasoning` 事件在历史里同样是丢弃的
  ///   （落到 [_historyEventFromSpecialPayload] 后返回 null）。这里单独接上会让
  ///   同一段会话按新旧格式渲染出不同的内容，先保持两边一致。
  void _consumeCompletedItem(
    Map<String, Object?> payload, {
    required AgentProviderRawPayload raw,
  }) {
    final item = _map(payload['item']);
    switch (_normalizedAgentItemType(_string(item['type']))) {
      case 'usermessage':
        final localImagePaths = _userInputLocalImagePaths(item['content']);
        final text = _trimmedText(_userInputText(item['content'])) ?? '';
        // 允许纯图消息：无正文但有本地路径时仍保留条目。
        if (text.isEmpty && localImagePaths.isEmpty) {
          return;
        }
        _appendEntry(
          AgentHistoryMessageEntry(
            id:
                _string(item['id']) ??
                _string(item['client_id']) ??
                _nextHistoryId('history-user'),
            role: AgentMessageRole.user,
            text: text,
            localImagePaths: localImagePaths,
            raw: raw,
          ),
        );
      case 'agentmessage':
        final text = _trimmedText(_agentMessageTextFromItem(item));
        if (text == null) {
          return;
        }
        _appendEntry(
          AgentHistoryMessageEntry(
            id: _string(item['id']) ?? _nextHistoryId('history-agent'),
            role: AgentMessageRole.agent,
            text: text,
            phase: _messagePhase(_string(item['phase'])),
            status: AgentMessageStatus.completed,
            raw: raw,
          ),
        );
      case 'plan':
        final text = _trimmedText(_agentMessageTextFromItem(item));
        if (text == null) {
          return;
        }
        _appendEntry(
          AgentHistoryMessageEntry(
            id: _string(item['id']) ?? _nextHistoryId('history-plan'),
            role: AgentMessageRole.agent,
            text: text,
            kind: AgentMessageKind.plan,
            status: AgentMessageStatus.completed,
            raw: raw,
          ),
        );
      case _:
        return;
    }
  }

  void _consumeTaskStarted(
    Map<String, Object?> payload, {
    required AgentProviderRawPayload raw,
  }) {
    final turn = _currentTurn();
    if (turn == null) {
      return;
    }
    turn
      ..status = AgentHistoryTurnStatus.running
      ..startedAt =
          _dateTimeFromAny(payload['started_at']) ??
          _currentRecordTimestamp ??
          turn.startedAt
      ..modelContextWindow =
          _numberToInt(payload['model_context_window']) ??
          turn.modelContextWindow
      ..collaborationMode =
          _conversationModeCodec.modeIdFromValue(
            payload['collaboration_mode_kind'],
          ) ??
          turn.collaborationMode;
    turn.raw['taskStarted'] = payload;
  }

  void _consumeTaskComplete(
    Map<String, Object?> payload, {
    required AgentProviderRawPayload raw,
  }) {
    final turn = _currentTurn();
    if (turn == null) {
      return;
    }
    turn
      ..status = AgentHistoryTurnStatus.completed
      ..completedAt =
          _dateTimeFromAny(payload['completed_at']) ??
          _currentRecordTimestamp ??
          turn.completedAt
      ..duration =
          _durationFromMilliseconds(payload['duration_ms']) ?? turn.duration
      ..timeToFirstToken =
          _durationFromMilliseconds(payload['time_to_first_token_ms']) ??
          turn.timeToFirstToken;
    turn.raw['taskComplete'] = payload;
  }

  void _consumeTurnAborted(
    Map<String, Object?> payload, {
    required AgentProviderRawPayload raw,
  }) {
    final turn = _currentTurn();
    if (turn == null) {
      return;
    }
    turn
      ..status = AgentHistoryTurnStatus.interrupted
      ..completedAt =
          _dateTimeFromAny(payload['completed_at']) ??
          _currentRecordTimestamp ??
          turn.completedAt
      ..duration =
          _durationFromMilliseconds(payload['duration_ms']) ?? turn.duration
      ..errorMessage = _string(payload['reason']) ?? textCatalog.userCancelled;
    turn.raw['turnAborted'] = payload;
  }

  void _consumeTurnContext(
    Map<String, Object?> payload, {
    required AgentProviderRawPayload raw,
  }) {
    final turn = _currentTurn();
    if (turn == null) {
      return;
    }
    turn
      ..cwd = _string(payload['cwd']) ?? turn.cwd
      ..modelId = _codexHistoryModelId(payload) ?? turn.modelId
      ..modelContextWindow =
          _numberToInt(payload['model_context_window']) ??
          turn.modelContextWindow
      ..collaborationMode =
          _conversationModeCodec.modeIdFromValue(
            payload['collaboration_mode'],
          ) ??
          turn.collaborationMode;
    if (payload.containsKey('effort')) {
      turn.reasoningEffort = _codexJsonlReasoningEffort(payload['effort']);
    }
    if (_codexHistoryContainsAnyKey(payload, _codexServiceTierKeys)) {
      turn.serviceTierId = _codexHistoryServiceTierId(payload);
    }
    final explicitFast = _codexHistoryExplicitFast(payload);
    if (explicitFast != null) {
      turn.explicitFast = explicitFast;
    }
    turn.raw['turnContext'] = payload;
  }

  void _consumeTokenCount(
    Map<String, Object?> payload, {
    required AgentProviderRawPayload raw,
  }) {
    final turn = _currentTurn();
    if (turn == null) {
      return;
    }
    final info = _map(payload['info']);
    final totalUsage = _map(info['total_token_usage']);
    final lastUsage = _map(info['last_token_usage']);
    final modelContextWindow = _numberToInt(info['model_context_window']);
    turn.tokenUsage = AgentTokenUsage(
      inputTokens: _numberToInt(totalUsage['input_tokens']),
      cachedInputTokens: _numberToInt(totalUsage['cached_input_tokens']),
      outputTokens: AgentTokenUsage.visibleOutputTokens(
        _numberToInt(totalUsage['output_tokens']),
        _numberToInt(totalUsage['reasoning_output_tokens']),
      ),
      reasoningOutputTokens: _numberToInt(
        totalUsage['reasoning_output_tokens'],
      ),
      totalTokens: _numberToInt(totalUsage['total_tokens']),
      lastInputTokens: _numberToInt(lastUsage['input_tokens']),
      lastCachedInputTokens: _numberToInt(lastUsage['cached_input_tokens']),
      lastOutputTokens: AgentTokenUsage.visibleOutputTokens(
        _numberToInt(lastUsage['output_tokens']),
        _numberToInt(lastUsage['reasoning_output_tokens']),
      ),
      lastReasoningOutputTokens: _numberToInt(
        lastUsage['reasoning_output_tokens'],
      ),
      lastTotalTokens: _numberToInt(lastUsage['total_tokens']),
      modelContextWindow: modelContextWindow,
    );
    if (modelContextWindow != null) {
      turn.modelContextWindow = modelContextWindow;
    }
    turn.raw['tokenCount'] = payload;
  }

  void _consumeResponseItem(
    Map<String, Object?> payload, {
    required AgentProviderRawPayload raw,
  }) {
    final type = _string(payload['type']);
    switch (type) {
      case 'function_call':
        _consumeFunctionCall(payload, raw: raw);
        return;
      case 'function_call_output':
        _consumeFunctionCallOutput(payload, raw: raw);
        return;
      case 'custom_tool_call':
        _consumeCustomToolCall(payload, raw: raw);
        return;
      case 'custom_tool_call_output':
        _consumeCustomToolCallOutput(payload);
        return;
      case 'tool_search_call':
        _consumeToolSearchCall(payload, raw: raw);
        return;
      case 'tool_search_output':
        _consumeToolSearchOutput(payload);
        return;
      case 'web_search_call':
        _consumeWebSearchCall(payload, raw: raw);
        return;
      case 'message':
      case 'reasoning':
      case 'token_count':
        return;
      default:
        final historyEvent = _historyEventFromSpecialPayload(
          type: type,
          payload: payload,
          raw: raw,
          id: _nextHistoryId('history-event'),
        );
        if (historyEvent != null) {
          _appendEntry(historyEvent);
        }
        return;
    }
  }

  void _consumeFunctionCall(
    Map<String, Object?> payload, {
    required AgentProviderRawPayload raw,
  }) {
    final name = _string(payload['name']);
    final callId = _responseCallId(payload) ?? _nextHistoryId('tool-call');
    final arguments = _decodedObjectMap(payload['arguments']);

    if (_isPermissionHistoryToolName(name)) {
      final event = _permissionEventFromToolInvocation(
        id: 'permission-$callId',
        name: name,
        arguments: arguments,
        stringInput: _string(payload['arguments']),
        raw: raw,
      );
      final index = _appendEntry(event);
      _pendingEventsByCallId[callId] = _JsonlPendingHistoryEvent(index: index);
      return;
    }

    final toolCall = AgentToolCall(
      id: callId,
      title: _jsonlToolTitle(
        name: name,
        catalog: textCatalog,
        arguments: arguments,
        stringInput: _string(payload['arguments']),
      ),
      kind: _jsonlToolKind(name),
      status: AgentToolStatus.completed,
      content: _jsonlToolInvocationContent(
        name: name,
        arguments: arguments,
        stringInput: _string(payload['arguments']),
      ),
      locations: _jsonlToolLocations(
        name: name,
        arguments: arguments,
        stringInput: _string(payload['arguments']),
      ),
      rawInput: wrapAgentProviderPayload(
        _jsonlRawInputMap(
          arguments: arguments,
          stringInput: _string(payload['arguments']),
        ),
      ),
      raw: raw,
    );
    final index = _appendEntry(AgentHistoryToolEntry(toolCall: toolCall));
    _pendingToolsByCallId[callId] = _JsonlPendingTool(index: index);
  }

  void _consumeFunctionCallOutput(
    Map<String, Object?> payload, {
    required AgentProviderRawPayload raw,
  }) {
    final callId = _responseCallId(payload);
    if (callId == null) {
      return;
    }

    final pending = _pendingEventsByCallId[callId];
    if (pending == null) {
      return;
    }

    final entry = _entries[pending.index];
    if (entry is! AgentHistoryEventEntry) {
      return;
    }

    final currentQaPairs = entry.qaPairs;
    if (currentQaPairs == null || currentQaPairs.isEmpty) {
      return;
    }

    final answersByQuestionId = _userInputAnswersByQuestionId(
      payload['output'],
    );
    if (answersByQuestionId.isEmpty) {
      return;
    }

    final updatedQaPairs = _mergeUserInputQaPairsWithAnswers(
      currentQaPairs,
      answersByQuestionId,
    );
    if (_sameUserInputQaPairs(updatedQaPairs, currentQaPairs)) {
      return;
    }

    _entries[pending.index] = AgentHistoryEventEntry(
      id: entry.id,
      kind: entry.kind,
      title: entry.title,
      description: entry.description,
      content: entry.content,
      qaPairs: updatedQaPairs,
      raw: entry.raw.mergedWith(raw),
    );
  }

  void _consumeCustomToolCall(
    Map<String, Object?> payload, {
    required AgentProviderRawPayload raw,
  }) {
    final name = _string(payload['name']);
    final callId = _responseCallId(payload) ?? _nextHistoryId('tool-call');
    final stringInput = _string(payload['input']);
    final arguments = _decodedObjectMap(payload['input']);
    final toolCall = AgentToolCall(
      id: callId,
      title: _jsonlToolTitle(
        name: name,
        catalog: textCatalog,
        arguments: arguments,
        stringInput: stringInput,
      ),
      kind: _jsonlToolKind(name),
      status: _historyToolStatus(_string(payload['status'])),
      content: _jsonlToolInvocationContent(
        name: name,
        arguments: arguments,
        stringInput: stringInput,
      ),
      locations: _jsonlToolLocations(
        name: name,
        arguments: arguments,
        stringInput: stringInput,
      ),
      rawInput: wrapAgentProviderPayload(
        _jsonlRawInputMap(arguments: arguments, stringInput: stringInput),
      ),
      raw: raw,
    );
    final index = _appendEntry(AgentHistoryToolEntry(toolCall: toolCall));
    _pendingToolsByCallId[callId] = _JsonlPendingTool(index: index);
  }

  void _consumeCustomToolCallOutput(Map<String, Object?> _) {}

  void _consumePatchApplyEnd(
    Map<String, Object?> payload, {
    required AgentProviderRawPayload raw,
  }) {
    final callId = _string(payload['call_id']);
    final toolCallId = callId ?? _nextHistoryId('patch');
    final fileProjection = _fileChangeTracker.projectJsonlPatchApply(
      runtimeScope: null,
      sessionId: _threadId,
      turnId: _currentTurnId ?? _unscopedTurnId,
      toolCallId: toolCallId,
      hasStructuredChanges: payload.containsKey('changes'),
      changes: payload['changes'],
    );
    final locations = fileProjection.snapshot == null
        ? _patchApplyLocations(payload['changes'])
        : fileProjection.locations;
    final content =
        _patchApplySummary(
          locations,
          stdout: _string(payload['stdout']),
          stderr: _string(payload['stderr']),
        ) ??
        _jsonlToolOutputPreview(_string(payload['stdout'])) ??
        _jsonlToolOutputPreview(_string(payload['stderr']));

    if (callId != null && _pendingToolsByCallId.containsKey(callId)) {
      _updatePendingTool(
        callId,
        title: textCatalog.applyPatchTitle,
        kind: AgentToolKind.edit,
        status: payload['success'] == false
            ? AgentToolStatus.failed
            : AgentToolStatus.completed,
        content: content,
        locations: locations,
        rawOutput: wrapAgentProviderPayload(payload),
        raw: raw,
        fileChanges: fileProjection.snapshot,
      );
      return;
    }

    final toolCall = AgentToolCall(
      id: toolCallId,
      title: textCatalog.applyPatchTitle,
      kind: AgentToolKind.edit,
      status: payload['success'] == false
          ? AgentToolStatus.failed
          : AgentToolStatus.completed,
      content: content,
      locations: locations,
      rawOutput: wrapAgentProviderPayload(payload),
      raw: raw,
      fileChanges: fileProjection.snapshot,
    );
    _appendEntry(AgentHistoryToolEntry(toolCall: toolCall));
  }

  void _consumeMcpToolCallEnd(
    Map<String, Object?> payload, {
    required AgentProviderRawPayload raw,
  }) {
    final invocation = _map(payload['invocation']);
    final arguments = _map(invocation['arguments']);
    final result = _mcpResultMap(payload['result']);
    final toolName = _string(invocation['tool']);
    final toolCall = AgentToolCall(
      id: _string(payload['call_id']) ?? _nextHistoryId('mcp'),
      title: _toolPathTitle(
        prefix: 'MCP',
        first: _string(invocation['server']),
        second: toolName,
      ),
      kind: _jsonlToolKind(toolName),
      status: _mcpResultIsError(result)
          ? AgentToolStatus.failed
          : AgentToolStatus.completed,
      content:
          _mcpResultPreview(result) ??
          _jsonlToolInvocationContent(name: toolName, arguments: arguments),
      locations: _jsonlToolLocations(name: toolName, arguments: arguments),
      rawInput: wrapAgentProviderPayload(arguments),
      rawOutput: wrapAgentProviderPayload(result),
      raw: raw,
    );
    _appendEntry(AgentHistoryToolEntry(toolCall: toolCall));
  }

  void _consumeToolSearchCall(
    Map<String, Object?> payload, {
    required AgentProviderRawPayload raw,
  }) {
    final arguments = _map(payload['arguments']);
    final callId = _responseCallId(payload) ?? _nextHistoryId('search');
    final query = _trimmedText(_string(arguments['query']));
    final entry = AgentHistoryEventEntry(
      id: 'search-$callId',
      kind: AgentHistoryEventKind.search,
      title: textCatalog.toolSearchTitle,
      description: query,
      content: _toolSearchQueryPreview(arguments),
      raw: raw,
    );
    final index = _appendEntry(entry);
    _pendingEventsByCallId[callId] = _JsonlPendingHistoryEvent(index: index);
  }

  void _consumeToolSearchOutput(Map<String, Object?> _) {}

  void _consumeWebSearchCall(
    Map<String, Object?> payload, {
    required AgentProviderRawPayload raw,
  }) {
    final callId = _responseCallId(payload) ?? _nextHistoryId('search');
    final action = _map(payload['action']);
    final entry = AgentHistoryEventEntry(
      id: 'search-$callId',
      kind: AgentHistoryEventKind.search,
      title: textCatalog.historyWebSearchTitle,
      description:
          _trimmedText(_string(action['query'])) ??
          _trimmedText(_string(payload['query'])),
      content: _webSearchQueryPreview(action),
      raw: raw,
    );
    final index = _appendEntry(entry);
    _pendingEventsByCallId[callId] = _JsonlPendingHistoryEvent(index: index);
  }

  AgentHistoryEventEntry _permissionEventFromToolInvocation({
    required String id,
    required String? name,
    required Map<String, Object?> arguments,
    required String? stringInput,
    required AgentProviderRawPayload raw,
  }) {
    return AgentHistoryEventEntry(
      id: id,
      kind: AgentHistoryEventKind.permission,
      title: switch (name) {
        'request_user_input' => 'Requested user input',
        'request_permissions' => 'Requested permissions',
        _ => 'Permission request',
      },
      description: _permissionEventDescription(
        name: name,
        arguments: arguments,
        stringInput: stringInput,
      ),
      content: _permissionEventContent(
        name: name,
        arguments: arguments,
        stringInput: stringInput,
      ),
      qaPairs: name == 'request_user_input'
          ? _userInputQaPairs(arguments)
          : null,
      raw: raw,
    );
  }

  AgentHistoryEventEntry? _historyEventFromSpecialPayload({
    required String? type,
    required Map<String, Object?> payload,
    required AgentProviderRawPayload raw,
    required String id,
  }) {
    final normalizedType = type?.toLowerCase();
    if (normalizedType == null || normalizedType.isEmpty) {
      return null;
    }

    final message =
        _trimmedText(_string(payload['message'])) ??
        _trimmedText(_string(payload['title'])) ??
        _trimmedText(_string(payload['description']));
    final content = _specialEventContent(payload);

    if (normalizedType.contains('warning') ||
        normalizedType.contains('guardian')) {
      return AgentHistoryEventEntry(
        id: id,
        kind: AgentHistoryEventKind.warning,
        title: _humanizeIdentifier(type!),
        description: message,
        content: content,
        raw: raw,
      );
    }

    if (normalizedType.contains('system') ||
        normalizedType.contains('notice') ||
        normalizedType.contains('error')) {
      return AgentHistoryEventEntry(
        id: id,
        kind: AgentHistoryEventKind.system,
        title: _humanizeIdentifier(type!),
        description: message,
        content: content,
        raw: raw,
      );
    }

    return null;
  }

  int _appendEntry(AgentHistoryEntry entry) {
    final turnId = _currentTurnId ?? _unscopedTurnId;
    _entries.add(entry);
    _entryTurnIds.add(turnId);
    _ensureTurn(turnId);
    return _entries.length - 1;
  }

  void _updatePendingTool(
    String callId, {
    String? title,
    AgentToolKind? kind,
    AgentToolStatus? status,
    String? content,
    List<String>? locations,
    AgentProviderRawPayload? rawInput,
    AgentProviderRawPayload? rawOutput,
    AgentProviderRawPayload? raw,
    AgentFileChangeSnapshot? fileChanges,
  }) {
    final pending = _pendingToolsByCallId[callId];
    if (pending == null) {
      return;
    }

    final entry = _entries[pending.index];
    if (entry is! AgentHistoryToolEntry) {
      return;
    }

    final current = entry.toolCall;
    _entries[pending.index] = AgentHistoryToolEntry(
      toolCall: current.copyWith(
        title: title,
        kind: kind,
        status: status,
        content: content,
        locations: locations,
        rawInput: rawInput,
        rawOutput: rawOutput,
        raw: raw,
        fileChanges: fileChanges,
      ),
    );
  }

  String _nextHistoryId(String prefix) => '$prefix-$_lineNumber';

  _JsonlTurnBuilder _ensureTurn(String turnId) {
    return _turnBuildersById.putIfAbsent(
      turnId,
      () => _JsonlTurnBuilder(turnId),
    );
  }

  _JsonlTurnBuilder? _currentTurn() {
    final turnId = _currentTurnId;
    if (turnId == null) {
      return null;
    }
    return _ensureTurn(turnId);
  }
}

String? _turnIdFromRecord(
  Map<String, Object?> record,
  Map<String, Object?> payload,
) {
  return _string(payload['turn_id']) ??
      _string(
        _map(payload['internal_chat_message_metadata_passthrough'])['turn_id'],
      ) ??
      _string(
        _map(record['internal_chat_message_metadata_passthrough'])['turn_id'],
      );
}

class _JsonlTurnBuilder {
  _JsonlTurnBuilder(this.id);

  final String id;

  AgentHistoryTurnStatus status = AgentHistoryTurnStatus.unknown;
  DateTime? startedAt;
  DateTime? completedAt;
  Duration? duration;
  Duration? timeToFirstToken;
  String? cwd;
  String? modelId;
  AgentHistoryReasoningEffort reasoningEffort =
      const AgentHistoryReasoningEffort.unknown();
  String? serviceTierId;
  bool? explicitFast;
  int? modelContextWindow;
  AgentConversationModeId? collaborationMode;
  AgentTokenUsage? tokenUsage;
  String? errorMessage;
  String? errorCode;
  final Map<String, Object?> raw = <String, Object?>{};

  AgentHistoryTurn build(List<AgentHistoryEntry> entries) {
    final effectiveStatus =
        status == AgentHistoryTurnStatus.unknown && completedAt != null
        ? AgentHistoryTurnStatus.completed
        : status;
    return AgentHistoryTurn(
      id: id,
      entries: List<AgentHistoryEntry>.unmodifiable(entries),
      status: effectiveStatus,
      startedAt: startedAt,
      completedAt: completedAt,
      duration: duration,
      timeToFirstToken: timeToFirstToken,
      cwd: cwd,
      modelId: modelId,
      reasoningEffort: reasoningEffort,
      serviceTierId: serviceTierId,
      explicitFast: explicitFast,
      modelContextWindow: modelContextWindow,
      collaborationMode: collaborationMode,
      tokenUsage: tokenUsage,
      errorMessage: errorMessage,
      errorCode: errorCode,
    );
  }
}

AgentHistoryReasoningEffort _codexJsonlReasoningEffort(Object? value) {
  if (value == null) {
    return const AgentHistoryReasoningEffort.providerDefault();
  }
  final effort = _string(value);
  if (effort == null) {
    return const AgentHistoryReasoningEffort.unknown();
  }
  return AgentHistoryReasoningEffort.explicit(effort);
}

class _JsonlPendingTool {
  const _JsonlPendingTool({required this.index});

  final int index;
}

class _JsonlPendingHistoryEvent {
  const _JsonlPendingHistoryEvent({required this.index});

  final int index;
}

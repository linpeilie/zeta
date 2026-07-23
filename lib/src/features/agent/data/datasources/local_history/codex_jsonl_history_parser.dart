part of '../app_server/codex_app_server_agent_provider.dart';

/// 按 jsonl 日志顺序重建 thread 历史。
class _JsonlHistoryParser {
  _JsonlHistoryParser({
    required this.fallbackThreadId,
    required this.sessionPath,
  });

  final String fallbackThreadId;
  final String sessionPath;
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

  String? _currentTurnId;
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
        _consumeEventMessage(payload, raw: record);
        return;
      case 'turn_context':
        _consumeTurnContext(payload, raw: record);
        return;
      case 'response_item':
        _consumeResponseItem(payload, raw: record);
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
      raw: <String, Object?>{
        'source': 'sessionFile',
        'sessionPath': sessionPath,
        'turnIds': turns.map((turn) => turn.id).toList(),
      },
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
    required Map<String, Object?> raw,
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
        final text = _trimmedText(_jsonlUserMessageText(payload));
        if (text == null) {
          return;
        }
        _appendEntry(
          AgentHistoryMessageEntry(
            id: _string(payload['client_id']) ?? _nextHistoryId('history-user'),
            role: AgentMessageRole.user,
            text: text,
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
          raw: raw,
          id: _nextHistoryId('history-event'),
        );
        if (historyEvent != null) {
          _appendEntry(historyEvent);
        }
        return;
    }
  }

  void _consumeCompletedItem(
    Map<String, Object?> payload, {
    required Map<String, Object?> raw,
  }) {
    final item = _map(payload['item']);
    if (_normalizedAgentItemType(_string(item['type'])) != 'plan') {
      return;
    }
    final text = _trimmedText(_string(item['text']));
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
  }

  void _consumeTaskStarted(
    Map<String, Object?> payload, {
    required Map<String, Object?> raw,
  }) {
    final turn = _currentTurn();
    if (turn == null) {
      return;
    }
    turn
      ..status = AgentHistoryTurnStatus.running
      ..startedAt =
          _dateTimeFromAny(payload['started_at']) ??
          _dateTimeFromAny(raw['timestamp']) ??
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
    required Map<String, Object?> raw,
  }) {
    final turn = _currentTurn();
    if (turn == null) {
      return;
    }
    turn
      ..status = AgentHistoryTurnStatus.completed
      ..completedAt =
          _dateTimeFromAny(payload['completed_at']) ??
          _dateTimeFromAny(raw['timestamp']) ??
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
    required Map<String, Object?> raw,
  }) {
    final turn = _currentTurn();
    if (turn == null) {
      return;
    }
    turn
      ..status = AgentHistoryTurnStatus.interrupted
      ..completedAt =
          _dateTimeFromAny(payload['completed_at']) ??
          _dateTimeFromAny(raw['timestamp']) ??
          turn.completedAt
      ..duration =
          _durationFromMilliseconds(payload['duration_ms']) ?? turn.duration
      ..errorMessage = _string(payload['reason']) ?? '用户取消';
    turn.raw['turnAborted'] = payload;
  }

  void _consumeTurnContext(
    Map<String, Object?> payload, {
    required Map<String, Object?> raw,
  }) {
    final turn = _currentTurn();
    if (turn == null) {
      return;
    }
    turn
      ..cwd = _string(payload['cwd']) ?? turn.cwd
      ..model = _string(payload['model']) ?? turn.model
      ..effort = _string(payload['effort']) ?? turn.effort
      ..modelContextWindow =
          _numberToInt(payload['model_context_window']) ??
          turn.modelContextWindow
      ..collaborationMode =
          _conversationModeCodec.modeIdFromValue(
            payload['collaboration_mode'],
          ) ??
          turn.collaborationMode;
    turn.raw['turnContext'] = payload;
  }

  void _consumeTokenCount(
    Map<String, Object?> payload, {
    required Map<String, Object?> raw,
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
    required Map<String, Object?> raw,
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
    required Map<String, Object?> raw,
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
      rawInput: _jsonlRawInputMap(
        arguments: arguments,
        stringInput: _string(payload['arguments']),
      ),
      raw: raw,
    );
    final index = _appendEntry(AgentHistoryToolEntry(toolCall: toolCall));
    _pendingToolsByCallId[callId] = _JsonlPendingTool(index: index);
  }

  void _consumeFunctionCallOutput(
    Map<String, Object?> payload, {
    required Map<String, Object?> raw,
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
      raw: entry.raw.isEmpty
          ? raw
          : <String, Object?>{...entry.raw, 'functionCallOutput': raw},
    );
  }

  void _consumeCustomToolCall(
    Map<String, Object?> payload, {
    required Map<String, Object?> raw,
  }) {
    final name = _string(payload['name']);
    final callId = _responseCallId(payload) ?? _nextHistoryId('tool-call');
    final stringInput = _string(payload['input']);
    final arguments = _decodedObjectMap(payload['input']);
    final toolCall = AgentToolCall(
      id: callId,
      title: _jsonlToolTitle(
        name: name,
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
      rawInput: _jsonlRawInputMap(
        arguments: arguments,
        stringInput: stringInput,
      ),
      raw: raw,
    );
    final index = _appendEntry(AgentHistoryToolEntry(toolCall: toolCall));
    _pendingToolsByCallId[callId] = _JsonlPendingTool(index: index);
  }

  void _consumeCustomToolCallOutput(Map<String, Object?> _) {}

  void _consumePatchApplyEnd(
    Map<String, Object?> payload, {
    required Map<String, Object?> raw,
  }) {
    final callId = _string(payload['call_id']);
    final locations = _patchApplyLocations(payload['changes']);
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
        title: 'Apply patch',
        kind: AgentToolKind.edit,
        status: payload['success'] == false
            ? AgentToolStatus.failed
            : AgentToolStatus.completed,
        content: content,
        locations: locations,
        rawOutput: payload,
        raw: raw,
      );
      return;
    }

    final toolCall = AgentToolCall(
      id: callId ?? _nextHistoryId('patch'),
      title: 'Apply patch',
      kind: AgentToolKind.edit,
      status: payload['success'] == false
          ? AgentToolStatus.failed
          : AgentToolStatus.completed,
      content: content,
      locations: locations,
      rawOutput: payload,
      raw: raw,
    );
    _appendEntry(AgentHistoryToolEntry(toolCall: toolCall));
  }

  void _consumeMcpToolCallEnd(
    Map<String, Object?> payload, {
    required Map<String, Object?> raw,
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
      rawInput: arguments,
      rawOutput: result,
      raw: raw,
    );
    _appendEntry(AgentHistoryToolEntry(toolCall: toolCall));
  }

  void _consumeToolSearchCall(
    Map<String, Object?> payload, {
    required Map<String, Object?> raw,
  }) {
    final arguments = _map(payload['arguments']);
    final callId = _responseCallId(payload) ?? _nextHistoryId('search');
    final query = _trimmedText(_string(arguments['query']));
    final entry = AgentHistoryEventEntry(
      id: 'search-$callId',
      kind: AgentHistoryEventKind.search,
      title: 'Tool search',
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
    required Map<String, Object?> raw,
  }) {
    final callId = _responseCallId(payload) ?? _nextHistoryId('search');
    final action = _map(payload['action']);
    final entry = AgentHistoryEventEntry(
      id: 'search-$callId',
      kind: AgentHistoryEventKind.search,
      title: 'Web search',
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
    required Map<String, Object?> raw,
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
    required Map<String, Object?> raw,
    required String id,
  }) {
    final payload = _map(raw['payload']);
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
    Map<String, Object?>? rawInput,
    Map<String, Object?>? rawOutput,
    Map<String, Object?>? raw,
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
      toolCall: AgentToolCall(
        id: current.id,
        title: title ?? current.title,
        kind: kind ?? current.kind,
        status: status ?? current.status,
        content: content ?? current.content,
        locations: locations ?? current.locations,
        rawInput: rawInput ?? current.rawInput,
        rawOutput: rawOutput ?? current.rawOutput,
        raw: raw ?? current.raw,
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
  String? model;
  String? effort;
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
      model: model,
      modelContextWindow: modelContextWindow,
      collaborationMode: collaborationMode,
      tokenUsage: tokenUsage,
      errorMessage: errorMessage,
      errorCode: errorCode,
      raw: Map<String, Object?>.unmodifiable(raw),
    );
  }
}

class _JsonlPendingTool {
  const _JsonlPendingTool({required this.index});

  final int index;
}

class _JsonlPendingHistoryEvent {
  const _JsonlPendingHistoryEvent({required this.index});

  final int index;
}

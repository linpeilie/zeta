part of '../datasources/app_server/codex_app_server_agent_provider.dart';

/// 负责把服务端通知转换成统一的 Agent 事件。
class _CodexNotificationMapper {
  const _CodexNotificationMapper({required this._providerId});

  final String _providerId;

  _NotificationMapping map(
    JsonRpcNotification notification, {
    required String? Function(String threadId) runningTurnIdForSession,
  }) {
    switch (notification.method) {
      case 'thread/started':
        final session = _sessionFromNotification(notification.params);
        if (session == null) {
          return const _NotificationMapping();
        }
        return _NotificationMapping(
          session: session,
          events: <AgentEvent>[AgentSessionStartedEvent(session)],
        );
      case 'turn/started':
        final turn = _turnFromNotification(notification.params);
        if (turn == null) {
          return const _NotificationMapping();
        }
        return _NotificationMapping(
          startedTurn: turn,
          events: <AgentEvent>[AgentTurnStartedEvent(turn)],
        );
      case 'turn/completed':
        final threadId = _string(notification.params['threadId']);
        final turn = _map(notification.params['turn']);
        final turnId =
            _string(turn['id']) ??
            _string(notification.params['turnId']) ??
            (threadId == null ? null : runningTurnIdForSession(threadId));
        if (threadId == null || turnId == null) {
          return const _NotificationMapping();
        }
        return _NotificationMapping(
          completedTurn: _CompletedTurn(sessionId: threadId, turnId: turnId),
          events: <AgentEvent>[
            AgentTurnCompletedEvent(
              sessionId: threadId,
              turnId: turnId,
              raw: notification.params,
            ),
          ],
        );
      case 'item/agentMessage/delta':
        final delta = _string(notification.params['delta']);
        final itemId = _string(notification.params['itemId']);
        if (delta == null || itemId == null) {
          return const _NotificationMapping();
        }
        final item = _map(notification.params['item']);
        return _NotificationMapping(
          events: <AgentEvent>[
            AgentMessageDeltaEvent(
              messageId: itemId,
              delta: delta,
              role: AgentMessageRole.agent,
              phase: _messagePhase(
                _string(notification.params['phase']) ?? _string(item['phase']),
              ),
              status: _messageStatus(
                _string(notification.params['status']) ??
                    _string(item['status']),
              ),
              duration: _messageDuration(item, notification.params),
              raw: notification.params,
              sessionId: _string(notification.params['threadId']),
              turnId: _string(notification.params['turnId']),
            ),
          ],
        );
      case 'turn/plan/updated':
        return _NotificationMapping(
          events: <AgentEvent>[
            AgentPlanUpdatedEvent(
              entries: _planEntries(notification.params),
              sessionId: _string(notification.params['threadId']),
              turnId: _string(notification.params['turnId']),
            ),
          ],
        );
      case 'item/started':
      case 'item/completed':
        final messageUpdate = _messageUpdateFromItemNotification(notification);
        if (messageUpdate != null) {
          return _NotificationMapping(events: <AgentEvent>[messageUpdate]);
        }
        final toolCall = _toolCallFromItemNotification(notification);
        if (toolCall == null) {
          return const _NotificationMapping();
        }
        return _NotificationMapping(
          events: <AgentEvent>[AgentToolCallEvent(toolCall)],
        );
      case 'item/commandExecution/outputDelta':
      case 'command/exec/outputDelta':
      case 'item/fileChange/outputDelta':
      case 'item/fileChange/patchUpdated':
        final toolCall = _toolCallFromProgressNotification(notification);
        if (toolCall == null) {
          return const _NotificationMapping();
        }
        return _NotificationMapping(
          events: <AgentEvent>[AgentToolCallEvent(toolCall)],
        );
      case 'turn/tokenCount':
      case 'item/tokenCount':
      case 'tokenCount':
        final usage = _tokenUsageFromNotification(notification.params);
        final threadId = _string(notification.params['threadId']);
        if (usage == null) {
          return const _NotificationMapping();
        }
        return _NotificationMapping(
          events: <AgentEvent>[
            AgentTokenUsageEvent(
              sessionId: threadId,
              turnId:
                  _string(notification.params['turnId']) ??
                  (threadId == null ? null : runningTurnIdForSession(threadId)),
              tokenUsage: usage,
              raw: notification.params,
            ),
          ],
        );
      case 'error':
      case 'warning':
      case 'guardianWarning':
      case 'configWarning':
        return _NotificationMapping(
          events: <AgentEvent>[
            AgentErrorEvent(
              message:
                  _string(notification.params['message']) ??
                  notification.method,
              details: _string(notification.params['details']),
              sessionId: _string(notification.params['threadId']),
              turnId: _string(notification.params['turnId']),
              raw: notification.params,
            ),
          ],
        );
      default:
        return const _NotificationMapping();
    }
  }

  AgentSession? _sessionFromNotification(Map<String, Object?> params) {
    final thread = _map(params['thread']);
    final id = _string(thread['id']) ?? _string(params['threadId']);
    if (id == null) {
      return null;
    }
    return AgentSession(
      id: id,
      providerId: _providerId,
      title: _string(thread['title']) ?? _string(thread['name']),
      raw: params,
    );
  }

  AgentTurn? _turnFromNotification(Map<String, Object?> params) {
    final turn = _map(params['turn']);
    final id = _string(turn['id']);
    final sessionId = _string(params['threadId']);
    if (id == null || sessionId == null) {
      return null;
    }
    return AgentTurn(id: id, sessionId: sessionId, raw: params);
  }

  List<AgentPlanEntry> _planEntries(Map<String, Object?> params) {
    final entries = params['entries'] ?? params['plan'];
    if (entries is! List<Object?>) {
      return const <AgentPlanEntry>[];
    }
    return entries.map((item) {
      final map = _map(item);
      return AgentPlanEntry(
        content: _string(map['content']) ?? _string(map['text']) ?? '$item',
        status: _string(map['status']),
        priority: _string(map['priority']),
      );
    }).toList();
  }

  AgentToolCall? _toolCallFromItemNotification(
    JsonRpcNotification notification,
  ) {
    final item = _map(notification.params['item']);
    final normalizedType = _normalizedAgentItemType(_string(item['type']));
    if (normalizedType == 'agentmessage' || normalizedType == 'plan') {
      return null;
    }
    final id = _string(item['id']) ?? _string(notification.params['itemId']);
    if (id == null) {
      return null;
    }
    return AgentToolCall(
      id: id,
      title: _toolTitle(item),
      kind: _toolKind(_string(item['kind']) ?? _string(item['type'])),
      status: notification.method == 'item/completed'
          ? AgentToolStatus.completed
          : AgentToolStatus.inProgress,
      content: _string(item['text']) ?? _string(item['command']),
      locations: _locations(item),
      sessionId: _string(notification.params['threadId']),
      turnId: _string(notification.params['turnId']),
      rawInput: _map(item['rawInput']),
      rawOutput: _map(item['rawOutput']),
      raw: notification.params,
    );
  }

  AgentMessageUpdatedEvent? _messageUpdateFromItemNotification(
    JsonRpcNotification notification,
  ) {
    final item = _map(notification.params['item']);
    final type = _string(item['type']) ?? _string(notification.params['type']);
    final normalizedType = _normalizedAgentItemType(type);
    if (normalizedType != 'agentmessage' && normalizedType != 'plan') {
      return null;
    }

    final id = _string(item['id']) ?? _string(notification.params['itemId']);
    if (id == null) {
      return null;
    }

    return AgentMessageUpdatedEvent(
      messageId: id,
      text: _string(item['text']) ?? _string(notification.params['text']),
      role: AgentMessageRole.agent,
      phase: _messagePhase(
        _string(item['phase']) ?? _string(notification.params['phase']),
      ),
      status: notification.method == 'item/completed'
          ? AgentMessageStatus.completed
          : _messageStatus(
              _string(item['status']) ?? _string(notification.params['status']),
            ),
      duration: _messageDuration(item, notification.params),
      raw: notification.params,
      sessionId: _string(notification.params['threadId']),
      turnId: _string(notification.params['turnId']),
    );
  }

  AgentToolCall? _toolCallFromProgressNotification(
    JsonRpcNotification notification,
  ) {
    final id =
        _string(notification.params['itemId']) ??
        _string(notification.params['toolCallId']) ??
        notification.method;
    return AgentToolCall(
      id: id,
      title: _progressTitle(notification.method),
      kind: notification.method.contains('fileChange')
          ? AgentToolKind.edit
          : AgentToolKind.execute,
      status: AgentToolStatus.inProgress,
      content:
          _string(notification.params['delta']) ??
          _string(notification.params['output']) ??
          _string(notification.params['patch']),
      sessionId: _string(notification.params['threadId']),
      turnId: _string(notification.params['turnId']),
      raw: notification.params,
    );
  }

  AgentTokenUsage? _tokenUsageFromNotification(Map<String, Object?> params) {
    final info = _map(params['info']);
    final effectiveInfo = info.isEmpty ? params : info;
    final total = _map(effectiveInfo['total_token_usage']);
    final last = _map(effectiveInfo['last_token_usage']);
    if (total.isEmpty && last.isEmpty) {
      return null;
    }
    return AgentTokenUsage(
      inputTokens: _numberToInt(total['input_tokens']),
      cachedInputTokens: _numberToInt(total['cached_input_tokens']),
      outputTokens: _numberToInt(total['output_tokens']),
      reasoningOutputTokens: _numberToInt(total['reasoning_output_tokens']),
      totalTokens: _numberToInt(total['total_tokens']),
      lastInputTokens: _numberToInt(last['input_tokens']),
      lastCachedInputTokens: _numberToInt(last['cached_input_tokens']),
      lastOutputTokens: _numberToInt(last['output_tokens']),
      lastReasoningOutputTokens: _numberToInt(last['reasoning_output_tokens']),
      lastTotalTokens: _numberToInt(last['total_tokens']),
    );
  }
}

class _NotificationMapping {
  const _NotificationMapping({
    this.session,
    this.startedTurn,
    this.completedTurn,
    this.events = const <AgentEvent>[],
  });

  final AgentSession? session;
  final AgentTurn? startedTurn;
  final _CompletedTurn? completedTurn;
  final List<AgentEvent> events;
}

class _CompletedTurn {
  const _CompletedTurn({required this.sessionId, required this.turnId});

  final String sessionId;
  final String turnId;
}

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
              status: _turnFinalStatus(_string(turn['status'])),
              errorMessage: _string(_map(turn['error'])['message']),
              duration: _durationFromMilliseconds(turn['durationMs']),
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
      // `thread/tokenUsage/updated` 是当前协议的 token 用量通知;
      // 其余三个是旧版方法名,保留用于兼容旧版 app-server。
      case 'thread/tokenUsage/updated':
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
        return _NotificationMapping(
          events: <AgentEvent>[_errorEventFromNotification(notification)],
        );
      case 'warning':
      case 'guardianWarning':
      case 'configWarning':
        return _NotificationMapping(
          events: <AgentEvent>[
            AgentErrorEvent(
              // `configWarning` 的概要字段是 `summary`，其余为 `message`。
              message:
                  _string(notification.params['message']) ??
                  _string(notification.params['summary']) ??
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

  /// 解析 `error` 通知，兼容两代协议结构：
  ///
  /// - 当前协议：`{ threadId, turnId, willRetry, error: TurnError }`，
  ///   `TurnError = { message, codexErrorInfo?, additionalDetails? }`。
  /// - 旧版协议：平铺的 `{ message, details }`。
  AgentErrorEvent _errorEventFromNotification(
    JsonRpcNotification notification,
  ) {
    final params = notification.params;
    final error = _map(params['error']);
    if (error.isEmpty) {
      return AgentErrorEvent(
        message: _string(params['message']) ?? notification.method,
        details: _string(params['details']),
        sessionId: _string(params['threadId']),
        turnId: _string(params['turnId']),
        raw: params,
      );
    }

    final willRetry = params['willRetry'];
    return AgentErrorEvent(
      message: _string(error['message']) ?? notification.method,
      details: _string(error['additionalDetails']),
      code: _codexErrorCode(error['codexErrorInfo']),
      willRetry: willRetry is bool ? willRetry : null,
      sessionId: _string(params['threadId']),
      turnId: _string(params['turnId']),
      raw: params,
    );
  }

  /// 将 `turn/completed` 携带的 `turn.status` 归一化为终态。
  ///
  /// 协议枚举为 completed/interrupted/failed/inProgress；该通知本身表示
  /// 回合已结束，无法识别或非终态的取值一律按 completed 处理。
  AgentHistoryTurnStatus _turnFinalStatus(String? status) {
    return switch (_historyTurnStatus(status)) {
      AgentHistoryTurnStatus.interrupted => AgentHistoryTurnStatus.interrupted,
      AgentHistoryTurnStatus.failed => AgentHistoryTurnStatus.failed,
      _ => AgentHistoryTurnStatus.completed,
    };
  }

  /// 归一化 `codexErrorInfo`：
  /// 字符串变体（如 `contextWindowExceeded`）直接返回；
  /// 对象变体（如 `{ httpConnectionFailed: { httpStatusCode } }`）返回其
  /// 唯一键名作为错误码。
  String? _codexErrorCode(Object? info) {
    if (info is String) {
      return info;
    }
    final map = _map(info);
    if (map.length == 1) {
      return map.keys.first;
    }
    return null;
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

  /// 解析 token 用量通知，同时兼容两代协议结构：
  ///
  /// - 当前协议 `thread/tokenUsage/updated`：
  ///   `{ tokenUsage: { total: {...}, last: {...}, modelContextWindow } }`，
  ///   字段为 camelCase（`inputTokens` 等）。
  /// - 旧版 `turn/tokenCount` 等：
  ///   `{ info: { total_token_usage: {...}, last_token_usage: {...} } }`，
  ///   字段为 snake_case（`input_tokens` 等）。
  AgentTokenUsage? _tokenUsageFromNotification(Map<String, Object?> params) {
    final tokenUsage = _map(params['tokenUsage']);
    final info = _map(params['info']);
    final container = tokenUsage.isNotEmpty
        ? tokenUsage
        : (info.isEmpty ? params : info);

    final total = _firstNonEmptyMap(<Object?>[
      container['total'],
      container['total_token_usage'],
    ]);
    final last = _firstNonEmptyMap(<Object?>[
      container['last'],
      container['last_token_usage'],
    ]);
    if (total.isEmpty && last.isEmpty) {
      return null;
    }
    return AgentTokenUsage(
      inputTokens: _breakdownInt(total, 'inputTokens', 'input_tokens'),
      cachedInputTokens: _breakdownInt(
        total,
        'cachedInputTokens',
        'cached_input_tokens',
      ),
      outputTokens: _breakdownInt(total, 'outputTokens', 'output_tokens'),
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
      lastOutputTokens: _breakdownInt(last, 'outputTokens', 'output_tokens'),
      lastReasoningOutputTokens: _breakdownInt(
        last,
        'reasoningOutputTokens',
        'reasoning_output_tokens',
      ),
      lastTotalTokens: _breakdownInt(last, 'totalTokens', 'total_tokens'),
      modelContextWindow: _breakdownInt(
        container,
        'modelContextWindow',
        'model_context_window',
      ),
    );
  }

  /// 返回候选值中第一个非空的 Map，全部为空时返回空 Map。
  Map<String, Object?> _firstNonEmptyMap(List<Object?> candidates) {
    for (final candidate in candidates) {
      final map = _map(candidate);
      if (map.isNotEmpty) {
        return map;
      }
    }
    return const <String, Object?>{};
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

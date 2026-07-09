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
      case 'thread/status/changed':
        final threadId = _string(notification.params['threadId']);
        final statusMap = _map(notification.params['status']);
        if (threadId == null || statusMap.isEmpty) {
          return const _NotificationMapping();
        }
        final flags = _threadActiveFlags(statusMap);
        return _NotificationMapping(
          events: <AgentEvent>[
            AgentThreadStatusChangedEvent(
              threadId: threadId,
              status: _threadRuntimeStatus(statusMap),
              waitingOnApproval: flags.waitingOnApproval,
              waitingOnUserInput: flags.waitingOnUserInput,
              raw: notification.params,
            ),
          ],
        );
      case 'thread/name/updated':
        final threadId = _string(notification.params['threadId']);
        if (threadId == null) {
          return const _NotificationMapping();
        }
        return _NotificationMapping(
          events: <AgentEvent>[
            AgentThreadNameUpdatedEvent(
              threadId: threadId,
              threadName: _string(notification.params['threadName']),
              raw: notification.params,
            ),
          ],
        );
      case 'thread/archived':
        return _threadIdEventMapping(
          notification,
          (threadId) => AgentThreadArchivedEvent(
            threadId: threadId,
            raw: notification.params,
          ),
        );
      case 'thread/unarchived':
        return _threadIdEventMapping(
          notification,
          (threadId) => AgentThreadUnarchivedEvent(
            threadId: threadId,
            raw: notification.params,
          ),
        );
      case 'thread/deleted':
        return _threadIdEventMapping(
          notification,
          (threadId) => AgentThreadDeletedEvent(
            threadId: threadId,
            raw: notification.params,
          ),
        );
      case 'thread/closed':
        return _threadIdEventMapping(
          notification,
          (threadId) => AgentThreadClosedEvent(
            threadId: threadId,
            raw: notification.params,
          ),
        );
      case 'thread/compacted':
        final threadId = _string(notification.params['threadId']);
        if (threadId == null) {
          return const _NotificationMapping();
        }
        return _NotificationMapping(
          events: <AgentEvent>[
            AgentThreadCompactedEvent(
              threadId: threadId,
              turnId: _string(notification.params['turnId']),
              raw: notification.params,
            ),
          ],
        );
      case 'thread/settings/updated':
        final threadId = _string(notification.params['threadId']);
        if (threadId == null) {
          return const _NotificationMapping();
        }
        final settings = _map(notification.params['threadSettings']);
        final approvalRaw = settings['approvalPolicy'];
        final approvalPolicy = approvalRaw is String ? approvalRaw : null;
        final sandboxPolicy =
            AgentPermissionSelection.sandboxPolicyFromProtocol(
              settings['sandboxPolicy'] ?? settings['sandbox'],
            );
        final activeProfile = _map(settings['activePermissionProfile']);
        return _NotificationMapping(
          events: <AgentEvent>[
            AgentThreadSettingsUpdatedEvent(
              threadId: threadId,
              model: _string(settings['model']),
              approvalPolicy: approvalPolicy,
              sandboxPolicy: sandboxPolicy,
              activePermissionProfileId: _string(activeProfile['id']),
              raw: notification.params,
            ),
          ],
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
      // Reasoning 三通知：原始推理文本 / 摘要文本 / 摘要分段边界。
      case 'item/reasoning/textDelta':
        return _reasoningDeltaMapping(
          notification,
          kind: AgentReasoningDeltaKind.text,
        );
      case 'item/reasoning/summaryTextDelta':
        return _reasoningDeltaMapping(
          notification,
          kind: AgentReasoningDeltaKind.summaryText,
        );
      case 'item/reasoning/summaryPartAdded':
        return _reasoningDeltaMapping(
          notification,
          kind: AgentReasoningDeltaKind.summaryPart,
          requireDelta: false,
        );
      // Plan item 文本流；completed item 仍是权威全文（拼接 delta 可能不一致）。
      case 'item/plan/delta':
        final delta = _string(notification.params['delta']);
        final itemId = _string(notification.params['itemId']);
        if (delta == null || itemId == null) {
          return const _NotificationMapping();
        }
        return _NotificationMapping(
          events: <AgentEvent>[
            AgentMessageDeltaEvent(
              messageId: itemId,
              delta: delta,
              role: AgentMessageRole.agent,
              status: AgentMessageStatus.streaming,
              // 注入 type=plan，让 timeline 走计划卡片而非普通气泡。
              raw: <String, Object?>{...notification.params, 'type': 'plan'},
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
      // 回合级聚合 unified diff；每次通知携带最新全文，非增量拼接。
      case 'turn/diff/updated':
        final threadId = _string(notification.params['threadId']);
        final turnId = _string(notification.params['turnId']);
        final diff = notification.params['diff'];
        if (threadId == null || turnId == null || diff is! String) {
          return const _NotificationMapping();
        }
        return _NotificationMapping(
          events: <AgentEvent>[
            AgentTurnDiffEvent(
              sessionId: threadId,
              turnId: turnId,
              diff: diff,
              raw: notification.params,
            ),
          ],
        );
      case 'item/started':
      case 'item/completed':
        final messageUpdate = _messageUpdateFromItemNotification(notification);
        if (messageUpdate != null) {
          return _NotificationMapping(events: <AgentEvent>[messageUpdate]);
        }
        final systemItem = _systemItemFromItemNotification(notification);
        if (systemItem != null) {
          return _NotificationMapping(events: <AgentEvent>[systemItem]);
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
      // MCP 工具进度消息；timeline 会追加到对应 item 的工具卡 content。
      case 'item/mcpToolCall/progress':
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
      // 他端已应答该服务端请求；本端清掉待审批状态并关闭审批卡。
      case 'serverRequest/resolved':
        final requestId = _requestIdString(notification.params['requestId']);
        final threadId = _string(notification.params['threadId']);
        if (requestId == null || threadId == null) {
          return const _NotificationMapping();
        }
        return _NotificationMapping(
          events: <AgentEvent>[
            AgentPermissionResolvedEvent(
              requestId: requestId,
              threadId: threadId,
              raw: notification.params,
            ),
          ],
        );
      // 服务端将本回合模型改道；UI 插入系统事件并在头栏提示。
      case 'model/rerouted':
        final threadId = _string(notification.params['threadId']);
        final turnId = _string(notification.params['turnId']);
        final fromModel = _string(notification.params['fromModel']);
        final toModel = _string(notification.params['toModel']);
        final reason = _string(notification.params['reason']);
        if (threadId == null ||
            turnId == null ||
            fromModel == null ||
            toModel == null ||
            reason == null) {
          return const _NotificationMapping();
        }
        return _NotificationMapping(
          events: <AgentEvent>[
            AgentModelReroutedEvent(
              threadId: threadId,
              turnId: turnId,
              fromModel: fromModel,
              toModel: toModel,
              reason: reason,
              raw: notification.params,
            ),
          ],
        );
      // API 弃用提示；UI 按 summary 去重一次性展示。
      case 'deprecationNotice':
        final summary = _string(notification.params['summary']);
        if (summary == null) {
          return const _NotificationMapping();
        }
        return _NotificationMapping(
          events: <AgentEvent>[
            AgentDeprecationNoticeEvent(
              summary: summary,
              details: _string(notification.params['details']),
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
      case 'item/autoApprovalReview/started':
      case 'item/autoApprovalReview/completed':
        final threadId = _string(notification.params['threadId']);
        final turnId = _string(notification.params['turnId']);
        final reviewId = _string(notification.params['reviewId']);
        if (threadId == null || turnId == null || reviewId == null) {
          return const _NotificationMapping();
        }
        final review = _map(notification.params['review']);
        final status =
            _string(review['status']) ??
            (notification.method.endsWith('/started')
                ? 'inProgress'
                : 'approved');
        return _NotificationMapping(
          events: <AgentEvent>[
            AgentAutoApprovalReviewEvent(
              threadId: threadId,
              turnId: turnId,
              reviewId: reviewId,
              status: status,
              rationale: _string(review['rationale']),
              riskLevel: _string(review['riskLevel']),
              targetItemId: _string(notification.params['targetItemId']),
              raw: notification.params,
            ),
          ],
        );
      default:
        // 未识别的通知不产生事件；由 provider 记 fine 日志并累计诊断计数。
        return _NotificationMapping(unmatchedMethod: notification.method);
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

  /// 将仅含 `threadId` 的生命周期通知映射为对应事件。
  _NotificationMapping _threadIdEventMapping(
    JsonRpcNotification notification,
    AgentEvent Function(String threadId) build,
  ) {
    final threadId = _string(notification.params['threadId']);
    if (threadId == null) {
      return const _NotificationMapping();
    }
    return _NotificationMapping(events: <AgentEvent>[build(threadId)]);
  }

  /// 将 `item/reasoning/*` 通知映射为 [AgentReasoningDeltaEvent]。
  ///
  /// [requireDelta] 为 true 时缺少 `delta`/`itemId` 则丢弃；
  /// `summaryPartAdded` 无文本，仅要求 `itemId`。
  _NotificationMapping _reasoningDeltaMapping(
    JsonRpcNotification notification, {
    required AgentReasoningDeltaKind kind,
    bool requireDelta = true,
  }) {
    final itemId = _string(notification.params['itemId']);
    final delta = _string(notification.params['delta']) ?? '';
    if (itemId == null || (requireDelta && delta.isEmpty)) {
      return const _NotificationMapping();
    }
    return _NotificationMapping(
      events: <AgentEvent>[
        AgentReasoningDeltaEvent(
          itemId: itemId,
          kind: kind,
          delta: delta,
          contentIndex: _numberToInt(notification.params['contentIndex']),
          summaryIndex: _numberToInt(notification.params['summaryIndex']),
          sessionId: _string(notification.params['threadId']),
          turnId: _string(notification.params['turnId']),
          raw: notification.params,
        ),
      ],
    );
  }

  AgentToolCall? _toolCallFromItemNotification(
    JsonRpcNotification notification,
  ) {
    final item = _map(notification.params['item']);
    final id = _string(item['id']) ?? _string(notification.params['itemId']);
    if (id == null) {
      return null;
    }
    final status = _historyToolStatus(_string(item['status']));
    return _toolCallFromThreadItem(
      item,
      id: id,
      // started 一律视为进行中；completed 再按 item.status 细分失败/取消。
      status: notification.method == 'item/completed'
          ? status
          : AgentToolStatus.inProgress,
      sessionId: _string(notification.params['threadId']),
      turnId: _string(notification.params['turnId']),
      raw: notification.params,
    );
  }

  /// 评审 / 压缩 / hook / sleep / 子代理等系统类 ThreadItem。
  AgentSystemItemEvent? _systemItemFromItemNotification(
    JsonRpcNotification notification,
  ) {
    final item = _map(notification.params['item']);
    final id = _string(item['id']) ?? _string(notification.params['itemId']);
    if (id == null) {
      return null;
    }
    final entry = _systemHistoryEventFromThreadItem(item, id: id);
    if (entry == null) {
      return null;
    }
    return AgentSystemItemEvent(
      entry: entry,
      sessionId: _string(notification.params['threadId']),
      turnId: _string(notification.params['turnId']),
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
    final method = notification.method;
    // MCP 进度通知必填 itemId + message；缺一则丢弃，避免生成无归属卡片。
    if (method == 'item/mcpToolCall/progress') {
      final itemId = _string(notification.params['itemId']);
      final message = _string(notification.params['message']);
      if (itemId == null || message == null) {
        return null;
      }
      return AgentToolCall(
        id: itemId,
        title: _progressTitle(method),
        kind: AgentToolKind.other,
        status: AgentToolStatus.inProgress,
        content: message,
        sessionId: _string(notification.params['threadId']),
        turnId: _string(notification.params['turnId']),
        // 标记进度追加，供 timeline 合并时保留既有标题并追加 content。
        raw: <String, Object?>{...notification.params, '_progressAppend': true},
      );
    }

    final id =
        _string(notification.params['itemId']) ??
        _string(notification.params['toolCallId']) ??
        method;
    return AgentToolCall(
      id: id,
      title: _progressTitle(method),
      kind: method.contains('fileChange')
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
    this.unmatchedMethod,
  });

  final AgentSession? session;
  final AgentTurn? startedTurn;
  final _CompletedTurn? completedTurn;
  final List<AgentEvent> events;

  /// 非空表示该方法未进入任何已知 case，供 provider 做可观测性记录。
  final String? unmatchedMethod;
}

class _CompletedTurn {
  const _CompletedTurn({required this.sessionId, required this.turnId});

  final String sessionId;
  final String turnId;
}

import 'package:zeta/src/features/agent/application/agent_conversation_effect.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_mutation.dart';
import 'package:zeta/src/features/agent/application/agent_ui_update_request.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

typedef AgentConversationClock = DateTime Function();

/// 会话时间线本地条目的同步 identity 生成器。
///
/// live facade 与 live reducer 共用一个实例，保持命令侧和事件侧 entryId 的单调唯一性；
/// history/replay 必须各自创建实例，避免跨 reduction scope 共享 identity 状态。
final class AgentConversationLocalTimelineIdGenerator {
  AgentConversationLocalTimelineIdGenerator({AgentConversationClock? clock})
    : _clock = clock ?? DateTime.now;

  final AgentConversationClock _clock;
  int _sequence = 0;

  String next(String prefix) {
    _sequence += 1;
    return '$prefix-${_clock().microsecondsSinceEpoch}-$_sequence';
  }
}

/// live/history/replay 各自持有独立可变 identity 状态的 reducer 集合。
final class AgentConversationReducerContexts {
  AgentConversationReducerContexts({
    AgentConversationClock? clock,
    AgentConversationLocalTimelineIdGenerator? liveTimelineIds,
  }) : live = AgentConversationReducer.live(
         clock: clock,
         timelineIds: liveTimelineIds,
       ),
       history = AgentConversationReducer.history(clock: clock),
       replay = AgentConversationReducer.replay(clock: clock);

  final AgentConversationReducer live;
  final AgentConversationReducer history;
  final AgentConversationReducer replay;
}

/// reducer 所需的只读会话视图。
///
/// [hasTurn] 与 [isHistoryTurnId] 是 O(1)/增量 Store 查询端口，避免每个 delta
/// 为了接收判断复制完整 Timeline。
final class AgentConversationReducerContext {
  const AgentConversationReducerContext({
    required this.scope,
    required this.selectedThreadId,
    required this.requiresResumedSelectedThread,
    required this.pendingTurnGroupId,
    required this.hasTurn,
    required this.isHistoryTurnId,
    required this.modelsRefreshing,
    required this.activeProviderName,
    required this.activeProviderConfig,
    required this.effectScope,
  });

  final AgentConversationReductionScope scope;
  final String? selectedThreadId;
  final bool requiresResumedSelectedThread;
  final String? pendingTurnGroupId;
  final bool Function(String turnId) hasTurn;
  final bool Function(String turnId) isHistoryTurnId;
  final bool modelsRefreshing;
  final String activeProviderName;
  final AgentProviderConfig activeProviderConfig;
  final AgentConversationEffectScope effectScope;
}

/// 将规范化 [AgentEvent] 纯同步归约为 state/timeline/UI/snapshot/effect 描述。
///
/// reducer 不访问 Flutter scheduler，不创建 Timer，也不执行 Future。每个 live、
/// history、replay consumer 必须创建独立实例。
final class AgentConversationReducer {
  AgentConversationReducer._({
    required this.scope,
    AgentConversationClock? clock,
    AgentConversationLocalTimelineIdGenerator? timelineIds,
  }) : _timelineIds =
           timelineIds ??
           AgentConversationLocalTimelineIdGenerator(clock: clock);

  factory AgentConversationReducer.live({
    AgentConversationClock? clock,
    AgentConversationLocalTimelineIdGenerator? timelineIds,
  }) {
    return AgentConversationReducer._(
      scope: AgentConversationReductionScope.live,
      clock: clock,
      timelineIds: timelineIds,
    );
  }

  factory AgentConversationReducer.history({AgentConversationClock? clock}) {
    return AgentConversationReducer._(
      scope: AgentConversationReductionScope.history,
      clock: clock,
    );
  }

  factory AgentConversationReducer.replay({AgentConversationClock? clock}) {
    return AgentConversationReducer._(
      scope: AgentConversationReductionScope.replay,
      clock: clock,
    );
  }

  final AgentConversationReductionScope scope;
  final AgentConversationLocalTimelineIdGenerator _timelineIds;
  final Set<String> _shownDeprecationSummaries = <String>{};
  String? _lastShownErrorMessage;

  /// detached runtime 仍可交付的精确 critical allowlist。
  static bool isCriticalDetachedEvent(AgentEvent event) {
    return event is AgentStatusEvent ||
        event is AgentErrorEvent ||
        event is AgentTurnCompletedEvent ||
        event is AgentThreadClosedEvent ||
        event is AgentPermissionRequestedEvent ||
        event is AgentPermissionResolvedEvent ||
        event is AgentPlanApprovalRequestedEvent ||
        event is AgentPlanApprovalResolvedEvent;
  }

  AgentConversationMutation reduce(
    AgentEvent event,
    AgentConversationReducerContext context,
  ) {
    assert(
      context.scope == scope,
      'Reducer 与 context 的 live/history/replay scope 必须一致。',
    );
    return switch (event) {
      AgentStatusEvent() => _status(event),
      AgentSessionStartedEvent() => _sessionStarted(event, context),
      AgentThreadStatusChangedEvent() => _threadStatus(event, context),
      AgentThreadNameUpdatedEvent() => _threadName(event, context),
      AgentThreadArchivedEvent() => _noOp(),
      AgentThreadUnarchivedEvent() => _noOp(),
      AgentThreadDeletedEvent() => _noOp(),
      AgentThreadClosedEvent() => _threadClosed(event, context),
      AgentThreadCompactedEvent() => _threadCompacted(event, context),
      AgentThreadSettingsUpdatedEvent() => _threadSettings(event, context),
      AgentAutoApprovalReviewEvent() => _autoApprovalReview(event, context),
      AgentTurnStartedEvent() => _turnStarted(event, context),
      AgentTurnCompletedEvent() => _turnCompleted(event, context),
      AgentTokenUsageEvent() => _tokenUsage(event, context),
      AgentContextWindowUsageEvent() => _contextUsage(event, context),
      AgentMessageDeltaEvent() => _messageDelta(event, context),
      AgentReasoningDeltaEvent() => _reasoningDelta(event, context),
      AgentMessageUpdatedEvent() => _messageUpdated(event, context),
      AgentPlanUpdatedEvent() => _planUpdated(event, context),
      AgentSessionConfigUpdatedEvent() => _sessionConfig(event, context),
      AgentConversationModeUpdatedEvent() => _conversationModeUpdated(
        event,
        context,
      ),
      AgentPlanApprovalRequestedEvent() => _planApprovalRequested(
        event,
        context,
      ),
      AgentPlanApprovalResolvedEvent() => _planApprovalResolved(event, context),
      AgentTurnDiffEvent() => _turnDiff(event, context),
      AgentToolCallEvent() => _toolCall(event, context),
      AgentPermissionRequestedEvent() => _permissionRequested(event, context),
      AgentPermissionResolvedEvent() => _permissionResolved(event, context),
      AgentQuestionRequestedEvent() => _questionRequested(event, context),
      AgentQuestionResolvedEvent() => _questionResolved(event, context),
      AgentModelReroutedEvent() => _modelRerouted(event, context),
      AgentDeprecationNoticeEvent() => _deprecation(event),
      AgentSystemItemEvent() => _systemItem(event, context),
      AgentErrorEvent() => _error(event, context),
      AgentModelListEvent() => _modelList(event, context),
    };
  }

  /// Provider stream onDone 与 thread/closed 共用的中断收尾 mutation。
  AgentConversationMutation settleInterruptedTurn({
    required String fallbackTurnId,
  }) {
    return AgentConversationMutation(
      accepted: true,
      stateChangesBeforeTimeline: const <AgentConversationStateChange>[
        AgentPrepareInterruptedTurnChange(),
      ],
      timelineMutations: <AgentTimelineMutation>[
        AgentSettleInterruptedTimelineMutation(fallbackTurnId),
      ],
      stateChanges: const <AgentConversationStateChange>[
        AgentFinalizeInterruptedTurnChange(),
      ],
      uiUpdate: AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{
          AgentUiRegion.history,
          AgentUiRegion.liveTurnBinding,
          AgentUiRegion.header,
          AgentUiRegion.composer,
        },
        urgency: AgentUiUpdateUrgency.immediate,
      ),
      uiResolution: const AgentConversationUiResolution(
        includePendingInteractionWhenStateChanges: true,
      ),
      threadSnapshot: AgentThreadSnapshotMutation.refresh,
    );
  }

  AgentConversationMutation _status(AgentStatusEvent event) {
    return AgentConversationMutation(
      accepted: true,
      stateChanges: <AgentConversationStateChange>[
        AgentSetProviderStatusChange(event.status),
      ],
      // 空 immediate request 仍可吸收并冲刷已有的 next-frame pending。
      uiUpdate: AgentUiUpdateRequest(urgency: AgentUiUpdateUrgency.immediate),
    );
  }

  AgentConversationMutation _sessionStarted(
    AgentSessionStartedEvent event,
    AgentConversationReducerContext context,
  ) {
    final selectedThreadId = context.selectedThreadId;
    final accepted = selectedThreadId != null
        ? selectedThreadId == event.session.id
        : !context.requiresResumedSelectedThread;
    if (!accepted) {
      return AgentConversationMutation.rejected('sessionStartedThreadMismatch');
    }
    return AgentConversationMutation(
      accepted: true,
      stateChanges: <AgentConversationStateChange>[
        AgentApplySessionStartedChange(event.session),
      ],
      uiUpdate: AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{
          AgentUiRegion.header,
          AgentUiRegion.composer,
        },
        urgency: AgentUiUpdateUrgency.immediate,
      ),
      threadSnapshot: AgentThreadSnapshotMutation.refresh,
    );
  }

  AgentConversationMutation _threadStatus(
    AgentThreadStatusChangedEvent event,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(context, sessionId: event.threadId)) {
      return AgentConversationMutation.rejected('currentThreadMismatch');
    }
    return AgentConversationMutation(
      accepted: true,
      stateChanges: <AgentConversationStateChange>[
        AgentApplyThreadRuntimeStatusChange(
          status: event.status,
          waitingOnApproval: event.waitingOnApproval,
          waitingOnUserInput: event.waitingOnUserInput,
        ),
      ],
      uiUpdate: AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{AgentUiRegion.header},
        urgency: AgentUiUpdateUrgency.immediate,
      ),
      threadSnapshot: AgentThreadSnapshotMutation.refresh,
    );
  }

  AgentConversationMutation _threadName(
    AgentThreadNameUpdatedEvent event,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(context, sessionId: event.threadId)) {
      return AgentConversationMutation.rejected('currentThreadMismatch');
    }
    return AgentConversationMutation(
      accepted: true,
      stateChanges: <AgentConversationStateChange>[
        AgentApplyThreadNameChange(event.threadName),
      ],
      uiUpdate: AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{AgentUiRegion.header},
        urgency: AgentUiUpdateUrgency.immediate,
      ),
      threadSnapshot: AgentThreadSnapshotMutation.refresh,
    );
  }

  AgentConversationMutation _noOp() {
    return AgentConversationMutation(accepted: true);
  }

  AgentConversationMutation _threadClosed(
    AgentThreadClosedEvent event,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(context, sessionId: event.threadId)) {
      return AgentConversationMutation.rejected('currentThreadMismatch');
    }
    return settleInterruptedTurn(fallbackTurnId: 'closed');
  }

  AgentConversationMutation _threadCompacted(
    AgentThreadCompactedEvent event,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(context, sessionId: event.threadId)) {
      return AgentConversationMutation.rejected('currentThreadMismatch');
    }
    return AgentConversationMutation(
      accepted: true,
      stateChanges: const <AgentConversationStateChange>[
        AgentSetCompactingChange(false),
      ],
      uiUpdate: AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{
          AgentUiRegion.header,
          AgentUiRegion.composer,
        },
        urgency: AgentUiUpdateUrgency.immediate,
      ),
    );
  }

  AgentConversationMutation _threadSettings(
    AgentThreadSettingsUpdatedEvent event,
    AgentConversationReducerContext context,
  ) {
    final permissionSelection = event.permissionSelection;
    final isCurrent = _shouldHandleCurrent(context, sessionId: event.threadId);
    if (!isCurrent && permissionSelection == null) {
      return AgentConversationMutation.rejected('currentThreadMismatch');
    }
    final stateChanges = <AgentConversationStateChange>[
      if (permissionSelection != null)
        AgentApplyThreadPermissionSettingsChange(
          threadId: event.threadId,
          permissionSelection: permissionSelection,
        ),
      if (isCurrent) AgentApplyThreadSettingsChange(event),
    ];
    return AgentConversationMutation(
      accepted: true,
      stateChanges: stateChanges,
      uiUpdate: isCurrent
          ? AgentUiUpdateRequest(
              regions: const <AgentUiRegion>{AgentUiRegion.composer},
              urgency: AgentUiUpdateUrgency.immediate,
            )
          : null,
    );
  }

  AgentConversationMutation _sessionConfig(
    AgentSessionConfigUpdatedEvent event,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(context, sessionId: event.sessionId)) {
      return AgentConversationMutation.rejected('currentThreadMismatch');
    }
    return AgentConversationMutation(
      accepted: true,
      stateChanges: <AgentConversationStateChange>[
        AgentApplySessionConfigChange(event.options),
      ],
      uiUpdate: AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{AgentUiRegion.composer},
        urgency: AgentUiUpdateUrgency.immediate,
      ),
    );
  }

  AgentConversationMutation _conversationModeUpdated(
    AgentConversationModeUpdatedEvent event,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(context, sessionId: event.sessionId)) {
      return AgentConversationMutation.rejected('currentThreadMismatch');
    }
    return AgentConversationMutation(
      accepted: true,
      stateChanges: <AgentConversationStateChange>[
        AgentApplyConversationModeChange(event),
      ],
      uiUpdate: AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{
          AgentUiRegion.header,
          AgentUiRegion.composer,
        },
        urgency: AgentUiUpdateUrgency.immediate,
      ),
    );
  }

  AgentConversationMutation _autoApprovalReview(
    AgentAutoApprovalReviewEvent event,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(
      context,
      sessionId: event.threadId,
      turnId: event.turnId,
    )) {
      return AgentConversationMutation.rejected('currentThreadMismatch');
    }
    return AgentConversationMutation(
      accepted: true,
      stateChanges: <AgentConversationStateChange>[
        AgentApplyAutoApprovalReviewChange(event),
      ],
      uiUpdate: AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{
          AgentUiRegion.header,
          AgentUiRegion.liveTurn,
          AgentUiRegion.history,
        },
        urgency: AgentUiUpdateUrgency.immediate,
      ),
    );
  }

  AgentConversationMutation _turnStarted(
    AgentTurnStartedEvent event,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(
      context,
      sessionId: event.turn.sessionId,
      turnId: event.turn.id,
    )) {
      return AgentConversationMutation.rejected('currentThreadMismatch');
    }
    _lastShownErrorMessage = null;
    return AgentConversationMutation(
      accepted: true,
      timelineMutations: <AgentTimelineMutation>[
        AgentBeginLiveTurnTimelineMutation(event.turn),
      ],
      stateChanges: const <AgentConversationStateChange>[
        AgentFinalizeTurnStartedChange(),
      ],
      uiUpdate: AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{
          AgentUiRegion.liveTurnBinding,
          AgentUiRegion.liveTurn,
          AgentUiRegion.header,
          AgentUiRegion.composer,
        },
        urgency: AgentUiUpdateUrgency.immediate,
      ),
      threadSnapshot: AgentThreadSnapshotMutation.refresh,
    );
  }

  AgentConversationMutation _turnCompleted(
    AgentTurnCompletedEvent event,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(
      context,
      sessionId: event.sessionId,
      turnId: event.turnId,
    )) {
      return AgentConversationMutation.rejected('currentThreadMismatch');
    }
    final timelineMutations = <AgentTimelineMutation>[];
    final errorMessage = event.errorMessage;
    if (event.status == AgentHistoryTurnStatus.failed &&
        errorMessage != null &&
        errorMessage != _lastShownErrorMessage) {
      _lastShownErrorMessage = errorMessage;
      timelineMutations.add(
        AgentAddConversationMessageTimelineMutation(
          AgentConversationMessageMutationData(
            id: _nextLocalTimelineId('turn-failed'),
            role: AgentMessageRole.system,
            text: AgentProviderErrorPresentation.formatUserVisibleText(
              message: errorMessage,
              code: event.errorCode,
              prefixTurnFailed: true,
            ),
          ),
        ),
      );
    }
    timelineMutations.add(AgentCompleteLiveTurnTimelineMutation(event));
    return AgentConversationMutation(
      accepted: true,
      stateChangesBeforeTimeline: <AgentConversationStateChange>[
        AgentPrepareTurnCompletedChange(event),
      ],
      timelineMutations: timelineMutations,
      stateChanges: <AgentConversationStateChange>[
        AgentFinalizeTurnCompletedChange(event),
      ],
      uiUpdate: AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{
          AgentUiRegion.history,
          AgentUiRegion.liveTurnBinding,
          AgentUiRegion.header,
          AgentUiRegion.composer,
        },
        urgency: AgentUiUpdateUrgency.immediate,
        effects: const <AgentUiEffect>[AgentRequestAutoScroll()],
      ),
      uiResolution: const AgentConversationUiResolution(
        includePendingInteractionWhenStateChanges: true,
      ),
      threadSnapshot: AgentThreadSnapshotMutation.refresh,
      effects: <AgentConversationEffect>[
        AgentTurnCompletedEffect(
          scope: context.effectScope.forTurn(event.turnId),
          turnId: event.turnId,
          attention: AgentAttentionSignal(
            kind: switch (event.status) {
              AgentHistoryTurnStatus.completed =>
                AgentAttentionKind.turnCompleted,
              AgentHistoryTurnStatus.failed => AgentAttentionKind.turnFailed,
              AgentHistoryTurnStatus.interrupted =>
                AgentAttentionKind.turnInterrupted,
              AgentHistoryTurnStatus.running =>
                AgentAttentionKind.turnInterrupted,
              AgentHistoryTurnStatus.unknown =>
                AgentAttentionKind.turnInterrupted,
            },
            phase: AgentAttentionPhase.raised,
            sourceId: event.turnId,
            threadId: event.sessionId,
            turnId: event.turnId,
          ),
        ),
      ],
    );
  }

  AgentConversationMutation _tokenUsage(
    AgentTokenUsageEvent event,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(
      context,
      sessionId: event.sessionId,
      turnId: event.turnId,
    )) {
      return AgentConversationMutation.rejected('currentThreadMismatch');
    }
    final usageTurnId = event.turnId;
    final usageOnHistory =
        usageTurnId != null && context.isHistoryTurnId(usageTurnId);
    return AgentConversationMutation(
      accepted: true,
      timelineMutations: <AgentTimelineMutation>[
        AgentUpdateTurnTokenUsageTimelineMutation(event),
      ],
      uiUpdate: AgentUiUpdateRequest(
        regions: <AgentUiRegion>{
          AgentUiRegion.header,
          AgentUiRegion.composer,
          if (usageOnHistory) AgentUiRegion.history,
          if (!usageOnHistory) AgentUiRegion.liveTurn,
        },
        urgency: AgentUiUpdateUrgency.immediate,
      ),
    );
  }

  AgentConversationMutation _contextUsage(
    AgentContextWindowUsageEvent event,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(
      context,
      sessionId: event.sessionId,
      turnId: event.turnId,
    )) {
      return AgentConversationMutation.rejected('currentThreadMismatch');
    }
    return AgentConversationMutation(
      accepted: true,
      timelineMutations: <AgentTimelineMutation>[
        AgentUpdateContextWindowUsageTimelineMutation(event),
      ],
      uiUpdate: AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{
          AgentUiRegion.liveTurn,
          AgentUiRegion.composer,
        },
        urgency: AgentUiUpdateUrgency.nextFrame,
      ),
    );
  }

  AgentConversationMutation _messageDelta(
    AgentMessageDeltaEvent event,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(
      context,
      sessionId: event.sessionId,
      turnId: event.turnId,
    )) {
      return AgentConversationMutation.rejected('currentThreadMismatch');
    }
    return AgentConversationMutation(
      accepted: true,
      timelineMutations: <AgentTimelineMutation>[
        AgentAppendMessageDeltaTimelineMutation(event),
      ],
      uiUpdate: AgentUiUpdateRequest(
        regions: <AgentUiRegion>{
          AgentUiRegion.liveTurn,
          if (event.kind == AgentMessageKind.plan) AgentUiRegion.expansion,
        },
        urgency: AgentUiUpdateUrgency.nextFrame,
        effects: const <AgentUiEffect>[AgentRequestAutoScroll()],
      ),
      uiResolution: const AgentConversationUiResolution(
        includeHeaderWhenActivityChanges: true,
      ),
    );
  }

  AgentConversationMutation _reasoningDelta(
    AgentReasoningDeltaEvent event,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(
      context,
      sessionId: event.sessionId,
      turnId: event.turnId,
    )) {
      return AgentConversationMutation.rejected('currentThreadMismatch');
    }
    return AgentConversationMutation(
      accepted: true,
      timelineMutations: <AgentTimelineMutation>[
        AgentAppendReasoningDeltaTimelineMutation(event),
      ],
      uiUpdate: AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{
          AgentUiRegion.liveTurn,
          AgentUiRegion.expansion,
        },
        urgency: AgentUiUpdateUrgency.nextFrame,
        effects: const <AgentUiEffect>[AgentRequestAutoScroll()],
      ),
      uiResolution: const AgentConversationUiResolution(
        includeHeaderWhenActivityChanges: true,
      ),
    );
  }

  AgentConversationMutation _messageUpdated(
    AgentMessageUpdatedEvent event,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(
      context,
      sessionId: event.sessionId,
      turnId: event.turnId,
    )) {
      return AgentConversationMutation.rejected('currentThreadMismatch');
    }
    return AgentConversationMutation(
      accepted: true,
      timelineMutations: <AgentTimelineMutation>[
        AgentUpdateMessageTimelineMutation(event),
      ],
      uiUpdate: AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{AgentUiRegion.liveTurn},
        urgency: AgentUiUpdateUrgency.immediate,
        effects: const <AgentUiEffect>[AgentRequestAutoScroll()],
      ),
    );
  }

  AgentConversationMutation _planUpdated(
    AgentPlanUpdatedEvent event,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(
      context,
      sessionId: event.sessionId,
      turnId: event.turnId,
    )) {
      return AgentConversationMutation.rejected('currentThreadMismatch');
    }
    return AgentConversationMutation(
      accepted: true,
      timelineMutations: <AgentTimelineMutation>[
        AgentReplaceActivePlanTimelineMutation(event),
      ],
      uiUpdate: AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{AgentUiRegion.liveTurn},
        urgency: AgentUiUpdateUrgency.immediate,
      ),
    );
  }

  AgentConversationMutation _turnDiff(
    AgentTurnDiffEvent event,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(
      context,
      sessionId: event.sessionId,
      turnId: event.turnId,
    )) {
      return AgentConversationMutation.rejected('currentThreadMismatch');
    }
    return AgentConversationMutation(
      accepted: true,
      timelineMutations: <AgentTimelineMutation>[
        AgentUpsertTurnDiffTimelineMutation(event),
      ],
      uiUpdate: AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{AgentUiRegion.liveTurn},
        urgency: AgentUiUpdateUrgency.immediate,
        effects: const <AgentUiEffect>[AgentRequestAutoScroll()],
      ),
    );
  }

  AgentConversationMutation _toolCall(
    AgentToolCallEvent event,
    AgentConversationReducerContext context,
  ) {
    final toolCall = event.toolCall;
    if (!_shouldHandleCurrent(
      context,
      sessionId: toolCall.sessionId,
      turnId: toolCall.turnId,
    )) {
      return AgentConversationMutation.rejected('currentThreadMismatch');
    }
    final isActive =
        toolCall.status == AgentToolStatus.inProgress ||
        toolCall.status == AgentToolStatus.pending;
    return AgentConversationMutation(
      accepted: true,
      timelineMutations: <AgentTimelineMutation>[
        AgentUpsertToolCallTimelineMutation(toolCall),
      ],
      stateChanges: isActive
          ? <AgentConversationStateChange>[AgentApplyToolStatusChange(toolCall)]
          : const <AgentConversationStateChange>[],
      uiUpdate: AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{AgentUiRegion.liveTurn},
        urgency: isActive
            ? AgentUiUpdateUrgency.nextFrame
            : AgentUiUpdateUrgency.immediate,
        effects: const <AgentUiEffect>[AgentRequestAutoScroll()],
      ),
      uiResolution: const AgentConversationUiResolution(
        includeHeaderWhenActivityChanges: true,
      ),
    );
  }

  AgentConversationMutation _permissionRequested(
    AgentPermissionRequestedEvent event,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(
      context,
      sessionId: event.request.sessionId,
      turnId: event.request.turnId,
    )) {
      return AgentConversationMutation.rejected('currentThreadMismatch');
    }
    return _pendingInteraction(
      AgentAddPermissionRequestTimelineMutation(event.request),
      effect: AgentAttentionEffect(
        scope: context.effectScope.forTurn(event.request.turnId),
        signal: AgentAttentionSignal(
          kind: AgentAttentionKind.permissionRequired,
          phase: AgentAttentionPhase.raised,
          sourceId: event.request.id,
          threadId: event.request.sessionId,
          turnId: event.request.turnId,
        ),
      ),
    );
  }

  AgentConversationMutation _permissionResolved(
    AgentPermissionResolvedEvent event,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(context, sessionId: event.threadId)) {
      return AgentConversationMutation.rejected('currentThreadMismatch');
    }
    return _pendingInteraction(
      AgentRemovePermissionRequestTimelineMutation(event.requestId),
      effect: AgentAttentionEffect(
        scope: context.effectScope,
        signal: AgentAttentionSignal(
          kind: AgentAttentionKind.permissionRequired,
          phase: AgentAttentionPhase.resolved,
          sourceId: event.requestId,
          threadId: event.threadId,
        ),
      ),
    );
  }

  AgentConversationMutation _questionRequested(
    AgentQuestionRequestedEvent event,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(
      context,
      sessionId: event.request.sessionId,
      turnId: event.request.turnId,
    )) {
      return AgentConversationMutation.rejected('currentThreadMismatch');
    }
    return _pendingInteraction(
      AgentAddQuestionRequestTimelineMutation(event.request),
      effect: AgentAttentionEffect(
        scope: context.effectScope.forTurn(event.request.turnId),
        signal: AgentAttentionSignal(
          kind: AgentAttentionKind.questionRequired,
          phase: AgentAttentionPhase.raised,
          sourceId: event.request.id,
          threadId: event.request.sessionId,
          turnId: event.request.turnId,
        ),
      ),
    );
  }

  AgentConversationMutation _questionResolved(
    AgentQuestionResolvedEvent event,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(context, sessionId: event.threadId)) {
      return AgentConversationMutation.rejected('currentThreadMismatch');
    }
    return _pendingInteraction(
      AgentRemoveQuestionRequestTimelineMutation(event.requestId),
      effect: AgentAttentionEffect(
        scope: context.effectScope,
        signal: AgentAttentionSignal(
          kind: AgentAttentionKind.questionRequired,
          phase: AgentAttentionPhase.resolved,
          sourceId: event.requestId,
          threadId: event.threadId,
        ),
      ),
    );
  }

  AgentConversationMutation _planApprovalRequested(
    AgentPlanApprovalRequestedEvent event,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(
      context,
      sessionId: event.request.sessionId,
      turnId: event.request.turnId,
    )) {
      return AgentConversationMutation.rejected('currentThreadMismatch');
    }
    return _pendingInteraction(
      AgentAddPlanApprovalRequestTimelineMutation(event.request),
      effect: AgentAttentionEffect(
        scope: context.effectScope.forTurn(event.request.turnId),
        signal: AgentAttentionSignal(
          kind: AgentAttentionKind.planApprovalRequired,
          phase: AgentAttentionPhase.raised,
          sourceId: event.request.id,
          threadId: event.request.sessionId,
          turnId: event.request.turnId,
        ),
      ),
    );
  }

  AgentConversationMutation _planApprovalResolved(
    AgentPlanApprovalResolvedEvent event,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(context, sessionId: event.sessionId)) {
      return AgentConversationMutation.rejected('currentThreadMismatch');
    }
    return _pendingInteraction(
      AgentRemovePlanApprovalRequestTimelineMutation(event.requestId),
      effect: AgentAttentionEffect(
        scope: context.effectScope,
        signal: AgentAttentionSignal(
          kind: AgentAttentionKind.planApprovalRequired,
          phase: AgentAttentionPhase.resolved,
          sourceId: event.requestId,
          threadId: event.sessionId,
        ),
      ),
    );
  }

  AgentConversationMutation _pendingInteraction(
    AgentTimelineMutation timelineMutation, {
    AgentConversationEffect? effect,
  }) {
    return AgentConversationMutation(
      accepted: true,
      timelineMutations: <AgentTimelineMutation>[timelineMutation],
      uiUpdate: AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{
          AgentUiRegion.liveTurn,
          AgentUiRegion.pendingInteraction,
        },
        urgency: AgentUiUpdateUrgency.immediate,
      ),
      effects: <AgentConversationEffect>[?effect],
    );
  }

  AgentConversationMutation _modelRerouted(
    AgentModelReroutedEvent event,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(
      context,
      sessionId: event.threadId,
      turnId: event.turnId,
    )) {
      return AgentConversationMutation.rejected('currentThreadMismatch');
    }
    return AgentConversationMutation(
      accepted: true,
      stateChanges: <AgentConversationStateChange>[
        AgentSetModelRerouteNoticeChange('已改道至 ${event.toModel}'),
      ],
      timelineMutations: <AgentTimelineMutation>[
        AgentAddHistoryEventTimelineMutation(
          AgentHistoryEventEntry(
            id: _nextLocalTimelineId('model-reroute'),
            kind: AgentHistoryEventKind.system,
            title: '模型已改道',
            description: '${event.fromModel} → ${event.toModel}',
            content: _modelRerouteReasonLabel(event.reason),
            raw: event.raw,
          ),
        ),
      ],
      uiUpdate: AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{
          AgentUiRegion.liveTurn,
          AgentUiRegion.header,
        },
        urgency: AgentUiUpdateUrgency.immediate,
        effects: const <AgentUiEffect>[AgentRequestAutoScroll()],
      ),
    );
  }

  AgentConversationMutation _deprecation(AgentDeprecationNoticeEvent event) {
    if (!_shownDeprecationSummaries.add(event.summary)) {
      return AgentConversationMutation.rejected('duplicateDeprecation');
    }
    return AgentConversationMutation(
      accepted: true,
      timelineMutations: <AgentTimelineMutation>[
        AgentAddHistoryEventTimelineMutation(
          AgentHistoryEventEntry(
            id: _nextLocalTimelineId('deprecation'),
            kind: AgentHistoryEventKind.warning,
            title: '适配层弃用提示',
            description: event.summary,
            content: event.details == null
                ? '请升级 Codex 适配层以继续兼容协议变更。'
                : '${event.details}\n请升级 Codex 适配层以继续兼容协议变更。',
            raw: event.raw,
          ),
        ),
      ],
      uiUpdate: AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{AgentUiRegion.liveTurn},
        urgency: AgentUiUpdateUrgency.immediate,
        effects: const <AgentUiEffect>[AgentRequestAutoScroll()],
      ),
    );
  }

  AgentConversationMutation _systemItem(
    AgentSystemItemEvent event,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(
      context,
      sessionId: event.sessionId,
      turnId: event.turnId,
    )) {
      return AgentConversationMutation.rejected('currentThreadMismatch');
    }
    final rawType = event.entry.raw['type']?.toString();
    final completesCompaction =
        (event.entry.title.contains('压缩') ||
            event.entry.kind == AgentHistoryEventKind.system) &&
        (rawType == 'contextCompaction' ||
            event.entry.title.contains('上下文已压缩'));
    return AgentConversationMutation(
      accepted: true,
      stateChanges: completesCompaction
          ? const <AgentConversationStateChange>[
              AgentSetCompactingChange(false),
            ]
          : const <AgentConversationStateChange>[],
      timelineMutations: <AgentTimelineMutation>[
        AgentAddHistoryEventTimelineMutation(event.entry),
      ],
      uiUpdate: AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{
          AgentUiRegion.liveTurn,
          AgentUiRegion.header,
          AgentUiRegion.composer,
        },
        urgency: AgentUiUpdateUrgency.immediate,
        effects: const <AgentUiEffect>[AgentRequestAutoScroll()],
      ),
    );
  }

  AgentConversationMutation _modelList(
    AgentModelListEvent event,
    AgentConversationReducerContext context,
  ) {
    return AgentConversationMutation(
      accepted: true,
      stateChanges: <AgentConversationStateChange>[
        AgentHandleModelListChange(event.models),
      ],
      uiUpdate: AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{AgentUiRegion.composer},
        urgency: AgentUiUpdateUrgency.immediate,
      ),
      effects: context.modelsRefreshing
          ? const <AgentConversationEffect>[]
          : <AgentConversationEffect>[
              AgentRecordModelCatalogEffect(
                scope: context.effectScope,
                config: context.activeProviderConfig,
                models: event.models,
                source: '${context.activeProviderName} runtime',
              ),
            ],
    );
  }

  AgentConversationMutation _error(
    AgentErrorEvent event,
    AgentConversationReducerContext context,
  ) {
    final logEffect = AgentLogProviderErrorEffect(
      scope: context.effectScope.forTurn(event.turnId),
      event: event,
    );
    if (!_shouldHandleCurrent(
      context,
      sessionId: event.sessionId,
      turnId: event.turnId,
    )) {
      return AgentConversationMutation.rejected(
        'currentThreadMismatch',
        effects: <AgentConversationEffect>[logEffect],
      );
    }
    _lastShownErrorMessage = event.message;
    return AgentConversationMutation(
      accepted: true,
      timelineMutations: <AgentTimelineMutation>[
        AgentAddConversationMessageTimelineMutation(
          AgentConversationMessageMutationData(
            id: _nextLocalTimelineId('error'),
            role: AgentMessageRole.system,
            text: _errorMessageText(event),
          ),
        ),
      ],
      uiUpdate: AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{
          AgentUiRegion.history,
          AgentUiRegion.liveTurn,
          AgentUiRegion.header,
        },
        urgency: AgentUiUpdateUrgency.immediate,
        effects: const <AgentUiEffect>[AgentRequestAutoScroll()],
      ),
      effects: <AgentConversationEffect>[logEffect],
    );
  }

  bool _shouldHandleCurrent(
    AgentConversationReducerContext context, {
    String? sessionId,
    String? turnId,
  }) {
    if (sessionId != null) {
      // 保持现有语义：有 sessionId 时不再加强 turnId 校验。
      return context.selectedThreadId == sessionId;
    }
    if (turnId != null) {
      return context.hasTurn(turnId) || turnId == context.pendingTurnGroupId;
    }
    return true;
  }

  String _nextLocalTimelineId(String prefix) {
    return _timelineIds.next(prefix);
  }

  String _modelRerouteReasonLabel(String reason) {
    return switch (reason) {
      'highRiskCyberActivity' => '原因：高风险网络活动策略',
      _ => '原因：$reason',
    };
  }

  String _errorMessageText(AgentErrorEvent event) {
    return AgentProviderErrorPresentation.formatUserVisibleText(
      message: event.message,
      details: event.details,
      code: event.code,
      willRetry: event.willRetry,
    );
  }
}

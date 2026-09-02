import 'package:zeta_agent_core/src/application/agent_conversation_effect.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_mutation.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_session_state.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_timeline_store.dart';
import 'package:zeta_agent_core/src/application/agent_ui_update_request.dart';
import 'package:zeta_agent_core/src/domain/agent_models.dart';
import 'package:zeta_agent_core/src/domain/fallback_agent_ui_text_catalog.dart';

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
  factory AgentConversationReducerContexts({
    AgentConversationClock? clock,
    AgentConversationLocalTimelineIdGenerator? liveTimelineIds,
    AgentUiTextCatalog textCatalog = const FallbackAgentUiTextCatalog(),
  }) {
    return AgentConversationReducerContexts._(
      clock,
      liveTimelineIds,
      textCatalog,
    );
  }

  AgentConversationReducerContexts._(
    this._clock,
    this._liveTimelineIds,
    this._textCatalog,
  );

  final AgentConversationClock? _clock;
  final AgentConversationLocalTimelineIdGenerator? _liveTimelineIds;
  final AgentUiTextCatalog _textCatalog;

  /// 生产路径唯一消费者。
  late final AgentConversationReducer live = AgentConversationReducer.live(
    clock: _clock,
    timelineIds: _liveTimelineIds,
    textCatalog: _textCatalog,
  );

  /// 历史加载路径预留；当前仅测试消费（G3 隔离守卫）。
  late final AgentConversationReducer history =
      AgentConversationReducer.history(
        clock: _clock,
        textCatalog: _textCatalog,
      );

  /// 回放路径预留；当前仅测试消费（G3 隔离守卫）。
  late final AgentConversationReducer replay = AgentConversationReducer.replay(
    clock: _clock,
    textCatalog: _textCatalog,
  );
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
    required this.hasRunningTurnExcluding,
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

  /// 排除指定 turn 后，是否仍有 running turn。
  ///
  /// 供 turn 终态归约判断"这一回合结束后会话是否仍在运行"，
  /// 避免 reducer 依赖 timeline mutation 的应用顺序。
  final bool Function(String excludedTurnId) hasRunningTurnExcluding;
  final bool modelsRefreshing;
  final String activeProviderName;
  final AgentProviderConfig activeProviderConfig;
  final AgentConversationEffectScope effectScope;
}

/// 将规范化 [AgentEvent] 纯同步归约为 nextState/timeline/UI/snapshot/effect 描述。
///
/// reducer 返回 [AgentConversationSessionState]，不访问 Flutter scheduler，
/// 不创建 Timer，也不执行 Future。副作用一律走 EffectRunner。每个 live、
/// history、replay consumer 必须创建独立实例。
final class AgentConversationReducer {
  AgentConversationReducer._({
    required this.scope,
    required this.textCatalog,
    AgentConversationClock? clock,
    AgentConversationLocalTimelineIdGenerator? timelineIds,
  }) : _timelineIds =
           timelineIds ??
           AgentConversationLocalTimelineIdGenerator(clock: clock);

  factory AgentConversationReducer.live({
    AgentConversationClock? clock,
    AgentConversationLocalTimelineIdGenerator? timelineIds,
    AgentUiTextCatalog textCatalog = const FallbackAgentUiTextCatalog(),
  }) {
    return AgentConversationReducer._(
      scope: AgentConversationReductionScope.live,
      clock: clock,
      timelineIds: timelineIds,
      textCatalog: textCatalog,
    );
  }

  factory AgentConversationReducer.history({
    AgentConversationClock? clock,
    AgentUiTextCatalog textCatalog = const FallbackAgentUiTextCatalog(),
  }) {
    return AgentConversationReducer._(
      scope: AgentConversationReductionScope.history,
      clock: clock,
      textCatalog: textCatalog,
    );
  }

  factory AgentConversationReducer.replay({
    AgentConversationClock? clock,
    AgentUiTextCatalog textCatalog = const FallbackAgentUiTextCatalog(),
  }) {
    return AgentConversationReducer._(
      scope: AgentConversationReductionScope.replay,
      clock: clock,
      textCatalog: textCatalog,
    );
  }

  final AgentConversationReductionScope scope;

  /// 步骤 11 贯通注入；步骤 12 起消费 Zeta 自有 context-free 文案。
  final AgentUiTextCatalog textCatalog;
  final AgentConversationLocalTimelineIdGenerator _timelineIds;
  final Set<String> _shownDeprecationSummaries = <String>{};
  String? _lastShownErrorMessage;

  AgentConversationReduction reduce(
    AgentEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
  ) {
    assert(
      context.scope == scope,
      'Reducer 与 context 的 live/history/replay scope 必须一致。',
    );
    return switch (event) {
      AgentStatusEvent() => _status(event, state),
      AgentSessionStartedEvent() => _sessionStarted(event, state, context),
      AgentThreadStatusChangedEvent() => _threadStatus(event, state, context),
      AgentThreadNameUpdatedEvent() => _threadName(event, state, context),
      AgentThreadPreviewUpdatedEvent() => _threadPreview(event, state, context),
      AgentThreadArchivedEvent() => _noOp(state),
      AgentThreadUnarchivedEvent() => _noOp(state),
      AgentThreadDeletedEvent() => _noOp(state),
      AgentThreadClosedEvent() => _threadClosed(event, state, context),
      AgentThreadCompactedEvent() => _threadCompacted(event, state, context),
      AgentThreadSettingsUpdatedEvent() => _threadSettings(
        event,
        state,
        context,
      ),
      AgentAutoApprovalReviewEvent() => _autoApprovalReview(
        event,
        state,
        context,
      ),
      AgentTurnStartedEvent() => _turnStarted(event, state, context),
      AgentTurnCompletedEvent() => _turnCompleted(event, state, context),
      AgentTokenUsageEvent() => _tokenUsage(event, state, context),
      AgentContextWindowUsageEvent() => _contextUsage(event, state, context),
      AgentMessageDeltaEvent() => _messageDelta(event, state, context),
      AgentReasoningDeltaEvent() => _reasoningDelta(event, state, context),
      AgentMessageUpdatedEvent() => _messageUpdated(event, state, context),
      AgentPlanUpdatedEvent() => _planUpdated(event, state, context),
      AgentSessionConfigUpdatedEvent() => _sessionConfig(event, state, context),
      AgentConversationModeUpdatedEvent() => _conversationModeUpdated(
        event,
        state,
        context,
      ),
      AgentPlanApprovalRequestedEvent() => _planApprovalRequested(
        event,
        state,
        context,
      ),
      AgentPlanApprovalResolvedEvent() => _planApprovalResolved(
        event,
        state,
        context,
      ),
      AgentTurnFileChangesEvent() => _turnFileChanges(event, state, context),
      AgentToolCallEvent() => _toolCall(event, state, context),
      AgentPermissionRequestedEvent() => _permissionRequested(
        event,
        state,
        context,
      ),
      AgentPermissionResolvedEvent() => _permissionResolved(
        event,
        state,
        context,
      ),
      AgentQuestionRequestedEvent() => _questionRequested(
        event,
        state,
        context,
      ),
      AgentQuestionResolvedEvent() => _questionResolved(event, state, context),
      AgentModelReroutedEvent() => _modelRerouted(event, state, context),
      AgentDeprecationNoticeEvent() => _deprecation(event, state),
      AgentSystemItemEvent() => _systemItem(event, state, context),
      AgentErrorEvent() => _error(event, state, context),
      AgentModelListEvent() => _modelList(event, state, context),
    };
  }

  /// Provider stream onDone 与 thread/closed 共用的中断收尾 mutation。
  AgentConversationReduction settleInterruptedTurn({
    required String fallbackTurnId,
    required AgentConversationSessionState state,
    required AgentConversationReducerContext context,
  }) {
    return _accept(
      state.copyWith(
        threadRuntimeStatus: null,
        threadWaitingOnApproval: false,
        threadWaitingOnUserInput: false,
      ),
      timelineMutations: <AgentTimelineMutation>[
        AgentSettleInterruptedTimelineMutation(fallbackTurnId),
      ],
      effects: <AgentConversationEffect>[
        AgentClearPlanHandoffEffect(scope: context.effectScope),
        AgentSyncTurnRunningEffect(scope: context.effectScope),
      ],
      threadSnapshot: AgentThreadSnapshotMutation.refresh,
    );
  }

  AgentConversationReduction _status(
    AgentStatusEvent event,
    AgentConversationSessionState state,
  ) {
    return _accept(
      state.copyWith(status: event.status),
      // 空 immediate request 仍可吸收并冲刷已有的 next-frame pending。
    );
  }

  AgentConversationReduction _sessionStarted(
    AgentSessionStartedEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
  ) {
    final selectedThreadId = context.selectedThreadId;
    final accepted = selectedThreadId != null
        ? selectedThreadId == event.session.id
        : !context.requiresResumedSelectedThread;
    if (!accepted) {
      return _rejected(state, 'sessionStartedThreadMismatch');
    }
    var next = state.copyWith(
      session: event.session,
      restoredSessionId: event.session.id,
      threadOpenPhase: AgentThreadOpenPhase.idle,
      requiresResumedSelectedThread: false,
    );
    next = _adoptSessionTitle(next, event.session);
    return _accept(
      next,
      effects: <AgentConversationEffect>[
        if (state.session?.id != event.session.id)
          AgentBindConversationModeThreadEffect(
            scope: context.effectScope,
            threadId: event.session.id,
          ),
      ],
      threadSnapshot: AgentThreadSnapshotMutation.refresh,
    );
  }

  AgentConversationReduction _threadStatus(
    AgentThreadStatusChangedEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(context, sessionId: event.threadId)) {
      return _rejected(state, 'currentThreadMismatch');
    }
    return _accept(
      _withThreadRuntimeStatus(
        state,
        status: event.status,
        waitingOnApproval: event.waitingOnApproval,
        waitingOnUserInput: event.waitingOnUserInput,
      ),
      threadSnapshot: AgentThreadSnapshotMutation.refresh,
    );
  }

  AgentConversationReduction _threadName(
    AgentThreadNameUpdatedEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(context, sessionId: event.threadId)) {
      return _rejected(state, 'currentThreadMismatch');
    }
    final name = event.threadName?.trim();
    return _accept(
      name != null && name.isNotEmpty ? _withThreadTitle(state, name) : state,
      threadSnapshot: AgentThreadSnapshotMutation.refresh,
    );
  }

  AgentConversationReduction _threadPreview(
    AgentThreadPreviewUpdatedEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(context, sessionId: event.threadId)) {
      return _rejected(state, 'currentThreadMismatch');
    }
    return _accept(
      state.copyWith(currentThreadPreview: event.preview),
      // 旁文案只影响列表 snapshot；仍发一次 UI publish，以便延帧刷新 snapshot。
      threadSnapshot: AgentThreadSnapshotMutation.refresh,
    );
  }

  AgentConversationReduction _noOp(AgentConversationSessionState state) {
    return _accept(state, urgency: null);
  }

  AgentConversationReduction _threadClosed(
    AgentThreadClosedEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(context, sessionId: event.threadId)) {
      return _rejected(state, 'currentThreadMismatch');
    }
    return settleInterruptedTurn(
      fallbackTurnId: 'closed',
      state: state,
      context: context,
    );
  }

  AgentConversationReduction _threadCompacted(
    AgentThreadCompactedEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(context, sessionId: event.threadId)) {
      return _rejected(state, 'currentThreadMismatch');
    }
    return _accept(state, urgency: null);
  }

  AgentConversationReduction _threadSettings(
    AgentThreadSettingsUpdatedEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
  ) {
    final permissionSelection = event.permissionSelection;
    final isCurrent = _shouldHandleCurrent(context, sessionId: event.threadId);
    if (!isCurrent && permissionSelection == null) {
      return _rejected(state, 'currentThreadMismatch');
    }
    return _accept(
      state,
      effects: <AgentConversationEffect>[
        if (permissionSelection != null)
          AgentApplyThreadPermissionEffect(
            scope: context.effectScope,
            threadId: event.threadId,
            permissionSelection: permissionSelection,
          ),
        if (isCurrent)
          AgentApplyThreadSettingsEffect(
            scope: context.effectScope,
            event: event,
          ),
      ],
      urgency: isCurrent ? AgentUiUpdateUrgency.immediate : null,
    );
  }

  AgentConversationReduction _sessionConfig(
    AgentSessionConfigUpdatedEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(context, sessionId: event.sessionId)) {
      return _rejected(state, 'currentThreadMismatch');
    }
    return _accept(
      state.copyWith(sessionConfigOptions: event.options),
      effects: <AgentConversationEffect>[
        AgentSyncThreadSelectionEffect(
          scope: context.effectScope,
          options: event.options,
        ),
      ],
    );
  }

  AgentConversationReduction _conversationModeUpdated(
    AgentConversationModeUpdatedEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(context, sessionId: event.sessionId)) {
      return _rejected(state, 'currentThreadMismatch');
    }
    return _accept(
      state,
      effects: <AgentConversationEffect>[
        AgentApplyServerConversationModeEffect(
          scope: context.effectScope,
          event: event,
        ),
      ],
    );
  }

  AgentConversationReduction _autoApprovalReview(
    AgentAutoApprovalReviewEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(
      context,
      sessionId: event.threadId,
      turnId: event.turnId,
    )) {
      return _rejected(state, 'currentThreadMismatch');
    }
    return _accept(_withAutoReview(state, event));
  }

  AgentConversationReduction _turnStarted(
    AgentTurnStartedEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(
      context,
      sessionId: event.turn.sessionId,
      turnId: event.turn.id,
    )) {
      return _rejected(state, 'currentThreadMismatch');
    }
    _lastShownErrorMessage = null;
    return _accept(
      state,
      timelineMutations: <AgentTimelineMutation>[
        AgentBeginLiveTurnTimelineMutation(event.turn),
      ],
      effects: <AgentConversationEffect>[
        AgentSyncTurnRunningEffect(
          scope: context.effectScope.forTurn(event.turn.id),
          forceRunning: true,
        ),
      ],
      threadSnapshot: AgentThreadSnapshotMutation.refresh,
    );
  }

  AgentConversationReduction _turnCompleted(
    AgentTurnCompletedEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(
      context,
      sessionId: event.sessionId,
      turnId: event.turnId,
    )) {
      return _rejected(state, 'currentThreadMismatch');
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
              catalog: textCatalog,
              code: event.errorCode,
              prefixTurnFailed: true,
            ),
          ),
        ),
      );
    }
    timelineMutations.add(AgentCompleteLiveTurnTimelineMutation(event));
    final turnScope = context.effectScope.forTurn(event.turnId);
    return _accept(
      _finalizeTurnCompleted(state, event, context),
      timelineMutations: timelineMutations,
      effects: <AgentConversationEffect>[
        AgentPreparePlanHandoffEffect(scope: turnScope, event: event),
        AgentTurnCompletedEffect(
          scope: turnScope,
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
        AgentSyncTurnRunningEffect(scope: turnScope),
        AgentAutoStartPlanExecutionEffect(scope: turnScope),
      ],
      uiEffects: const <AgentUiEffect>[AgentRequestAutoScroll()],
      threadSnapshot: AgentThreadSnapshotMutation.refresh,
    );
  }

  AgentConversationReduction _tokenUsage(
    AgentTokenUsageEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(
      context,
      sessionId: event.sessionId,
      turnId: event.turnId,
    )) {
      return _rejected(state, 'currentThreadMismatch');
    }
    return _accept(
      state,
      timelineMutations: <AgentTimelineMutation>[
        AgentUpdateTurnTokenUsageTimelineMutation(event),
      ],
    );
  }

  AgentConversationReduction _contextUsage(
    AgentContextWindowUsageEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(
      context,
      sessionId: event.sessionId,
      turnId: event.turnId,
    )) {
      return _rejected(state, 'currentThreadMismatch');
    }
    return _accept(
      state,
      timelineMutations: <AgentTimelineMutation>[
        AgentUpdateContextWindowUsageTimelineMutation(event),
      ],
      urgency: AgentUiUpdateUrgency.nextFrame,
    );
  }

  AgentConversationReduction _messageDelta(
    AgentMessageDeltaEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(
      context,
      sessionId: event.sessionId,
      turnId: event.turnId,
    )) {
      return _rejected(state, 'currentThreadMismatch');
    }
    return _accept(
      state,
      timelineMutations: <AgentTimelineMutation>[
        AgentAppendMessageDeltaTimelineMutation(event),
      ],
      urgency: AgentUiUpdateUrgency.nextFrame,
      uiEffects: const <AgentUiEffect>[AgentRequestAutoScroll()],
    );
  }

  AgentConversationReduction _reasoningDelta(
    AgentReasoningDeltaEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(
      context,
      sessionId: event.sessionId,
      turnId: event.turnId,
    )) {
      return _rejected(state, 'currentThreadMismatch');
    }
    return _accept(
      state,
      timelineMutations: <AgentTimelineMutation>[
        AgentAppendReasoningDeltaTimelineMutation(event),
      ],
      urgency: AgentUiUpdateUrgency.nextFrame,
      uiEffects: const <AgentUiEffect>[AgentRequestAutoScroll()],
    );
  }

  AgentConversationReduction _messageUpdated(
    AgentMessageUpdatedEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(
      context,
      sessionId: event.sessionId,
      turnId: event.turnId,
    )) {
      return _rejected(state, 'currentThreadMismatch');
    }
    return _accept(
      state,
      timelineMutations: <AgentTimelineMutation>[
        AgentUpdateMessageTimelineMutation(event),
      ],
      uiEffects: const <AgentUiEffect>[AgentRequestAutoScroll()],
    );
  }

  AgentConversationReduction _planUpdated(
    AgentPlanUpdatedEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(
      context,
      sessionId: event.sessionId,
      turnId: event.turnId,
    )) {
      return _rejected(state, 'currentThreadMismatch');
    }
    return _accept(
      state,
      timelineMutations: <AgentTimelineMutation>[
        AgentReplaceActivePlanTimelineMutation(event),
      ],
    );
  }

  AgentConversationReduction _turnFileChanges(
    AgentTurnFileChangesEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(
      context,
      sessionId: event.sessionId,
      turnId: event.turnId,
    )) {
      return _rejected(state, 'currentThreadMismatch');
    }
    return _accept(
      state,
      timelineMutations: <AgentTimelineMutation>[
        AgentUpsertTurnFileChangesTimelineMutation(event),
      ],
      uiEffects: const <AgentUiEffect>[AgentRequestAutoScroll()],
    );
  }

  AgentConversationReduction _toolCall(
    AgentToolCallEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
  ) {
    final toolCall = event.toolCall;
    if (!_shouldHandleCurrent(
      context,
      sessionId: toolCall.sessionId,
      turnId: toolCall.turnId,
    )) {
      return _rejected(state, 'currentThreadMismatch');
    }
    final isActive =
        toolCall.status == AgentToolStatus.inProgress ||
        toolCall.status == AgentToolStatus.pending;
    var next = state;
    if (isActive) {
      final title = toolCall.displayTitle(textCatalog).trim();
      if (title.isNotEmpty) {
        next = next.copyWith(
          status: AgentProviderStatus(
            state: AgentProviderConnectionState.running,
            message: title.length > 80 ? '${title.substring(0, 80)}…' : title,
          ),
        );
      }
    }
    return _accept(
      next,
      timelineMutations: <AgentTimelineMutation>[
        AgentUpsertToolCallTimelineMutation(toolCall),
      ],
      urgency: isActive
          ? AgentUiUpdateUrgency.nextFrame
          : AgentUiUpdateUrgency.immediate,
      uiEffects: const <AgentUiEffect>[AgentRequestAutoScroll()],
    );
  }

  AgentConversationReduction _permissionRequested(
    AgentPermissionRequestedEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(
      context,
      sessionId: event.request.sessionId,
      turnId: event.request.turnId,
    )) {
      return _rejected(state, 'currentThreadMismatch');
    }
    return _pendingInteraction(
      state,
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

  AgentConversationReduction _permissionResolved(
    AgentPermissionResolvedEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(context, sessionId: event.threadId)) {
      return _rejected(state, 'currentThreadMismatch');
    }
    return _pendingInteraction(
      state,
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

  AgentConversationReduction _questionRequested(
    AgentQuestionRequestedEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(
      context,
      sessionId: event.request.sessionId,
      turnId: event.request.turnId,
    )) {
      return _rejected(state, 'currentThreadMismatch');
    }
    return _pendingInteraction(
      state,
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

  AgentConversationReduction _questionResolved(
    AgentQuestionResolvedEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(context, sessionId: event.threadId)) {
      return _rejected(state, 'currentThreadMismatch');
    }
    return _pendingInteraction(
      state,
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

  AgentConversationReduction _planApprovalRequested(
    AgentPlanApprovalRequestedEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(
      context,
      sessionId: event.request.sessionId,
      turnId: event.request.turnId,
    )) {
      return _rejected(state, 'currentThreadMismatch');
    }
    return _pendingInteraction(
      state,
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

  AgentConversationReduction _planApprovalResolved(
    AgentPlanApprovalResolvedEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(context, sessionId: event.sessionId)) {
      return _rejected(state, 'currentThreadMismatch');
    }
    return _pendingInteraction(
      state,
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

  AgentConversationReduction _pendingInteraction(
    AgentConversationSessionState state,
    AgentTimelineMutation timelineMutation, {
    AgentConversationEffect? effect,
  }) {
    return _accept(
      state,
      timelineMutations: <AgentTimelineMutation>[timelineMutation],
      effects: <AgentConversationEffect>[?effect],
    );
  }

  AgentConversationReduction _modelRerouted(
    AgentModelReroutedEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(
      context,
      sessionId: event.threadId,
      turnId: event.turnId,
    )) {
      return _rejected(state, 'currentThreadMismatch');
    }
    return _accept(
      state.copyWith(
        modelRerouteNotice: textCatalog.modelReroutedNotice(event.toModel),
      ),
      timelineMutations: <AgentTimelineMutation>[
        AgentAddHistoryEventTimelineMutation(
          AgentHistoryEventEntry(
            id: _nextLocalTimelineId('model-reroute'),
            kind: AgentHistoryEventKind.system,
            title: textCatalog.modelReroutedTitle,
            description: '${event.fromModel} → ${event.toModel}',
            content: _modelRerouteReasonLabel(event.reason),
          ),
        ),
      ],
      uiEffects: const <AgentUiEffect>[AgentRequestAutoScroll()],
    );
  }

  AgentConversationReduction _deprecation(
    AgentDeprecationNoticeEvent event,
    AgentConversationSessionState state,
  ) {
    if (!_shownDeprecationSummaries.add(event.summary)) {
      return _rejected(state, 'duplicateDeprecation');
    }
    return _accept(
      state,
      timelineMutations: <AgentTimelineMutation>[
        AgentAddHistoryEventTimelineMutation(
          AgentHistoryEventEntry(
            id: _nextLocalTimelineId('deprecation'),
            kind: AgentHistoryEventKind.warning,
            title: textCatalog.deprecationNoticeTitle,
            description: event.summary,
            content: event.details == null
                ? textCatalog.deprecationUpgradeHint
                : '${event.details}\n${textCatalog.deprecationUpgradeHint}',
          ),
        ),
      ],
      uiEffects: const <AgentUiEffect>[AgentRequestAutoScroll()],
    );
  }

  AgentConversationReduction _systemItem(
    AgentSystemItemEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
  ) {
    if (!_shouldHandleCurrent(
      context,
      sessionId: event.sessionId,
      turnId: event.turnId,
    )) {
      return _rejected(state, 'currentThreadMismatch');
    }
    return _accept(
      state,
      timelineMutations: <AgentTimelineMutation>[
        AgentAddHistoryEventTimelineMutation(event.entry),
      ],
      uiEffects: const <AgentUiEffect>[AgentRequestAutoScroll()],
    );
  }

  AgentConversationReduction _modelList(
    AgentModelListEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
  ) {
    return _accept(
      state,
      effects: <AgentConversationEffect>[
        AgentApplyModelListEffect(
          scope: context.effectScope,
          models: event.models,
        ),
        if (!context.modelsRefreshing)
          AgentRecordModelCatalogEffect(
            scope: context.effectScope,
            config: context.activeProviderConfig,
            models: event.models,
            source: '${context.activeProviderName} runtime',
          ),
      ],
    );
  }

  AgentConversationReduction _error(
    AgentErrorEvent event,
    AgentConversationSessionState state,
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
      return _rejected(
        state,
        'currentThreadMismatch',
        effects: <AgentConversationEffect>[logEffect],
      );
    }
    _lastShownErrorMessage = event.message;
    return _accept(
      state,
      timelineMutations: <AgentTimelineMutation>[
        AgentAddConversationMessageTimelineMutation(
          AgentConversationMessageMutationData(
            id: _nextLocalTimelineId('error'),
            role: AgentMessageRole.system,
            text: _errorMessageText(event),
          ),
        ),
      ],
      uiEffects: const <AgentUiEffect>[AgentRequestAutoScroll()],
      effects: <AgentConversationEffect>[logEffect],
    );
  }

  AgentConversationReduction _accept(
    AgentConversationSessionState state, {
    Iterable<AgentTimelineMutation> timelineMutations =
        const <AgentTimelineMutation>[],
    Iterable<AgentConversationEffect> effects =
        const <AgentConversationEffect>[],
    AgentUiUpdateUrgency? urgency = AgentUiUpdateUrgency.immediate,
    Iterable<AgentUiEffect> uiEffects = const <AgentUiEffect>[],
    AgentThreadSnapshotMutation? threadSnapshot,
  }) {
    return AgentConversationReduction(
      accepted: true,
      state: state,
      timelineMutations: timelineMutations,
      effects: effects,
      urgency: urgency,
      uiEffects: uiEffects,
      threadSnapshot: threadSnapshot,
    );
  }

  AgentConversationReduction _rejected(
    AgentConversationSessionState state,
    String reason, {
    Iterable<AgentConversationEffect> effects =
        const <AgentConversationEffect>[],
  }) {
    return AgentConversationReduction.rejected(reason, state, effects: effects);
  }

  AgentConversationSessionState _adoptSessionTitle(
    AgentConversationSessionState state,
    AgentSession session,
  ) {
    final title = session.title?.trim();
    if (isAgentThreadTitlePlaceholder(title)) {
      return state;
    }
    if (!isAgentThreadTitlePlaceholder(state.currentThreadTitle)) {
      return state;
    }
    return _withThreadTitle(state, title!);
  }

  AgentConversationSessionState _withThreadTitle(
    AgentConversationSessionState state,
    String title,
  ) {
    final session = state.session;
    return state.copyWith(
      currentThreadTitle: title,
      session: session == null
          ? null
          : AgentSession(
              id: session.id,
              providerId: session.providerId,
              title: title,
            ),
    );
  }

  AgentConversationSessionState _withThreadRuntimeStatus(
    AgentConversationSessionState state, {
    required AgentThreadRuntimeStatus status,
    required bool waitingOnApproval,
    required bool waitingOnUserInput,
  }) {
    final isActive = status == AgentThreadRuntimeStatus.active;
    return state.copyWith(
      threadRuntimeStatus: status,
      threadWaitingOnApproval: isActive && waitingOnApproval,
      threadWaitingOnUserInput: isActive && waitingOnUserInput,
    );
  }

  AgentConversationSessionState _withAutoReview(
    AgentConversationSessionState state,
    AgentAutoApprovalReviewEvent event,
  ) {
    final reviews = Map<String, AgentAutoApprovalReviewEvent>.of(
      state.autoReviewsByTurnId,
    );
    reviews[event.turnId] = event;
    var latest = state.latestDeniedAutoReview;
    if (event.status == 'denied') {
      latest = event;
    } else if (event.status == 'approved' &&
        latest?.reviewId == event.reviewId) {
      latest = null;
    }
    return state.copyWith(
      autoReviewsByTurnId: reviews,
      latestDeniedAutoReview: latest,
    );
  }

  AgentConversationSessionState _finalizeTurnCompleted(
    AgentConversationSessionState state,
    AgentTurnCompletedEvent event,
    AgentConversationReducerContext context,
  ) {
    final willBeRunning = context.hasRunningTurnExcluding(event.turnId);
    var next = state.copyWith(modelRerouteNotice: null);
    if (!willBeRunning &&
        state.status.state == AgentProviderConnectionState.running) {
      next = next.copyWith(
        status: AgentProviderStatus(
          state: AgentProviderConnectionState.ready,
          message: textCatalog.providerReady(context.activeProviderName),
        ),
      );
    }
    if (!willBeRunning &&
        state.threadRuntimeStatus == AgentThreadRuntimeStatus.active) {
      next = next.copyWith(
        threadRuntimeStatus: AgentThreadRuntimeStatus.idle,
        threadWaitingOnApproval: false,
        threadWaitingOnUserInput: false,
      );
    }
    return next;
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
      'highRiskCyberActivity' => textCatalog.rerouteReasonHighRisk,
      _ => textCatalog.rerouteReasonUnknown(reason),
    };
  }

  String _errorMessageText(AgentErrorEvent event) {
    return AgentProviderErrorPresentation.formatUserVisibleText(
      message: event.message,
      catalog: textCatalog,
      details: event.details,
      code: event.code,
      willRetry: event.willRetry,
    );
  }
}

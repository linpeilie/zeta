import 'package:zeta_agent_core/src/application/agent_conversation_effect.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_session_state.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_timeline_store.dart';
import 'package:zeta_agent_core/src/application/agent_ui_update_request.dart';
import 'package:zeta_agent_core/src/domain/agent_models.dart';
import 'package:zeta_agent_core/src/domain/agent_provider_raw_payload.dart';

/// TimelineStore 执行的高性能增量 mutation。
///
/// 这些对象只描述数据变化，不携带 UI urgency，也不根据 Provider 类型分支。
sealed class AgentTimelineMutation {
  const AgentTimelineMutation({this.trackActivityChange = false});

  /// mutation 后是否读取并清除 Store 的 activity dirty 标志。
  final bool trackActivityChange;

  /// 把本次变化应用到 Store。
  ///
  /// **只允许 [AgentConversationEventProcessor] 调用。**
  /// reducer 内调用即违反 G3（reducer 必须纯同步、不得触碰 Store）。
  /// 守卫：`agent_reducer_purity_guard_test.dart`。
  void applyTo(AgentConversationTimelineStore store);
}

final class AgentBeginLiveTurnTimelineMutation extends AgentTimelineMutation {
  const AgentBeginLiveTurnTimelineMutation(this.turn);

  final AgentTurn turn;

  @override
  void applyTo(AgentConversationTimelineStore store) =>
      store.beginLiveTurnGroup(turn);
}

final class AgentCompleteLiveTurnTimelineMutation
    extends AgentTimelineMutation {
  const AgentCompleteLiveTurnTimelineMutation(this.event);

  final AgentTurnCompletedEvent event;

  @override
  void applyTo(AgentConversationTimelineStore store) =>
      store.completeLiveTurnGroup(
        event.turnId,
        status: event.status,
        duration: event.duration,
      );
}

final class AgentSettleInterruptedTimelineMutation
    extends AgentTimelineMutation {
  const AgentSettleInterruptedTimelineMutation(this.fallbackTurnId);

  final String fallbackTurnId;

  @override
  void applyTo(AgentConversationTimelineStore store) {
    if (!store.isTurnRunning) {
      return;
    }
    store.completeLiveTurnGroup(
      store.selectedRunningTurnId ?? fallbackTurnId,
      status: AgentHistoryTurnStatus.interrupted,
    );
  }
}

/// 新增会话消息所需的纯 Dart 白名单字段。
final class AgentConversationMessageMutationData {
  const AgentConversationMessageMutationData({
    required this.id,
    required this.role,
    required this.text,
    this.sourceMessageId,
    this.kind = AgentMessageKind.regular,
    this.phase,
    this.status,
    this.duration,
    this.localImagePaths = const <String>[],
    this.raw = const AgentProviderRawPayload.empty(),
  });

  final String id;
  final String? sourceMessageId;
  final AgentMessageRole role;
  final String text;
  final AgentMessageKind kind;
  final AgentMessagePhase? phase;
  final AgentMessageStatus? status;
  final Duration? duration;
  final List<String> localImagePaths;
  final AgentProviderRawPayload raw;
}

final class AgentAddConversationMessageTimelineMutation
    extends AgentTimelineMutation {
  const AgentAddConversationMessageTimelineMutation(this.message);

  final AgentConversationMessageMutationData message;

  @override
  void applyTo(AgentConversationTimelineStore store) {
    // 白名单字段逐个搬运，禁止直接透传对象。
    // addConversationMessage 返回 entryId；与原 processor 实现一致丢弃返回值。
    store.addConversationMessage(
      AgentConversationMessage(
        id: message.id,
        sourceMessageId: message.sourceMessageId,
        role: message.role,
        text: message.text,
        kind: message.kind,
        phase: message.phase,
        status: message.status,
        duration: message.duration,
        localImagePaths: message.localImagePaths,
        raw: message.raw,
      ),
    );
  }
}

final class AgentAddHistoryEventTimelineMutation extends AgentTimelineMutation {
  const AgentAddHistoryEventTimelineMutation(this.event);

  final AgentHistoryEventEntry event;

  @override
  void applyTo(AgentConversationTimelineStore store) =>
      store.addHistoryEvent(event);
}

final class AgentUpdateTurnTokenUsageTimelineMutation
    extends AgentTimelineMutation {
  const AgentUpdateTurnTokenUsageTimelineMutation(this.event);

  final AgentTokenUsageEvent event;

  @override
  void applyTo(AgentConversationTimelineStore store) =>
      store.updateTurnTokenUsage(event);
}

final class AgentUpdateContextWindowUsageTimelineMutation
    extends AgentTimelineMutation {
  const AgentUpdateContextWindowUsageTimelineMutation(this.event);

  final AgentContextWindowUsageEvent event;

  @override
  void applyTo(AgentConversationTimelineStore store) =>
      store.updateContextWindowUsage(event);
}

final class AgentAppendMessageDeltaTimelineMutation
    extends AgentTimelineMutation {
  const AgentAppendMessageDeltaTimelineMutation(this.event)
    : super(trackActivityChange: true);

  final AgentMessageDeltaEvent event;

  @override
  void applyTo(AgentConversationTimelineStore store) =>
      store.appendMessageDelta(event);
}

final class AgentAppendReasoningDeltaTimelineMutation
    extends AgentTimelineMutation {
  const AgentAppendReasoningDeltaTimelineMutation(this.event)
    : super(trackActivityChange: true);

  final AgentReasoningDeltaEvent event;

  @override
  void applyTo(AgentConversationTimelineStore store) =>
      store.appendReasoningDelta(event);
}

final class AgentUpdateMessageTimelineMutation extends AgentTimelineMutation {
  const AgentUpdateMessageTimelineMutation(this.event);

  final AgentMessageUpdatedEvent event;

  @override
  void applyTo(AgentConversationTimelineStore store) =>
      store.updateMessage(event);
}

final class AgentReplaceActivePlanTimelineMutation
    extends AgentTimelineMutation {
  const AgentReplaceActivePlanTimelineMutation(this.event);

  final AgentPlanUpdatedEvent event;

  @override
  void applyTo(AgentConversationTimelineStore store) =>
      store.replaceActivePlan(event);
}

/// 原位写入或清除回合级中立文件变更快照。
final class AgentUpsertTurnFileChangesTimelineMutation
    extends AgentTimelineMutation {
  const AgentUpsertTurnFileChangesTimelineMutation(this.event);

  final AgentTurnFileChangesEvent event;

  @override
  void applyTo(AgentConversationTimelineStore store) =>
      store.upsertTurnFileChanges(event);
}

final class AgentUpsertToolCallTimelineMutation extends AgentTimelineMutation {
  const AgentUpsertToolCallTimelineMutation(this.toolCall)
    : super(trackActivityChange: true);

  final AgentToolCall toolCall;

  @override
  void applyTo(AgentConversationTimelineStore store) =>
      store.upsertToolCall(toolCall);
}

final class AgentAddPermissionRequestTimelineMutation
    extends AgentTimelineMutation {
  const AgentAddPermissionRequestTimelineMutation(this.request);

  final AgentPermissionRequest request;

  @override
  void applyTo(AgentConversationTimelineStore store) =>
      store.addPermissionRequest(request);
}

final class AgentRemovePermissionRequestTimelineMutation
    extends AgentTimelineMutation {
  const AgentRemovePermissionRequestTimelineMutation(this.requestId);

  final String requestId;

  @override
  void applyTo(AgentConversationTimelineStore store) =>
      store.removePermissionRequest(requestId);
}

final class AgentAddQuestionRequestTimelineMutation
    extends AgentTimelineMutation {
  const AgentAddQuestionRequestTimelineMutation(this.request);

  final AgentQuestionRequest request;

  @override
  void applyTo(AgentConversationTimelineStore store) =>
      store.addQuestionRequest(request);
}

final class AgentRemoveQuestionRequestTimelineMutation
    extends AgentTimelineMutation {
  const AgentRemoveQuestionRequestTimelineMutation(this.requestId);

  final String requestId;

  @override
  void applyTo(AgentConversationTimelineStore store) =>
      store.removeQuestionRequest(requestId);
}

final class AgentAddPlanApprovalRequestTimelineMutation
    extends AgentTimelineMutation {
  const AgentAddPlanApprovalRequestTimelineMutation(this.request);

  final AgentPlanApprovalRequest request;

  @override
  void applyTo(AgentConversationTimelineStore store) =>
      store.addPlanApprovalRequest(request);
}

final class AgentRemovePlanApprovalRequestTimelineMutation
    extends AgentTimelineMutation {
  const AgentRemovePlanApprovalRequestTimelineMutation(this.requestId);

  final String requestId;

  @override
  void applyTo(AgentConversationTimelineStore store) =>
      store.removePlanApprovalRequest(requestId);
}

/// Timeline/state outcome 参与最终 UI request 合成的规则。
final class AgentConversationUiResolution {
  const AgentConversationUiResolution({
    this.includeHeaderWhenActivityChanges = false,
    this.includePendingInteractionWhenStateChanges = false,
  });

  final bool includeHeaderWhenActivityChanges;
  final bool includePendingInteractionWhenStateChanges;
}

/// ThreadSnapshot 的独立刷新请求。
enum AgentThreadSnapshotMutation { refresh }

/// 一次 AgentEvent 的完整同步 reduction 结果。
final class AgentConversationReduction {
  AgentConversationReduction({
    required this.accepted,
    required this.state,
    this.rejectionReason,
    Iterable<AgentTimelineMutation> timelineMutations =
        const <AgentTimelineMutation>[],
    Iterable<AgentConversationEffect> effects =
        const <AgentConversationEffect>[],
    this.urgency = AgentUiUpdateUrgency.nextFrame,
    Iterable<AgentUiEffect> uiEffects = const <AgentUiEffect>[],
    this.uiRegions,
    this.uiResolution = const AgentConversationUiResolution(),
    this.threadSnapshot,
  }) : timelineMutations = List<AgentTimelineMutation>.unmodifiable(
         timelineMutations,
       ),
       effects = List<AgentConversationEffect>.unmodifiable(effects),
       uiEffects = List<AgentUiEffect>.unmodifiable(uiEffects);

  factory AgentConversationReduction.rejected(
    String reason,
    AgentConversationSessionState state, {
    Iterable<AgentConversationEffect> effects =
        const <AgentConversationEffect>[],
  }) {
    return AgentConversationReduction(
      accepted: false,
      state: state,
      rejectionReason: reason,
      effects: effects,
    );
  }

  final bool accepted;
  final AgentConversationSessionState state;
  final String? rejectionReason;
  final List<AgentTimelineMutation> timelineMutations;
  final List<AgentConversationEffect> effects;
  final AgentUiUpdateUrgency urgency;
  final List<AgentUiEffect> uiEffects;

  /// null 表示该 case 完全不发布 UI；空集合与 null 不同，可冲刷 pending。
  final Set<AgentUiRegion>? uiRegions;
  final AgentConversationUiResolution uiResolution;
  final AgentThreadSnapshotMutation? threadSnapshot;

  /// 由 [uiRegions] / [urgency] / [uiEffects] 合成；null 表示不发布。
  AgentUiUpdateRequest? get uiUpdate {
    final regions = uiRegions;
    if (regions == null) {
      return null;
    }
    return AgentUiUpdateRequest(
      regions: regions,
      urgency: urgency,
      effects: uiEffects,
    );
  }
}

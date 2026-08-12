import 'package:zeta/src/features/agent/application/agent_conversation_effect.dart';
import 'package:zeta/src/features/agent/application/agent_ui_update_request.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// reducer 产生的类型化会话状态变化。
sealed class AgentConversationStateChange {
  const AgentConversationStateChange();
}

final class AgentSetProviderStatusChange extends AgentConversationStateChange {
  const AgentSetProviderStatusChange(this.status);

  final AgentProviderStatus status;
}

final class AgentApplySessionStartedChange
    extends AgentConversationStateChange {
  const AgentApplySessionStartedChange(this.session);

  final AgentSession session;
}

final class AgentApplyThreadRuntimeStatusChange
    extends AgentConversationStateChange {
  const AgentApplyThreadRuntimeStatusChange({
    required this.status,
    required this.waitingOnApproval,
    required this.waitingOnUserInput,
  });

  final AgentThreadRuntimeStatus status;
  final bool waitingOnApproval;
  final bool waitingOnUserInput;
}

final class AgentApplyThreadNameChange extends AgentConversationStateChange {
  const AgentApplyThreadNameChange(this.threadName);

  final String? threadName;
}

/// 回写 thread 列表旁文案（preview），不改正式标题。
final class AgentApplyThreadPreviewChange extends AgentConversationStateChange {
  const AgentApplyThreadPreviewChange(this.preview);

  final String preview;
}

final class AgentApplyThreadSettingsChange
    extends AgentConversationStateChange {
  const AgentApplyThreadSettingsChange(this.event);

  final AgentThreadSettingsUpdatedEvent event;
}

/// 将服务端 settings 中已中立化的权限事实写入事件所属 thread。
///
/// 此变化不要求该 thread 是当前 Canvas，也不触发 provider apply。
final class AgentApplyThreadPermissionSettingsChange
    extends AgentConversationStateChange {
  const AgentApplyThreadPermissionSettingsChange({
    required this.threadId,
    required this.permissionSelection,
  });

  final String threadId;
  final AgentPermissionSelection permissionSelection;
}

final class AgentApplySessionConfigChange extends AgentConversationStateChange {
  const AgentApplySessionConfigChange(this.options);

  final List<AgentSessionConfigOption> options;
}

final class AgentApplyConversationModeChange
    extends AgentConversationStateChange {
  const AgentApplyConversationModeChange(this.event);

  final AgentConversationModeUpdatedEvent event;
}

final class AgentApplyAutoApprovalReviewChange
    extends AgentConversationStateChange {
  const AgentApplyAutoApprovalReviewChange(this.event);

  final AgentAutoApprovalReviewEvent event;
}

/// 在 live plan 被归档前生成本地执行交接。
final class AgentPrepareTurnCompletedChange
    extends AgentConversationStateChange {
  const AgentPrepareTurnCompletedChange(this.event);

  final AgentTurnCompletedEvent event;
}

final class AgentFinalizeTurnStartedChange
    extends AgentConversationStateChange {
  const AgentFinalizeTurnStartedChange();
}

final class AgentFinalizeTurnCompletedChange
    extends AgentConversationStateChange {
  const AgentFinalizeTurnCompletedChange(this.event);

  final AgentTurnCompletedEvent event;
}

/// 清理 runtime/waiting 与本地 plan handoff，再收尾中断 turn。
final class AgentPrepareInterruptedTurnChange
    extends AgentConversationStateChange {
  const AgentPrepareInterruptedTurnChange();
}

final class AgentFinalizeInterruptedTurnChange
    extends AgentConversationStateChange {
  const AgentFinalizeInterruptedTurnChange();
}

final class AgentApplyToolStatusChange extends AgentConversationStateChange {
  const AgentApplyToolStatusChange(this.toolCall);

  final AgentToolCall toolCall;
}

final class AgentSetModelRerouteNoticeChange
    extends AgentConversationStateChange {
  const AgentSetModelRerouteNoticeChange(this.notice);

  final String? notice;
}

final class AgentHandleModelListChange extends AgentConversationStateChange {
  const AgentHandleModelListChange(this.models);

  final AgentModelList models;
}

/// TimelineStore 执行的高性能增量 mutation。
///
/// 这些对象只描述数据变化，不携带 UI urgency，也不根据 Provider 类型分支。
sealed class AgentTimelineMutation {
  const AgentTimelineMutation({this.trackActivityChange = false});

  /// mutation 后是否读取并清除 Store 的 activity dirty 标志。
  final bool trackActivityChange;
}

final class AgentBeginLiveTurnTimelineMutation extends AgentTimelineMutation {
  const AgentBeginLiveTurnTimelineMutation(this.turn);

  final AgentTurn turn;
}

final class AgentCompleteLiveTurnTimelineMutation
    extends AgentTimelineMutation {
  const AgentCompleteLiveTurnTimelineMutation(this.event);

  final AgentTurnCompletedEvent event;
}

final class AgentSettleInterruptedTimelineMutation
    extends AgentTimelineMutation {
  const AgentSettleInterruptedTimelineMutation(this.fallbackTurnId);

  final String fallbackTurnId;
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
    this.raw = const <String, Object?>{},
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
  final Map<String, Object?> raw;
}

final class AgentAddConversationMessageTimelineMutation
    extends AgentTimelineMutation {
  const AgentAddConversationMessageTimelineMutation(this.message);

  final AgentConversationMessageMutationData message;
}

final class AgentAddHistoryEventTimelineMutation extends AgentTimelineMutation {
  const AgentAddHistoryEventTimelineMutation(this.event);

  final AgentHistoryEventEntry event;
}

final class AgentUpdateTurnTokenUsageTimelineMutation
    extends AgentTimelineMutation {
  const AgentUpdateTurnTokenUsageTimelineMutation(this.event);

  final AgentTokenUsageEvent event;
}

final class AgentUpdateContextWindowUsageTimelineMutation
    extends AgentTimelineMutation {
  const AgentUpdateContextWindowUsageTimelineMutation(this.event);

  final AgentContextWindowUsageEvent event;
}

final class AgentAppendMessageDeltaTimelineMutation
    extends AgentTimelineMutation {
  const AgentAppendMessageDeltaTimelineMutation(this.event)
    : super(trackActivityChange: true);

  final AgentMessageDeltaEvent event;
}

final class AgentAppendReasoningDeltaTimelineMutation
    extends AgentTimelineMutation {
  const AgentAppendReasoningDeltaTimelineMutation(this.event)
    : super(trackActivityChange: true);

  final AgentReasoningDeltaEvent event;
}

final class AgentUpdateMessageTimelineMutation extends AgentTimelineMutation {
  const AgentUpdateMessageTimelineMutation(this.event);

  final AgentMessageUpdatedEvent event;
}

final class AgentReplaceActivePlanTimelineMutation
    extends AgentTimelineMutation {
  const AgentReplaceActivePlanTimelineMutation(this.event);

  final AgentPlanUpdatedEvent event;
}

/// 原位写入或清除回合级中立文件变更快照。
final class AgentUpsertTurnFileChangesTimelineMutation
    extends AgentTimelineMutation {
  const AgentUpsertTurnFileChangesTimelineMutation(this.event);

  final AgentTurnFileChangesEvent event;
}

final class AgentUpsertToolCallTimelineMutation extends AgentTimelineMutation {
  const AgentUpsertToolCallTimelineMutation(this.toolCall)
    : super(trackActivityChange: true);

  final AgentToolCall toolCall;
}

final class AgentAddPermissionRequestTimelineMutation
    extends AgentTimelineMutation {
  const AgentAddPermissionRequestTimelineMutation(this.request);

  final AgentPermissionRequest request;
}

final class AgentRemovePermissionRequestTimelineMutation
    extends AgentTimelineMutation {
  const AgentRemovePermissionRequestTimelineMutation(this.requestId);

  final String requestId;
}

final class AgentAddQuestionRequestTimelineMutation
    extends AgentTimelineMutation {
  const AgentAddQuestionRequestTimelineMutation(this.request);

  final AgentQuestionRequest request;
}

final class AgentRemoveQuestionRequestTimelineMutation
    extends AgentTimelineMutation {
  const AgentRemoveQuestionRequestTimelineMutation(this.requestId);

  final String requestId;
}

final class AgentAddPlanApprovalRequestTimelineMutation
    extends AgentTimelineMutation {
  const AgentAddPlanApprovalRequestTimelineMutation(this.request);

  final AgentPlanApprovalRequest request;
}

final class AgentRemovePlanApprovalRequestTimelineMutation
    extends AgentTimelineMutation {
  const AgentRemovePlanApprovalRequestTimelineMutation(this.requestId);

  final String requestId;
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
final class AgentConversationMutation {
  AgentConversationMutation({
    required this.accepted,
    this.rejectionReason,
    Iterable<AgentConversationStateChange> stateChangesBeforeTimeline =
        const <AgentConversationStateChange>[],
    Iterable<AgentTimelineMutation> timelineMutations =
        const <AgentTimelineMutation>[],
    Iterable<AgentConversationStateChange> stateChanges =
        const <AgentConversationStateChange>[],
    this.uiUpdate,
    this.uiResolution = const AgentConversationUiResolution(),
    this.threadSnapshot,
    Iterable<AgentConversationEffect> effects =
        const <AgentConversationEffect>[],
  }) : stateChangesBeforeTimeline =
           List<AgentConversationStateChange>.unmodifiable(
             stateChangesBeforeTimeline,
           ),
       timelineMutations = List<AgentTimelineMutation>.unmodifiable(
         timelineMutations,
       ),
       stateChanges = List<AgentConversationStateChange>.unmodifiable(
         stateChanges,
       ),
       effects = List<AgentConversationEffect>.unmodifiable(effects);

  factory AgentConversationMutation.rejected(
    String reason, {
    Iterable<AgentConversationEffect> effects =
        const <AgentConversationEffect>[],
  }) {
    return AgentConversationMutation(
      accepted: false,
      rejectionReason: reason,
      effects: effects,
    );
  }

  final bool accepted;
  final String? rejectionReason;
  final List<AgentConversationStateChange> stateChangesBeforeTimeline;
  final List<AgentTimelineMutation> timelineMutations;
  final List<AgentConversationStateChange> stateChanges;

  /// null 表示该 case 完全不发布 UI；空 request 与 null 不同，可冲刷 pending。
  final AgentUiUpdateRequest? uiUpdate;
  final AgentConversationUiResolution uiResolution;
  final AgentThreadSnapshotMutation? threadSnapshot;
  final List<AgentConversationEffect> effects;
}

/// typed state application 的同步结果。
final class AgentConversationStateMutationOutcome {
  const AgentConversationStateMutationOutcome({
    this.pendingInteractionChanged = false,
  });

  static const none = AgentConversationStateMutationOutcome();

  final bool pendingInteractionChanged;

  AgentConversationStateMutationOutcome mergedWith(
    AgentConversationStateMutationOutcome other,
  ) {
    return AgentConversationStateMutationOutcome(
      pendingInteractionChanged:
          pendingInteractionChanged || other.pendingInteractionChanged,
    );
  }
}

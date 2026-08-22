import 'package:zeta/src/features/agent/application/agent_conversation_mode_controller.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_region_state.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_model_config_ui_state.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 五个 region state 的共享测试夹具。
///
/// UI state 测试与 Phase 2 切片测试都要造这几个对象；抄两份迟早会漂移。

AgentHeaderState agentHeaderStateFixture({
  String title = 'Thread',
  AgentTokenUsage? tokenUsage,
}) {
  return AgentHeaderState(
    title: title,
    threadOpenPhase: AgentThreadOpenPhase.idle,
    systemNoticeLabel: null,
    statusCapsuleLabel: null,
    waitingOnApproval: false,
    waitingOnUserInput: false,
    showRunningIndicator: false,
    runningActivityLabel: null,
    segmentStartedAt: null,
    turnStartedAt: null,
    tokenUsage: tokenUsage,
    isTurnRunning: false,
    isReadOnly: false,
    canFork: false,
    canRename: false,
    canArchive: false,
    isPlanMode: false,
  );
}

AgentComposerState agentComposerStateFixture({
  Iterable<AgentConversationModePreset> conversationModes =
      const <AgentConversationModePreset>[],
  Iterable<AgentSessionConfigOption> sessionConfigOptions =
      const <AgentSessionConfigOption>[],
}) {
  return AgentComposerState(
    canSubmitMessage: true,
    isTurnRunning: false,
    threadOpenPhase: AgentThreadOpenPhase.idle,
    contextUsage: null,
    isReadOnly: false,
    canAttachImages: true,
    canMentionResources: true,
    canUseSkills: false,
    conversationModeStatus: AgentConversationModeLoadStatus.ready,
    conversationModeOptions: conversationModes,
    selectedConversationMode: AgentConversationModeId.defaultMode,
    conversationModeAppliesToNextTurn: false,
    conversationModeStatusMessage: null,
    conversationModeContextId: const (providerId: 'provider', threadId: 't'),
    showModelSelection: true,
    modelConfigState: AgentModelConfigUiState(
      models: const <AgentModelInfo>[],
      selectedModelId: null,
      selectedReasoningEffort: null,
      selectedServiceTierId: null,
      preferences: const <String, AgentModelPreference>{},
      savingModelIds: const <String>{},
      isRefreshing: false,
      appliesNextTurn: false,
      supportsReasoningOptions: true,
      supportsServiceTierSelection: true,
    ),
    showPermissionPolicy: true,
    permissionPolicyLabel: 'Workspace write',
    permissionOptions: const <AgentPermissionOption>[
      AgentPermissionOption(
        id: ':workspace',
        label: 'Workspace write',
        description: 'Workspace write',
      ),
    ],
    selectedPermissionOptionId: ':workspace',
    sessionConfigOptions: sessionConfigOptions,
  );
}

AgentPendingInteractionState agentPendingInteractionStateFixture({
  Iterable<AgentPermissionRequest> permissions =
      const <AgentPermissionRequest>[],
}) {
  return AgentPendingInteractionState(
    permissions: permissions,
    questions: const <AgentQuestionRequest>[],
    planApprovals: const <AgentPlanApprovalRequest>[],
    planExecutionHandoff: null,
    isReadOnly: false,
    autoReviewsByTurnId: const <String, AgentAutoApprovalReviewEvent>{},
    latestDeniedAutoReview: null,
  );
}

AgentConversationHistoryState agentConversationHistoryStateFixture({
  List<AgentTimelineEntry> entries = const <AgentTimelineEntry>[],
  int contentRevision = 0,
}) {
  return AgentConversationHistoryState(
    standbyTurn: null,
    visibleTurns: <AgentConversationTurnGroup>[
      AgentConversationTurnGroup(
        id: 'turn-1',
        entries: List<AgentTimelineEntry>.unmodifiable(entries),
        isStandby: false,
        contentRevision: contentRevision,
      ),
    ],
    threadOpenPhase: AgentThreadOpenPhase.idle,
    providerId: 'provider',
    providerKind: AgentProviderKind.codexAppServer,
    providerName: 'Provider',
  );
}

AgentExpansionState agentExpansionStateFixture({
  Iterable<String> toolCallIds = const <String>[],
  Iterable<String> planMessageIds = const <String>[],
  Iterable<String> activePlanTurnIds = const <String>[],
  Iterable<String> commandGroupIds = const <String>[],
  Iterable<String> fileEditItemIds = const <String>[],
}) {
  return AgentExpansionState(
    toolCallIds: toolCallIds,
    planMessageIds: planMessageIds,
    activePlanTurnIds: activePlanTurnIds,
    commandGroupIds: commandGroupIds,
    fileEditItemIds: fileEditItemIds,
  );
}

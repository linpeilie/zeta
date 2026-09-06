import 'package:zeta_agent_core/zeta_agent_core.dart';
import '../agent_command_outcome.dart';
import 'agent_conversation_command_result.dart';
import 'agent_conversation_slice_effect.dart';
import 'agent_conversation_command_scope.dart';
import 'agent_conversation_region_state.dart';

abstract interface class AgentConversationRegionSource {
  AgentConversationHistoryState get historyState;
  AgentHeaderState get headerState;
  AgentComposerState get composerState;
  AgentPendingInteractionState get pendingInteractionState;
  AgentExpansionState get expansionState;

  /// 订阅 scheduler 批处理之后的 UI 更新。
  void addUiUpdateListener(
    void Function(AgentUiUpdateRequest request) listener,
  );

  void removeUiUpdateListener(
    void Function(AgentUiUpdateRequest request) listener,
  );

  /// 当前命令作用域快照；用于命令执行前/回写前的两次换代校验。
  AgentConversationCommandScope currentCommandScope();
}

abstract interface class AgentConversationCommandPort {
  Future<AgentCommandOutcome> sendMessage(
    String text, {
    List<String> localImagePaths = const [],
    List<({String name, String path})> mentions = const [],
    List<AgentSkillRef> skills = const [],
    AgentPermissionRequestSnapshot? permissionSnapshotOverride,
  });
  Future<AgentCommandOutcome> cancelActiveTurn();
  Future<AgentCommandOutcome> editLastUserMessageAndRetry(String newText);
  Future<AgentCommandOutcome> retryOpenThread();
  Future<AgentCommandOutcome> respondToPermission(
    AgentPermissionRequest request, {
    required bool approved,
    bool cancelTurn = false,
    AgentCommandApprovalDecisionKind? commandDecision,
    List<String> execpolicyAmendment = const [],
  });
  Future<AgentCommandOutcome> respondToQuestion(
    AgentQuestionRequest request, {
    Map<String, List<String>> answers = const {},
  });
  Future<AgentCommandOutcome> respondToPlanApproval(
    AgentPlanApprovalRequest request,
    AgentPlanApprovalDecisionKind kind, {
    String? reason,
  });
  Future<AgentCommandOutcome> startPlanExecution(
    AgentPlanExecutionRequest request,
  );
  Future<AgentCommandOutcome> revisePlanExecution(
    AgentPlanExecutionRequest request, {
    String? revisionMessage,
  });
  AgentCommandOutcome dismissPlanExecution(AgentPlanExecutionRequest request);
  AgentCommandOutcome selectPlanExecutionPermissionOption(
    AgentPlanExecutionRequest request,
    AgentPermissionOption option,
  );
  Future<AgentCommandOutcome> approveGuardianDeniedAction();
  Future<AgentForkCommandOutcome> forkCurrentThread();
  Future<AgentCommandOutcome> renameCurrentThread(String name);
  Future<AgentCommandOutcome> archiveCurrentThread();
  Future<AgentCommandOutcome> compactCurrentThread();
  AgentCommandOutcome toggleToolCall(String toolCallId);
  AgentCommandOutcome togglePlanMessage(String messageId);
  AgentCommandOutcome toggleActivePlan(String turnId);
  AgentCommandOutcome toggleCommandGroup(String commandGroupId);
  AgentCommandOutcome toggleFileEditItem(String fileEditItemId);
  Future<AgentCommandOutcome> loadModels({bool forceRefresh = false});
  Future<AgentCommandOutcome> ensureSkillsCatalog();
  Future<AgentCommandOutcome> retryConversationModes();
  AgentCommandOutcome selectConversationMode(AgentConversationModeId modeId);
  Future<AgentCommandOutcome> selectModel(String modelId);
  Future<AgentCommandOutcome> selectReasoningEffort(String? effort);
  Future<AgentCommandOutcome> selectFastEnabled(bool enabled);
  Future<AgentCommandOutcome> resolveModelCompatibilityConflict();
  Future<AgentCommandOutcome> retryModelConfigurationSave();
  AgentCommandOutcome clearModelConfigurationTransientState();
  Future<AgentCommandOutcome> selectPermissionOption(
    AgentPermissionOption option,
  );
  Future<AgentCommandOutcome> retryPermissionPreferencePersistence();
  Future<AgentCommandOutcome> selectSessionConfigOption(
    String configId,
    Object value,
  );
  Future<AgentCommandOutcome> switchActiveProvider(String providerId);
}

abstract interface class AgentConversationSliceEffectRunner {
  void run(AgentConversationSliceEffect effect);
  void close();
}

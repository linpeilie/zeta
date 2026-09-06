import 'package:zeta_agent_core/zeta_agent_core.dart';
import '../agent_command_outcome.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'agent_conversation_command_result.dart';
import 'agent_conversation_owner_key.dart';
import 'agent_conversation_session_dependencies.dart';
import 'agent_conversation_slice_notifier.dart';

/// UI 写入的唯一入口。捕获的句柄永久属于同一个 entry lifetime。
abstract interface class AgentConversationActions {
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
  Future<AgentCommandOutcome> dismissPlanExecution(
    AgentPlanExecutionRequest request,
  );
  Future<AgentCommandOutcome> selectPlanExecutionPermissionOption(
    AgentPlanExecutionRequest request,
    AgentPermissionOption option,
  );
  Future<AgentCommandOutcome> approveGuardianDeniedAction();

  Future<AgentForkCommandOutcome> forkCurrentThread();
  Future<AgentCommandOutcome> renameCurrentThread(String name);
  Future<AgentCommandOutcome> archiveCurrentThread();
  Future<AgentCommandOutcome> compactCurrentThread();

  Future<AgentCommandOutcome> toggleToolCall(String toolCallId);
  Future<AgentCommandOutcome> togglePlanMessage(String messageId);
  Future<AgentCommandOutcome> toggleActivePlan(String turnId);
  Future<AgentCommandOutcome> toggleCommandGroup(String commandGroupId);
  Future<AgentCommandOutcome> toggleFileEditItem(String fileEditItemId);

  Future<AgentCommandOutcome> loadModels({bool forceRefresh = false});
  Future<AgentCommandOutcome> ensureSkillsCatalog();
  Future<AgentCommandOutcome> retryConversationModes();
  Future<AgentCommandOutcome> selectConversationMode(
    AgentConversationModeId modeId,
  );
  Future<AgentCommandOutcome> selectModel(String modelId);
  Future<AgentCommandOutcome> selectReasoningEffort(String? effort);
  Future<AgentCommandOutcome> selectFastEnabled(bool enabled);
  Future<AgentCommandOutcome> resolveModelCompatibilityConflict();
  Future<AgentCommandOutcome> retryModelConfigurationSave();
  Future<AgentCommandOutcome> clearModelConfigurationTransientState();
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

final agentConversationActionsProvider = Provider.autoDispose
    .family<AgentConversationActions, AgentConversationBindingKey>((ref, key) {
      return switch (ref.watch(agentConversationOwnerResolutionProvider(key))) {
        AgentConversationOwnerLive(:final ownerKey) => ref.read(
          agentConversationSliceOwnerProvider(ownerKey).notifier,
        ),
        AgentConversationOwnerClosing() ||
        AgentConversationOwnerClosed() ||
        AgentConversationOwnerUnknown() =>
          const AgentClosedConversationActions(),
      };
    });

/// 终止或未知 alias 不创建 owner 或资源。
final class AgentClosedConversationActions implements AgentConversationActions {
  const AgentClosedConversationActions();
  @override
  Future<AgentCommandOutcome> sendMessage(
    String text, {
    List<String> localImagePaths = const [],
    List<({String name, String path})> mentions = const [],
    List<AgentSkillRef> skills = const [],
    AgentPermissionRequestSnapshot? permissionSnapshotOverride,
  }) => Future.value(
    const AgentCommandOutcome.failed(AgentCommandFailureKind.staleTarget),
  );
  @override
  Future<AgentCommandOutcome> cancelActiveTurn() => Future.value(
    const AgentCommandOutcome.failed(AgentCommandFailureKind.staleTarget),
  );
  @override
  Future<AgentCommandOutcome> editLastUserMessageAndRetry(String newText) =>
      Future.value(
        const AgentCommandOutcome.failed(AgentCommandFailureKind.staleTarget),
      );
  @override
  Future<AgentCommandOutcome> retryOpenThread() => Future.value(
    const AgentCommandOutcome.failed(AgentCommandFailureKind.staleTarget),
  );
  @override
  Future<AgentCommandOutcome> respondToPermission(
    AgentPermissionRequest request, {
    required bool approved,
    bool cancelTurn = false,
    AgentCommandApprovalDecisionKind? commandDecision,
    List<String> execpolicyAmendment = const [],
  }) => Future.value(
    const AgentCommandOutcome.failed(AgentCommandFailureKind.staleTarget),
  );
  @override
  Future<AgentCommandOutcome> respondToQuestion(
    AgentQuestionRequest request, {
    Map<String, List<String>> answers = const {},
  }) => Future.value(
    const AgentCommandOutcome.failed(AgentCommandFailureKind.staleTarget),
  );
  @override
  Future<AgentCommandOutcome> respondToPlanApproval(
    AgentPlanApprovalRequest request,
    AgentPlanApprovalDecisionKind kind, {
    String? reason,
  }) => Future.value(
    const AgentCommandOutcome.failed(AgentCommandFailureKind.staleTarget),
  );
  @override
  Future<AgentCommandOutcome> startPlanExecution(
    AgentPlanExecutionRequest request,
  ) => Future.value(
    const AgentCommandOutcome.failed(AgentCommandFailureKind.staleTarget),
  );
  @override
  Future<AgentCommandOutcome> revisePlanExecution(
    AgentPlanExecutionRequest request, {
    String? revisionMessage,
  }) => Future.value(
    const AgentCommandOutcome.failed(AgentCommandFailureKind.staleTarget),
  );
  @override
  Future<AgentCommandOutcome> dismissPlanExecution(
    AgentPlanExecutionRequest request,
  ) => Future.value(
    const AgentCommandOutcome.failed(AgentCommandFailureKind.staleTarget),
  );
  @override
  Future<AgentCommandOutcome> selectPlanExecutionPermissionOption(
    AgentPlanExecutionRequest request,
    AgentPermissionOption option,
  ) => Future.value(
    const AgentCommandOutcome.failed(AgentCommandFailureKind.staleTarget),
  );
  @override
  Future<AgentCommandOutcome> approveGuardianDeniedAction() => Future.value(
    const AgentCommandOutcome.failed(AgentCommandFailureKind.staleTarget),
  );
  @override
  Future<AgentForkCommandOutcome> forkCurrentThread() => Future.value(
    AgentForkCommandOutcome.failed(AgentCommandFailureKind.staleTarget),
  );
  @override
  Future<AgentCommandOutcome> renameCurrentThread(String name) => Future.value(
    const AgentCommandOutcome.failed(AgentCommandFailureKind.staleTarget),
  );
  @override
  Future<AgentCommandOutcome> archiveCurrentThread() => Future.value(
    const AgentCommandOutcome.failed(AgentCommandFailureKind.staleTarget),
  );
  @override
  Future<AgentCommandOutcome> compactCurrentThread() => Future.value(
    const AgentCommandOutcome.failed(AgentCommandFailureKind.staleTarget),
  );
  @override
  Future<AgentCommandOutcome> toggleToolCall(String toolCallId) => Future.value(
    const AgentCommandOutcome.failed(AgentCommandFailureKind.staleTarget),
  );
  @override
  Future<AgentCommandOutcome> togglePlanMessage(String messageId) =>
      Future.value(
        const AgentCommandOutcome.failed(AgentCommandFailureKind.staleTarget),
      );
  @override
  Future<AgentCommandOutcome> toggleActivePlan(String turnId) => Future.value(
    const AgentCommandOutcome.failed(AgentCommandFailureKind.staleTarget),
  );
  @override
  Future<AgentCommandOutcome> toggleCommandGroup(String commandGroupId) =>
      Future.value(
        const AgentCommandOutcome.failed(AgentCommandFailureKind.staleTarget),
      );
  @override
  Future<AgentCommandOutcome> toggleFileEditItem(String fileEditItemId) =>
      Future.value(
        const AgentCommandOutcome.failed(AgentCommandFailureKind.staleTarget),
      );
  @override
  Future<AgentCommandOutcome> loadModels({bool forceRefresh = false}) =>
      Future.value(
        const AgentCommandOutcome.failed(AgentCommandFailureKind.staleTarget),
      );
  @override
  Future<AgentCommandOutcome> ensureSkillsCatalog() => Future.value(
    const AgentCommandOutcome.failed(AgentCommandFailureKind.staleTarget),
  );
  @override
  Future<AgentCommandOutcome> retryConversationModes() => Future.value(
    const AgentCommandOutcome.failed(AgentCommandFailureKind.staleTarget),
  );
  @override
  Future<AgentCommandOutcome> selectConversationMode(
    AgentConversationModeId modeId,
  ) => Future.value(
    const AgentCommandOutcome.failed(AgentCommandFailureKind.staleTarget),
  );
  @override
  Future<AgentCommandOutcome> selectModel(String modelId) => Future.value(
    const AgentCommandOutcome.failed(AgentCommandFailureKind.staleTarget),
  );
  @override
  Future<AgentCommandOutcome> selectReasoningEffort(String? effort) =>
      Future.value(
        const AgentCommandOutcome.failed(AgentCommandFailureKind.staleTarget),
      );
  @override
  Future<AgentCommandOutcome> selectFastEnabled(bool enabled) => Future.value(
    const AgentCommandOutcome.failed(AgentCommandFailureKind.staleTarget),
  );
  @override
  Future<AgentCommandOutcome> resolveModelCompatibilityConflict() =>
      Future.value(
        const AgentCommandOutcome.failed(AgentCommandFailureKind.staleTarget),
      );
  @override
  Future<AgentCommandOutcome> retryModelConfigurationSave() => Future.value(
    const AgentCommandOutcome.failed(AgentCommandFailureKind.staleTarget),
  );
  @override
  Future<AgentCommandOutcome> clearModelConfigurationTransientState() =>
      Future.value(
        const AgentCommandOutcome.failed(AgentCommandFailureKind.staleTarget),
      );
  @override
  Future<AgentCommandOutcome> selectPermissionOption(
    AgentPermissionOption option,
  ) => Future.value(
    const AgentCommandOutcome.failed(AgentCommandFailureKind.staleTarget),
  );
  @override
  Future<AgentCommandOutcome> retryPermissionPreferencePersistence() =>
      Future.value(
        const AgentCommandOutcome.failed(AgentCommandFailureKind.staleTarget),
      );
  @override
  Future<AgentCommandOutcome> selectSessionConfigOption(
    String configId,
    Object value,
  ) => Future.value(
    const AgentCommandOutcome.failed(AgentCommandFailureKind.staleTarget),
  );
  @override
  Future<AgentCommandOutcome> switchActiveProvider(String providerId) =>
      Future.value(
        const AgentCommandOutcome.failed(AgentCommandFailureKind.staleTarget),
      );
}

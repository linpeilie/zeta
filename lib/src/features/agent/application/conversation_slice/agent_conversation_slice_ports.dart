import 'package:zeta/src/features/agent/application/agent_command_outcome.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_command_scope.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_region_state.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

/// Conversation slice 的 **region 只读来源**。
///
/// 切片只需要"五个 region 的当前值 + 批处理 UI 更新通知 + 当前作用域"，不需要整个
/// runtime controller。把它收成端口之后，SliceStore 与 controller 之间只剩这一条
/// 窄依赖。
///
/// **订阅是纯 Dart 的**：一次 [AgentUiUpdateRequest] 携带 region 集合，SliceStore
/// 据此组装一次 `RegionsRefreshed`。不再按 region 拆成五条 listener——那是
/// UiStateStore 时代一拆一合的中间态。
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

/// Conversation slice 的 **命令执行端口**。
///
/// 切片产出的 effect 描述最终落到这些方法上。**每个方法都必须显式回报结果**
/// （`AgentCommandOutcome`），不允许用"Future 正常结束"推断成功——Agent 的命令
/// 会吞异常、提前 return 或用 `null` 表示失败。
///
/// G5：四种审批语义各自独立成方法，不共享已授权状态。
abstract interface class AgentConversationCommandPort {
  void toggleToolCall(String toolCallId);
  void togglePlanMessage(String messageId);
  void toggleActivePlan(String turnId);
  void toggleCommandGroup(String commandGroupId);
  void toggleFileEditItem(String fileEditItemId);

  void dismissPlanExecution(AgentPlanExecutionRequest request);

  Future<AgentCommandOutcome> sendMessage(
    String text, {
    List<String> localImagePaths,
    List<({String name, String path})> mentions,
    List<AgentSkillRef> skills,
    AgentPermissionRequestSnapshot? permissionSnapshotOverride,
  });

  Future<AgentCommandOutcome> cancelActiveTurn();

  Future<AgentCommandOutcome> editLastUserMessageAndRetry(String newText);

  Future<AgentCommandOutcome> retryOpenThread();

  Future<AgentCommandOutcome> respondToPermission(
    AgentPermissionRequest request, {
    required bool approved,
    bool cancelTurn,
    AgentCommandApprovalDecisionKind? commandDecision,
    List<String> execpolicyAmendment,
  });

  Future<AgentCommandOutcome> respondToQuestion(
    AgentQuestionRequest request, {
    Map<String, List<String>> answers,
  });

  Future<AgentCommandOutcome> respondToPlanApproval(
    AgentPlanApprovalRequest request,
    AgentPlanApprovalDecisionKind kind, {
    String? reason,
  });

  Future<AgentCommandOutcome> revisePlanExecution(
    AgentPlanExecutionRequest request, {
    String? revisionMessage,
  });

  Future<AgentCommandOutcome> startPlanExecution(
    AgentPlanExecutionRequest request,
  );

  Future<AgentCommandOutcome> approveGuardianDeniedAction();

  /// fork 用 `null` 表示失败；调用方必须显式翻译，不得让它冒充成功。
  Future<AgentSession?> forkCurrentThread();

  Future<AgentCommandOutcome> renameCurrentThread(String name);

  Future<AgentCommandOutcome> archiveCurrentThread();

  Future<AgentCommandOutcome> compactCurrentThread();

  Future<AgentCommandOutcome> loadModels({bool forceRefresh});

  Future<AgentCommandOutcome> ensureSkillsCatalog();

  Future<AgentCommandOutcome> retryConversationModes();
}

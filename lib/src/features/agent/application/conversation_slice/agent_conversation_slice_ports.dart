import 'package:zeta/src/features/agent/application/agent_command_outcome.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_command_scope.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_region_state.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

/// Conversation 切片关心的五个 region。
enum AgentConversationSliceRegion {
  header,
  composer,
  pendingInteractions,
  expansion,
  history,
}

/// Conversation slice 的 **region 只读来源**。
///
/// 切片组合只需要"五个 region 的当前值 + 变化通知 + 当前作用域"，不需要整个
/// ViewModel。把它收成端口之后，组合层与 ViewModel 之间只剩这一条窄依赖。
///
/// **订阅是纯 Dart 的**，不暴露 Flutter `ValueListenable`：
/// 一来 application 层禁止 import Flutter（G6 / 目标架构 §12.5）；
/// 二来 presentation 的 region 订阅必须统一走 `AgentRegionBuilder`，
/// 一个对外暴露裸 listenable 的端口会给 UI 开第二条直连路径。
abstract interface class AgentConversationRegionSource {
  AgentConversationHistoryState get historyState;
  AgentHeaderState get headerState;
  AgentComposerState get composerState;
  AgentPendingInteractionState get pendingInteractionState;
  AgentExpansionState get expansionState;

  /// 订阅某个 region 的变化通知。
  void addRegionListener(
    AgentConversationSliceRegion region,
    void Function() listener,
  );

  void removeRegionListener(
    AgentConversationSliceRegion region,
    void Function() listener,
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

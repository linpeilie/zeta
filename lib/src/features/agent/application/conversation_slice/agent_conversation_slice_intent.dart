import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_state.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_command_scope.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_region_state.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

/// Agent Conversation 切片的意图。
///
/// 命名按 Phase 1 §3：变体用**发生的事**命名，不用 `SetXxx`。意图分三族：
///
/// 1. **ingress**：presentation 的 region 发布流进切片；
/// 2. **command**：用户动作，reducer 只登记在途身份并产出 effect 描述；
/// 3. **result**：effect 完成后回写状态的唯一通道。
sealed class AgentConversationSliceIntent {
  const AgentConversationSliceIntent();
}

// ---------------------------------------------------------------------------
// 1. ingress
// ---------------------------------------------------------------------------

/// 同一帧内变化的 region 合并成一次切片转移。
///
/// 每个字段为 null 表示"该 region 本帧没变"，据此避免无谓的对象重建。
final class AgentConversationRegionsRefreshed
    extends AgentConversationSliceIntent {
  const AgentConversationRegionsRefreshed({
    this.header,
    this.composer,
    this.pendingInteractions,
    this.expansion,
    this.history,
  });

  final AgentHeaderState? header;
  final AgentComposerState? composer;
  final AgentPendingInteractionState? pendingInteractions;
  final AgentExpansionState? expansion;
  final AgentConversationHistoryState? history;

  /// 本次是否没有任何 region 变化。
  bool get isEmpty =>
      header == null &&
      composer == null &&
      pendingInteractions == null &&
      expansion == null &&
      history == null;
}

// ---------------------------------------------------------------------------
// 2. command
// ---------------------------------------------------------------------------

/// 携带操作身份与作用域的命令意图。
///
/// [operationId] 与 [scope] 都由 store 在 dispatch 前拍好，reducer 保持纯同步。
/// 两者缺一不可：id 回答"是不是同一次操作"，scope 回答"这次操作所属的 Binding /
/// runtime 还在不在"。
sealed class AgentConversationCommandIntent
    extends AgentConversationSliceIntent {
  const AgentConversationCommandIntent(this.operationId, this.scope);

  final OperationId operationId;

  /// 发起时的作用域快照。
  final AgentConversationCommandScope scope;
}

/// 会话主流程。
final class AgentConversationSendMessageRequested
    extends AgentConversationCommandIntent {
  const AgentConversationSendMessageRequested(
    super.operationId,
    super.scope, {
    required this.text,
    this.localImagePaths = const <String>[],
    this.mentions = const <({String name, String path})>[],
    this.skills = const <AgentSkillRef>[],
  });

  final String text;
  final List<String> localImagePaths;
  final List<({String name, String path})> mentions;
  final List<AgentSkillRef> skills;
}

final class AgentConversationActiveTurnCancelRequested
    extends AgentConversationCommandIntent {
  const AgentConversationActiveTurnCancelRequested(
    super.operationId,
    super.scope,
  );
}

final class AgentConversationLastUserMessageEditRequested
    extends AgentConversationCommandIntent {
  const AgentConversationLastUserMessageEditRequested(
    super.operationId,
    super.scope, {
    required this.text,
  });

  final String text;
}

final class AgentConversationThreadOpenRetried
    extends AgentConversationCommandIntent {
  const AgentConversationThreadOpenRetried(super.operationId, super.scope);
}

/// 四种审批语义（G5）：四条独立链路，禁止互相复用已授权状态。
final class AgentConversationPermissionResponded
    extends AgentConversationCommandIntent {
  const AgentConversationPermissionResponded(
    super.operationId,
    super.scope, {
    required this.request,
    required this.approved,
    this.cancelTurn = false,
    this.commandDecision,
    this.execpolicyAmendment = const <String>[],
  });

  final AgentPermissionRequest request;
  final bool approved;
  final bool cancelTurn;
  final AgentCommandApprovalDecisionKind? commandDecision;
  final List<String> execpolicyAmendment;
}

final class AgentConversationQuestionResponded
    extends AgentConversationCommandIntent {
  const AgentConversationQuestionResponded(
    super.operationId,
    super.scope, {
    required this.request,
    this.answers = const <String, List<String>>{},
  });

  final AgentQuestionRequest request;
  final Map<String, List<String>> answers;
}

final class AgentConversationPlanApprovalResponded
    extends AgentConversationCommandIntent {
  const AgentConversationPlanApprovalResponded(
    super.operationId,
    super.scope, {
    required this.request,
    required this.decision,
    this.reason,
  });

  final AgentPlanApprovalRequest request;
  final AgentPlanApprovalDecisionKind decision;
  final String? reason;
}

final class AgentConversationPlanExecutionStarted
    extends AgentConversationCommandIntent {
  const AgentConversationPlanExecutionStarted(
    super.operationId,
    super.scope, {
    required this.request,
  });

  final AgentPlanExecutionRequest request;
}

final class AgentConversationPlanExecutionRevised
    extends AgentConversationCommandIntent {
  const AgentConversationPlanExecutionRevised(
    super.operationId,
    super.scope, {
    required this.request,
    required this.feedback,
  });

  final AgentPlanExecutionRequest request;
  final String feedback;
}

final class AgentConversationGuardianDeniedActionApproved
    extends AgentConversationCommandIntent {
  const AgentConversationGuardianDeniedActionApproved(
    super.operationId,
    super.scope,
  );
}

/// thread 管理。
enum AgentConversationThreadMutationKind { fork, rename, archive, compact }

final class AgentConversationThreadMutationRequested
    extends AgentConversationCommandIntent {
  const AgentConversationThreadMutationRequested(
    super.operationId,
    super.scope, {
    required this.kind,
    this.name,
  });

  final AgentConversationThreadMutationKind kind;

  /// 仅 [AgentConversationThreadMutationKind.rename] 使用。
  final String? name;
}

/// 目录类加载。
enum AgentConversationCatalogKind { models, skills, conversationModes }

final class AgentConversationCatalogLoadRequested
    extends AgentConversationCommandIntent {
  const AgentConversationCatalogLoadRequested(
    super.operationId,
    super.scope, {
    required this.kind,
    this.forceRefresh = false,
  });

  final AgentConversationCatalogKind kind;
  final bool forceRefresh;
}

// ---------------------------------------------------------------------------
// 3. 同步命令（无 effect，不占用在途身份）
// ---------------------------------------------------------------------------

/// 纯 UI 展开态切换。
///
/// 展开集合的 owner 仍是 TimelineStore：这里只是把切换动作交给 effect runner，
/// 变化随后经 ingress 回流。它不需要操作身份——没有"迟到结果"可言。
enum AgentConversationExpansionTarget {
  toolCall,
  planMessage,
  activePlan,
  commandGroup,
  fileEditItem,
}

final class AgentConversationExpansionToggled
    extends AgentConversationSliceIntent {
  const AgentConversationExpansionToggled({
    required this.target,
    required this.id,
  });

  final AgentConversationExpansionTarget target;
  final String id;
}

/// 计划执行交接被用户忽略。
final class AgentConversationPlanExecutionDismissed
    extends AgentConversationSliceIntent {
  const AgentConversationPlanExecutionDismissed(this.request);

  final AgentPlanExecutionRequest request;
}

// ---------------------------------------------------------------------------
// 4. result
// ---------------------------------------------------------------------------

/// 命令完成。
///
/// 结果意图刻意**不按命令种类拆成十几个空壳类**：`OperationId.scope` 已经带了
/// 是哪一类命令（`conversation.send` / `conversation.permission` …），再拆一层
/// 只是重复。
final class AgentConversationCommandSucceeded
    extends AgentConversationSliceIntent {
  const AgentConversationCommandSucceeded(this.operationId);

  final OperationId operationId;
}

/// 命令失败。
final class AgentConversationCommandFailed
    extends AgentConversationSliceIntent {
  const AgentConversationCommandFailed(this.failure);

  final AgentConversationOperationFailure failure;

  OperationId get operationId => failure.operationId;
}

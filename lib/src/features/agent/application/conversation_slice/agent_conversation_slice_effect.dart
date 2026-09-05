import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_command_scope.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_intent.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

/// Agent Conversation 切片的副作用**描述**。
///
/// 它们只是数据：执行由 `AgentConversationSliceEffectRunner` 负责，完成后只能
/// 通过 result intent 回写状态（G3：reducer 纯同步）。
sealed class AgentConversationSliceEffect {
  const AgentConversationSliceEffect();
}

/// 需要回报成败的命令副作用。
///
/// 每个命令副作用都带着**发起时的作用域快照**：runner 在执行前和结果回写前各校验
/// 一次，Provider 重启 / runtime 换代 / Binding 变化之后的旧 effect 不会被执行，
/// 也不会把结果写回当前世界（G3 的 scope-aware EffectRunner 要求）。
sealed class AgentConversationCommandEffect
    extends AgentConversationSliceEffect {
  const AgentConversationCommandEffect(this.operationId, this.scope);

  /// 与发起它的命令意图共享同一个身份，用于判定迟到结果。
  final OperationId operationId;

  /// 发起时的 Binding / runtime / thread 作用域。
  final AgentConversationCommandScope scope;
}

final class AgentConversationSendMessageEffect
    extends AgentConversationCommandEffect {
  const AgentConversationSendMessageEffect(
    super.operationId,
    super.scope, {
    required this.text,
    required this.localImagePaths,
    required this.mentions,
    required this.skills,
  });

  final String text;
  final List<String> localImagePaths;
  final List<({String name, String path})> mentions;
  final List<AgentSkillRef> skills;
}

final class AgentConversationCancelTurnEffect
    extends AgentConversationCommandEffect {
  const AgentConversationCancelTurnEffect(super.operationId, super.scope);
}

final class AgentConversationEditLastUserMessageEffect
    extends AgentConversationCommandEffect {
  const AgentConversationEditLastUserMessageEffect(
    super.operationId,
    super.scope, {
    required this.text,
  });

  final String text;
}

final class AgentConversationRetryOpenThreadEffect
    extends AgentConversationCommandEffect {
  const AgentConversationRetryOpenThreadEffect(super.operationId, super.scope);
}

/// 权限决定回传。**独立链路**，不与提问 / Plan 共用（G5）。
final class AgentConversationRespondPermissionEffect
    extends AgentConversationCommandEffect {
  const AgentConversationRespondPermissionEffect(
    super.operationId,
    super.scope, {
    required this.request,
    required this.approved,
    required this.cancelTurn,
    required this.commandDecision,
    required this.execpolicyAmendment,
  });

  final AgentPermissionRequest request;
  final bool approved;
  final bool cancelTurn;
  final AgentCommandApprovalDecisionKind? commandDecision;
  final List<String> execpolicyAmendment;
}

/// 提问回答回传。**独立链路**。
final class AgentConversationRespondQuestionEffect
    extends AgentConversationCommandEffect {
  const AgentConversationRespondQuestionEffect(
    super.operationId,
    super.scope, {
    required this.request,
    required this.answers,
  });

  final AgentQuestionRequest request;
  final Map<String, List<String>> answers;
}

/// Plan 审批回传。**独立链路**。
final class AgentConversationRespondPlanApprovalEffect
    extends AgentConversationCommandEffect {
  const AgentConversationRespondPlanApprovalEffect(
    super.operationId,
    super.scope, {
    required this.request,
    required this.decision,
    required this.reason,
  });

  final AgentPlanApprovalRequest request;
  final AgentPlanApprovalDecisionKind decision;
  final String? reason;
}

/// Plan 本地执行交接。**独立链路**。
final class AgentConversationPlanExecutionEffect
    extends AgentConversationCommandEffect {
  const AgentConversationPlanExecutionEffect(
    super.operationId,
    super.scope, {
    required this.request,
    this.revisionFeedback,
  });

  final AgentPlanExecutionRequest request;

  /// 非 null 表示这是"带反馈的修订"，null 表示直接开始执行。
  final String? revisionFeedback;
}

final class AgentConversationApproveGuardianDeniedActionEffect
    extends AgentConversationCommandEffect {
  const AgentConversationApproveGuardianDeniedActionEffect(
    super.operationId,
    super.scope,
  );
}

final class AgentConversationThreadMutationEffect
    extends AgentConversationCommandEffect {
  const AgentConversationThreadMutationEffect(
    super.operationId,
    super.scope, {
    required this.kind,
    this.name,
  });

  final AgentConversationThreadMutationKind kind;
  final String? name;
}

final class AgentConversationLoadCatalogEffect
    extends AgentConversationCommandEffect {
  const AgentConversationLoadCatalogEffect(
    super.operationId,
    super.scope, {
    required this.kind,
    required this.forceRefresh,
  });

  final AgentConversationCatalogKind kind;
  final bool forceRefresh;
}

/// 无需回报成败的即发即忘副作用。
sealed class AgentConversationFireAndForgetEffect
    extends AgentConversationSliceEffect {
  const AgentConversationFireAndForgetEffect();
}

final class AgentConversationToggleExpansionEffect
    extends AgentConversationFireAndForgetEffect {
  const AgentConversationToggleExpansionEffect({
    required this.target,
    required this.id,
  });

  final AgentConversationExpansionTarget target;
  final String id;
}

final class AgentConversationDismissPlanExecutionEffect
    extends AgentConversationFireAndForgetEffect {
  const AgentConversationDismissPlanExecutionEffect(this.request);

  final AgentPlanExecutionRequest request;
}

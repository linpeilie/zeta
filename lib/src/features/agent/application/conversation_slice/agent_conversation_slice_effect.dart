import 'package:flutter/foundation.dart';
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
sealed class AgentConversationCommandEffect
    extends AgentConversationSliceEffect {
  const AgentConversationCommandEffect(this.operationId);

  /// 与发起它的命令意图共享同一个身份，用于判定迟到结果。
  final OperationId operationId;
}

@immutable
final class AgentConversationSendMessageEffect
    extends AgentConversationCommandEffect {
  const AgentConversationSendMessageEffect(
    super.operationId, {
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

@immutable
final class AgentConversationCancelTurnEffect
    extends AgentConversationCommandEffect {
  const AgentConversationCancelTurnEffect(super.operationId);
}

@immutable
final class AgentConversationEditLastUserMessageEffect
    extends AgentConversationCommandEffect {
  const AgentConversationEditLastUserMessageEffect(
    super.operationId, {
    required this.text,
  });

  final String text;
}

@immutable
final class AgentConversationRetryOpenThreadEffect
    extends AgentConversationCommandEffect {
  const AgentConversationRetryOpenThreadEffect(super.operationId);
}

/// 权限决定回传。**独立链路**，不与提问 / Plan 共用（G5）。
@immutable
final class AgentConversationRespondPermissionEffect
    extends AgentConversationCommandEffect {
  const AgentConversationRespondPermissionEffect(
    super.operationId, {
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
@immutable
final class AgentConversationRespondQuestionEffect
    extends AgentConversationCommandEffect {
  const AgentConversationRespondQuestionEffect(
    super.operationId, {
    required this.request,
    required this.answers,
  });

  final AgentQuestionRequest request;
  final Map<String, List<String>> answers;
}

/// Plan 审批回传。**独立链路**。
@immutable
final class AgentConversationRespondPlanApprovalEffect
    extends AgentConversationCommandEffect {
  const AgentConversationRespondPlanApprovalEffect(
    super.operationId, {
    required this.request,
    required this.decision,
    required this.reason,
  });

  final AgentPlanApprovalRequest request;
  final AgentPlanApprovalDecisionKind decision;
  final String? reason;
}

/// Plan 本地执行交接。**独立链路**。
@immutable
final class AgentConversationPlanExecutionEffect
    extends AgentConversationCommandEffect {
  const AgentConversationPlanExecutionEffect(
    super.operationId, {
    required this.request,
    this.revisionFeedback,
  });

  final AgentPlanExecutionRequest request;

  /// 非 null 表示这是"带反馈的修订"，null 表示直接开始执行。
  final String? revisionFeedback;
}

@immutable
final class AgentConversationApproveGuardianDeniedActionEffect
    extends AgentConversationCommandEffect {
  const AgentConversationApproveGuardianDeniedActionEffect(super.operationId);
}

@immutable
final class AgentConversationThreadMutationEffect
    extends AgentConversationCommandEffect {
  const AgentConversationThreadMutationEffect(
    super.operationId, {
    required this.kind,
    this.name,
  });

  final AgentConversationThreadMutationKind kind;
  final String? name;
}

@immutable
final class AgentConversationLoadCatalogEffect
    extends AgentConversationCommandEffect {
  const AgentConversationLoadCatalogEffect(
    super.operationId, {
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

@immutable
final class AgentConversationToggleExpansionEffect
    extends AgentConversationFireAndForgetEffect {
  const AgentConversationToggleExpansionEffect({
    required this.target,
    required this.id,
  });

  final AgentConversationExpansionTarget target;
  final String id;
}

@immutable
final class AgentConversationDismissPlanExecutionEffect
    extends AgentConversationFireAndForgetEffect {
  const AgentConversationDismissPlanExecutionEffect(this.request);

  final AgentPlanExecutionRequest request;
}

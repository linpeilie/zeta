import 'package:zeta_agent_core/src/domain/agent_provider_raw_payload.dart';

/// Agent 向用户请求审批的中立分类。
enum AgentPermissionKind { commandExecution, fileChange, permissions, other }

/// 命令执行审批的决策变体（对应协议 `CommandExecutionApprovalDecision`）。
enum AgentCommandApprovalDecisionKind {
  /// 同意本次命令。
  accept,

  /// 同意且本会话内同类命令不再提示。
  acceptForSession,

  /// 同意并持久化 execpolicy 白名单修正。
  acceptWithExecpolicyAmendment,

  /// 拒绝，回合继续。
  decline,

  /// 拒绝并中断回合。
  cancel,
}

/// Provider 发出的权限审批请求。
///
/// UI 用该模型渲染审批卡片，再通过 [AgentPermissionDecision] 把结果传回 provider。
class AgentPermissionRequest {
  const AgentPermissionRequest({
    required this.id,
    required this.title,
    required this.kind,
    this.description,
    this.command,
    this.cwd,
    this.sessionId,
    this.turnId,
    this.fileChanges = const <String, Object?>{},
    this.commandActions = const <String>[],
    this.proposedExecpolicyAmendment = const <String>[],
    this.raw = const AgentProviderRawPayload.empty(),
  });

  /// 审批请求 id，UI 用它作为稳定 key。
  final String id;

  /// 审批卡片标题。
  final String title;

  /// 审批类型。
  final AgentPermissionKind kind;

  /// provider 给出的原因或说明。
  final String? description;

  /// 命令执行审批中的命令文本。
  final String? command;

  /// 命令执行目录。
  final String? cwd;

  /// 可选会话 id，用于将实时事件路由到当前 thread。
  final String? sessionId;

  /// 可选回合 id，用于将实时事件路由到当前 turn。
  final String? turnId;

  /// 文件变更审批中的变更摘要。
  final Map<String, Object?> fileChanges;

  /// 命令语义摘要（由 `commandActions` 解析而来）。
  final List<String> commandActions;

  /// 服务端建议的 execpolicy 白名单修正。
  final List<String> proposedExecpolicyAmendment;

  /// 原始审批请求 payload。
  final AgentProviderRawPayload raw;
}

/// 用户对审批请求的决定。
class AgentPermissionDecision {
  const AgentPermissionDecision({
    required this.requestId,
    required this.approved,
    this.cancelTurn = false,
    this.message,
    this.commandDecision,
    this.execpolicyAmendment = const <String>[],
  });

  /// 对应 [AgentPermissionRequest.id]。
  final String requestId;

  /// 是否同意（非命令类审批 / 兼容路径）。
  final bool approved;

  /// 拒绝时是否同时取消当前 turn。
  final bool cancelTurn;

  /// 可选的人类说明，预留给支持文本反馈的 provider。
  final String? message;

  /// 命令执行审批的显式决策变体；为 null 时回退到 [approved]/[cancelTurn]。
  final AgentCommandApprovalDecisionKind? commandDecision;

  /// 与 [AgentCommandApprovalDecisionKind.acceptWithExecpolicyAmendment] 配套的修正列表。
  final List<String> execpolicyAmendment;
}

/// 被拒操作的人工放行请求。
///
/// UI 只回传 typed [requestId]；协议对象由 Provider-local pending registry 持有。
final class AgentDeniedActionOverrideRequest {
  const AgentDeniedActionOverrideRequest({
    required this.threadId,
    required this.requestId,
  });

  final String threadId;
  final String requestId;
}

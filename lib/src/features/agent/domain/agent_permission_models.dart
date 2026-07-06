/// Agent 向用户请求审批或输入的中立分类。
enum AgentPermissionKind {
  commandExecution,
  fileChange,
  permissions,
  userInput,
  other,
}

/// Provider 发出的审批或输入请求。
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
    this.raw = const <String, Object?>{},
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

  /// 原始审批请求 payload。
  final Map<String, Object?> raw;
}

/// 用户对审批请求的决定。
class AgentPermissionDecision {
  const AgentPermissionDecision({
    required this.requestId,
    required this.approved,
    this.cancelTurn = false,
    this.message,
  });

  /// 对应 [AgentPermissionRequest.id]。
  final String requestId;

  /// 是否同意。
  final bool approved;

  /// 拒绝时是否同时取消当前 turn。
  final bool cancelTurn;

  /// 可选的人类说明，预留给支持文本反馈的 provider。
  final String? message;
}

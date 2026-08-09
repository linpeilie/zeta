/// Plan 回合完成后，由 Zeta 本地创建的执行交接请求。
///
/// 该请求不属于 Provider 协议，也不代表命令、文件或网络权限已获批准。
/// 它只承载用户是否要把上一回合计划切换到 Default 模式执行的选择。
final class AgentPlanExecutionRequest {
  const AgentPlanExecutionRequest({
    required this.id,
    required this.sessionId,
    required this.turnId,
    required this.title,
    required this.markdown,
    this.messageId,
  });

  /// 本地交接请求的稳定标识。
  final String id;

  /// 计划所属会话，用于阻止跨 thread 的陈旧操作。
  final String sessionId;

  /// 生成计划的回合。
  final String turnId;

  /// 确认卡标题。
  final String title;

  /// 计划正文；优先使用 Provider 的 plan 消息，必要时由结构化步骤生成。
  final String markdown;

  /// 提供 [markdown] 的 plan 消息 id；正文由结构化步骤合成时为 null。
  ///
  /// UI 据此在对话流中定位要升级为交互卡的那条 plan 消息，避免同一份计划
  /// 正文既出现在折叠消息卡、又出现在交互卡里。
  final String? messageId;
}

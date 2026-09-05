import 'package:zeta_agent_core/src/domain/agent_permission_policy_models.dart';

/// 本地 Plan 执行使用的权限来源。
enum AgentPlanExecutionPermissionOrigin {
  /// 恢复进入 Plan 前的有效权限。
  beforePlan,

  /// 原权限失效后回落到 Provider 目录声明的保守默认。
  catalogDefault,

  /// 用户在执行卡上为本次执行显式覆盖。
  userOverride,

  /// Provider 没有权限选择端口，沿用其自身默认行为。
  providerFallback,
}

/// Plan 执行卡冻结的一次性权限选择。
final class AgentPlanExecutionPermissionChoice {
  const AgentPlanExecutionPermissionChoice({
    required this.label,
    required this.origin,
    this.selection,
  }) : assert(
         selection != null ||
             origin == AgentPlanExecutionPermissionOrigin.providerFallback,
       );

  final AgentPermissionSelection? selection;
  final String label;
  final AgentPlanExecutionPermissionOrigin origin;

  /// 转为这一次新回合独占的权限快照，不写回默认偏好。
  AgentPermissionRequestSnapshot toRequestSnapshot() {
    final resolved = selection;
    if (resolved == null) {
      return const AgentPermissionRequestSnapshot.providerFallback();
    }
    return AgentPermissionRequestSnapshot.resolved(
      selection: resolved,
      source: AgentPermissionRequestSource.localWorkflowOverride,
    );
  }
}

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
    this.executionPermission,
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

  /// 执行卡当前已校验的一次性权限；null 表示必须先选择，不能执行。
  final AgentPlanExecutionPermissionChoice? executionPermission;

  AgentPlanExecutionRequest copyWithExecutionPermission(
    AgentPlanExecutionPermissionChoice? value,
  ) {
    return AgentPlanExecutionRequest(
      id: id,
      sessionId: sessionId,
      turnId: turnId,
      title: title,
      markdown: markdown,
      messageId: messageId,
      executionPermission: value,
    );
  }
}

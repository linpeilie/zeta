import 'package:agent_provider_contracts/src/models/agent_tool_models.dart';
import 'package:agent_provider_contracts/src/models/immutable_collections.dart';

/// 计划审批中的阶段分组。
final class AgentPlanApprovalPhase {
  AgentPlanApprovalPhase({
    required this.name,
    List<AgentPlanEntry> todos = const <AgentPlanEntry>[],
  }) : todos = immutableList(todos);

  final String name;
  final List<AgentPlanEntry> todos;
}

/// Provider 接受计划后由谁承接后续执行。
///
/// application 只读取这个中立语义，不按 Provider id、kind 或实现类型分支。
enum AgentPlanApprovalContinuation {
  /// Provider 会在审批响应后自行继续，不创建 Zeta 本地执行交接。
  providerManaged,

  /// Provider 只负责结束 Plan 回合；成功终态后由 Zeta 再向用户确认执行。
  localExecutionHandoff,
}

/// App-owned plan approval title variants.
enum AgentPlanApprovalTitleCode { planApproval }

/// Provider 发起的独立计划审批请求。
///
/// 该模型刻意与命令权限审批分离，避免把“接受计划”误解为“允许执行命令”。
final class AgentPlanApprovalRequest {
  AgentPlanApprovalRequest({
    required this.id,
    required this.markdown,
    this.title,
    this.titleCode,
    this.overview,
    List<AgentPlanEntry> todos = const <AgentPlanEntry>[],
    List<AgentPlanApprovalPhase> phases = const <AgentPlanApprovalPhase>[],
    this.isProject = false,
    this.sessionId,
    this.turnId,
    this.continuation = AgentPlanApprovalContinuation.providerManaged,
    Map<String, Object?> raw = const <String, Object?>{},
  }) : assert(
         title != null || titleCode != null,
         'A provider title or app-owned title code is required.',
       ),
       todos = immutableList(todos),
       phases = immutableList(phases),
       raw = immutableJsonMap(raw);

  final String id;
  final String? title;
  final AgentPlanApprovalTitleCode? titleCode;
  final String markdown;
  final String? overview;
  final List<AgentPlanEntry> todos;
  final List<AgentPlanApprovalPhase> phases;
  final bool isProject;
  final String? sessionId;
  final String? turnId;

  /// 接受审批后的中立续接语义。
  final AgentPlanApprovalContinuation continuation;

  final Map<String, Object?> raw;
}

/// 计划审批结果。
enum AgentPlanApprovalDecisionKind { accepted, rejected, cancelled }

/// 用户对计划审批请求的决定。
final class AgentPlanApprovalDecision {
  const AgentPlanApprovalDecision({
    required this.requestId,
    required this.kind,
    this.reason,
  });

  final String requestId;
  final AgentPlanApprovalDecisionKind kind;
  final String? reason;
}

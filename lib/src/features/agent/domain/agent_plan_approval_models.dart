import 'package:zeta/src/features/agent/domain/agent_tool_models.dart';

/// 计划审批中的阶段分组。
class AgentPlanApprovalPhase {
  const AgentPlanApprovalPhase({
    required this.name,
    this.todos = const <AgentPlanEntry>[],
  });

  final String name;
  final List<AgentPlanEntry> todos;
}

/// Provider 发起的独立计划审批请求。
///
/// 该模型刻意与命令权限审批分离，避免把“接受计划”误解为“允许执行命令”。
class AgentPlanApprovalRequest {
  const AgentPlanApprovalRequest({
    required this.id,
    required this.title,
    required this.markdown,
    this.overview,
    this.todos = const <AgentPlanEntry>[],
    this.phases = const <AgentPlanApprovalPhase>[],
    this.isProject = false,
    this.sessionId,
    this.turnId,
    this.raw = const <String, Object?>{},
  });

  final String id;
  final String title;
  final String markdown;
  final String? overview;
  final List<AgentPlanEntry> todos;
  final List<AgentPlanApprovalPhase> phases;
  final bool isProject;
  final String? sessionId;
  final String? turnId;
  final Map<String, Object?> raw;
}

/// 计划审批结果。
enum AgentPlanApprovalDecisionKind { accepted, rejected, cancelled }

/// 用户对计划审批请求的决定。
class AgentPlanApprovalDecision {
  const AgentPlanApprovalDecision({
    required this.requestId,
    required this.kind,
    this.reason,
  });

  final String requestId;
  final AgentPlanApprovalDecisionKind kind;
  final String? reason;
}

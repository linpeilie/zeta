import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// 管理 Plan 完成后、执行开始前的本地交接状态。
///
/// Controller 不依赖 Widget、时间线 Store 或 Provider 协议。调用方负责从当前
/// live turn 提取最终计划，并在用户选择“执行”后发起新的 Default 回合。
final class AgentPlanExecutionHandoffController {
  AgentPlanExecutionRequest? _pendingRequest;

  /// 当前待用户处理的本地计划执行请求。
  AgentPlanExecutionRequest? get pendingRequest => _pendingRequest;

  /// 尝试为一个已完成的 Plan 回合创建执行交接请求。
  ///
  /// 非 Plan、非成功终态或没有可展示计划内容时返回 null，并清除旧请求。
  AgentPlanExecutionRequest? offerCompletedPlan({
    required String sessionId,
    required String turnId,
    required AgentHistoryTurnStatus status,
    required AgentConversationModeId? modeId,
    required String? planMarkdown,
    Iterable<AgentPlanEntry> planEntries = const <AgentPlanEntry>[],
  }) {
    final markdown = _resolvedPlanMarkdown(planMarkdown, planEntries);
    if (status != AgentHistoryTurnStatus.completed ||
        modeId?.kind != AgentConversationModeKind.plan ||
        markdown == null) {
      _pendingRequest = null;
      return null;
    }

    final request = AgentPlanExecutionRequest(
      id: 'plan-execution:$sessionId:$turnId',
      sessionId: sessionId,
      turnId: turnId,
      title: 'Plan ready',
      markdown: markdown,
    );
    _pendingRequest = request;
    return request;
  }

  /// 仅在 [request] 仍是当前请求时完成交接，避免旧卡片回调清除新状态。
  bool resolve(AgentPlanExecutionRequest request) {
    if (_pendingRequest?.id != request.id) {
      return false;
    }
    _pendingRequest = null;
    return true;
  }

  /// 会话、Provider 或工作区切换时清除非持久化交接状态。
  bool clear() {
    if (_pendingRequest == null) {
      return false;
    }
    _pendingRequest = null;
    return true;
  }

  String? _resolvedPlanMarkdown(
    String? planMarkdown,
    Iterable<AgentPlanEntry> planEntries,
  ) {
    final normalizedMarkdown = planMarkdown?.trim();
    if (normalizedMarkdown != null && normalizedMarkdown.isNotEmpty) {
      return normalizedMarkdown;
    }

    final steps = planEntries
        .map((entry) => entry.content.trim())
        .where((content) => content.isNotEmpty)
        .toList(growable: false);
    if (steps.isEmpty) {
      return null;
    }
    return <String>[
      '## Execution plan',
      '',
      for (var index = 0; index < steps.length; index += 1)
        '${index + 1}. ${steps[index]}',
    ].join('\n');
  }
}

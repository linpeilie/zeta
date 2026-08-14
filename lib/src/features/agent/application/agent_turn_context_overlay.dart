import 'package:zeta/src/features/agent/domain/agent_turn_context_models.dart';
import 'package:zeta/src/features/agent/domain/agent_turn_history_models.dart';

/// 用 Zeta 本地 turn 上下文按字段覆盖 Provider 历史快照。
///
/// [local] 为空或没有匹配 turn 时原样返回 [snapshot]。Zeta 多出来的 turn
/// 不会发明历史条目。
AgentThreadHistorySnapshot overlayThreadTurnContext(
  AgentThreadHistorySnapshot snapshot,
  AgentThreadTurnContext? local,
) {
  if (local == null || local.turns.isEmpty) {
    return snapshot;
  }
  final byId = <String, AgentTurnContextRecord>{
    for (final turn in local.turns) turn.turnId: turn,
  };
  final turns = <AgentHistoryTurn>[
    for (final turn in snapshot.turns) _overlayTurn(turn, byId[turn.id]),
  ];
  final currentTurnId = snapshot.currentTurn?.id;
  AgentHistoryTurn? currentTurn;
  if (currentTurnId != null) {
    for (final turn in turns) {
      if (turn.id == currentTurnId) {
        currentTurn = turn;
        break;
      }
    }
  }
  return AgentThreadHistorySnapshot(
    threadId: snapshot.threadId,
    turns: List<AgentHistoryTurn>.unmodifiable(turns),
    currentTurn: currentTurn,
    raw: snapshot.raw,
  );
}

AgentHistoryTurn _overlayTurn(
  AgentHistoryTurn turn,
  AgentTurnContextRecord? local,
) {
  if (local == null) {
    return turn;
  }
  final reasoningEffort = _overlayReasoningEffort(
    turn.reasoningEffort,
    local.reasoningEffort,
  );
  final modelId = _nonEmpty(local.modelId) ?? turn.modelId;
  final serviceTierId = _nonEmpty(local.serviceTierId) ?? turn.serviceTierId;
  final explicitFast = local.explicitFast ?? turn.explicitFast;
  final startedAt = local.startedAt ?? turn.startedAt;
  final completedAt = local.completedAt ?? turn.completedAt;
  final status = local.status ?? turn.status;
  if (identical(reasoningEffort, turn.reasoningEffort) &&
      modelId == turn.modelId &&
      serviceTierId == turn.serviceTierId &&
      explicitFast == turn.explicitFast &&
      startedAt == turn.startedAt &&
      completedAt == turn.completedAt &&
      status == turn.status) {
    return turn;
  }
  return AgentHistoryTurn(
    id: turn.id,
    entries: turn.entries,
    status: status,
    startedAt: startedAt,
    completedAt: completedAt,
    duration: turn.duration,
    timeToFirstToken: turn.timeToFirstToken,
    cwd: turn.cwd,
    modelId: modelId,
    reasoningEffort: reasoningEffort,
    serviceTierId: serviceTierId,
    explicitFast: explicitFast,
    modelContextWindow: turn.modelContextWindow,
    collaborationMode: turn.collaborationMode,
    tokenUsage: turn.tokenUsage,
    tokenUsageIsSessionCumulative: turn.tokenUsageIsSessionCumulative,
    errorMessage: turn.errorMessage,
    errorCode: turn.errorCode,
    raw: turn.raw,
  );
}

AgentHistoryReasoningEffort _overlayReasoningEffort(
  AgentHistoryReasoningEffort original,
  String? localValue,
) {
  final effort = _nonEmpty(localValue);
  if (effort == null) {
    return original;
  }
  return AgentHistoryReasoningEffort.explicit(effort);
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}

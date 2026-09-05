import 'package:zeta_agent_core/zeta_agent_core.dart';

/// live 合成 turnId 与 Provider 历史 turnId 不一致时，用开始时间对齐的最大间隔。
///
/// 超过该窗口不覆盖，避免把相邻回合的模型配置错配到另一条历史上。
const Duration kAgentTurnContextTimeMatchWindow = Duration(seconds: 5);

/// 用 Zeta 本地 turn 上下文按字段覆盖 Provider 历史快照。
///
/// [local] 为空或没有匹配 turn 时原样返回 [snapshot]。Zeta 多出来的 turn
/// 不会发明历史条目。
///
/// 匹配顺序：先按 `turnId` 精确对齐；未命中的历史回合再按
/// [startedAt]（缺省 [completedAt]）与剩余本地记录做一对一最近邻匹配。
/// 窗口外、双边等距或同一本地记录被两条历史争用时 fail-closed。
AgentThreadHistorySnapshot overlayThreadTurnContext(
  AgentThreadHistorySnapshot snapshot,
  AgentThreadTurnContext? local,
) {
  if (local == null || local.turns.isEmpty) {
    return snapshot;
  }
  final matched = _matchLocalTurns(snapshot.turns, local.turns);
  final turns = <AgentHistoryTurn>[
    for (var i = 0; i < snapshot.turns.length; i++)
      _overlayTurn(snapshot.turns[i], matched[i]),
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
    sourceLabel: snapshot.sourceLabel,
    sessionPath: snapshot.sessionPath,
  );
}

List<AgentTurnContextRecord?> _matchLocalTurns(
  List<AgentHistoryTurn> historyTurns,
  List<AgentTurnContextRecord> localTurns,
) {
  final matches = List<AgentTurnContextRecord?>.filled(
    historyTurns.length,
    null,
  );
  final unusedLocals = <AgentTurnContextRecord>[];
  final claimedIds = <String>{};

  for (var i = 0; i < historyTurns.length; i++) {
    final history = historyTurns[i];
    for (final local in localTurns) {
      if (local.turnId == history.id && claimedIds.add(local.turnId)) {
        matches[i] = local;
        break;
      }
    }
  }

  for (final local in localTurns) {
    if (!claimedIds.contains(local.turnId)) {
      unusedLocals.add(local);
    }
  }
  if (unusedLocals.isEmpty) {
    return matches;
  }

  final unmatchedHistory = <int>[];
  for (var i = 0; i < historyTurns.length; i++) {
    if (matches[i] == null) {
      unmatchedHistory.add(i);
    }
  }
  if (unmatchedHistory.isEmpty) {
    return matches;
  }

  final pairs = <_TimeMatchCandidate>[];
  for (final historyIndex in unmatchedHistory) {
    final historyTime = _turnTime(historyTurns[historyIndex]);
    if (historyTime == null) {
      continue;
    }
    for (var localIndex = 0; localIndex < unusedLocals.length; localIndex++) {
      final localTime = _localTime(unusedLocals[localIndex]);
      if (localTime == null) {
        continue;
      }
      final delta = historyTime.difference(localTime).abs();
      if (delta > kAgentTurnContextTimeMatchWindow) {
        continue;
      }
      pairs.add(
        _TimeMatchCandidate(
          historyIndex: historyIndex,
          localIndex: localIndex,
          delta: delta,
        ),
      );
    }
  }

  final ambiguousHistory = <int>{};
  final bestForHistory = <int, _TimeMatchCandidate>{};
  for (final pair in pairs) {
    final current = bestForHistory[pair.historyIndex];
    if (current == null || pair.delta < current.delta) {
      bestForHistory[pair.historyIndex] = pair;
      continue;
    }
    if (pair.delta == current.delta && pair.localIndex != current.localIndex) {
      ambiguousHistory.add(pair.historyIndex);
    }
  }

  final ambiguousLocal = <int>{};
  final bestForLocal = <int, _TimeMatchCandidate>{};
  for (final pair in pairs) {
    final current = bestForLocal[pair.localIndex];
    if (current == null || pair.delta < current.delta) {
      bestForLocal[pair.localIndex] = pair;
      continue;
    }
    if (pair.delta == current.delta &&
        pair.historyIndex != current.historyIndex) {
      ambiguousLocal.add(pair.localIndex);
    }
  }

  for (final historyIndex in unmatchedHistory) {
    if (ambiguousHistory.contains(historyIndex)) {
      continue;
    }
    final candidate = bestForHistory[historyIndex];
    if (candidate == null || ambiguousLocal.contains(candidate.localIndex)) {
      continue;
    }
    final reciprocal = bestForLocal[candidate.localIndex];
    if (reciprocal == null || reciprocal.historyIndex != historyIndex) {
      continue;
    }
    matches[historyIndex] = unusedLocals[candidate.localIndex];
  }
  return matches;
}

DateTime? _turnTime(AgentHistoryTurn turn) =>
    turn.startedAt ?? turn.completedAt;

DateTime? _localTime(AgentTurnContextRecord turn) =>
    turn.startedAt ?? turn.completedAt;

final class _TimeMatchCandidate {
  const _TimeMatchCandidate({
    required this.historyIndex,
    required this.localIndex,
    required this.delta,
  });

  final int historyIndex;
  final int localIndex;
  final Duration delta;
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

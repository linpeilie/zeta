import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 将 [AgentThreadTurnContext] 编码为版本化白名单 JSON。
Map<String, Object?> encodeAgentThreadTurnContext(
  AgentThreadTurnContext context,
) {
  return <String, Object?>{
    'version': AgentThreadTurnContext.currentVersion,
    'providerId': context.providerId,
    'threadId': context.threadId,
    'turns': <Map<String, Object?>>[
      for (final turn in context.turns) _encodeTurn(turn),
    ],
  };
}

/// 宽容解码会话上下文。损坏、缺字段或未知版本返回 null，不抛出。
AgentThreadTurnContext? tryDecodeAgentThreadTurnContext(Object? value) {
  if (value is! Map) {
    return null;
  }
  final map = value.cast<Object?, Object?>();
  if (map['version'] != AgentThreadTurnContext.currentVersion) {
    return null;
  }
  final providerId = _nonEmptyString(map['providerId']);
  final threadId = _nonEmptyString(map['threadId']);
  if (providerId == null || threadId == null) {
    return null;
  }
  final rawTurns = map['turns'];
  if (rawTurns is! List) {
    return AgentThreadTurnContext(providerId: providerId, threadId: threadId);
  }
  final turns = <AgentTurnContextRecord>[];
  final seen = <String>{};
  for (final item in rawTurns) {
    final turn = _decodeTurn(item);
    if (turn == null || !seen.add(turn.turnId)) {
      continue;
    }
    turns.add(turn);
  }
  return AgentThreadTurnContext(
    providerId: providerId,
    threadId: threadId,
    turns: List<AgentTurnContextRecord>.unmodifiable(turns),
  );
}

Map<String, Object?> _encodeTurn(AgentTurnContextRecord turn) {
  return <String, Object?>{
    'turnId': turn.turnId,
    if (turn.modelId != null) 'modelId': turn.modelId,
    if (turn.reasoningEffort != null) 'reasoningEffort': turn.reasoningEffort,
    if (turn.serviceTierId != null) 'serviceTierId': turn.serviceTierId,
    if (turn.explicitFast != null) 'explicitFast': turn.explicitFast,
    if (turn.startedAt != null)
      'startedAt': turn.startedAt!.toUtc().toIso8601String(),
    if (turn.completedAt != null)
      'completedAt': turn.completedAt!.toUtc().toIso8601String(),
    if (turn.status != null) 'status': turn.status!.name,
  };
}

AgentTurnContextRecord? _decodeTurn(Object? value) {
  if (value is! Map) {
    return null;
  }
  final map = value.cast<Object?, Object?>();
  final turnId = _nonEmptyString(map['turnId']);
  if (turnId == null) {
    return null;
  }
  return AgentTurnContextRecord(
    turnId: turnId,
    modelId: _nonEmptyString(map['modelId']),
    reasoningEffort: _nonEmptyString(map['reasoningEffort']),
    serviceTierId: _nonEmptyString(map['serviceTierId']),
    explicitFast: map['explicitFast'] is bool
        ? map['explicitFast']! as bool
        : null,
    startedAt: _dateTime(map['startedAt']),
    completedAt: _dateTime(map['completedAt']),
    status: _status(map['status']),
  );
}

AgentHistoryTurnStatus? _status(Object? value) {
  if (value is! String) {
    return null;
  }
  for (final status in AgentHistoryTurnStatus.values) {
    if (status.name == value) {
      return status;
    }
  }
  return null;
}

DateTime? _dateTime(Object? value) {
  if (value is! String) {
    return null;
  }
  return DateTime.tryParse(value.trim());
}

String? _nonEmptyString(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

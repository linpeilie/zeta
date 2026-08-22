import 'package:zeta_agent_providers/src/mappers/agent_provider_timestamp.dart';

/// 从 Grok ACP/session history envelope 提取时间。
///
/// `agentTimestampMs` 的单位由 Grok 协议明确为毫秒；行级 `timestamp` 兼容现有
/// 秒/毫秒历史格式。该函数不得用于 tool rawInput/rawOutput。
DateTime? grokProviderEnvelopeCapturedAt(Map<String, Object?> envelope) {
  final meta = _stringKeyedMap(envelope['_meta']);
  final agentTimestamp = tryParseAgentProviderTimestamp(
    meta['agentTimestampMs'],
    unit: AgentProviderTimestampUnit.milliseconds,
  );
  if (agentTimestamp != null) {
    return agentTimestamp;
  }

  for (final value in <Object?>[
    envelope['timestamp'],
    envelope['created_at'],
  ]) {
    final parsed = tryParseAgentProviderTimestamp(value);
    if (parsed != null) {
      return parsed;
    }
  }
  return null;
}

Map<String, Object?> _stringKeyedMap(Object? value) {
  if (value is! Map) {
    return const <String, Object?>{};
  }
  return <String, Object?>{
    for (final entry in value.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}

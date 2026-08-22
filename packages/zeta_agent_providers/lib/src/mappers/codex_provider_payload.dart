import 'package:zeta_agent_providers/src/mappers/agent_provider_timestamp.dart';

/// 从 Codex app-server item / notification / JSONL record envelope 提取时间。
///
/// 调用者必须保证 [envelope] 是 Codex 报文外壳，而不是工具 arguments/result。
/// 键名兼容只留在 Codex adapter 内，不扩散到共享包装器。
DateTime? codexProviderEnvelopeCapturedAt(Map<String, Object?> envelope) {
  final timestamp = tryParseAgentProviderTimestamp(envelope['timestamp']);
  if (timestamp != null) {
    return timestamp;
  }
  final startedAt = tryParseAgentProviderTimestamp(envelope['startedAt']);
  if (startedAt != null) {
    return startedAt;
  }
  final startedAtMs = tryParseAgentProviderTimestamp(
    envelope['startedAtMs'],
    unit: AgentProviderTimestampUnit.milliseconds,
  );
  if (startedAtMs != null) {
    return startedAtMs;
  }
  final completedAt = tryParseAgentProviderTimestamp(envelope['completedAt']);
  if (completedAt != null) {
    return completedAt;
  }
  final completedAtMs = tryParseAgentProviderTimestamp(
    envelope['completedAtMs'],
    unit: AgentProviderTimestampUnit.milliseconds,
  );
  return completedAtMs ?? tryParseAgentProviderTimestamp(envelope['createdAt']);
}

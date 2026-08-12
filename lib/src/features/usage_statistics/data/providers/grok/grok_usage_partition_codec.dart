import 'package:zeta/src/features/usage_statistics/data/providers/grok/grok_usage_log_scanner.dart';
import 'package:zeta/src/features/usage_statistics/data/usage_statistics_partition_store.dart';

/// Grok 自有 v1 分区 codec；通用 Store 不解析 sessions 结构。
final class GrokUsagePartitionCodec {
  const GrokUsagePartitionCodec();

  static const int schemaVersion = 1;

  Map<String, GrokUsageIndexedSession> decode(
    UsageStatisticsIndexPartition? partition,
  ) {
    if (partition == null || partition.schemaVersion != schemaVersion) {
      return const <String, GrokUsageIndexedSession>{};
    }
    final sessions = <String, GrokUsageIndexedSession>{};
    final rawSessions = partition.payload['sessions'];
    if (rawSessions is List) {
      for (final value in rawSessions) {
        final session = GrokUsageIndexedSession.tryDecode(value);
        if (session != null) {
          sessions[session.sourceId] = session;
        }
      }
    }
    return Map<String, GrokUsageIndexedSession>.unmodifiable(sessions);
  }

  UsageStatisticsIndexPartition encode(
    Iterable<GrokUsageIndexedSession> sessions,
  ) {
    return UsageStatisticsIndexPartition(
      schemaVersion: schemaVersion,
      payload: <String, Object?>{
        'sessions': sessions.map((session) => session.toJson()).toList(),
      },
    );
  }
}

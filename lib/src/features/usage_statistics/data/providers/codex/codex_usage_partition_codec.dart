import 'package:zeta/src/features/usage_statistics/data/providers/codex/codex_usage_log_scanner.dart';
import 'package:zeta/src/features/usage_statistics/data/usage_statistics_partition_store.dart';

/// Codex 自有 v1 分区 codec；通用 Store 不解析 sessions 结构。
final class CodexUsagePartitionCodec {
  const CodexUsagePartitionCodec();

  static const int schemaVersion = 1;

  Map<String, CodexUsageSessionSnapshot> decode(
    UsageStatisticsIndexPartition? partition,
  ) {
    if (partition == null || partition.schemaVersion != schemaVersion) {
      return const <String, CodexUsageSessionSnapshot>{};
    }
    final sessions = <String, CodexUsageSessionSnapshot>{};
    final rawSessions = partition.payload['sessions'];
    if (rawSessions is List) {
      for (final value in rawSessions) {
        final session = CodexUsageSessionSnapshot.tryDecode(value);
        if (session != null) {
          sessions[session.sourceId] = session;
        }
      }
    }
    return Map<String, CodexUsageSessionSnapshot>.unmodifiable(sessions);
  }

  UsageStatisticsIndexPartition encode(
    Iterable<CodexUsageSessionSnapshot> sessions,
  ) {
    return UsageStatisticsIndexPartition(
      schemaVersion: schemaVersion,
      payload: <String, Object?>{
        'sessions': sessions.map((session) => session.toJson()).toList(),
      },
    );
  }
}

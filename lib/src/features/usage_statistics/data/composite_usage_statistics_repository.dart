import 'package:zeta/src/features/agent/domain/agent_usage_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_repository.dart';

/// 并行聚合多个 Provider 本地历史的使用统计数据源。
///
/// 任一子源失败只记 warning，不阻断其它源；身份由各子源自行固定，
/// 与当前激活 Provider 无关。
class CompositeUsageStatisticsRepository implements UsageStatisticsRepository {
  CompositeUsageStatisticsRepository({
    required List<UsageStatisticsRepository> sources,
    DateTime Function()? clock,
  }) : sources = List<UsageStatisticsRepository>.unmodifiable(sources),
       _clock = clock ?? DateTime.now;

  final List<UsageStatisticsRepository> sources;
  final DateTime Function() _clock;

  @override
  Future<UsageStatisticsSourceSnapshot> load({
    required DateTime earliest,
    bool forceRefresh = false,
  }) async {
    if (sources.isEmpty) {
      return UsageStatisticsSourceSnapshot(
        records: const <AgentUsageRecord>[],
        refreshedAt: _clock(),
      );
    }

    final parts = await Future.wait(<Future<UsageStatisticsSourceSnapshot>>[
      for (final source in sources)
        _loadSource(source, earliest: earliest, forceRefresh: forceRefresh),
    ]);

    final records = <AgentUsageRecord>[
      for (final part in parts) ...part.records,
    ]..sort((left, right) => right.startedAt.compareTo(left.startedAt));

    final warnings = <String>[for (final part in parts) ...part.warnings];

    AgentUsageQuotaSnapshot? quota;
    for (final part in parts) {
      if (part.quota != null) {
        quota = part.quota;
        break;
      }
    }

    DateTime refreshedAt = parts.first.refreshedAt;
    for (final part in parts.skip(1)) {
      if (part.refreshedAt.isAfter(refreshedAt)) {
        refreshedAt = part.refreshedAt;
      }
    }

    return UsageStatisticsSourceSnapshot(
      records: List<AgentUsageRecord>.unmodifiable(records),
      refreshedAt: refreshedAt,
      quota: quota,
      warnings: List<String>.unmodifiable(warnings),
    );
  }

  Future<UsageStatisticsSourceSnapshot> _loadSource(
    UsageStatisticsRepository source, {
    required DateTime earliest,
    required bool forceRefresh,
  }) async {
    try {
      return await source.load(earliest: earliest, forceRefresh: forceRefresh);
    } catch (error) {
      return UsageStatisticsSourceSnapshot(
        records: const <AgentUsageRecord>[],
        refreshedAt: _clock(),
        warnings: <String>['部分 Agent 使用统计暂时无法读取：$error'],
      );
    }
  }
}

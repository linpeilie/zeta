import 'package:zeta/src/features/agent/domain/agent_usage_models.dart';
import 'package:zeta/src/features/usage_statistics/application/agent_usage_query_service.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_query_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_repository.dart';

/// 将统一用量查询结果聚合为完整统计页现有仓储契约。
final class QueryUsageStatisticsRepository
    implements UsageStatisticsRepository {
  QueryUsageStatisticsRepository(
    this._queryService, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AgentUsageQueryService _queryService;
  final DateTime Function() _clock;

  @override
  Future<UsageStatisticsSourceSnapshot> load({
    required DateTime earliest,
    bool forceRefresh = false,
  }) async {
    var providers = const <AgentUsageProviderDescriptor>[];
    final snapshots = <String, AgentUsageProviderSnapshot>{};
    DateTime? completedAt;

    await for (final event in _queryService.load(
      AgentUsageQuery(earliest: earliest, forceRefresh: forceRefresh),
    )) {
      switch (event) {
        case AgentUsageProvidersDiscovered():
          providers = event.providers;
        case AgentUsageProviderResolved():
          snapshots[event.snapshot.provider.providerId] = event.snapshot;
        case AgentUsageQueryCompleted():
          completedAt = event.refreshedAt;
      }
    }

    final records = <AgentUsageRecord>[];
    final warnings = <String>[];
    AgentUsageQuotaSnapshot? quota;
    DateTime? refreshedAt;
    for (final provider in providers) {
      final snapshot = snapshots[provider.providerId];
      if (snapshot == null) {
        continue;
      }
      if (quota == null && snapshot.quota.isAvailable) {
        quota = snapshot.quota.value;
      }
      switch (snapshot.tokenHistory.status) {
        case AgentUsageCapabilityStatus.available:
          final history = snapshot.tokenHistory.value;
          if (history == null) {
            continue;
          }
          records.addAll(history.records);
          warnings.addAll(history.warnings.map((warning) => warning.message));
          if (refreshedAt == null || history.refreshedAt.isAfter(refreshedAt)) {
            refreshedAt = history.refreshedAt;
          }
        case AgentUsageCapabilityStatus.unavailable:
          final warning = snapshot.tokenHistory.warning;
          if (warning != null) {
            warnings.add(warning.message);
          }
        case AgentUsageCapabilityStatus.unsupported:
          break;
      }
    }
    records.sort((left, right) => right.startedAt.compareTo(left.startedAt));

    return UsageStatisticsSourceSnapshot(
      records: List<AgentUsageRecord>.unmodifiable(records),
      refreshedAt: refreshedAt ?? completedAt ?? _clock(),
      quota: quota,
      warnings: List<String>.unmodifiable(warnings),
    );
  }
}

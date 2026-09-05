import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';

/// Zeta 使用统计自有文案目录。不暴露 ARB key、Locale 或 Provider raw payload。
abstract interface class UsageStatisticsTextCatalog
    implements AgentUsageSourceTextCatalog {
  String timeRangeLabel(UsageTimeRangePreset preset);

  String taskStatusLabel(UsageTaskStatus status);

  String errorCategoryLabel(UsageErrorCategory category);

  String errorNextAction(UsageErrorCategory category);

  String trendMetricLabel(UsageTrendMetric metric);

  String rankSortLabel(UsageRankSort sort);

  String get unknownProjectName;

  String loadFailed(Object error);

  String get quotaUnreadable;

  String get agentTemporarilyUnavailable;

  String get tokenHistoryUnavailable;

  String get tokenSourceMismatch;

  String get noTokenHistory;

  String get todayTokensUnreadable;

  @override
  String get indexWriteFailed;

  @override
  String indexReadRescanned(String providerName);

  String get agentDisabledOrUnavailable;

  String get agentUsageTemporarilyUnavailable;

  @override
  String sessionDirIncomplete(String name);

  @override
  String sessionFilesUnreadable(String count, String name);

  @override
  String historyRowsCorrupt(String count, String name);
}

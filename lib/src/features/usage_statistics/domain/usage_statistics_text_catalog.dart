import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';

/// Zeta 使用统计自有文案目录。不暴露 ARB key、Locale 或 Provider raw payload。
abstract interface class UsageStatisticsTextCatalog {
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

  String get indexWriteFailed;

  String indexReadRescanned(String providerName);

  String get agentDisabledOrUnavailable;

  String get agentUsageTemporarilyUnavailable;
}

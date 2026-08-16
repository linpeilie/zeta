import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_text_catalog.dart';
import 'package:zeta/src/ui/localization/generated/app_localizations.dart';

/// 把同一份 [AppLocalizations] 拆成各 feature 文本目录的组合对象。
final class ZetaTextCatalogs {
  const ZetaTextCatalogs(this.l10n);

  final AppLocalizations l10n;

  UsageStatisticsTextCatalog get usageStatistics =>
      AppUsageStatisticsTextCatalog(l10n);
}

final class AppUsageStatisticsTextCatalog
    implements UsageStatisticsTextCatalog {
  const AppUsageStatisticsTextCatalog(this._l10n);

  final AppLocalizations _l10n;

  @override
  String timeRangeLabel(UsageTimeRangePreset preset) => switch (preset) {
    UsageTimeRangePreset.today => _l10n.usageTimeRangeToday,
    UsageTimeRangePreset.last7Days => _l10n.usageTimeRangeLast7Days,
    UsageTimeRangePreset.last30Days => _l10n.usageTimeRangeLast30Days,
    UsageTimeRangePreset.last90Days => _l10n.usageTimeRangeLast90Days,
    UsageTimeRangePreset.thisMonth => _l10n.usageTimeRangeThisMonth,
    UsageTimeRangePreset.previousMonth => _l10n.usageTimeRangePreviousMonth,
    UsageTimeRangePreset.custom => _l10n.usageTimeRangeCustom,
  };

  @override
  String taskStatusLabel(UsageTaskStatus status) => switch (status) {
    UsageTaskStatus.running => _l10n.usageTaskStatusRunning,
    UsageTaskStatus.completed => _l10n.usageTaskStatusCompleted,
    UsageTaskStatus.interrupted => _l10n.usageTaskStatusInterrupted,
    UsageTaskStatus.failed => _l10n.usageTaskStatusFailed,
    UsageTaskStatus.unknown => _l10n.usageTaskStatusUnknown,
  };

  @override
  String errorCategoryLabel(UsageErrorCategory category) => switch (category) {
    UsageErrorCategory.account => _l10n.usageErrorCategoryAccount,
    UsageErrorCategory.cli => _l10n.usageErrorCategoryCli,
    UsageErrorCategory.network => _l10n.usageErrorCategoryNetwork,
    UsageErrorCategory.timeout => _l10n.usageErrorCategoryTimeout,
    UsageErrorCategory.cancelled => _l10n.usageErrorCategoryCancelled,
    UsageErrorCategory.other => _l10n.usageErrorCategoryOther,
  };

  @override
  String errorNextAction(UsageErrorCategory category) => switch (category) {
    UsageErrorCategory.account => _l10n.usageErrorNextActionAccount,
    UsageErrorCategory.cli => _l10n.usageErrorNextActionCli,
    UsageErrorCategory.network => _l10n.usageErrorNextActionNetwork,
    UsageErrorCategory.timeout => _l10n.usageErrorNextActionTimeout,
    UsageErrorCategory.cancelled => _l10n.usageErrorNextActionCancelled,
    UsageErrorCategory.other => _l10n.usageErrorNextActionOther,
  };

  @override
  String trendMetricLabel(UsageTrendMetric metric) => switch (metric) {
    UsageTrendMetric.calls => _l10n.usageTrendMetricCalls,
    UsageTrendMetric.successRate => _l10n.usageTrendMetricSuccessRate,
    UsageTrendMetric.totalTokens => _l10n.usageTrendMetricTotalTokens,
    UsageTrendMetric.averageResponse => _l10n.usageTrendMetricAverageResponse,
    UsageTrendMetric.averageDuration => _l10n.usageTrendMetricAverageDuration,
  };

  @override
  String rankSortLabel(UsageRankSort sort) => switch (sort) {
    UsageRankSort.calls => _l10n.usageRankSortCalls,
    UsageRankSort.totalTokens => _l10n.usageRankSortTotalTokens,
    UsageRankSort.failures => _l10n.usageRankSortFailures,
    UsageRankSort.averageDuration => _l10n.usageRankSortAverageDuration,
  };

  @override
  String get unknownProjectName => _l10n.usageUnknownProject;

  @override
  String loadFailed(Object error) => _l10n.usageLoadFailed('$error');

  @override
  String get quotaUnreadable => _l10n.usageQuotaUnreadable;

  @override
  String get agentTemporarilyUnavailable =>
      _l10n.usageAgentTemporarilyUnavailable;

  @override
  String get tokenHistoryUnavailable => _l10n.usageTokenHistoryUnavailable;

  @override
  String get tokenSourceMismatch => _l10n.usageTokenSourceMismatch;

  @override
  String get noTokenHistory => _l10n.usageNoTokenHistory;

  @override
  String get todayTokensUnreadable => _l10n.usageTodayTokensUnreadable;

  @override
  String get indexWriteFailed => _l10n.usageIndexWriteFailed;

  @override
  String indexReadRescanned(String providerName) =>
      _l10n.usageIndexReadRescanned(providerName);

  @override
  String get agentDisabledOrUnavailable =>
      _l10n.usageAgentDisabledOrUnavailable;

  @override
  String get agentUsageTemporarilyUnavailable =>
      _l10n.usageAgentUsageTemporarilyUnavailable;
}

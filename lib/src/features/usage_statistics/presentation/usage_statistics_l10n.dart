import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';
import 'package:zeta/src/ui/localization/generated/app_localizations.dart';

extension UsageTimeRangePresetL10n on UsageTimeRangePreset {
  String localizedLabel(AppLocalizations l10n) => switch (this) {
    UsageTimeRangePreset.today => l10n.usageTimeRangeToday,
    UsageTimeRangePreset.last7Days => l10n.usageTimeRangeLast7Days,
    UsageTimeRangePreset.last30Days => l10n.usageTimeRangeLast30Days,
    UsageTimeRangePreset.last90Days => l10n.usageTimeRangeLast90Days,
    UsageTimeRangePreset.thisMonth => l10n.usageTimeRangeThisMonth,
    UsageTimeRangePreset.previousMonth => l10n.usageTimeRangePreviousMonth,
    UsageTimeRangePreset.custom => l10n.usageTimeRangeCustom,
  };
}

extension UsageTaskStatusL10n on UsageTaskStatus {
  String localizedLabel(AppLocalizations l10n) => switch (this) {
    UsageTaskStatus.running => l10n.usageTaskStatusRunning,
    UsageTaskStatus.completed => l10n.usageTaskStatusCompleted,
    UsageTaskStatus.interrupted => l10n.usageTaskStatusInterrupted,
    UsageTaskStatus.failed => l10n.usageTaskStatusFailed,
    UsageTaskStatus.unknown => l10n.usageTaskStatusUnknown,
  };
}

extension UsageErrorCategoryL10n on UsageErrorCategory {
  String localizedLabel(AppLocalizations l10n) => switch (this) {
    UsageErrorCategory.account => l10n.usageErrorCategoryAccount,
    UsageErrorCategory.cli => l10n.usageErrorCategoryCli,
    UsageErrorCategory.network => l10n.usageErrorCategoryNetwork,
    UsageErrorCategory.timeout => l10n.usageErrorCategoryTimeout,
    UsageErrorCategory.cancelled => l10n.usageErrorCategoryCancelled,
    UsageErrorCategory.other => l10n.usageErrorCategoryOther,
  };

  String localizedNextAction(AppLocalizations l10n) => switch (this) {
    UsageErrorCategory.account => l10n.usageErrorNextActionAccount,
    UsageErrorCategory.cli => l10n.usageErrorNextActionCli,
    UsageErrorCategory.network => l10n.usageErrorNextActionNetwork,
    UsageErrorCategory.timeout => l10n.usageErrorNextActionTimeout,
    UsageErrorCategory.cancelled => l10n.usageErrorNextActionCancelled,
    UsageErrorCategory.other => l10n.usageErrorNextActionOther,
  };
}

extension UsageTrendMetricL10n on UsageTrendMetric {
  String localizedLabel(AppLocalizations l10n) => switch (this) {
    UsageTrendMetric.calls => l10n.usageTrendMetricCalls,
    UsageTrendMetric.successRate => l10n.usageTrendMetricSuccessRate,
    UsageTrendMetric.totalTokens => l10n.usageTrendMetricTotalTokens,
    UsageTrendMetric.averageResponse => l10n.usageTrendMetricAverageResponse,
    UsageTrendMetric.averageDuration => l10n.usageTrendMetricAverageDuration,
  };
}

extension UsageRankSortL10n on UsageRankSort {
  String localizedLabel(AppLocalizations l10n) => switch (this) {
    UsageRankSort.calls => l10n.usageRankSortCalls,
    UsageRankSort.totalTokens => l10n.usageRankSortTotalTokens,
    UsageRankSort.failures => l10n.usageRankSortFailures,
    UsageRankSort.averageDuration => l10n.usageRankSortAverageDuration,
  };
}

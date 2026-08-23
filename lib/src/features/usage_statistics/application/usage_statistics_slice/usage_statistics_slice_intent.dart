import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';

/// 完整使用统计页的 typed intent。
sealed class UsageStatisticsSliceIntent {
  const UsageStatisticsSliceIntent();
}

final class UsageStatisticsLoadRequested extends UsageStatisticsSliceIntent {
  const UsageStatisticsLoadRequested({
    required this.operationId,
    required this.earliest,
    required this.forceRefresh,
    required this.reportNow,
    required this.markInitialized,
  });

  final OperationId operationId;
  final DateTime earliest;
  final bool forceRefresh;
  final DateTime reportNow;
  final bool markInitialized;
}

final class UsageStatisticsSourceLoaded extends UsageStatisticsSliceIntent {
  const UsageStatisticsSourceLoaded({
    required this.operationId,
    required this.earliest,
    required this.source,
    required this.reportNow,
  });

  final OperationId operationId;
  final DateTime earliest;
  final UsageStatisticsSourceSnapshot source;
  final DateTime reportNow;
}

final class UsageStatisticsLoadFailed extends UsageStatisticsSliceIntent {
  const UsageStatisticsLoadFailed({
    required this.operationId,
    required this.message,
  });

  final OperationId operationId;
  final String message;
}

final class UsageStatisticsTimePresetSelected
    extends UsageStatisticsSliceIntent {
  const UsageStatisticsTimePresetSelected(this.value, this.reportNow);

  final UsageTimeRangePreset value;
  final DateTime reportNow;
}

final class UsageStatisticsCustomRangeSelected
    extends UsageStatisticsSliceIntent {
  const UsageStatisticsCustomRangeSelected({
    required this.start,
    required this.endInclusive,
    required this.reportNow,
  });

  final DateTime start;
  final DateTime endInclusive;
  final DateTime reportNow;
}

final class UsageStatisticsProjectSelected extends UsageStatisticsSliceIntent {
  const UsageStatisticsProjectSelected(this.value, this.reportNow);

  final String? value;
  final DateTime reportNow;
}

final class UsageStatisticsProviderSelected extends UsageStatisticsSliceIntent {
  const UsageStatisticsProviderSelected(this.value, this.reportNow);

  final String? value;
  final DateTime reportNow;
}

final class UsageStatisticsModelSelected extends UsageStatisticsSliceIntent {
  const UsageStatisticsModelSelected(this.value, this.reportNow);

  final String? value;
  final DateTime reportNow;
}

final class UsageStatisticsRankSortSelected extends UsageStatisticsSliceIntent {
  const UsageStatisticsRankSortSelected(this.value, this.reportNow);

  final UsageRankSort value;
  final DateTime reportNow;
}

import 'package:zeta_foundation/zeta_foundation.dart';

/// 完整使用统计页的副作用描述；执行统一留在 app runner。
sealed class UsageStatisticsSliceEffect {
  const UsageStatisticsSliceEffect();
}

/// 从既有 repository 读取指定覆盖边界后的中立统计快照。
final class LoadUsageStatisticsSourceEffect extends UsageStatisticsSliceEffect {
  const LoadUsageStatisticsSourceEffect({
    required this.operationId,
    required this.earliest,
    required this.forceRefresh,
    required this.reportNow,
  });

  final OperationId operationId;
  final DateTime earliest;
  final bool forceRefresh;

  /// result intent 重建报表时使用的显式时间，reducer 不读取系统时钟。
  final DateTime reportNow;
}

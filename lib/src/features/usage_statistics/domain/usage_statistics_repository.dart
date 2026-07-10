import 'usage_statistics_models.dart';

/// 使用统计的中立数据源。
abstract class UsageStatisticsRepository {
  /// 加载 [earliest] 之后的调用记录，并按需刷新 provider 原始历史。
  Future<UsageStatisticsSourceSnapshot> load({
    required DateTime earliest,
    bool forceRefresh = false,
  });
}

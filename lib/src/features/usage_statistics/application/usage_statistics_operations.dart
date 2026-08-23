import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_repository.dart';

/// 完整使用统计页对 presentation 暴露的稳定操作面。
///
/// 迁移期间 legacy controller 与 MVI store 分别实现本端口；Widget 不感知
/// owner 形态，也不会同时写入两条路径。
abstract interface class UsageStatisticsOperations {
  UsageStatisticsRepository get repository;

  UsageTimeRangePreset get timePreset;
  DateTime? get customStart;
  DateTime? get customEndInclusive;
  String? get projectPath;
  String? get providerId;
  String? get model;
  UsageRankSort get rankSort;
  UsageStatisticsReport? get report;
  UsageStatisticsSourceSnapshot? get source;
  bool get loading;
  String? get errorMessage;
  DateTime? get lastUpdated;
  List<String> get warnings;
  UsageDateWindow get window;

  Future<void> initialize();
  Future<void> refresh();
  Future<void> selectTimePreset(UsageTimeRangePreset value);
  Future<void> selectCustomRange(DateTime start, DateTime endInclusive);
  void selectProject(String? value);
  void selectProvider(String? value);
  void selectModel(String? value);
  void selectRankSort(UsageRankSort value);

  void dispose();
}

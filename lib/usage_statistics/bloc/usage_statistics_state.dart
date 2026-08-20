import 'package:equatable/equatable.dart';
import 'package:usage_statistics_repository/usage_statistics_repository.dart';

export 'package:usage_statistics_repository/usage_statistics_repository.dart'
    show
        UsageRecord,
        UsageStatisticsQuery,
        UsageStatisticsReport,
        UsageWarning,
        UsageWarningCode;

enum UsageStatisticsStatus { initial, loading, ready, failure }

enum UsageTimePreset {
  today,
  last7Days,
  last30Days,
  last90Days,
  thisMonth,
  previousMonth,
}

enum UsageRankSort { calls, totalTokens, failures, averageDuration }

final class UsageChartPoint extends Equatable {
  const UsageChartPoint({required this.x, required this.y});

  final double x;
  final double y;

  @override
  List<Object?> get props => <Object?>[x, y];
}

final class UsageStatisticsState extends Equatable {
  const UsageStatisticsState({
    this.status = UsageStatisticsStatus.initial,
    this.preset = UsageTimePreset.last7Days,
    this.projectPath,
    this.providerId,
    this.model,
    this.rankSort = UsageRankSort.totalTokens,
    this.report,
    this.chartPoints = const <UsageChartPoint>[],
    this.rankedRecords = const <UsageRecord>[],
    this.queryGeneration = 0,
    this.cancelled = false,
  });

  final UsageStatisticsStatus status;
  final UsageTimePreset preset;
  final String? projectPath;
  final String? providerId;
  final String? model;
  final UsageRankSort rankSort;
  final UsageStatisticsReport? report;
  final List<UsageChartPoint> chartPoints;
  final List<UsageRecord> rankedRecords;
  final int queryGeneration;
  final bool cancelled;

  UsageStatisticsState copyWith({
    UsageStatisticsStatus? status,
    UsageTimePreset? preset,
    String? projectPath,
    String? providerId,
    String? model,
    UsageRankSort? rankSort,
    UsageStatisticsReport? report,
    List<UsageChartPoint>? chartPoints,
    List<UsageRecord>? rankedRecords,
    int? queryGeneration,
    bool? cancelled,
    bool clearProject = false,
    bool clearProvider = false,
    bool clearModel = false,
    bool clearReport = false,
  }) {
    return UsageStatisticsState(
      status: status ?? this.status,
      preset: preset ?? this.preset,
      projectPath: clearProject ? null : (projectPath ?? this.projectPath),
      providerId: clearProvider ? null : (providerId ?? this.providerId),
      model: clearModel ? null : (model ?? this.model),
      rankSort: rankSort ?? this.rankSort,
      report: clearReport ? null : (report ?? this.report),
      chartPoints: chartPoints ?? this.chartPoints,
      rankedRecords: rankedRecords ?? this.rankedRecords,
      queryGeneration: queryGeneration ?? this.queryGeneration,
      cancelled: cancelled ?? this.cancelled,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    status,
    preset,
    projectPath,
    providerId,
    model,
    rankSort,
    report,
    chartPoints,
    rankedRecords,
    queryGeneration,
    cancelled,
  ];
}

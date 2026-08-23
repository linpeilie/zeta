import 'package:meta/meta.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';

const Object _usageStatisticsUnset = Object();

/// 完整使用统计页的不可变 application state。
@immutable
final class UsageStatisticsSliceState {
  const UsageStatisticsSliceState({
    this.timePreset = UsageTimeRangePreset.last7Days,
    this.customStart,
    this.customEndInclusive,
    this.selectedProjectPath,
    this.selectedProviderId,
    this.selectedModel,
    this.rankSort = UsageRankSort.calls,
    this.source,
    this.report,
    this.loadedEarliest,
    this.loadingOperationId,
    this.initialized = false,
    this.errorMessage,
  });

  final UsageTimeRangePreset timePreset;
  final DateTime? customStart;
  final DateTime? customEndInclusive;
  final String? selectedProjectPath;
  final String? selectedProviderId;
  final String? selectedModel;
  final UsageRankSort rankSort;
  final UsageStatisticsSourceSnapshot? source;
  final UsageStatisticsReport? report;
  final DateTime? loadedEarliest;
  final OperationId? loadingOperationId;
  final bool initialized;

  /// 文本目录投影后的稳定错误；不保存 raw exception。
  final String? errorMessage;

  bool get loading => loadingOperationId != null;
  DateTime? get lastUpdated => source?.refreshedAt;
  List<String> get warnings => source?.warnings ?? const <String>[];

  UsageStatisticsSliceState copyWith({
    UsageTimeRangePreset? timePreset,
    Object? customStart = _usageStatisticsUnset,
    Object? customEndInclusive = _usageStatisticsUnset,
    Object? selectedProjectPath = _usageStatisticsUnset,
    Object? selectedProviderId = _usageStatisticsUnset,
    Object? selectedModel = _usageStatisticsUnset,
    UsageRankSort? rankSort,
    Object? source = _usageStatisticsUnset,
    Object? report = _usageStatisticsUnset,
    Object? loadedEarliest = _usageStatisticsUnset,
    Object? loadingOperationId = _usageStatisticsUnset,
    bool? initialized,
    Object? errorMessage = _usageStatisticsUnset,
  }) {
    return UsageStatisticsSliceState(
      timePreset: timePreset ?? this.timePreset,
      customStart: identical(customStart, _usageStatisticsUnset)
          ? this.customStart
          : customStart as DateTime?,
      customEndInclusive: identical(customEndInclusive, _usageStatisticsUnset)
          ? this.customEndInclusive
          : customEndInclusive as DateTime?,
      selectedProjectPath: identical(selectedProjectPath, _usageStatisticsUnset)
          ? this.selectedProjectPath
          : selectedProjectPath as String?,
      selectedProviderId: identical(selectedProviderId, _usageStatisticsUnset)
          ? this.selectedProviderId
          : selectedProviderId as String?,
      selectedModel: identical(selectedModel, _usageStatisticsUnset)
          ? this.selectedModel
          : selectedModel as String?,
      rankSort: rankSort ?? this.rankSort,
      source: identical(source, _usageStatisticsUnset)
          ? this.source
          : source as UsageStatisticsSourceSnapshot?,
      report: identical(report, _usageStatisticsUnset)
          ? this.report
          : report as UsageStatisticsReport?,
      loadedEarliest: identical(loadedEarliest, _usageStatisticsUnset)
          ? this.loadedEarliest
          : loadedEarliest as DateTime?,
      loadingOperationId: identical(loadingOperationId, _usageStatisticsUnset)
          ? this.loadingOperationId
          : loadingOperationId as OperationId?,
      initialized: initialized ?? this.initialized,
      errorMessage: identical(errorMessage, _usageStatisticsUnset)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}

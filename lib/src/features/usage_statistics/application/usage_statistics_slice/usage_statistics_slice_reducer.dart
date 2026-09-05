import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/usage_statistics/application/usage_statistics_report_builder.dart';
import 'package:zeta/src/features/usage_statistics/application/usage_statistics_slice/usage_statistics_slice_effect.dart';
import 'package:zeta/src/features/usage_statistics/application/usage_statistics_slice/usage_statistics_slice_intent.dart';
import 'package:zeta/src/features/usage_statistics/application/usage_statistics_slice/usage_statistics_slice_state.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';

/// 完整使用统计页的纯同步 reducer。
Transition<UsageStatisticsSliceState, UsageStatisticsSliceEffect>
usageStatisticsSliceReduce(
  UsageStatisticsSliceState state,
  UsageStatisticsSliceIntent intent,
) {
  switch (intent) {
    case UsageStatisticsLoadRequested():
      return Transition(
        state.copyWith(
          loadingOperationId: intent.operationId,
          initialized: state.initialized || intent.markInitialized,
          errorMessage: null,
        ),
        <UsageStatisticsSliceEffect>[
          LoadUsageStatisticsSourceEffect(
            operationId: intent.operationId,
            earliest: intent.earliest,
            forceRefresh: intent.forceRefresh,
            reportNow: intent.reportNow,
          ),
        ],
      );

    case UsageStatisticsSourceLoaded():
      if (state.loadingOperationId != intent.operationId) {
        return Transition.none(state);
      }
      final loadedEarliest = state.loadedEarliest;
      return Transition.stateOnly(
        rebuildUsageStatisticsReport(
          state.copyWith(
            source: intent.source,
            loadedEarliest:
                loadedEarliest == null ||
                    intent.earliest.isBefore(loadedEarliest)
                ? intent.earliest
                : loadedEarliest,
            loadingOperationId: null,
            errorMessage: null,
          ),
          intent.reportNow,
        ),
      );

    case UsageStatisticsLoadFailed():
      if (state.loadingOperationId != intent.operationId) {
        return Transition.none(state);
      }
      return Transition.stateOnly(
        state.copyWith(loadingOperationId: null, errorMessage: intent.message),
      );

    case UsageStatisticsTimePresetSelected():
      if (state.timePreset == intent.value) {
        return Transition.none(state);
      }
      return Transition.stateOnly(
        rebuildUsageStatisticsReport(
          state.copyWith(timePreset: intent.value),
          intent.reportNow,
        ),
      );

    case UsageStatisticsCustomRangeSelected():
      return Transition.stateOnly(
        rebuildUsageStatisticsReport(
          state.copyWith(
            timePreset: UsageTimeRangePreset.custom,
            customStart: intent.start,
            customEndInclusive: intent.endInclusive,
          ),
          intent.reportNow,
        ),
      );

    case UsageStatisticsProjectSelected():
      if (state.selectedProjectPath == intent.value) {
        return Transition.none(state);
      }
      return Transition.stateOnly(
        rebuildUsageStatisticsReport(
          state.copyWith(selectedProjectPath: intent.value),
          intent.reportNow,
        ),
      );

    case UsageStatisticsProviderSelected():
      if (state.selectedProviderId == intent.value) {
        return Transition.none(state);
      }
      return Transition.stateOnly(
        rebuildUsageStatisticsReport(
          state.copyWith(selectedProviderId: intent.value),
          intent.reportNow,
        ),
      );

    case UsageStatisticsModelSelected():
      if (state.selectedModel == intent.value) {
        return Transition.none(state);
      }
      return Transition.stateOnly(
        rebuildUsageStatisticsReport(
          state.copyWith(selectedModel: intent.value),
          intent.reportNow,
        ),
      );

    case UsageStatisticsRankSortSelected():
      if (state.rankSort == intent.value) {
        return Transition.none(state);
      }
      return Transition.stateOnly(
        rebuildUsageStatisticsReport(
          state.copyWith(rankSort: intent.value),
          intent.reportNow,
        ),
      );
  }
}

/// 按现有 controller 的两遍算法重建报表，并清除已不存在的筛选项。
UsageStatisticsSliceState rebuildUsageStatisticsReport(
  UsageStatisticsSliceState state,
  DateTime now,
) {
  final source = state.source;
  if (source == null) {
    return state.copyWith(report: null);
  }
  final window = usageStatisticsWindow(state, now);
  final candidate = buildUsageStatisticsReport(
    source: source,
    window: window,
    filter: UsageStatisticsFilter(
      projectPath: state.selectedProjectPath,
      providerId: state.selectedProviderId,
      model: state.selectedModel,
    ),
    trendMetric: UsageTrendMetric.totalTokens,
    rankSort: state.rankSort,
  );
  final project = _retainOption(
    state.selectedProjectPath,
    candidate.projectOptions,
  );
  final provider = _retainOption(
    state.selectedProviderId,
    candidate.agentOptions,
  );
  final model = _retainOption(state.selectedModel, candidate.modelOptions);
  final report = buildUsageStatisticsReport(
    source: source,
    window: window,
    filter: UsageStatisticsFilter(
      projectPath: project,
      providerId: provider,
      model: model,
    ),
    trendMetric: UsageTrendMetric.totalTokens,
    rankSort: state.rankSort,
  );
  return state.copyWith(
    selectedProjectPath: project,
    selectedProviderId: provider,
    selectedModel: model,
    report: report,
  );
}

UsageDateWindow usageStatisticsWindow(
  UsageStatisticsSliceState state,
  DateTime now,
) {
  return UsageDateWindow.resolve(
    preset: state.timePreset,
    now: now,
    customStart: state.customStart,
    customEndInclusive: state.customEndInclusive,
  );
}

String? _retainOption(String? selected, List<String> options) {
  return selected == null || options.contains(selected) ? selected : null;
}

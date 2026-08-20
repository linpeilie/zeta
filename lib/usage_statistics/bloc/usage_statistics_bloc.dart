import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:usage_statistics_repository/usage_statistics_repository.dart';
import 'package:zeta/usage_statistics/bloc/usage_statistics_event.dart';
import 'package:zeta/usage_statistics/bloc/usage_statistics_state.dart';

// Named public constructor parameters initialize private fields.
// ignore_for_file: prefer_initializing_formals

class UsageStatisticsBloc
    extends Bloc<UsageStatisticsEvent, UsageStatisticsState> {
  UsageStatisticsBloc({
    required UsageStatisticsRepository usageStatisticsRepository,
    DateTime Function()? clock,
  }) : _usageStatisticsRepository = usageStatisticsRepository,
       _clock = clock ?? DateTime.now,
       super(const UsageStatisticsState()) {
    on<UsageStatisticsStarted>(_onStarted, transformer: restartable());
    on<UsageStatisticsPresetChanged>(
      _onPresetChanged,
      transformer: restartable(),
    );
    on<UsageStatisticsProjectChanged>(
      _onProjectChanged,
      transformer: restartable(),
    );
    on<UsageStatisticsProviderChanged>(
      _onProviderChanged,
      transformer: restartable(),
    );
    on<UsageStatisticsModelChanged>(
      _onModelChanged,
      transformer: restartable(),
    );
    on<UsageStatisticsRankSortChanged>(_onRankSortChanged);
    on<UsageStatisticsRefreshRequested>(
      _onRefreshRequested,
      transformer: restartable(),
    );
    on<UsageStatisticsRepeatRefreshRequested>(
      _onRepeatRefreshRequested,
      transformer: droppable(),
    );
  }

  final UsageStatisticsRepository _usageStatisticsRepository;
  final DateTime Function() _clock;

  Future<void> _onStarted(
    UsageStatisticsStarted event,
    Emitter<UsageStatisticsState> emit,
  ) {
    return _load(emit, forceRefresh: false);
  }

  Future<void> _onPresetChanged(
    UsageStatisticsPresetChanged event,
    Emitter<UsageStatisticsState> emit,
  ) async {
    emit(state.copyWith(preset: event.preset, cancelled: false));
    await _load(emit, forceRefresh: false);
  }

  Future<void> _onProjectChanged(
    UsageStatisticsProjectChanged event,
    Emitter<UsageStatisticsState> emit,
  ) async {
    emit(
      state.copyWith(
        projectPath: event.projectPath,
        clearProject: event.projectPath == null,
        cancelled: false,
      ),
    );
    await _load(emit, forceRefresh: false);
  }

  Future<void> _onProviderChanged(
    UsageStatisticsProviderChanged event,
    Emitter<UsageStatisticsState> emit,
  ) async {
    emit(
      state.copyWith(
        providerId: event.providerId,
        clearProvider: event.providerId == null,
        cancelled: false,
      ),
    );
    await _load(emit, forceRefresh: false);
  }

  Future<void> _onModelChanged(
    UsageStatisticsModelChanged event,
    Emitter<UsageStatisticsState> emit,
  ) async {
    emit(
      state.copyWith(
        model: event.model,
        clearModel: event.model == null,
        cancelled: false,
      ),
    );
    await _load(emit, forceRefresh: false);
  }

  void _onRankSortChanged(
    UsageStatisticsRankSortChanged event,
    Emitter<UsageStatisticsState> emit,
  ) {
    final report = state.report;
    emit(
      state.copyWith(
        rankSort: event.sort,
        rankedRecords: report == null
            ? const <UsageRecord>[]
            : _rank(report.records, event.sort),
      ),
    );
  }

  Future<void> _onRefreshRequested(
    UsageStatisticsRefreshRequested event,
    Emitter<UsageStatisticsState> emit,
  ) {
    return _load(emit, forceRefresh: true);
  }

  Future<void> _onRepeatRefreshRequested(
    UsageStatisticsRepeatRefreshRequested event,
    Emitter<UsageStatisticsState> emit,
  ) {
    return _load(emit, forceRefresh: true);
  }

  Future<void> _load(
    Emitter<UsageStatisticsState> emit, {
    required bool forceRefresh,
  }) async {
    final generation = state.queryGeneration + 1;
    emit(
      state.copyWith(
        status: UsageStatisticsStatus.loading,
        queryGeneration: generation,
        cancelled: false,
      ),
    );
    try {
      final report = await _usageStatisticsRepository.report(
        _query(forceRefresh: forceRefresh),
        isCancelled: () => emit.isDone || generation != state.queryGeneration,
      );
      if (emit.isDone || generation != state.queryGeneration) {
        return;
      }
      emit(
        state.copyWith(
          status: UsageStatisticsStatus.ready,
          report: report,
          chartPoints: _chartPoints(report),
          rankedRecords: _rank(report.records, state.rankSort),
        ),
      );
    } on UsageStatisticsCancelledException {
      if (emit.isDone || generation != state.queryGeneration) {
        return;
      }
      emit(
        state.copyWith(
          status: state.report == null
              ? UsageStatisticsStatus.failure
              : UsageStatisticsStatus.ready,
          cancelled: true,
        ),
      );
    } on Object {
      if (emit.isDone || generation != state.queryGeneration) {
        return;
      }
      emit(
        state.copyWith(
          status: UsageStatisticsStatus.failure,
          clearReport: true,
          chartPoints: const <UsageChartPoint>[],
          rankedRecords: const <UsageRecord>[],
        ),
      );
    }
  }

  UsageStatisticsQuery _query({required bool forceRefresh}) {
    final now = _clock();
    final today = DateTime(now.year, now.month, now.day);
    final nextDay = today.add(const Duration(days: 1));
    final range = switch (state.preset) {
      UsageTimePreset.today => (today, nextDay),
      UsageTimePreset.last7Days => (
        today.subtract(const Duration(days: 6)),
        nextDay,
      ),
      UsageTimePreset.last30Days => (
        today.subtract(const Duration(days: 29)),
        nextDay,
      ),
      UsageTimePreset.last90Days => (
        today.subtract(const Duration(days: 89)),
        nextDay,
      ),
      UsageTimePreset.thisMonth => (DateTime(now.year, now.month), nextDay),
      UsageTimePreset.previousMonth => (
        DateTime(now.year, now.month - 1),
        DateTime(now.year, now.month),
      ),
    };
    return UsageStatisticsQuery(
      startInclusive: range.$1,
      endExclusive: range.$2,
      forceRefresh: forceRefresh,
    );
  }

  List<UsageChartPoint> _chartPoints(UsageStatisticsReport report) {
    final start = DateTime(
      report.query.startInclusive.year,
      report.query.startInclusive.month,
      report.query.startInclusive.day,
    );
    final buckets = <int, double>{};
    for (final record in _filtered(report.records)) {
      final day = DateTime(
        record.startedAt.year,
        record.startedAt.month,
        record.startedAt.day,
      );
      final index = day.difference(start).inDays;
      if (index < 0) {
        continue;
      }
      buckets[index] =
          (buckets[index] ?? 0) + (record.tokens.effectiveTotal ?? 0);
    }
    final keys = buckets.keys.toList()..sort();
    return <UsageChartPoint>[
      for (final key in keys)
        UsageChartPoint(x: key.toDouble(), y: buckets[key]!),
    ];
  }

  List<UsageRecord> _rank(List<UsageRecord> records, UsageRankSort sort) {
    final filtered = _filtered(records).toList()
      ..sort((left, right) {
        final comparison = switch (sort) {
          UsageRankSort.calls => 0,
          UsageRankSort.totalTokens =>
            (right.tokens.effectiveTotal ?? 0).compareTo(
              left.tokens.effectiveTotal ?? 0,
            ),
          UsageRankSort.failures =>
            (right.status.isFailure ? 1 : 0) - (left.status.isFailure ? 1 : 0),
          UsageRankSort.averageDuration =>
            (right.duration ?? Duration.zero).compareTo(
              left.duration ?? Duration.zero,
            ),
        };
        if (comparison != 0) {
          return comparison;
        }
        return right.startedAt.compareTo(left.startedAt);
      });
    return filtered;
  }

  Iterable<UsageRecord> _filtered(List<UsageRecord> records) {
    return records.where((record) {
      final projectPath = state.projectPath;
      final providerId = state.providerId;
      final model = state.model;
      if (projectPath != null && record.projectPath != projectPath) {
        return false;
      }
      if (providerId != null && record.providerId != providerId) {
        return false;
      }
      if (model != null && record.model != model) {
        return false;
      }
      return true;
    });
  }
}

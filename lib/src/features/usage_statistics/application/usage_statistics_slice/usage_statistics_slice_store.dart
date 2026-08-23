import 'dart:async';

import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/usage_statistics/application/usage_statistics_operations.dart';
import 'package:zeta/src/features/usage_statistics/application/usage_statistics_slice/usage_statistics_slice_effect.dart';
import 'package:zeta/src/features/usage_statistics/application/usage_statistics_slice/usage_statistics_slice_intent.dart';
import 'package:zeta/src/features/usage_statistics/application/usage_statistics_slice/usage_statistics_slice_reducer.dart';
import 'package:zeta/src/features/usage_statistics/application/usage_statistics_slice/usage_statistics_slice_state.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_repository.dart';

/// 完整使用统计页 effect 的 app 组合层执行入口。
abstract interface class UsageStatisticsSliceEffectRunner {
  UsageStatisticsRepository get repository;

  void run(UsageStatisticsSliceEffect effect);

  void close();
}

/// 完整使用统计页的纯 Dart MVI owner。
final class UsageStatisticsSliceStore implements UsageStatisticsOperations {
  UsageStatisticsSliceStore({
    required UsageStatisticsSliceState initialState,
    required this.effectRunner,
    DateTime Function()? clock,
    OperationIdGenerator? operationIdGenerator,
  }) : _state = initialState,
       _clock = clock ?? DateTime.now,
       _operationIdGenerator =
           operationIdGenerator ??
           OperationIdGenerator(scope: 'usage-statistics/load');

  final UsageStatisticsSliceEffectRunner effectRunner;
  final DateTime Function() _clock;
  final OperationIdGenerator _operationIdGenerator;
  final List<void Function()> _listeners = <void Function()>[];
  final Map<OperationId, Completer<void>> _loadCompleters =
      <OperationId, Completer<void>>{};

  UsageStatisticsSliceState _state;
  bool _closed = false;

  UsageStatisticsSliceState get state => _state;
  bool get isClosed => _closed;

  @override
  UsageStatisticsRepository get repository => effectRunner.repository;

  @override
  UsageTimeRangePreset get timePreset => _state.timePreset;

  @override
  DateTime? get customStart => _state.customStart;

  @override
  DateTime? get customEndInclusive => _state.customEndInclusive;

  @override
  String? get projectPath => _state.selectedProjectPath;

  @override
  String? get providerId => _state.selectedProviderId;

  @override
  String? get model => _state.selectedModel;

  @override
  UsageRankSort get rankSort => _state.rankSort;

  @override
  UsageStatisticsReport? get report => _state.report;

  @override
  UsageStatisticsSourceSnapshot? get source => _state.source;

  @override
  bool get loading => _state.loading;

  @override
  String? get errorMessage => _state.errorMessage;

  @override
  DateTime? get lastUpdated => _state.lastUpdated;

  @override
  List<String> get warnings => _state.warnings;

  @override
  UsageDateWindow get window => usageStatisticsWindow(_state, _clock());

  void addListener(void Function() listener) => _listeners.add(listener);

  void removeListener(void Function() listener) => _listeners.remove(listener);

  void Function() subscribe(void Function() listener) {
    addListener(listener);
    return () => removeListener(listener);
  }

  @override
  Future<void> initialize() {
    _ensureOpen();
    if (_state.initialized) {
      return Future<void>.value();
    }
    return _load(forceRefresh: false, markInitialized: true);
  }

  @override
  Future<void> refresh() {
    _ensureOpen();
    return _load(forceRefresh: true, markInitialized: false);
  }

  @override
  Future<void> selectTimePreset(UsageTimeRangePreset value) async {
    _ensureOpen();
    final before = _state;
    _dispatch(UsageStatisticsTimePresetSelected(value, _clock()));
    if (identical(before, _state)) {
      return;
    }
    await _ensureWindowLoaded();
  }

  @override
  Future<void> selectCustomRange(DateTime start, DateTime endInclusive) async {
    _ensureOpen();
    _dispatch(
      UsageStatisticsCustomRangeSelected(
        start: start,
        endInclusive: endInclusive,
        reportNow: _clock(),
      ),
    );
    await _ensureWindowLoaded();
  }

  @override
  void selectProject(String? value) {
    _ensureOpen();
    _dispatch(UsageStatisticsProjectSelected(value, _clock()));
  }

  @override
  void selectProvider(String? value) {
    _ensureOpen();
    _dispatch(UsageStatisticsProviderSelected(value, _clock()));
  }

  @override
  void selectModel(String? value) {
    _ensureOpen();
    _dispatch(UsageStatisticsModelSelected(value, _clock()));
  }

  @override
  void selectRankSort(UsageRankSort value) {
    _ensureOpen();
    _dispatch(UsageStatisticsRankSortSelected(value, _clock()));
  }

  Future<void> _ensureWindowLoaded() {
    final requiredEarliest = window.previous.start;
    final loadedEarliest = _state.loadedEarliest;
    if (loadedEarliest == null || requiredEarliest.isBefore(loadedEarliest)) {
      return _load(forceRefresh: false, markInitialized: false);
    }
    return Future<void>.value();
  }

  Future<void> _load({
    required bool forceRefresh,
    required bool markInitialized,
  }) {
    final operationId = _operationIdGenerator.next();
    final completer = Completer<void>();
    _loadCompleters[operationId] = completer;
    final now = _clock();
    final requiredEarliest = usageStatisticsWindow(_state, now).previous.start;
    try {
      _dispatch(
        UsageStatisticsLoadRequested(
          operationId: operationId,
          earliest: requiredEarliest,
          forceRefresh: forceRefresh,
          reportNow: now,
          markInitialized: markInitialized,
        ),
      );
    } catch (_) {
      _loadCompleters.remove(operationId);
      rethrow;
    }
    return completer.future;
  }

  /// runner 的 typed 成功回流入口。
  void sourceLoaded({
    required OperationId operationId,
    required DateTime earliest,
    required UsageStatisticsSourceSnapshot source,
    required DateTime reportNow,
  }) {
    if (_closed) {
      return;
    }
    _dispatch(
      UsageStatisticsSourceLoaded(
        operationId: operationId,
        earliest: earliest,
        source: source,
        reportNow: reportNow,
      ),
    );
    _completeLoad(operationId);
  }

  /// runner 的 typed 失败回流入口；message 已由文本目录脱敏投影。
  void loadFailed({required OperationId operationId, required String message}) {
    if (_closed) {
      return;
    }
    _dispatch(
      UsageStatisticsLoadFailed(operationId: operationId, message: message),
    );
    _completeLoad(operationId);
  }

  void _completeLoad(OperationId operationId) {
    final completer = _loadCompleters.remove(operationId);
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  void _dispatch(UsageStatisticsSliceIntent intent) {
    if (_closed) {
      return;
    }
    final transition = usageStatisticsSliceReduce(_state, intent);
    final nextState = transition.state;
    if (!identical(nextState, _state)) {
      _state = nextState;
      for (final listener in List<void Function()>.of(_listeners)) {
        listener();
      }
    }
    for (final effect in transition.effects) {
      effectRunner.run(effect);
    }
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('UsageStatisticsSliceStore is closed');
    }
  }

  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    effectRunner.close();
    for (final completer in _loadCompleters.values) {
      if (!completer.isCompleted) {
        // 页面以 unawaited initialize 启动；关闭是取消，不应在卸载阶段制造
        // 未处理异常。真实查询失败仍由 loadFailed intent 投影到 state。
        completer.complete();
      }
    }
    _loadCompleters.clear();
    _listeners.clear();
  }

  @override
  void dispose() => close();
}

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  void run(UsageStatisticsSliceEffect effect);

  void close();
}

/// runner 工厂：把 notifier 作为 typed 回流目标，避免 runner 延迟反向绑定。
typedef UsageStatisticsSliceEffectRunnerFactory =
    UsageStatisticsSliceEffectRunner Function(
      UsageStatisticsSliceNotifier notifier,
    );

/// 完整使用统计页切片所需的中立 application 依赖。
final class UsageStatisticsSliceDependencies {
  UsageStatisticsSliceDependencies({
    required this.repository,
    this.initialState = const UsageStatisticsSliceState(),
    DateTime Function()? clock,
    OperationIdGenerator? operationIdGenerator,
  }) : clock = clock ?? DateTime.now,
       operationIdGenerator =
           operationIdGenerator ??
           OperationIdGenerator(scope: 'usage-statistics/load');

  final UsageStatisticsSliceState initialState;
  final UsageStatisticsRepository repository;
  final DateTime Function() clock;
  final OperationIdGenerator operationIdGenerator;
}

/// 组合根必须安装的切片依赖；缺失时 fail-closed。
final usageStatisticsSliceDependenciesProvider =
    Provider<UsageStatisticsSliceDependencies>(
      (ref) => throw StateError(
        'usageStatisticsSliceDependenciesProvider was read before the '
        'composition root overrode it',
      ),
      name: 'usageStatisticsSliceDependencies',
    );

/// 组合根必须安装的 runner 工厂；缺失时不伪造加载成功。
final usageStatisticsSliceEffectRunnerFactoryProvider =
    Provider<UsageStatisticsSliceEffectRunnerFactory>(
      (ref) => throw StateError(
        'usageStatisticsSliceEffectRunnerFactoryProvider was read before '
        'the composition root overrode it',
      ),
      name: 'usageStatisticsSliceEffectRunnerFactory',
    );

/// 完整使用统计页的唯一 app-session 状态 owner。
///
/// 不是 autoDispose：在途历史聚合与缓存跟随应用会话，不能由统计页是否挂载决定。
final usageStatisticsSliceProvider =
    NotifierProvider<UsageStatisticsSliceNotifier, UsageStatisticsSliceState>(
      UsageStatisticsSliceNotifier.new,
      name: 'usageStatisticsSlice',
    );

/// 完整使用统计页的 Riverpod MVI owner。
final class UsageStatisticsSliceNotifier
    extends Notifier<UsageStatisticsSliceState>
    implements UsageStatisticsOperations {
  late UsageStatisticsSliceEffectRunner _effectRunner;
  late UsageStatisticsRepository _repository;
  late DateTime Function() _clock;
  late OperationIdGenerator _operationIdGenerator;
  final Map<OperationId, Completer<void>> _loadCompleters =
      <OperationId, Completer<void>>{};

  late UsageStatisticsSliceState _working;
  bool _publishScheduled = false;
  bool _closed = false;

  @override
  UsageStatisticsSliceState build() {
    final dependencies = ref.watch(usageStatisticsSliceDependenciesProvider);
    _repository = dependencies.repository;
    _clock = dependencies.clock;
    _operationIdGenerator = dependencies.operationIdGenerator;
    _working = dependencies.initialState;
    _effectRunner = ref.watch(usageStatisticsSliceEffectRunnerFactoryProvider)(
      this,
    );
    ref.onDispose(_handleDispose);
    return _working;
  }

  @override
  UsageStatisticsSliceState get state => _working;

  bool get isClosed => _closed;

  /// 组合测试使用的只读接线出口；presentation 仍只依赖操作端口。
  UsageStatisticsRepository get repository => _repository;

  @override
  UsageTimeRangePreset get timePreset => _working.timePreset;

  @override
  DateTime? get customStart => _working.customStart;

  @override
  DateTime? get customEndInclusive => _working.customEndInclusive;

  @override
  String? get projectPath => _working.selectedProjectPath;

  @override
  String? get providerId => _working.selectedProviderId;

  @override
  String? get model => _working.selectedModel;

  @override
  UsageRankSort get rankSort => _working.rankSort;

  @override
  UsageStatisticsReport? get report => _working.report;

  @override
  UsageStatisticsSourceSnapshot? get source => _working.source;

  @override
  bool get loading => _working.loading;

  @override
  String? get errorMessage => _working.errorMessage;

  @override
  DateTime? get lastUpdated => _working.lastUpdated;

  @override
  List<String> get warnings => _working.warnings;

  @override
  UsageDateWindow get window => usageStatisticsWindow(_working, _clock());

  @override
  Future<void> initialize() {
    _ensureOpen();
    if (_working.initialized) {
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
    final before = _working;
    _dispatch(UsageStatisticsTimePresetSelected(value, _clock()));
    if (identical(before, _working)) {
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
    final loadedEarliest = _working.loadedEarliest;
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
    final requiredEarliest = usageStatisticsWindow(
      _working,
      now,
    ).previous.start;
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
    final transition = usageStatisticsSliceReduce(_working, intent);
    final nextState = transition.state;
    if (!identical(nextState, _working)) {
      _working = nextState;
      _schedulePublish();
    }
    for (final effect in transition.effects) {
      _effectRunner.run(effect);
    }
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('UsageStatisticsSliceNotifier is disposed');
    }
  }

  /// 命令同步提交到 [_working]，Riverpod 广播延后到当前 build 生命周期之外。
  void _schedulePublish() {
    if (_publishScheduled || _closed) {
      return;
    }
    _publishScheduled = true;
    scheduleMicrotask(() {
      _publishScheduled = false;
      if (!_closed) {
        state = _working;
      }
    });
  }

  void _handleDispose() {
    if (_closed) {
      return;
    }
    _closed = true;
    _effectRunner.close();
    for (final completer in _loadCompleters.values) {
      if (!completer.isCompleted) {
        // 页面以 unawaited initialize 启动；关闭是取消，不应在卸载阶段制造
        // 未处理异常。真实查询失败仍由 loadFailed intent 投影到 state。
        completer.complete();
      }
    }
    _loadCompleters.clear();
  }
}

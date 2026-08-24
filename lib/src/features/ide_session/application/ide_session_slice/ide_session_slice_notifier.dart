import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/ide_session/application/ide_session_restore_result.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_effect.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_intent.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_operations.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_reducer.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_state.dart';
import 'package:zeta/src/features/ide_session/domain/ide_session_state.dart';
import 'package:zeta/src/features/ide_session/domain/ide_workbench_layout_state.dart';

/// IDE Session effect 的执行端口。
///
/// 实现住在 `app` 组合层（它要碰 `dart:io` 与持久化 coordinator），切片本身只描述
/// 要做什么。
abstract interface class IdeSessionSliceEffectRunner {
  void run(IdeSessionSliceEffect effect);

  /// 释放 runner 独占的资源（持久化 coordinator 的 timer 等）。
  void close();
}

/// runner 工厂：拿到 notifier 本身，因此 runner 能直接回流结果。
///
/// 用工厂而不是「runner provider + 反向 `ref.read` notifier」：后者会被 Riverpod
/// 判定成 `CircularDependencyError`（notifier 依赖 runner provider，runner 又读
/// notifier），deferred read 也救不了。工厂把这条边变成普通的构造参数，环从此
/// 不存在。
typedef IdeSessionSliceEffectRunnerFactory =
    IdeSessionSliceEffectRunner Function(IdeSessionSliceNotifier notifier);

/// 组合根必须覆盖的 effect runner 工厂。
///
/// fail-closed：没被覆盖就抛错，而不是静默退化成一个什么都不做的 runner——
/// 那会让「会话没保存」变成一个没人发现的哑 failure。
final ideSessionSliceEffectRunnerFactoryProvider =
    Provider<IdeSessionSliceEffectRunnerFactory>(
      (ref) => throw StateError(
        'ideSessionSliceEffectRunnerFactoryProvider was read before the '
        'composition root overrode it',
      ),
      name: 'ideSessionSliceEffectRunnerFactory',
    );

/// IDE Session restore lifecycle 与 Workbench intent 的唯一 owner。
///
/// 用纯 Dart 的 `package:riverpod`：application 层不依赖 Flutter，因此这个
/// notifier 在 `ProviderContainer` 里就能被完整测试，不需要 widget binding
/// （工程规范 §3.0）。
///
/// **不是 autoDispose。** 会话恢复与保存的生命周期跟 app session 走，不能由
/// 「当前有没有 Widget 在看」决定。
final ideSessionSliceProvider =
    NotifierProvider<IdeSessionSliceNotifier, IdeSessionSliceState>(
      IdeSessionSliceNotifier.new,
      name: 'ideSessionSlice',
      dependencies: [ideSessionSliceEffectRunnerFactoryProvider],
    );

final class IdeSessionSliceNotifier extends Notifier<IdeSessionSliceState>
    implements IdeSessionSliceOperations {
  IdeSessionSliceNotifier({
    OperationIdGenerator Function(String scope)? operationIdGeneratorFactory,
  }) : _generatorFactory =
           operationIdGeneratorFactory ??
           ((scope) => OperationIdGenerator(scope: scope));

  static const String _saveNowScope = 'ide-session/save-now';

  final OperationIdGenerator Function(String scope) _generatorFactory;
  final Map<OperationId, Completer<void>> _saveNowCompleters =
      <OperationId, Completer<void>>{};
  final Completer<void> _initialRestoreCompleter = Completer<void>();

  late IdeSessionSliceEffectRunner _effectRunner;

  /// 已提交的切片状态：这是唯一 owner，[state] 只是它的广播通道。
  ///
  /// 两件事让「提交」和「广播」必须分开：
  ///
  /// 1. runner 可能在 `run(effect)` 里同步回流结果，形成嵌套 dispatch。中间态不
  ///    该被广播出去，因此归约结果先落在这里，等最外层 dispatch 结束才发布。
  /// 2. Shell 会在 `IdeHome.initState` 里同步发起 restore。此时向 Riverpod 写
  ///    state 会撞上 "Tried to modify a provider while the widget tree was
  ///    building"，因此广播排到 microtask。命令入口的调用方不该为这个调度细节
  ///    买单——它们读 [state] 永远拿到已提交值。
  late IdeSessionSliceState _working;

  OperationIdGenerator? _saveNowGenerator;
  bool _publishScheduled = false;
  Completer<IdeSessionRestoreResult>? _restoreCompleter;
  bool _closed = false;
  int _dispatchDepth = 0;
  bool _notificationPending = false;

  @override
  IdeSessionSliceState build() {
    // 工厂由组合根一次性覆盖，容器存活期内不再变化。
    _effectRunner = ref.watch(ideSessionSliceEffectRunnerFactoryProvider)(this);
    _working = const IdeSessionSliceState();
    ref.onDispose(_handleDispose);
    return _working;
  }

  bool get isClosed => _closed;

  @override
  IdeSessionSliceState get state => _working;

  @override
  Future<IdeSessionRestoreResult> restore() {
    _ensureOpen();
    final active = _restoreCompleter;
    if (active != null) {
      return active.future;
    }
    final completer = Completer<IdeSessionRestoreResult>();
    _restoreCompleter = completer;
    _dispatch(const IdeSessionRestoreRequested());
    return completer.future;
  }

  @override
  void cancelPendingRestore() {
    _dispatch(const IdeSessionRestoreCancellationRequested());
  }

  @override
  void requestSave(IdeSessionState snapshot) {
    _dispatch(IdeSessionSaveRequested(snapshot));
  }

  @override
  Future<void> saveNow(IdeSessionState snapshot) {
    _ensureOpen();
    final operationId = (_saveNowGenerator ??= _generatorFactory(
      _saveNowScope,
    )).next();
    final completer = Completer<void>();
    _saveNowCompleters[operationId] = completer;
    _dispatch(IdeSessionSaveNowRequested(operationId, snapshot));
    return completer.future;
  }

  @override
  void setWorkbenchLayout(IdeWorkbenchLayoutState layout) {
    _dispatch(IdeSessionWorkbenchLayoutChanged(layout));
  }

  @override
  void releaseInitialRestoreWait() {
    if (!_initialRestoreCompleter.isCompleted) {
      _initialRestoreCompleter.complete();
    }
  }

  @override
  void completeInitialRestore() {
    _dispatch(const IdeSessionInitialRestoreCompleted());
    releaseInitialRestoreWait();
  }

  @override
  Future<void> get initialRestoreDone => _initialRestoreCompleter.future;

  /// app runner 回流：coordinator 已完成一次 typed restore。
  void restoreResultReceived(IdeSessionRestoreResult result) {
    if (_closed) {
      return;
    }
    _dispatch(IdeSessionRestoreResultReceived(result));
    final completer = _restoreCompleter;
    _restoreCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete(result);
    }
  }

  /// app runner 回流：立即保存已按 coordinator 语义结算。
  void saveNowCompleted(OperationId operationId) {
    if (_closed) {
      return;
    }
    _dispatch(IdeSessionSaveNowCompleted(operationId));
    _saveNowCompleters.remove(operationId)?.complete();
  }

  void _handleDispose() {
    if (_closed) {
      return;
    }
    _closed = true;
    final restoreCompleter = _restoreCompleter;
    _restoreCompleter = null;
    if (restoreCompleter != null && !restoreCompleter.isCompleted) {
      restoreCompleter.complete(const IdeSessionRestoreResult.cancelled());
    }
    releaseInitialRestoreWait();
    for (final completer in _saveNowCompleters.values) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
    _saveNowCompleters.clear();
    _effectRunner.close();
  }

  void _dispatch(IdeSessionSliceIntent intent) {
    if (_closed) {
      return;
    }
    _dispatchDepth += 1;
    try {
      final before = _working;
      final transition = ideSessionSliceReduce(before, intent);
      if (!identical(transition.state, before)) {
        _working = transition.state;
        _notificationPending = true;
      }
      for (final effect in transition.effects) {
        _effectRunner.run(effect);
      }
    } finally {
      _dispatchDepth -= 1;
      if (_dispatchDepth == 0 && _notificationPending) {
        _notificationPending = false;
        _schedulePublish();
      }
    }
  }

  /// 把已提交状态广播给 Riverpod，同一 microtask 内的多次提交合并成一次。
  void _schedulePublish() {
    if (_publishScheduled || _closed) {
      return;
    }
    _publishScheduled = true;
    scheduleMicrotask(() {
      _publishScheduled = false;
      if (_closed) {
        return;
      }
      state = _working;
    });
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('IdeSessionSliceNotifier is disposed');
    }
  }
}

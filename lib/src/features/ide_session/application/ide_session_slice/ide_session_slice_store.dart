import 'dart:async';

import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/ide_session/application/ide_session_restore_result.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_effect.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_intent.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_operations.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_reducer.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_state.dart';
import 'package:zeta/src/features/ide_session/domain/ide_session_state.dart';
import 'package:zeta/src/features/ide_session/domain/ide_workbench_layout_state.dart';

/// IDE Session effect 的 app 组合层执行端口。
abstract interface class IdeSessionSliceEffectRunner {
  void run(IdeSessionSliceEffect effect);

  void close();
}

/// IDE Session restore lifecycle 与 Workbench intent 的纯 Dart owner。
final class IdeSessionSliceStore implements IdeSessionSliceOperations {
  IdeSessionSliceStore({
    required IdeSessionSliceState initialState,
    required this.effectRunner,
    OperationIdGenerator Function(String scope)? operationIdGeneratorFactory,
  }) : _state = initialState,
       _generatorFactory =
           operationIdGeneratorFactory ??
           ((scope) => OperationIdGenerator(scope: scope));

  static const String _saveNowScope = 'ide-session/save-now';

  final IdeSessionSliceEffectRunner effectRunner;
  final OperationIdGenerator Function(String scope) _generatorFactory;
  final List<void Function()> _listeners = <void Function()>[];
  final Map<OperationId, Completer<void>> _saveNowCompleters =
      <OperationId, Completer<void>>{};
  final Completer<void> _initialRestoreCompleter = Completer<void>();

  IdeSessionSliceState _state;
  OperationIdGenerator? _saveNowGenerator;
  Completer<IdeSessionRestoreResult>? _restoreCompleter;
  bool _closed = false;
  int _dispatchDepth = 0;
  bool _notificationPending = false;

  @override
  IdeSessionSliceState get state => _state;

  bool get isClosed => _closed;

  void addListener(void Function() listener) {
    if (_closed || _listeners.contains(listener)) {
      return;
    }
    _listeners.add(listener);
  }

  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  @override
  void Function() subscribe(void Function() listener) {
    addListener(listener);
    return () => removeListener(listener);
  }

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

  void dispose() {
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
    _listeners.clear();
    effectRunner.close();
  }

  void _dispatch(IdeSessionSliceIntent intent) {
    if (_closed) {
      return;
    }
    _dispatchDepth += 1;
    try {
      final before = _state;
      final transition = ideSessionSliceReduce(before, intent);
      if (!identical(transition.state, before)) {
        _state = transition.state;
        _notificationPending = true;
      }
      for (final effect in transition.effects) {
        effectRunner.run(effect);
      }
    } finally {
      _dispatchDepth -= 1;
      if (_dispatchDepth == 0 && _notificationPending) {
        _notificationPending = false;
        for (final listener in List<void Function()>.of(_listeners)) {
          if (!_closed && _listeners.contains(listener)) {
            listener();
          }
        }
      }
    }
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('IdeSessionSliceStore is closed');
    }
  }
}

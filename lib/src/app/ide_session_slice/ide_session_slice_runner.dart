import 'dart:async';

import 'package:zeta/src/features/ide_session/application/ide_session_persistence_coordinator.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_effect.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_store.dart';

/// IDE Session MVI 的 app 组合层 effect runner。
final class IdeSessionSliceRunner implements IdeSessionSliceEffectRunner {
  IdeSessionSliceRunner(this._store, this._coordinator);

  final IdeSessionSliceStore _store;
  final IdeSessionPersistenceCoordinator _coordinator;
  bool _closed = false;

  @override
  void run(IdeSessionSliceEffect effect) {
    if (_closed) {
      return;
    }
    switch (effect) {
      case RestoreIdeSessionEffect():
        unawaited(_restore());
      case CancelIdeSessionRestoreEffect():
        _coordinator.cancelPendingRestore();
      case RequestIdeSessionSaveEffect():
        _coordinator.requestSave(effect.snapshot);
      case SaveIdeSessionNowEffect():
        unawaited(_saveNow(effect));
    }
  }

  Future<void> _restore() async {
    final result = await _coordinator.restore();
    if (!_closed) {
      _store.restoreResultReceived(result);
    }
  }

  Future<void> _saveNow(SaveIdeSessionNowEffect effect) async {
    await _coordinator.saveNow(effect.snapshot);
    if (!_closed) {
      _store.saveNowCompleted(effect.operationId);
    }
  }

  @override
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _coordinator.dispose();
  }
}

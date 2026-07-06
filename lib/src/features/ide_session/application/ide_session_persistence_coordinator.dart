import 'dart:async';

import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/ide_session/data/ide_session_store.dart';
import 'package:zeta/src/features/ide_session/domain/ide_session_state.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_restore_result.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_state_builder.dart';

final _log = loggerFor('zeta.ide_session.persistence_coordinator');

/// 协调 IDE 会话的恢复与持久化时序。
///
/// 该对象负责：
/// - 处理恢复中的取消令牌
/// - 在恢复期间延迟保存请求
/// - 将恢复得到的快照先做清洗，再交给页面层应用
class IdeSessionPersistenceCoordinator {
  IdeSessionPersistenceCoordinator({
    required this.store,
    required this.saveDelay,
  });

  final IdeSessionStore store;
  final Duration saveDelay;

  Timer? _saveTimer;
  int _restoreToken = 0;
  bool _isRestoring = false;
  IdeSessionState? _pendingSnapshotAfterRestore;

  bool get isRestoring => _isRestoring;

  Future<IdeSessionRestoreResult> restore() async {
    final restoreToken = ++_restoreToken;
    _isRestoring = true;

    try {
      final snapshot = await store.load();
      if (!_isActiveRestore(restoreToken)) {
        return const IdeSessionRestoreResult.cancelled();
      }
      if (snapshot == null) {
        return const IdeSessionRestoreResult.empty();
      }
      return IdeSessionRestoreResult.restored(
        sanitizeIdeSessionState(snapshot),
      );
    } catch (error, stackTrace) {
      _log.warning('Could not restore IDE session', error, stackTrace);
      if (!_isActiveRestore(restoreToken)) {
        return const IdeSessionRestoreResult.cancelled();
      }
      return const IdeSessionRestoreResult.failed();
    } finally {
      if (restoreToken == _restoreToken) {
        _isRestoring = false;
        final pendingSnapshot = _pendingSnapshotAfterRestore;
        _pendingSnapshotAfterRestore = null;
        if (pendingSnapshot != null) {
          requestSave(pendingSnapshot);
        }
      }
    }
  }

  /// 让当前进行中的恢复结果失效，防止慢恢复覆盖用户后续操作。
  void cancelPendingRestore() {
    if (!_isRestoring) {
      return;
    }

    _restoreToken += 1;
    _isRestoring = false;
    final pendingSnapshot = _pendingSnapshotAfterRestore;
    _pendingSnapshotAfterRestore = null;
    if (pendingSnapshot != null) {
      requestSave(pendingSnapshot);
    }
  }

  /// 请求按延迟策略保存当前会话快照。
  void requestSave(IdeSessionState snapshot) {
    if (_isRestoring) {
      _pendingSnapshotAfterRestore = snapshot;
      return;
    }

    _saveTimer?.cancel();
    _saveTimer = Timer(saveDelay, () {
      unawaited(_saveSnapshot(snapshot));
    });
  }

  /// 立即持久化一次当前快照。
  Future<void> saveNow(IdeSessionState snapshot) async {
    if (_isRestoring) {
      _pendingSnapshotAfterRestore = snapshot;
      return;
    }

    _saveTimer?.cancel();
    await _saveSnapshot(snapshot);
  }

  void dispose() {
    _saveTimer?.cancel();
  }

  bool _isActiveRestore(int restoreToken) {
    return restoreToken == _restoreToken;
  }

  Future<void> _saveSnapshot(IdeSessionState snapshot) async {
    try {
      await store.save(snapshot);
    } catch (error, stackTrace) {
      _log.warning('Could not save IDE session', error, stackTrace);
    }
  }
}

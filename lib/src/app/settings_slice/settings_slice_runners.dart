import 'dart:async';

import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_effect.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_store.dart';
import 'package:zeta/src/features/settings/application/settings_slice/settings_slice_operation.dart';
import 'package:zeta/src/features/settings/data/general_settings_store.dart';

final _log = zetaLoggerFor('zeta.settings.slice_runner');

/// general 切片的 effect runner 适配器（app 组合层）。
///
/// persist 以单写者串行执行：落盘顺序与提交顺序一致，失败不阻断
/// 后续命令。
final class GeneralSettingsSliceRunnerAdapter
    implements GeneralSettingsSliceEffectRunner {
  GeneralSettingsSliceRunnerAdapter({
    required this._store,
    required this._sliceStore,
  });

  final GeneralSettingsStore _store;
  final GeneralSettingsSliceStore _sliceStore;

  Future<void> _queue = Future<void>.value();
  Future<void> _initialLoad = Future<void>.value();
  bool _loadStarted = false;
  bool _initialLoadSettled = false;

  @override
  void run(GeneralSettingsSliceEffect effect) {
    switch (effect) {
      case GeneralSettingsLoadEffect():
        if (!_loadStarted) {
          _loadStarted = true;
          _initialLoad = _load();
        }
      case GeneralSettingsPersistEffect():
        if (_initialLoadSettled) {
          _enqueue(() => _persist(effect));
        } else {
          _enqueue(() async {
            await _initialLoad;
            await _persist(effect);
          });
        }
    }
  }

  Future<void> _load() async {
    try {
      final settings = await _store.load();
      _initialLoadSettled = true;
      _sliceStore.loaded(settings);
    } catch (error, stackTrace) {
      _log.w(
        'Could not load general settings via slice',
        error: error,
        stackTrace: stackTrace,
      );
      _initialLoadSettled = true;
      _sliceStore.loadFailed();
    }
  }

  Future<void> _persist(GeneralSettingsPersistEffect effect) async {
    try {
      await _store.save(effect.value);
      _sliceStore.persisted(effect.operationId, effect.value);
    } catch (error, stackTrace) {
      _log.w(
        'Could not persist general settings via slice',
        error: error,
        stackTrace: stackTrace,
      );
      _sliceStore.persistFailed(
        effect.operationId,
        SettingsPersistFailureKind.persistence,
      );
    }
  }

  void _enqueue(Future<void> Function() action) {
    _queue = _queue.catchError((Object _) {}).then((_) => action());
  }
}

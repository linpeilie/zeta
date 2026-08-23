import 'dart:io';

import 'package:zeta/src/app/app_constants.dart';
import 'package:zeta/src/app/ide_session_slice/ide_session_slice_runner.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_persistence_coordinator.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_effect.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_state.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_store.dart';
import 'package:zeta/src/features/ide_session/data/ide_session_store.dart';

/// IDE Session 切片的 app 生命周期组合。
final class IdeSessionSliceComposition {
  IdeSessionSliceComposition._(this.store);

  final IdeSessionSliceStore store;

  factory IdeSessionSliceComposition.create({
    required IdeSessionStore sessionStore,
    Duration saveDelay = sessionSaveDelay,
    bool Function(String path)? fileExists,
    bool Function(String path)? directoryExists,
  }) {
    final deferredRunner = _DeferredIdeSessionSliceRunner();
    final store = IdeSessionSliceStore(
      initialState: const IdeSessionSliceState(),
      effectRunner: deferredRunner,
    );
    final coordinator = IdeSessionPersistenceCoordinator(
      store: sessionStore,
      saveDelay: saveDelay,
      fileExists: fileExists ?? (path) => File(path).existsSync(),
      directoryExists:
          directoryExists ?? (path) => Directory(path).existsSync(),
    );
    deferredRunner.delegate = IdeSessionSliceRunner(store, coordinator);
    return IdeSessionSliceComposition._(store);
  }

  void dispose() => store.dispose();
}

final class _DeferredIdeSessionSliceRunner
    implements IdeSessionSliceEffectRunner {
  IdeSessionSliceEffectRunner? delegate;

  @override
  void run(IdeSessionSliceEffect effect) => delegate?.run(effect);

  @override
  void close() => delegate?.close();
}

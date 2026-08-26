import 'dart:io';

import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:zeta/src/app/app_constants.dart';
import 'package:zeta/src/app/ide_session_slice/ide_session_slice_runner.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_persistence_coordinator.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_notifier.dart';
import 'package:zeta/src/app/storage/zeta_store_providers.dart';

/// IDE Session 切片的组合根装配。
///
/// 取代了旧的 `IdeSessionSliceComposition`：切片的所有权、构造顺序和释放时机
/// 全部由容器表达——状态由 `ideSessionSliceProvider` 拥有，coordinator 与 runner
/// 随 notifier 一起创建、一起释放，不再需要一个组合对象手工串 `dispose()`
/// （工程规范 §3.0）。
///
/// 仓库从 `ideSessionStoreProvider` 读：落盘还是内存已经由 `ZetaStorageBindings`
/// 在组合根决定一次，这里不再接收 store 参数。测试要换实现就覆盖那个 provider。
List<Override> ideSessionSliceOverrides({
  Duration saveDelay = sessionSaveDelay,
  bool Function(String path)? fileExists,
  bool Function(String path)? directoryExists,
}) {
  return <Override>[
    ideSessionSliceEffectRunnerFactoryProvider.overrideWith((ref) {
      final sessionStore = ref.watch(ideSessionStoreProvider);
      return (notifier) {
        final coordinator = IdeSessionPersistenceCoordinator(
          store: sessionStore,
          saveDelay: saveDelay,
          fileExists: fileExists ?? (path) => File(path).existsSync(),
          directoryExists:
              directoryExists ?? (path) => Directory(path).existsSync(),
        );
        return IdeSessionSliceRunner(notifier, coordinator);
      };
    }),
  ];
}

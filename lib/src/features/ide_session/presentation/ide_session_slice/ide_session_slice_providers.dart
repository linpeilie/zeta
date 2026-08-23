import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_state.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_store.dart';

/// MainApp 根 ProviderScope 注入的唯一 IDE Session store。
final ideSessionSliceStoreProvider = Provider<IdeSessionSliceStore>(
  (ref) => throw StateError('IdeSessionSliceStore is not bound'),
  name: 'ideSessionSliceStore',
);

/// IDE Session store 的只读 Riverpod 镜像；adapter 不拥有 store 生命周期。
final ideSessionSliceProvider =
    NotifierProvider<IdeSessionSliceNotifier, IdeSessionSliceState>(
      IdeSessionSliceNotifier.new,
      name: 'ideSessionSlice',
      dependencies: [ideSessionSliceStoreProvider],
      isAutoDispose: true,
    );

final class IdeSessionSliceNotifier extends Notifier<IdeSessionSliceState> {
  @override
  IdeSessionSliceState build() {
    final store = ref.watch(ideSessionSliceStoreProvider);
    var active = true;
    var publishScheduled = false;
    final unsubscribe = store.subscribe(() {
      if (publishScheduled) {
        return;
      }
      publishScheduled = true;
      scheduleMicrotask(() {
        publishScheduled = false;
        if (active && !store.isClosed) {
          state = store.state;
        }
      });
    });
    ref.onDispose(() {
      active = false;
      unsubscribe();
    });
    return store.state;
  }
}

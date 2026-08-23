import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zeta/src/features/workspace/application/workspace_slice/workspace_slice_state.dart';
import 'package:zeta/src/features/workspace/application/workspace_slice/workspace_slice_store.dart';

/// IdeHome 内层 ProviderScope 注入的唯一 workspace store。
final workspaceSliceStoreProvider = Provider<WorkspaceSliceStore>(
  (ref) => throw StateError('WorkspaceSliceStore is not bound'),
  name: 'workspaceSliceStore',
);

/// Workspace store 的只读 Riverpod 镜像；adapter 不拥有 store 生命周期。
final workspaceSliceProvider =
    NotifierProvider<WorkspaceSliceNotifier, WorkspaceSliceState>(
      WorkspaceSliceNotifier.new,
      name: 'workspaceSlice',
      dependencies: [workspaceSliceStoreProvider],
      isAutoDispose: true,
    );

final class WorkspaceSliceNotifier extends Notifier<WorkspaceSliceState> {
  @override
  WorkspaceSliceState build() {
    final store = ref.watch(workspaceSliceStoreProvider);
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

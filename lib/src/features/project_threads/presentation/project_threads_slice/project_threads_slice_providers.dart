import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zeta/src/features/project_threads/application/project_threads_slice/project_threads_slice_state.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_slice/project_threads_slice_store.dart';
import 'package:zeta/src/features/project_threads/domain/project_thread_list_state.dart';

/// IdeHome 内层 ProviderScope 必须注入唯一的页面 store。
final projectThreadsSliceStoreProvider = Provider<ProjectThreadsSliceStore>(
  (ref) => throw StateError('ProjectThreadsSliceStore is not bound'),
  name: 'projectThreadsSliceStore',
);

/// Project Threads store 的只读 Riverpod 镜像。
final projectThreadsSliceProvider =
    NotifierProvider<ProjectThreadsSliceNotifier, ProjectThreadsSliceState>(
      ProjectThreadsSliceNotifier.new,
      name: 'projectThreadsSlice',
      dependencies: [projectThreadsSliceStoreProvider],
      isAutoDispose: true,
    );

final class ProjectThreadsSliceNotifier
    extends Notifier<ProjectThreadsSliceState> {
  @override
  ProjectThreadsSliceState build() {
    final store = ref.watch(projectThreadsSliceStoreProvider);
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

/// 单项目只读 selector。
final projectThreadListStateProvider =
    Provider.family<ProjectThreadListState, String>(
      (ref, projectPath) => ref.watch(
        projectThreadsSliceProvider.select(
          (state) => state.stateFor(projectPath),
        ),
      ),
      name: 'projectThreadListState',
      dependencies: [projectThreadsSliceProvider],
      isAutoDispose: true,
    );

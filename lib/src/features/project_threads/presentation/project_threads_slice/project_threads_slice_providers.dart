import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zeta/src/features/project_threads/application/project_threads_slice/project_threads_slice_state.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_slice/project_threads_slice_store.dart';
import 'package:zeta/src/features/project_threads/domain/project_thread_list_state.dart';

/// IdeHome 内层 ProviderScope 注入的页面 store；null 表示完整走 legacy 路径。
final projectThreadsSliceStoreProvider = Provider<ProjectThreadsSliceStore?>(
  (ref) => null,
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
    if (store == null) {
      return ProjectThreadsSliceState();
    }
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

/// 单项目 selector，未启用切片时只返回空状态，调用方应走 legacy source。
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

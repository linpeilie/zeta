import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_slice/project_threads_slice_notifier.dart';
import 'package:zeta/src/features/project_threads/domain/project_thread_list_state.dart';

/// 单项目只读 selector。
final projectThreadListStateProvider =
    Provider.family<ProjectThreadListState, String>(
      (ref, projectPath) => ref.watch(
        projectThreadsSliceProvider.select(
          (state) => state.stateFor(projectPath),
        ),
      ),
      name: 'projectThreadListState',
      isAutoDispose: true,
    );

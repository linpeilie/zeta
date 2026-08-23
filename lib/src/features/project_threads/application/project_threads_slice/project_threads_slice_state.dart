import 'package:meta/meta.dart';

import 'package:zeta/src/features/project_threads/domain/project_thread_list_state.dart';

/// Project Threads 的不可变 application 状态。
///
/// Map 按项目路径规范化；列表项、选中态、分页和运行态仍由既有
/// [ProjectThreadListState] 表达，不新增业务事实。
@immutable
final class ProjectThreadsSliceState {
  ProjectThreadsSliceState({
    Map<String, ProjectThreadListState> statesByProject =
        const <String, ProjectThreadListState>{},
  }) : statesByProject = Map<String, ProjectThreadListState>.unmodifiable(
         statesByProject,
       );

  final Map<String, ProjectThreadListState> statesByProject;

  ProjectThreadListState stateFor(String projectPath) {
    return statesByProject[projectPath] ?? const ProjectThreadListState();
  }
}

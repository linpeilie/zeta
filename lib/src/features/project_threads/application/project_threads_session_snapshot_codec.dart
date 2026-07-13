import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/ide_session/domain/ide_session_state.dart';
import 'package:zeta/src/features/project_threads/domain/project_thread_list_state.dart';
import 'package:zeta/src/features/project_threads/domain/project_threads_session_snapshot.dart';

/// 从 IDE 会话快照中提取 Project Threads 模块自己的恢复数据。
ProjectThreadsSessionSnapshot projectThreadsSessionSnapshotFromIdeSessionState(
  IdeSessionState state,
) {
  return ProjectThreadsSessionSnapshot(
    expansionByProject: state.projectThreadExpansionByProject,
    cachedThreadsByProject: state.cachedThreadsByProject,
    selectedThreadIdsByProject: state.selectedThreadIdsByProject,
  );
}

/// 从当前 Project Threads 列表状态构建可持久化快照。
ProjectThreadsSessionSnapshot buildProjectThreadsSessionSnapshot(
  Map<String, ProjectThreadListState> states,
) {
  return ProjectThreadsSessionSnapshot(
    expansionByProject: <String, bool>{
      for (final entry in states.entries) entry.key: entry.value.isExpanded,
    },
    cachedThreadsByProject: <String, List<AgentThreadSummary>>{
      for (final entry in states.entries)
        if (entry.value.threads.isNotEmpty)
          entry.key: List<AgentThreadSummary>.unmodifiable(entry.value.threads),
    },
    selectedThreadIdsByProject: <String, String>{
      for (final entry in states.entries)
        if (entry.value.selectedThreadId != null)
          entry.key: entry.value.selectedThreadId!,
    },
  );
}

/// 恢复 Project Threads 列表状态时的应用层结果。
class ProjectThreadsRestorePlan {
  const ProjectThreadsRestorePlan({
    required this.states,
    required this.projectsToLoad,
  });

  final Map<String, ProjectThreadListState> states;
  final List<String> projectsToLoad;
}

/// 把会话快照转换成 Project Threads 模块可直接消费的恢复计划。
ProjectThreadsRestorePlan buildProjectThreadsRestorePlan({
  required List<String> projectPaths,
  required String? activeProjectPath,
  required ProjectThreadsSessionSnapshot snapshot,
}) {
  final states = <String, ProjectThreadListState>{};
  final projectsToLoad = <String>[];

  for (final path in projectPaths) {
    final cachedThreads =
        snapshot.cachedThreadsByProject[path] ?? const <AgentThreadSummary>[];
    final isExpanded =
        snapshot.expansionByProject[path] ?? path == activeProjectPath;
    states[path] = ProjectThreadListState(
      isExpanded: isExpanded,
      hasLoaded: cachedThreads.isNotEmpty,
      threads: List<AgentThreadSummary>.unmodifiable(cachedThreads),
      selectedThreadId: snapshot.selectedThreadIdsByProject[path],
    );
    if (isExpanded) {
      projectsToLoad.add(path);
    }
  }

  // 旧会话可能在多个项目上各存一条 selected；恢复时归一为全局唯一选中。
  _retainSingleSelectedThread(
    states: states,
    preferredProjectPath: activeProjectPath,
  );

  return ProjectThreadsRestorePlan(
    states: states,
    projectsToLoad: List<String>.unmodifiable(projectsToLoad),
  );
}

/// 保证 [states] 中至多一个项目保留 [ProjectThreadListState.selectedThreadId]。
///
/// 优先保留 [preferredProjectPath] 上的选中；否则保留 map 中第一条非空选中。
void _retainSingleSelectedThread({
  required Map<String, ProjectThreadListState> states,
  required String? preferredProjectPath,
}) {
  String? owner;
  if (preferredProjectPath != null &&
      states[preferredProjectPath]?.selectedThreadId != null) {
    owner = preferredProjectPath;
  } else {
    for (final entry in states.entries) {
      if (entry.value.selectedThreadId != null) {
        owner = entry.key;
        break;
      }
    }
  }

  if (owner == null) {
    return;
  }

  for (final path in states.keys.toList(growable: false)) {
    if (path == owner) {
      continue;
    }
    final state = states[path]!;
    if (state.selectedThreadId != null) {
      states[path] = state.copyWith(selectedThreadId: null);
    }
  }
}

import 'dart:io';

import 'package:zeta/src/core/utils/path_utils.dart';
import 'package:zeta/src/features/project_threads/domain/project_threads_session_snapshot.dart';
import 'package:zeta/src/features/ide_session/domain/ide_session_state.dart';

/// 从当前页面持有的运行时状态构建可持久化的 IDE 会话快照。
IdeSessionState buildIdeSessionState({
  required List<String> projectPaths,
  required String? activeProjectPath,
  required String? currentFilePath,
  required Set<String> expandedDirectoryPaths,
  required String? selectedTreeKey,
  required String? activeAgentProviderId,
  required Map<String, String> agentThreadIdsByProject,
  required ProjectThreadsSessionSnapshot projectThreadsSessionSnapshot,
  required String? currentProjectPath,
  required String? currentSessionId,
}) {
  final mergedAgentThreadIds = Map<String, String>.from(
    agentThreadIdsByProject,
  );
  final mergedSelectedThreadIds = Map<String, String>.from(
    projectThreadsSessionSnapshot.selectedThreadIdsByProject,
  );
  if (currentProjectPath != null && currentSessionId != null) {
    // 保存当前项目对应的 Agent thread，方便下次启动尝试恢复同一会话。
    mergedAgentThreadIds[currentProjectPath] = currentSessionId;
    mergedSelectedThreadIds[currentProjectPath] = currentSessionId;
  }

  return IdeSessionState(
    projectPaths: List<String>.unmodifiable(projectPaths),
    activeProjectPath: activeProjectPath,
    currentFilePath: currentFilePath,
    expandedDirectoryPaths: expandedDirectoryPaths,
    selectedTreeKey: selectedTreeKey,
    activeAgentProviderId: activeAgentProviderId,
    agentThreadIdsByProject: mergedAgentThreadIds,
    projectThreadExpansionByProject:
        projectThreadsSessionSnapshot.expansionByProject,
    cachedThreadsByProject:
        projectThreadsSessionSnapshot.cachedThreadsByProject,
    selectedThreadIdsByProject: mergedSelectedThreadIds,
  );
}

/// 清洗从持久化层恢复出的 IDE 会话快照。
///
/// 这里会剔除不存在的项目、文件和目录，并收敛项目级缓存映射，
/// 避免这些脏数据继续回流到页面层。
IdeSessionState sanitizeIdeSessionState(IdeSessionState state) {
  final existingProjects = existingDirectoryPaths(state.projectPaths);
  final existingProjectSet = existingProjects.toSet();
  final activeProjectPath = existingProjectSet.contains(state.activeProjectPath)
      ? state.activeProjectPath
      : null;
  final currentFilePath =
      activeProjectPath != null &&
          state.currentFilePath != null &&
          File(state.currentFilePath!).existsSync()
      ? state.currentFilePath
      : null;
  final expandedDirectoryPaths = state.expandedDirectoryPaths
      .where((path) => Directory(path).existsSync())
      .toSet();

  final agentThreadIdsByProject = _filterProjectMap(
    state.agentThreadIdsByProject,
    existingProjectSet,
  );
  final selectedThreadIdsByProject = _filterProjectMap(
    state.selectedThreadIdsByProject,
    existingProjectSet,
  );
  for (final entry in agentThreadIdsByProject.entries) {
    selectedThreadIdsByProject.putIfAbsent(entry.key, () => entry.value);
  }

  return IdeSessionState(
    projectPaths: existingProjects,
    activeProjectPath: activeProjectPath,
    currentFilePath: currentFilePath,
    expandedDirectoryPaths: expandedDirectoryPaths,
    selectedTreeKey: activeProjectPath == null ? null : state.selectedTreeKey,
    activeAgentProviderId: state.activeAgentProviderId,
    agentThreadIdsByProject: agentThreadIdsByProject,
    projectThreadExpansionByProject: _filterProjectMap(
      state.projectThreadExpansionByProject,
      existingProjectSet,
    ),
    cachedThreadsByProject: _filterProjectMap(
      state.cachedThreadsByProject,
      existingProjectSet,
    ),
    selectedThreadIdsByProject: selectedThreadIdsByProject,
  );
}

Map<String, T> _filterProjectMap<T>(
  Map<String, T> source,
  Set<String> existingProjectSet,
) {
  final filtered = <String, T>{};
  for (final entry in source.entries) {
    if (existingProjectSet.contains(entry.key)) {
      filtered[entry.key] = entry.value;
    }
  }
  return filtered;
}

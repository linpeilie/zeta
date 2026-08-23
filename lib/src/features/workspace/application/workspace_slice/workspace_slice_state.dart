import 'package:meta/meta.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/workspace/domain/workspace_node.dart';

/// 从 IDE session 投影到 workspace context 的白名单恢复快照。
@immutable
final class WorkspaceRestoreSnapshot {
  WorkspaceRestoreSnapshot({
    required List<String> projects,
    required this.activeProjectPath,
    required this.currentFilePath,
    required Set<String> expandedDirectoryPaths,
    required this.selectedTreePath,
    required Map<String, DateTime> projectLastOpenedAtByPath,
  }) : projects = List<String>.unmodifiable(projects),
       expandedDirectoryPaths = Set<String>.unmodifiable(
         expandedDirectoryPaths,
       ),
       projectLastOpenedAtByPath = Map<String, DateTime>.unmodifiable(
         projectLastOpenedAtByPath,
       );

  final List<String> projects;
  final String? activeProjectPath;
  final String? currentFilePath;
  final Set<String> expandedDirectoryPaths;
  final String? selectedTreePath;
  final Map<String, DateTime> projectLastOpenedAtByPath;
}

/// Workspace 的不可变 application 状态。
///
/// 这里只保存已加载的树层级；完整 @mention corpus 仍由有界索引缓存持有。
@immutable
final class WorkspaceSliceState {
  WorkspaceSliceState({
    List<String> projects = const <String>[],
    this.activeProjectPath,
    List<WorkspaceNode> tree = const <WorkspaceNode>[],
    Set<String> expandedDirectoryPaths = const <String>{},
    this.currentFilePath,
    this.selectedTreePath,
    Map<String, DateTime> projectLastOpenedAtByPath =
        const <String, DateTime>{},
    this.isLoadingProject = false,
    this.projectLoadOperationId,
    this.restoreOperationId,
  }) : projects = List<String>.unmodifiable(projects),
       tree = List<WorkspaceNode>.unmodifiable(tree),
       expandedDirectoryPaths = Set<String>.unmodifiable(
         expandedDirectoryPaths,
       ),
       projectLastOpenedAtByPath = Map<String, DateTime>.unmodifiable(
         projectLastOpenedAtByPath,
       );

  final List<String> projects;
  final String? activeProjectPath;
  final List<WorkspaceNode> tree;
  final Set<String> expandedDirectoryPaths;
  final String? currentFilePath;
  final String? selectedTreePath;
  final Map<String, DateTime> projectLastOpenedAtByPath;
  final bool isLoadingProject;

  /// 只用于拒绝迟到结果，不进入持久化 DTO。
  final OperationId? projectLoadOperationId;
  final OperationId? restoreOperationId;

  WorkspaceSliceState copyWith({
    List<String>? projects,
    String? activeProjectPath,
    bool clearActiveProjectPath = false,
    List<WorkspaceNode>? tree,
    Set<String>? expandedDirectoryPaths,
    String? currentFilePath,
    bool clearCurrentFilePath = false,
    String? selectedTreePath,
    bool clearSelectedTreePath = false,
    Map<String, DateTime>? projectLastOpenedAtByPath,
    bool? isLoadingProject,
    OperationId? projectLoadOperationId,
    bool clearProjectLoadOperationId = false,
    OperationId? restoreOperationId,
    bool clearRestoreOperationId = false,
  }) {
    return WorkspaceSliceState(
      projects: projects ?? this.projects,
      activeProjectPath: clearActiveProjectPath
          ? null
          : activeProjectPath ?? this.activeProjectPath,
      tree: tree ?? this.tree,
      expandedDirectoryPaths:
          expandedDirectoryPaths ?? this.expandedDirectoryPaths,
      currentFilePath: clearCurrentFilePath
          ? null
          : currentFilePath ?? this.currentFilePath,
      selectedTreePath: clearSelectedTreePath
          ? null
          : selectedTreePath ?? this.selectedTreePath,
      projectLastOpenedAtByPath:
          projectLastOpenedAtByPath ?? this.projectLastOpenedAtByPath,
      isLoadingProject: isLoadingProject ?? this.isLoadingProject,
      projectLoadOperationId: clearProjectLoadOperationId
          ? null
          : projectLoadOperationId ?? this.projectLoadOperationId,
      restoreOperationId: clearRestoreOperationId
          ? null
          : restoreOperationId ?? this.restoreOperationId,
    );
  }
}

import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/workspace/application/workspace_slice/workspace_slice_effect.dart';
import 'package:zeta/src/features/workspace/application/workspace_slice/workspace_slice_intent.dart';
import 'package:zeta/src/features/workspace/application/workspace_slice/workspace_slice_state.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';

/// Workspace 的纯同步 reducer。
Transition<WorkspaceSliceState, WorkspaceSliceEffect> workspaceSliceReduce(
  WorkspaceSliceState state,
  WorkspaceSliceIntent intent,
) {
  switch (intent) {
    case WorkspaceProjectLoadRequested():
      return Transition(
        state.copyWith(
          isLoadingProject: true,
          projectLoadOperationId: intent.operationId,
        ),
        <WorkspaceSliceEffect>[
          ReadWorkspaceProjectEffect(intent.operationId, intent.path),
        ],
      );

    case WorkspaceProjectLoadSucceeded():
      if (state.projectLoadOperationId != intent.operationId) {
        return Transition.none(state);
      }
      final projects = List<String>.of(state.projects);
      if (!projects.contains(intent.path)) {
        projects.insert(0, intent.path);
      }
      final opened = Map<String, DateTime>.of(state.projectLastOpenedAtByPath)
        ..[intent.path] = intent.openedAt;
      return Transition(
        state.copyWith(
          projects: projects,
          activeProjectPath: intent.path,
          tree: intent.tree,
          expandedDirectoryPaths: const <String>{},
          clearCurrentFilePath: true,
          clearSelectedTreePath: true,
          projectLastOpenedAtByPath: opened,
          isLoadingProject: false,
          clearProjectLoadOperationId: true,
        ),
        <WorkspaceSliceEffect>[IndexWorkspaceFilesEffect(intent.path)],
      );

    case WorkspaceProjectLoadFailed():
      if (state.projectLoadOperationId != intent.operationId) {
        return Transition.none(state);
      }
      return Transition.stateOnly(
        state.copyWith(
          isLoadingProject: false,
          clearProjectLoadOperationId: true,
        ),
      );

    case WorkspaceRestoreRequested():
      return Transition(
        state.copyWith(restoreOperationId: intent.operationId),
        <WorkspaceSliceEffect>[
          RestoreWorkspaceEffect(intent.operationId, intent.snapshot),
        ],
      );

    case WorkspaceRestoreSucceeded():
      if (state.restoreOperationId != intent.operationId) {
        return Transition.none(state);
      }
      final snapshot = intent.snapshot;
      final effects = <WorkspaceSliceEffect>[];
      final activeProjectPath = snapshot.activeProjectPath;
      if (activeProjectPath != null) {
        effects.add(IndexWorkspaceFilesEffect(activeProjectPath));
      }
      return Transition(
        WorkspaceSliceState(
          projects: snapshot.projects,
          activeProjectPath: activeProjectPath,
          tree: intent.tree,
          expandedDirectoryPaths: snapshot.expandedDirectoryPaths,
          currentFilePath: snapshot.currentFilePath,
          selectedTreePath: intent.selectedTreePath,
          projectLastOpenedAtByPath: snapshot.projectLastOpenedAtByPath,
        ),
        effects,
      );

    case WorkspaceRestoreFailed():
      if (state.restoreOperationId != intent.operationId) {
        return Transition.none(state);
      }
      return Transition.stateOnly(
        state.copyWith(clearRestoreOperationId: true),
      );

    case WorkspaceProjectOpened():
      final opened = Map<String, DateTime>.of(state.projectLastOpenedAtByPath)
        ..[intent.path] = intent.openedAt;
      return Transition.stateOnly(
        state.copyWith(projectLastOpenedAtByPath: opened),
      );

    case WorkspaceProjectRemoved():
      if (!state.projects.contains(intent.path)) {
        return Transition.none(state);
      }
      final projects = state.projects
          .where((path) => path != intent.path)
          .toList(growable: false);
      final opened = Map<String, DateTime>.of(state.projectLastOpenedAtByPath)
        ..remove(intent.path);
      return Transition.stateOnly(
        state.copyWith(projects: projects, projectLastOpenedAtByPath: opened),
      );

    case WorkspaceActiveProjectCleared():
      final effects = <WorkspaceSliceEffect>[];
      final activeProjectPath = state.activeProjectPath;
      if (activeProjectPath != null) {
        effects.add(InvalidateWorkspaceFilesEffect(activeProjectPath));
      }
      return Transition(
        state.copyWith(
          clearActiveProjectPath: true,
          tree: const <WorkspaceNode>[],
          expandedDirectoryPaths: const <String>{},
          clearCurrentFilePath: true,
          clearSelectedTreePath: true,
          isLoadingProject: false,
          clearProjectLoadOperationId: true,
        ),
        effects,
      );

    case WorkspaceCurrentFileCleared():
      if (state.currentFilePath == null) {
        return Transition.none(state);
      }
      return Transition.stateOnly(state.copyWith(clearCurrentFilePath: true));

    case WorkspaceTreeExpansionChanged():
      return _changeExpansion(state, intent.path, intent.expanded);

    case WorkspaceDirectoryLoaded():
      final nextTree = WorkspaceNode.updateNode(state.tree, intent.path, (
        node,
      ) {
        if (!node.isDirectory || node.childrenLoaded) {
          return node;
        }
        return node.copyWith(
          childrenLoaded: true,
          children: List<WorkspaceNode>.unmodifiable(intent.children),
        );
      });
      return identical(nextTree, state.tree)
          ? Transition.none(state)
          : Transition.stateOnly(state.copyWith(tree: nextTree));

    case WorkspaceTreeNodeSelected():
      final node = WorkspaceNode.findByPath(state.tree, intent.path);
      if (node == null) {
        return Transition.none(state);
      }
      final selected = state.copyWith(selectedTreePath: intent.path);
      if (!node.isDirectory) {
        return Transition.stateOnly(
          selected.copyWith(currentFilePath: node.path),
        );
      }
      return _changeExpansion(
        selected,
        node.path,
        !state.expandedDirectoryPaths.contains(node.path),
      );
  }
}

Transition<WorkspaceSliceState, WorkspaceSliceEffect> _changeExpansion(
  WorkspaceSliceState state,
  String path,
  bool expanded,
) {
  final node = WorkspaceNode.findByPath(state.tree, path);
  if (node == null || !node.isDirectory) {
    return Transition.none(state);
  }
  final paths = Set<String>.of(state.expandedDirectoryPaths);
  final changed = expanded ? paths.add(path) : paths.remove(path);
  if (!changed && (!expanded || node.childrenLoaded)) {
    return Transition.none(state);
  }
  final effects = <WorkspaceSliceEffect>[];
  if (expanded && !node.childrenLoaded) {
    effects.add(
      ReadWorkspaceDirectoryEffect(
        path: path,
        expandedDirectoryPaths: Set<String>.unmodifiable(paths),
      ),
    );
  }
  return Transition(state.copyWith(expandedDirectoryPaths: paths), effects);
}

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/workspace/application/workspace_file_index_controller.dart';
import 'package:zeta/src/features/workspace/application/workspace_file_tree_notifier.dart';
import 'package:zeta/src/features/workspace/application/workspace_restore_snapshot.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';
import 'package:zeta/src/features/workspace/domain/workspace_project.dart';

final _log = zetaLoggerFor('zeta.workspace');

/// 系统目录选择器。定义在本文件，由组合根覆盖；测试注入 fake。
typedef WorkspaceDirectoryPicker = Future<String?> Function();

/// 目录选择器。组合根必须覆盖。
final workspaceDirectoryPickerProvider = Provider<WorkspaceDirectoryPicker>(
  (ref) => throw StateError('Workspace directory picker is not installed'),
  name: 'workspaceDirectoryPicker',
);

/// 可注入时钟，便于测试固定 MRU 时间。
final workspaceNowProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
  name: 'workspaceNow',
);

/// 文件语料索引。默认在本 provider 创建；测试可覆盖。
final workspaceFileIndexControllerProvider =
    Provider<WorkspaceFileIndexController>((ref) {
      final controller = WorkspaceFileIndexController();
      ref.onDispose(controller.dispose);
      return controller;
    }, name: 'workspaceFileIndexController');

/// 工作区调度器：打开列表、激活项目、调度系统文件选择器。
final workspaceProvider = NotifierProvider<WorkspaceNotifier, WorkspaceState>(
  WorkspaceNotifier.new,
  name: 'workspace',
);

/// 活动项目的文件树投影。
final activeWorkspaceFileTreeProvider = Provider<WorkspaceFileTreeState>((ref) {
  final path = ref.watch(
    workspaceProvider.select((state) => state.activeProjectPath),
  );
  if (path == null) {
    return WorkspaceFileTreeState();
  }
  return ref.watch(workspaceFileTreeProvider(path));
}, name: 'activeWorkspaceFileTree');

/// 工作区调度器。
///
/// 不拥有文件树本体：树按项目路径走 [workspaceFileTreeProvider]。
/// 从工作区移除项目时必须显式 invalidate，不能靠 autoDispose。
final class WorkspaceNotifier extends Notifier<WorkspaceState> {
  int _openGeneration = 0;

  @override
  WorkspaceState build() => WorkspaceState();

  /// 供非 Riverpod 编排器（Shell）读取当前快照。
  WorkspaceState get currentState => state;

  DateTime get _now => ref.read(workspaceNowProvider)();

  WorkspaceFileIndexController get _index =>
      ref.read(workspaceFileIndexControllerProvider);

  WorkspaceFileTreeNotifier _treeNotifier(String path) {
    return ref.read(workspaceFileTreeProvider(path).notifier);
  }

  WorkspaceFileTreeState treeStateFor(String path) {
    return ref.read(workspaceFileTreeProvider(path));
  }

  WorkspaceFileTreeState get activeFileTree {
    final path = state.activeProjectPath;
    if (path == null) {
      return WorkspaceFileTreeState();
    }
    return treeStateFor(path);
  }

  /// 弹出系统目录选择器并打开/激活。取消返回 null；目录不存在也返回 null。
  Future<String?> openProject() async {
    final picked = await ref.read(workspaceDirectoryPickerProvider)();
    if (picked == null || picked.trim().isEmpty) {
      return null;
    }
    final loaded = await openOrActivate(picked);
    if (!loaded) {
      return null;
    }
    return state.activeProjectPath;
  }

  /// 打开或激活 [path]。已在列表中则只切换；目录不存在返回 false。
  ///
  /// 成功前不改 [WorkspaceState.activeProjectPath]，避免 await 期间 UI 先建出
  /// 草稿 Agent pane。
  Future<bool> openOrActivate(String path) async {
    final project = WorkspaceProject.fromPath(path);
    if (project.path.isEmpty) {
      return false;
    }
    final previousActive = state.activeProjectPath;
    final alreadyOpen = state.containsPath(project.path);
    if (alreadyOpen &&
        previousActive == project.path &&
        activeFileTree.hasLoaded) {
      return true;
    }

    final generation = ++_openGeneration;
    final loaded = _treeNotifier(project.path).ensureLoaded();
    if (!ref.mounted || generation != _openGeneration) {
      return false;
    }
    if (!loaded) {
      _log.w('Could not open project folder: ${project.path}');
      _discardProjectResources(project.path);
      return false;
    }

    final projects = List<WorkspaceProject>.of(state.openProjects);
    if (!alreadyOpen && !state.containsPath(project.path)) {
      projects.insert(0, project);
    }
    final opened = Map<String, DateTime>.of(state.projectLastOpenedAtByPath)
      ..[project.path] = _now;
    state = state.copyWith(
      openProjects: projects,
      activeProjectPath: project.path,
      projectLastOpenedAtByPath: opened,
    );
    if (previousActive != null &&
        previousActive != project.path &&
        !state.containsPath(previousActive)) {
      _discardProjectResources(previousActive);
    }
    unawaited(_index.index(project.path));
    return true;
  }

  /// 仅切换已打开的项目。不在列表中时返回 false。
  Future<bool> selectProject(String path) {
    final normalized = normalizeWorkspaceProjectPath(path);
    if (!state.containsPath(normalized)) {
      return Future<bool>.value(false);
    }
    return openOrActivate(normalized);
  }

  /// 从打开列表移除。若移除的是活动项目，调用方负责激活下一个或清空。
  bool removeProject(String path) {
    final normalized = normalizeWorkspaceProjectPath(path);
    if (!state.containsPath(normalized)) {
      return false;
    }
    final projects = state.openProjects
        .where((project) => project.path != normalized)
        .toList(growable: false);
    final opened = Map<String, DateTime>.of(state.projectLastOpenedAtByPath)
      ..remove(normalized);
    final removingActive = state.activeProjectPath == normalized;
    state = state.copyWith(
      openProjects: projects,
      projectLastOpenedAtByPath: opened,
    );
    if (!removingActive) {
      _discardProjectResources(normalized);
    }
    return true;
  }

  /// 清空当前激活项目（回首页）。打开列表保留。
  void clearActiveProject() {
    final active = state.activeProjectPath;
    if (active == null) {
      return;
    }
    state = state.copyWith(clearActiveProjectPath: true);
    if (!state.containsPath(active)) {
      _discardProjectResources(active);
    }
  }

  void markProjectOpened(String path, DateTime openedAt) {
    final normalized = normalizeWorkspaceProjectPath(path);
    if (normalized.isEmpty) {
      return;
    }
    final opened = Map<String, DateTime>.of(state.projectLastOpenedAtByPath)
      ..[normalized] = openedAt;
    state = state.copyWith(projectLastOpenedAtByPath: opened);
  }

  /// 从 session 白名单快照恢复。只加载当前激活项目的文件树。
  Future<bool> restore(WorkspaceRestoreSnapshot snapshot) async {
    final projects = <WorkspaceProject>[
      for (final path in snapshot.projects)
        if (normalizeWorkspaceProjectPath(path).isNotEmpty)
          WorkspaceProject.fromPath(path),
    ];
    final seen = <String>{};
    final unique = <WorkspaceProject>[];
    for (final project in projects) {
      if (seen.add(project.path)) {
        unique.add(project);
      }
    }
    final active = snapshot.activeProjectPath == null
        ? null
        : normalizeWorkspaceProjectPath(snapshot.activeProjectPath!);
    final activeExists =
        active != null && unique.any((project) => project.path == active);
    final lastOpened = <String, DateTime>{
      for (final entry in snapshot.projectLastOpenedAtByPath.entries)
        normalizeWorkspaceProjectPath(entry.key): entry.value,
    };
    final generation = ++_openGeneration;
    var loadedActive = true;
    final restoredActive = activeExists ? active : null;
    if (restoredActive != null) {
      loadedActive = _treeNotifier(restoredActive).ensureLoaded(
        expandedDirectoryPaths: snapshot.expandedDirectoryPaths,
        selectedTreePath: snapshot.selectedTreePath,
        currentFilePath: snapshot.currentFilePath,
        applyRestore: true,
      );
    }
    if (!ref.mounted || generation != _openGeneration) {
      return false;
    }
    state = WorkspaceState(
      openProjects: unique,
      activeProjectPath: loadedActive ? restoredActive : null,
      projectLastOpenedAtByPath: lastOpened,
    );
    if (loadedActive && restoredActive != null) {
      unawaited(_index.index(restoredActive));
    }
    return loadedActive;
  }

  void setDirectoryExpanded(String path, bool expanded) {
    final projectPath = state.activeProjectPath;
    if (projectPath == null) {
      return;
    }
    _treeNotifier(projectPath).setDirectoryExpanded(path, expanded);
  }

  WorkspaceNode? selectTreeNode(String path) {
    final projectPath = state.activeProjectPath;
    if (projectPath == null) {
      return null;
    }
    return _treeNotifier(projectPath).selectNode(path);
  }

  void clearCurrentFile() {
    final projectPath = state.activeProjectPath;
    if (projectPath == null) {
      return;
    }
    _treeNotifier(projectPath).clearCurrentFile();
  }

  /// 移除项目在切换走之后，释放其文件树与索引。
  void discardClosedProject(String path) {
    final normalized = normalizeWorkspaceProjectPath(path);
    if (state.activeProjectPath == normalized ||
        state.containsPath(normalized)) {
      return;
    }
    _discardProjectResources(normalized);
  }

  void _discardProjectResources(String path) {
    ref.invalidate(workspaceFileTreeProvider(path));
    _index.invalidate(path);
  }
}

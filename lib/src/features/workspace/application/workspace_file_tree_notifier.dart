import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/workspace/domain/workspace_directory_catalog.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';

/// 单个项目的文件树状态。
@immutable
final class WorkspaceFileTreeState {
  WorkspaceFileTreeState({
    List<WorkspaceNode> tree = const <WorkspaceNode>[],
    Set<String> expandedDirectoryPaths = const <String>{},
    this.selectedTreePath,
    this.currentFilePath,
    this.isLoading = false,
    this.loadOperationId,
    this.hasLoaded = false,
  }) : tree = List<WorkspaceNode>.unmodifiable(tree),
       expandedDirectoryPaths = Set<String>.unmodifiable(
         expandedDirectoryPaths,
       );

  final List<WorkspaceNode> tree;
  final Set<String> expandedDirectoryPaths;
  final String? selectedTreePath;
  final String? currentFilePath;
  final bool isLoading;
  final OperationId? loadOperationId;

  /// 是否已经成功提交过一次根目录读取。
  final bool hasLoaded;

  WorkspaceFileTreeState copyWith({
    List<WorkspaceNode>? tree,
    Set<String>? expandedDirectoryPaths,
    String? selectedTreePath,
    bool clearSelectedTreePath = false,
    String? currentFilePath,
    bool clearCurrentFilePath = false,
    bool? isLoading,
    OperationId? loadOperationId,
    bool clearLoadOperationId = false,
    bool? hasLoaded,
  }) {
    return WorkspaceFileTreeState(
      tree: tree ?? this.tree,
      expandedDirectoryPaths:
          expandedDirectoryPaths ?? this.expandedDirectoryPaths,
      selectedTreePath: clearSelectedTreePath
          ? null
          : selectedTreePath ?? this.selectedTreePath,
      currentFilePath: clearCurrentFilePath
          ? null
          : currentFilePath ?? this.currentFilePath,
      isLoading: isLoading ?? this.isLoading,
      loadOperationId: clearLoadOperationId
          ? null
          : loadOperationId ?? this.loadOperationId,
      hasLoaded: hasLoaded ?? this.hasLoaded,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is WorkspaceFileTreeState &&
        zetaListEquals(other.tree, tree) &&
        zetaSetEquals(other.expandedDirectoryPaths, expandedDirectoryPaths) &&
        other.selectedTreePath == selectedTreePath &&
        other.currentFilePath == currentFilePath &&
        other.isLoading == isLoading &&
        other.loadOperationId == loadOperationId &&
        other.hasLoaded == hasLoaded;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(tree),
    Object.hashAll(expandedDirectoryPaths),
    selectedTreePath,
    currentFilePath,
    isLoading,
    loadOperationId,
    hasLoaded,
  );
}

/// 按项目路径隔离的文件树 owner。
///
/// 生命周期由 [WorkspaceNotifier] 显式 `invalidate`，不用 `autoDispose`：
/// Files pane 暂时没 watch 时不能卸掉 Directory.watch / 已加载的树。
final class WorkspaceFileTreeNotifier extends Notifier<WorkspaceFileTreeState> {
  WorkspaceFileTreeNotifier(this.projectPath);

  final String projectPath;

  static const String _loadScope = 'workspace/file-tree/load';

  late final OperationIdGenerator _loadIds = OperationIdGenerator(
    scope: _loadScope,
  );

  @override
  WorkspaceFileTreeState build() {
    return WorkspaceFileTreeState();
  }

  WorkspaceDirectoryCatalog get _catalog =>
      ref.read(workspaceDirectoryCatalogProvider);

  /// 确保根目录已读取。已加载且未带 restore 覆盖时直接成功。
  bool ensureLoaded({
    Set<String>? expandedDirectoryPaths,
    String? selectedTreePath,
    String? currentFilePath,
    bool applyRestore = false,
  }) {
    if (state.hasLoaded && !applyRestore) {
      return true;
    }
    final operationId = _loadIds.next();
    final expanded =
        expandedDirectoryPaths ??
        (applyRestore ? const <String>{} : state.expandedDirectoryPaths);
    state = state.copyWith(
      isLoading: true,
      loadOperationId: operationId,
      expandedDirectoryPaths: applyRestore ? expanded : null,
      selectedTreePath: applyRestore ? selectedTreePath : null,
      clearSelectedTreePath: applyRestore && selectedTreePath == null,
      currentFilePath: applyRestore ? currentFilePath : null,
      clearCurrentFilePath: applyRestore && currentFilePath == null,
    );
    if (!_catalog.exists(projectPath)) {
      state = state.copyWith(isLoading: false, clearLoadOperationId: true);
      return false;
    }
    final tree = _catalog.readChildren(projectPath, expandedPaths: expanded);
    var selected = applyRestore ? selectedTreePath : state.selectedTreePath;
    if (selected == projectPath ||
        (selected != null &&
            WorkspaceNode.findByPath(tree, selected) == null)) {
      selected = null;
    }
    state = state.copyWith(
      tree: tree,
      expandedDirectoryPaths: expanded,
      selectedTreePath: selected,
      clearSelectedTreePath: selected == null,
      currentFilePath: applyRestore ? currentFilePath : state.currentFilePath,
      isLoading: false,
      clearLoadOperationId: true,
      hasLoaded: true,
    );
    return true;
  }

  void setDirectoryExpanded(String path, bool expanded) {
    _changeExpansion(path, expanded);
  }

  /// 选中节点。文件会写入 [WorkspaceFileTreeState.currentFilePath]；
  /// 目录则切换展开。返回命中的节点。
  WorkspaceNode? selectNode(String path) {
    final node = WorkspaceNode.findByPath(state.tree, path);
    if (node == null) {
      return null;
    }
    if (!node.isDirectory) {
      state = state.copyWith(
        selectedTreePath: path,
        currentFilePath: node.path,
      );
      return node;
    }
    state = state.copyWith(selectedTreePath: path);
    _changeExpansion(path, !state.expandedDirectoryPaths.contains(path));
    return node;
  }

  void clearCurrentFile() {
    if (state.currentFilePath == null) {
      return;
    }
    state = state.copyWith(clearCurrentFilePath: true);
  }

  void _changeExpansion(String path, bool expanded) {
    final node = WorkspaceNode.findByPath(state.tree, path);
    if (node == null || !node.isDirectory) {
      return;
    }
    final paths = Set<String>.of(state.expandedDirectoryPaths);
    final changed = expanded ? paths.add(path) : paths.remove(path);
    if (!changed && (!expanded || node.childrenLoaded)) {
      return;
    }
    var tree = state.tree;
    if (expanded && !node.childrenLoaded) {
      final children = _catalog.readChildren(
        path,
        expandedPaths: Set<String>.unmodifiable(paths),
      );
      tree = WorkspaceNode.updateNode(tree, path, (current) {
        if (!current.isDirectory || current.childrenLoaded) {
          return current;
        }
        return current.copyWith(
          childrenLoaded: true,
          children: List<WorkspaceNode>.unmodifiable(children),
        );
      });
    }
    state = state.copyWith(tree: tree, expandedDirectoryPaths: paths);
  }
}

/// 目录 catalog。组合根必须覆盖。
final workspaceDirectoryCatalogProvider = Provider<WorkspaceDirectoryCatalog>(
  (ref) => throw StateError('Workspace directory catalog is not installed'),
  name: 'workspaceDirectoryCatalog',
);

/// 按项目路径隔离的文件树。
final workspaceFileTreeProvider =
    NotifierProvider.family<
      WorkspaceFileTreeNotifier,
      WorkspaceFileTreeState,
      String
    >(WorkspaceFileTreeNotifier.new, name: 'workspaceFileTree');

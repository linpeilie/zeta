import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:desktop_platform_repository/desktop_platform_repository.dart';
import 'package:workspace_repository/workspace_repository.dart';
import 'package:zeta/workspace/cubit/workspace_state.dart';

// Named public constructor parameters initialize private fields.
// ignore_for_file: prefer_initializing_formals

class WorkspaceCubit extends Cubit<WorkspaceState> {
  WorkspaceCubit({
    required WorkspaceRepository workspaceRepository,
    required DesktopPlatformRepository desktopPlatformRepository,
  }) : _workspaceRepository = workspaceRepository,
       _desktopPlatformRepository = desktopPlatformRepository,
       super(const WorkspaceState()) {
    _indexSubscription = _workspaceRepository.indexChanges.listen(
      _onIndexChanged,
    );
    _treeSubscription = _workspaceRepository.treeChanges.listen(
      _onTreeChanged,
      onError: _onTreeError,
    );
  }

  final WorkspaceRepository _workspaceRepository;
  final DesktopPlatformRepository _desktopPlatformRepository;
  late final StreamSubscription<WorkspaceIndex> _indexSubscription;
  late final StreamSubscription<WorkspaceTreeChange> _treeSubscription;
  final Map<String, int> _indexGenerations = <String, int>{};
  final Map<String, int> _childrenGenerations = <String, int>{};

  Future<void> index(String rootPath) async {
    final root = rootPath.trim();
    if (root.isEmpty || isClosed) {
      return;
    }
    final generation = (_indexGenerations[root] ?? 0) + 1;
    _indexGenerations[root] = generation;
    emit(
      state.copyWith(
        status: WorkspaceStatus.loading,
        rootPath: root,
        clearFailure: true,
      ),
    );
    try {
      final index = await _workspaceRepository.index(root);
      if (!_isCurrentIndex(root, generation)) {
        return;
      }
      final children = await _workspaceRepository.loadChildren(
        rootPath: root,
        directoryPath: root,
      );
      if (!_isCurrentIndex(root, generation)) {
        return;
      }
      emit(
        state.copyWith(
          status: WorkspaceStatus.ready,
          rootPath: root,
          index: index,
          childrenByPath: <String, List<WorkspaceNode>>{
            ...state.childrenByPath,
            root: children,
          },
          expandedPaths: <String>{root, ...state.expandedPaths},
          clearFailure: true,
        ),
      );
    } on WorkspaceRepositoryException catch (error) {
      if (!_isCurrentIndex(root, generation)) {
        return;
      }
      if (error.failure.code == WorkspaceRepositoryFailureCode.cancelled) {
        return;
      }
      emit(
        state.copyWith(
          status: WorkspaceStatus.failure,
          failure: error.failure,
        ),
      );
    }
  }

  Future<void> invalidate() {
    final rootPath = state.rootPath;
    if (rootPath == null) {
      return Future<void>.value();
    }
    return index(rootPath);
  }

  Future<void> toggle(String path) async {
    final rootPath = state.rootPath;
    if (rootPath == null || isClosed) {
      return;
    }
    if (state.isExpanded(path)) {
      final expanded = Set<String>.from(state.expandedPaths)..remove(path);
      emit(state.copyWith(expandedPaths: expanded, clearFailure: true));
      return;
    }
    final generation = (_childrenGenerations[path] ?? 0) + 1;
    _childrenGenerations[path] = generation;
    emit(
      state.copyWith(
        expandedPaths: <String>{...state.expandedPaths, path},
        status: WorkspaceStatus.loading,
        clearFailure: true,
      ),
    );
    try {
      final children = await _workspaceRepository.loadChildren(
        rootPath: rootPath,
        directoryPath: path,
      );
      if (isClosed || _childrenGenerations[path] != generation) {
        return;
      }
      emit(
        state.copyWith(
          status: WorkspaceStatus.ready,
          childrenByPath: <String, List<WorkspaceNode>>{
            ...state.childrenByPath,
            path: children,
          },
        ),
      );
    } on WorkspaceRepositoryException catch (error) {
      if (isClosed || _childrenGenerations[path] != generation) {
        return;
      }
      if (error.failure.code == WorkspaceRepositoryFailureCode.cancelled) {
        return;
      }
      final expanded = Set<String>.from(state.expandedPaths)..remove(path);
      emit(
        state.copyWith(
          status: WorkspaceStatus.failure,
          expandedPaths: expanded,
          failure: error.failure,
        ),
      );
    }
  }

  void select(String path) {
    if (isClosed) {
      return;
    }
    emit(state.copyWith(selectedPath: path, clearFailure: true));
  }

  Future<void> pickRoot() async {
    try {
      final path = await _desktopPlatformRepository.pickDirectory(
        initialDirectory: state.rootPath,
      );
      if (path == null || isClosed) {
        return;
      }
      emit(
        state.copyWith(
          selectedPath: path,
          expandedPaths: <String>{path},
          childrenByPath: const <String, List<WorkspaceNode>>{},
        ),
      );
      await index(path);
    } on DesktopPlatformException catch (error) {
      if (isClosed) {
        return;
      }
      emit(
        state.copyWith(
          status: WorkspaceStatus.failure,
          failure: WorkspaceRepositoryFailure(
            operation: WorkspaceRepositoryOperation.indexWorkspace,
            code: WorkspaceRepositoryFailureCode.ioFailure,
            diagnosticCode: error.operation.name,
          ),
        ),
      );
    }
  }

  Future<void> reveal(String path) async {
    select(path);
    final directory = _directoryOf(path);
    try {
      await _desktopPlatformRepository.openDirectory(directory);
    } on DesktopPlatformException catch (error) {
      if (isClosed) {
        return;
      }
      emit(
        state.copyWith(
          status: WorkspaceStatus.failure,
          failure: WorkspaceRepositoryFailure(
            operation: WorkspaceRepositoryOperation.loadChildren,
            code: WorkspaceRepositoryFailureCode.ioFailure,
            diagnosticCode: error.operation.name,
          ),
        ),
      );
    }
  }

  void _onIndexChanged(WorkspaceIndex index) {
    if (isClosed || index.rootPath != state.rootPath) {
      return;
    }
    emit(state.copyWith(index: index, status: WorkspaceStatus.ready));
  }

  void _onTreeChanged(WorkspaceTreeChange change) {
    if (change.rootPath == state.rootPath) {
      unawaited(invalidate());
    }
  }

  void _onTreeError(Object error, StackTrace _) {
    if (isClosed) {
      return;
    }
    if (error is WorkspaceRepositoryException) {
      emit(
        state.copyWith(
          status: WorkspaceStatus.failure,
          failure: error.failure,
        ),
      );
    }
  }

  bool _isCurrentIndex(String root, int generation) {
    return !isClosed &&
        state.rootPath == root &&
        _indexGenerations[root] == generation;
  }

  String _directoryOf(String path) {
    final slash = path.lastIndexOf('/');
    final backslash = path.lastIndexOf(r'\');
    final index = slash > backslash ? slash : backslash;
    if (index <= 0) {
      return path;
    }
    return path.substring(0, index);
  }

  @override
  Future<void> close() async {
    await _indexSubscription.cancel();
    await _treeSubscription.cancel();
    return super.close();
  }
}

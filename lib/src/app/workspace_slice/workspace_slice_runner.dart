import 'dart:async';
import 'dart:io';

import 'package:zeta/src/features/workspace/application/workspace_file_index_controller.dart';
import 'package:zeta/src/features/workspace/application/workspace_slice/workspace_slice_effect.dart';
import 'package:zeta/src/features/workspace/application/workspace_slice/workspace_slice_store.dart';
import 'package:zeta/src/features/workspace/application/workspace_tree_builder.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';

/// Workspace MVI 的 app 组合层 effect runner。
final class WorkspaceSliceRunner implements WorkspaceSliceEffectRunner {
  WorkspaceSliceRunner(
    this._store,
    this._fileIndexController, {
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final WorkspaceSliceStore _store;
  final WorkspaceFileIndexController _fileIndexController;
  final DateTime Function() _now;
  bool _closed = false;

  @override
  void run(WorkspaceSliceEffect effect) {
    if (_closed) {
      return;
    }
    switch (effect) {
      case ReadWorkspaceProjectEffect():
        unawaited(_readProject(effect));
      case RestoreWorkspaceEffect():
        _restore(effect);
      case ReadWorkspaceDirectoryEffect():
        final children = buildWorkspaceDirectoryChildren(
          Directory(effect.path),
          expandedPaths: effect.expandedDirectoryPaths,
        );
        if (!_closed) {
          _store.directoryLoaded(effect.path, children);
        }
      case IndexWorkspaceFilesEffect():
        unawaited(_fileIndexController.index(effect.root));
      case InvalidateWorkspaceFilesEffect():
        _fileIndexController.invalidate(effect.root);
    }
  }

  Future<void> _readProject(ReadWorkspaceProjectEffect effect) async {
    try {
      final directory = Directory(effect.path);
      if (!await directory.exists()) {
        throw FileSystemException('Directory does not exist', effect.path);
      }
      final tree = buildWorkspaceDirectoryChildren(directory);
      if (!_closed) {
        _store.projectLoadSucceeded(
          operationId: effect.operationId,
          path: effect.path,
          tree: tree,
          openedAt: _now(),
        );
      }
    } catch (error, stackTrace) {
      if (!_closed) {
        _store.projectLoadFailed(effect.operationId, error, stackTrace);
      }
    }
  }

  void _restore(RestoreWorkspaceEffect effect) {
    try {
      final snapshot = effect.snapshot;
      final activeProjectPath = snapshot.activeProjectPath;
      var tree = const <WorkspaceNode>[];
      var selectedTreePath = snapshot.selectedTreePath;
      if (activeProjectPath != null) {
        tree = buildWorkspaceDirectoryChildren(
          Directory(activeProjectPath),
          expandedPaths: snapshot.expandedDirectoryPaths,
        );
        if (selectedTreePath == activeProjectPath ||
            (selectedTreePath != null &&
                WorkspaceNode.findByPath(tree, selectedTreePath) == null)) {
          selectedTreePath = null;
        }
      }
      if (!_closed) {
        _store.restoreSucceeded(
          operationId: effect.operationId,
          snapshot: snapshot,
          tree: tree,
          selectedTreePath: selectedTreePath,
        );
      }
    } catch (error, stackTrace) {
      if (!_closed) {
        _store.restoreFailed(effect.operationId, error, stackTrace);
      }
    }
  }

  @override
  void close() {
    _closed = true;
  }
}

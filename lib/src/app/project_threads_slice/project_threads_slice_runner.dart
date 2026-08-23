import 'dart:async';

import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/project_threads/application/project_threads_controller.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_slice/project_threads_slice_effect.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_slice/project_threads_slice_store.dart';

/// Project Threads MVI 的 app 组合层 effect runner。
///
/// controller 只执行 Provider 查询、能力校验和 Timer；所有状态写入都经构造时
/// 注入的 slice store typed ingress 回流。
final class ProjectThreadsSliceRunnerAdapter
    implements ProjectThreadsSliceEffectRunner {
  ProjectThreadsSliceRunnerAdapter(this._controller, this._store);

  final ProjectThreadsController _controller;
  final ProjectThreadsSliceStore _store;
  bool _closed = false;

  @override
  void run(ProjectThreadsSliceEffect effect) {
    if (_closed) {
      return;
    }
    switch (effect) {
      case RestoreProjectThreadsEffect():
        _controller.restoreSession(
          projectPaths: effect.projectPaths,
          activeProjectPath: effect.activeProjectPath,
          snapshot: effect.snapshot,
        );
      case ActivateProjectThreadsEffect():
        _controller.activateProject(effect.projectPath);
      case RetainProjectThreadsEffect():
        _controller.retainProjects(effect.projectPaths);
      case ToggleProjectThreadsEffect():
        unawaited(
          _completeVoid(
            effect.operationId,
            _controller.toggleProject(effect.projectPath),
          ),
        );
      case SetArchivedProjectThreadsEffect():
        unawaited(
          _completeVoid(
            effect.operationId,
            _controller.setArchivedView(
              projectPath: effect.projectPath,
              archived: effect.archived,
            ),
          ),
        );
      case SetProjectThreadSearchEffect():
        _controller.setSearchTerm(
          projectPath: effect.projectPath,
          searchTerm: effect.searchTerm,
        );
      case LoadInitialProjectThreadsEffect():
        unawaited(
          _completeVoid(
            effect.operationId,
            _controller.loadInitial(effect.projectPath),
          ),
        );
      case LoadMoreProjectThreadsEffect():
        unawaited(
          _completeVoid(
            effect.operationId,
            _controller.loadMore(effect.projectPath),
          ),
        );
      case RenameProjectThreadEffect():
        unawaited(
          _completeVoid(
            effect.operationId,
            _controller.renameThread(
              projectPath: effect.projectPath,
              threadId: effect.threadId,
              name: effect.name,
            ),
          ),
        );
      case ArchiveProjectThreadEffect():
        unawaited(
          _completeVoid(
            effect.operationId,
            _controller.archiveThread(
              projectPath: effect.projectPath,
              threadId: effect.threadId,
            ),
          ),
        );
      case UnarchiveProjectThreadEffect():
        unawaited(
          _completeVoid(
            effect.operationId,
            _controller.unarchiveThread(
              projectPath: effect.projectPath,
              threadId: effect.threadId,
            ),
          ),
        );
      case DeleteProjectThreadEffect():
        unawaited(
          _completeVoid(
            effect.operationId,
            _controller.deleteThread(
              projectPath: effect.projectPath,
              threadId: effect.threadId,
            ),
          ),
        );
      case ForkProjectThreadEffect():
        unawaited(_fork(effect));
    }
  }

  Future<void> _completeVoid(
    OperationId operationId,
    Future<void> operation,
  ) async {
    try {
      await operation;
      if (!_closed) {
        _store.operationSucceeded(operationId);
      }
    } catch (error, stackTrace) {
      if (!_closed) {
        _store.operationFailed(operationId, error, stackTrace);
      }
    }
  }

  Future<void> _fork(ForkProjectThreadEffect effect) async {
    try {
      final session = await _controller.forkThread(
        projectPath: effect.projectPath,
        threadId: effect.threadId,
        permissionSnapshot: effect.permissionSnapshot,
      );
      if (!_closed) {
        _store.forkSucceeded(effect.operationId, session);
      }
    } catch (error, stackTrace) {
      if (!_closed) {
        _store.operationFailed(effect.operationId, error, stackTrace);
      }
    }
  }

  @override
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _controller.dispose();
  }
}

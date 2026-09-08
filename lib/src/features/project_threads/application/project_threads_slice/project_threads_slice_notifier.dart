import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'project_threads_slice_dependencies.dart';

import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/project_threads/application/project_threads_operations.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_slice/project_threads_slice_effect.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_slice/project_threads_slice_intent.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_slice/project_threads_slice_reducer.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_slice/project_threads_slice_state.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_state_owner.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_session_snapshot_codec.dart';
import 'package:zeta/src/features/project_threads/domain/project_thread_list_state.dart';
import 'package:zeta/src/features/project_threads/domain/project_threads_session_snapshot.dart';

final projectThreadsSliceProvider =
    NotifierProvider<ProjectThreadsSliceNotifier, ProjectThreadsSliceState>(
      ProjectThreadsSliceNotifier.new,
      name: 'projectThreadsSlice',
    );

final projectThreadsOperationsProvider = Provider<ProjectThreadsOperations>(
  (ref) => ref.read(projectThreadsSliceProvider.notifier),
  name: 'projectThreadsOperations',
);

/// App-session owner of list state, the thread index and command waiters.
final class ProjectThreadsSliceNotifier
    extends Notifier<ProjectThreadsSliceState>
    implements
        ProjectThreadsOperations,
        ProjectThreadsStateOwner,
        ProjectThreadsOwnerLifecycle {
  @override
  ProjectThreadsSliceState build() {
    if (_built) {
      throw StateError('Project Threads owner requires a new app session');
    }
    _built = true;
    final deps = ref.read(projectThreadsSliceDependenciesProvider);
    _generatorFactory = deps.operationIdGeneratorFactory;
    _now = deps.now;
    _rebuildThreadMappings(deps.initialState);
    effectRunner = ref.read(projectThreadsRunnerFactoryProvider)(this);
    ref.onDispose(stopAcceptingCommandsAndSettleWaiters);
    return deps.initialState;
  }

  static const String _toggleScope = 'project-threads/toggle';
  static const String _archiveViewScope = 'project-threads/archive-view';
  static const String _loadInitialScope = 'project-threads/load-initial';
  static const String _loadMoreScope = 'project-threads/load-more';
  static const String _renameScope = 'project-threads/rename';
  static const String _archiveScope = 'project-threads/archive';
  static const String _unarchiveScope = 'project-threads/unarchive';
  static const String _deleteScope = 'project-threads/delete';
  static const String _forkScope = 'project-threads/fork';

  late final ProjectThreadsSliceEffectRunner effectRunner;
  late final OperationIdGenerator Function(String scope) _generatorFactory;
  late final DateTime Function() _now;
  final Map<String, OperationIdGenerator> _generators =
      <String, OperationIdGenerator>{};
  final Map<String, String> _projectPathByThreadId = <String, String>{};
  final Map<OperationId, Completer<void>> _voidCompleters =
      <OperationId, Completer<void>>{};
  final Map<OperationId, Completer<AgentSession?>> _forkCompleters =
      <OperationId, Completer<AgentSession?>>{};

  bool _built = false;
  Future<void>? _drainFuture;
  bool _closed = false;
  int _staleResultCount = 0;

  ProjectThreadsSliceState get current => state;

  bool get isClosed => _closed;

  int get staleResultCount => _staleResultCount;

  @override
  Map<String, ProjectThreadListState> get states => state.statesByProject;

  @override
  void Function(String projectPath, String threadId)? onActiveThreadCleared;

  @override
  ProjectThreadListState stateFor(String projectPath) {
    return state.stateFor(projectPath);
  }

  @override
  AgentThreadSummary? threadFor(String projectPath, String threadId) {
    return _threadById(stateFor(projectPath), threadId);
  }

  @override
  ProjectThreadsSessionSnapshot get sessionSnapshot {
    return buildProjectThreadsSessionSnapshot(state.statesByProject);
  }

  @override
  void restoreSession({
    required List<String> projectPaths,
    required String? activeProjectPath,
    required ProjectThreadsSessionSnapshot snapshot,
  }) {
    _dispatch(
      ProjectThreadsEffectRequested(
        RestoreProjectThreadsEffect(
          projectPaths: List<String>.unmodifiable(projectPaths),
          activeProjectPath: activeProjectPath,
          snapshot: snapshot,
        ),
      ),
    );
  }

  @override
  void activateProject(String projectPath) {
    _dispatch(
      ProjectThreadsEffectRequested(ActivateProjectThreadsEffect(projectPath)),
    );
  }

  @override
  void retainProjects(List<String> projectPaths) {
    _dispatch(
      ProjectThreadsEffectRequested(
        RetainProjectThreadsEffect(List<String>.unmodifiable(projectPaths)),
      ),
    );
  }

  @override
  Future<void> toggleProject(String projectPath) {
    final operationId = _nextOperationId(_toggleScope);
    return _runVoid(
      operationId,
      ToggleProjectThreadsEffect(operationId, projectPath),
    );
  }

  @override
  Future<void> setArchivedView({
    required String projectPath,
    required bool archived,
  }) {
    final operationId = _nextOperationId(_archiveViewScope);
    return _runVoid(
      operationId,
      SetArchivedProjectThreadsEffect(
        operationId: operationId,
        projectPath: projectPath,
        archived: archived,
      ),
    );
  }

  @override
  void setSearchTerm({
    required String projectPath,
    required String searchTerm,
  }) {
    _dispatch(
      ProjectThreadsEffectRequested(
        SetProjectThreadSearchEffect(
          projectPath: projectPath,
          searchTerm: searchTerm,
        ),
      ),
    );
  }

  @override
  Future<void> loadInitial(String projectPath) {
    final operationId = _nextOperationId(_loadInitialScope);
    return _runVoid(
      operationId,
      LoadInitialProjectThreadsEffect(operationId, projectPath),
    );
  }

  @override
  Future<void> loadMore(String projectPath) {
    final operationId = _nextOperationId(_loadMoreScope);
    return _runVoid(
      operationId,
      LoadMoreProjectThreadsEffect(operationId, projectPath),
    );
  }

  @override
  void selectThread(String projectPath, AgentThreadSummary thread) {
    registerThreadMapping(projectPath, thread.id);
    applyThreadSelection(projectPath, thread.id);
  }

  @override
  void selectThreadId(String projectPath, String threadId) {
    registerThreadMapping(projectPath, threadId);
    applyThreadSelection(projectPath, threadId);
  }

  @override
  void clearSelectedThread(String projectPath) {
    applyThreadSelectionClear(projectPath);
  }

  @override
  void clearAllSelectedThreads() {
    applyAllThreadSelectionsClear();
  }

  @override
  void registerThreadMapping(String projectPath, String threadId) {
    if (_closed) return;
    _projectPathByThreadId[threadId] = projectPath;
  }

  @override
  AgentThreadSummary registerSession(
    String projectPath,
    AgentSession session, {
    String? preview,
    bool markRunning = false,
  }) {
    _ensureOpen();
    registerThreadMapping(projectPath, session.id);
    final formalTitle = isAgentThreadTitlePlaceholder(session.title)
        ? null
        : session.title?.trim();
    final resolvedPreview = (preview ?? session.title ?? '').trim();
    final now = _now();
    final thread = AgentThreadSummary(
      id: session.id,
      providerId: session.providerId,
      projectPath: projectPath,
      title: formalTitle,
      preview: resolvedPreview,
      createdAt: now,
      updatedAt: now,
      status: AgentThreadRuntimeStatus.idle,
    );
    applyThreadPrepend(projectPath: projectPath, thread: thread);
    if (formalTitle != null) {
      applyThreadTitle(
        projectPath: projectPath,
        threadId: session.id,
        title: formalTitle,
      );
    }
    applyThreadSelection(projectPath, session.id);
    if (markRunning) {
      setThreadRunning(session.id, isRunning: true);
    }
    return thread;
  }

  @override
  void setThreadRunning(String threadId, {required bool isRunning}) {
    final projectPath = _projectPathByThreadId[threadId];
    if (projectPath == null) {
      return;
    }
    applyThreadRunning(
      projectPath: projectPath,
      threadId: threadId,
      isRunning: isRunning,
    );
  }

  @override
  void dismissCompletedThread({
    required String projectPath,
    required String threadId,
  }) {
    applyCompletedThreadDismissal(projectPath: projectPath, threadId: threadId);
  }

  @override
  void syncRuntimeSnapshot({
    required String projectPath,
    required AgentConversationThreadSnapshot snapshot,
  }) {
    if (_closed) return;
    final sessionId = snapshot.sessionId;
    if (sessionId == null || sessionId.isEmpty) {
      return;
    }
    registerThreadMapping(projectPath, sessionId);
    final current = stateFor(projectPath);
    final thread = _threadById(current, sessionId);
    final threadTitle = snapshot.threadTitle.trim();
    if (!isAgentThreadTitlePlaceholder(threadTitle) &&
        thread?.title?.trim() != threadTitle) {
      applyThreadTitle(
        projectPath: projectPath,
        threadId: sessionId,
        title: threadTitle,
      );
    }
    final threadPreview = snapshot.threadPreview.trim();
    if (threadPreview.isNotEmpty && thread?.preview != threadPreview) {
      applyThreadPreview(
        projectPath: projectPath,
        threadId: sessionId,
        preview: threadPreview,
      );
    }
    final runtimeStatus = _effectiveListRuntimeStatus(snapshot);
    if (runtimeStatus != null) {
      applyThreadRuntimeStatus(
        projectPath: projectPath,
        threadId: sessionId,
        status: runtimeStatus,
        waitingOnApproval: snapshot.waitingOnApproval,
        waitingOnUserInput: snapshot.waitingOnUserInput,
      );
    }
    setThreadRunning(sessionId, isRunning: snapshot.isTurnRunning);
  }

  @override
  void updateThreadTitle({
    required String projectPath,
    required String threadId,
    required String? title,
  }) {
    registerThreadMapping(projectPath, threadId);
    applyThreadTitle(
      projectPath: projectPath,
      threadId: threadId,
      title: title,
    );
  }

  @override
  void updateThreadPreview({
    required String projectPath,
    required String threadId,
    required String preview,
  }) {
    registerThreadMapping(projectPath, threadId);
    applyThreadPreview(
      projectPath: projectPath,
      threadId: threadId,
      preview: preview,
    );
  }

  @override
  Future<void> renameThread({
    required String projectPath,
    required String threadId,
    required String name,
  }) {
    final operationId = _nextOperationId(_renameScope);
    return _runVoid(
      operationId,
      RenameProjectThreadEffect(
        operationId: operationId,
        projectPath: projectPath,
        threadId: threadId,
        name: name,
      ),
    );
  }

  @override
  Future<void> archiveThread({
    required String projectPath,
    required String threadId,
  }) {
    final operationId = _nextOperationId(_archiveScope);
    return _runVoid(
      operationId,
      ArchiveProjectThreadEffect(
        operationId: operationId,
        projectPath: projectPath,
        threadId: threadId,
      ),
    );
  }

  @override
  Future<void> unarchiveThread({
    required String projectPath,
    required String threadId,
  }) {
    final operationId = _nextOperationId(_unarchiveScope);
    return _runVoid(
      operationId,
      UnarchiveProjectThreadEffect(
        operationId: operationId,
        projectPath: projectPath,
        threadId: threadId,
      ),
    );
  }

  @override
  Future<void> deleteThread({
    required String projectPath,
    required String threadId,
  }) {
    final operationId = _nextOperationId(_deleteScope);
    return _runVoid(
      operationId,
      DeleteProjectThreadEffect(
        operationId: operationId,
        projectPath: projectPath,
        threadId: threadId,
      ),
    );
  }

  @override
  Future<AgentSession?> forkThread({
    required String projectPath,
    required String threadId,
    AgentPermissionRequestSnapshot? permissionSnapshot,
  }) {
    _ensureOpen();
    final operationId = _nextOperationId(_forkScope);
    final completer = Completer<AgentSession?>();
    _forkCompleters[operationId] = completer;
    _dispatch(
      ProjectThreadsEffectRequested(
        ForkProjectThreadEffect(
          operationId: operationId,
          projectPath: projectPath,
          threadId: threadId,
          permissionSnapshot: permissionSnapshot,
        ),
      ),
    );
    return completer.future;
  }

  @override
  void applyStatesReplacement(Map<String, ProjectThreadListState> states) {
    if (_closed) return;
    _dispatch(ProjectThreadStatesReplaced(states));
    _rebuildThreadMappings(state);
  }

  @override
  void applyProjectsRetention(List<String> projectPaths) {
    if (_closed) return;
    _dispatch(ProjectThreadProjectsRetained(projectPaths));
    final allowed = projectPaths.toSet();
    _projectPathByThreadId.removeWhere(
      (_, projectPath) => !allowed.contains(projectPath),
    );
  }

  @override
  void applyProjectState(String projectPath, ProjectThreadListState state) {
    if (_closed) return;
    _dispatch(ProjectThreadStateApplied(projectPath, state));
    _registerStateThreadMappings(projectPath, state);
  }

  @override
  void applyThreadSelection(String projectPath, String threadId) {
    registerThreadMapping(projectPath, threadId);
    _dispatch(ProjectThreadSelected(projectPath, threadId));
  }

  @override
  void applyThreadSelectionClear(String projectPath) {
    _dispatch(ProjectThreadSelectionCleared(projectPath));
  }

  @override
  void applyAllThreadSelectionsClear() {
    _dispatch(const AllProjectThreadSelectionsCleared());
  }

  @override
  void applyThreadRunning({
    required String projectPath,
    required String threadId,
    required bool isRunning,
  }) {
    _dispatch(
      ProjectThreadRunningChanged(
        projectPath: projectPath,
        threadId: threadId,
        isRunning: isRunning,
        activityAt: _now(),
      ),
    );
  }

  @override
  void applyCompletedThreadDismissal({
    required String projectPath,
    required String threadId,
  }) {
    _dispatch(CompletedProjectThreadDismissed(projectPath, threadId));
  }

  @override
  void applyThreadRuntimeStatus({
    required String projectPath,
    required String threadId,
    required AgentThreadRuntimeStatus status,
    required bool waitingOnApproval,
    required bool waitingOnUserInput,
  }) {
    _dispatch(
      ProjectThreadRuntimeStatusChanged(
        projectPath: projectPath,
        threadId: threadId,
        status: status,
        waitingOnApproval: waitingOnApproval,
        waitingOnUserInput: waitingOnUserInput,
        activityAt: _now(),
      ),
    );
  }

  @override
  void applyThreadTitle({
    required String projectPath,
    required String threadId,
    required String? title,
  }) {
    _dispatch(
      ProjectThreadTitleChanged(
        projectPath: projectPath,
        threadId: threadId,
        title: title,
      ),
    );
  }

  @override
  void applyThreadPreview({
    required String projectPath,
    required String threadId,
    required String preview,
  }) {
    _dispatch(
      ProjectThreadPreviewChanged(
        projectPath: projectPath,
        threadId: threadId,
        preview: preview,
      ),
    );
  }

  @override
  bool applyThreadRemoval({
    required String projectPath,
    required String threadId,
  }) {
    if (_closed) return false;
    final current = stateFor(projectPath);
    final exists = current.threads.any((thread) => thread.id == threadId);
    // 返回编排选中是否被清掉，供 shell 决定是否导航离开；不是 UI 高亮。
    final clearedSelection = exists && current.selectedThreadId == threadId;
    _dispatch(ProjectThreadRemoved(projectPath, threadId));
    if (exists) {
      _projectPathByThreadId.remove(threadId);
    }
    return !_closed && clearedSelection;
  }

  @override
  void applyThreadPrepend({
    required String projectPath,
    required AgentThreadSummary thread,
  }) {
    registerThreadMapping(projectPath, thread.id);
    _dispatch(ProjectThreadPrepended(projectPath, thread));
  }

  @override
  void activeThreadCleared(String projectPath, String threadId) {
    if (_closed) return;
    onActiveThreadCleared?.call(projectPath, threadId);
  }

  /// effect runner 的成功回执。
  @override
  void operationSucceeded(OperationId operationId) {
    _dispatch(ProjectThreadsOperationSucceeded(operationId));
  }

  /// fork effect 的 typed 成功回执。
  @override
  void forkSucceeded(OperationId operationId, AgentSession? session) {
    _dispatch(ProjectThreadsForkSucceeded(operationId, session));
  }

  /// effect runner 的失败回执；错误只用于结算调用方 Future，不进入 state。
  @override
  void operationFailed(
    OperationId operationId,
    Object error,
    StackTrace stackTrace,
  ) {
    _dispatch(ProjectThreadsOperationFailed(operationId, error, stackTrace));
  }

  @override
  void stopAcceptingCommandsAndSettleWaiters() {
    if (_closed) {
      return;
    }
    _closed = true;
    for (final completer in _voidCompleters.values) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
    for (final completer in _forkCompleters.values) {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    }
    _voidCompleters.clear();
    _forkCompleters.clear();
    _projectPathByThreadId.clear();
    onActiveThreadCleared = null;
    effectRunner.close();
  }

  @override
  Future<void> drainExecutions() {
    if (!_closed) {
      throw StateError('Project Threads owner must stop before drain');
    }
    return _drainFuture ??= effectRunner.drainExecutions();
  }

  Future<void> _runVoid(
    OperationId operationId,
    ProjectThreadsSliceEffect effect,
  ) {
    _ensureOpen();
    final completer = Completer<void>();
    _voidCompleters[operationId] = completer;
    _dispatch(ProjectThreadsEffectRequested(effect));
    return completer.future;
  }

  void _dispatch(ProjectThreadsSliceIntent intent) {
    if (_closed) {
      return;
    }
    final before = state;
    final transition = projectThreadsSliceReduce(before, intent);
    if (!identical(transition.state, before)) {
      state = transition.state;
    }
    for (final effect in transition.effects) {
      if (_closed) break;
      effectRunner.run(effect);
    }
    _settleResult(intent);
  }

  void _settleResult(ProjectThreadsSliceIntent intent) {
    switch (intent) {
      case ProjectThreadsOperationSucceeded():
        final completer = _voidCompleters.remove(intent.operationId);
        if (completer == null) {
          _staleResultCount += 1;
        } else if (!completer.isCompleted) {
          completer.complete();
        }
      case ProjectThreadsForkSucceeded():
        final completer = _forkCompleters.remove(intent.operationId);
        if (completer == null) {
          _staleResultCount += 1;
        } else if (!completer.isCompleted) {
          completer.complete(intent.session);
        }
      case ProjectThreadsOperationFailed():
        final voidCompleter = _voidCompleters.remove(intent.operationId);
        final forkCompleter = _forkCompleters.remove(intent.operationId);
        final completer = voidCompleter ?? forkCompleter;
        if (completer == null) {
          _staleResultCount += 1;
        } else if (!completer.isCompleted) {
          completer.completeError(intent.error, intent.stackTrace);
        }
      default:
        break;
    }
  }

  OperationId _nextOperationId(String scope) {
    return _generators
        .putIfAbsent(scope, () => _generatorFactory(scope))
        .next();
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('ProjectThreadsSliceStore is closed');
    }
  }

  void _rebuildThreadMappings(ProjectThreadsSliceState initialState) {
    _projectPathByThreadId.clear();
    for (final entry in initialState.statesByProject.entries) {
      _registerStateThreadMappings(entry.key, entry.value);
    }
  }

  void _registerStateThreadMappings(
    String projectPath,
    ProjectThreadListState state,
  ) {
    for (final thread in state.threads) {
      registerThreadMapping(projectPath, thread.id);
    }
    final selectedThreadId = state.selectedThreadId;
    if (selectedThreadId != null) {
      // 当前编排会话可能尚未进入已加载分页，仍要登记映射。
      registerThreadMapping(projectPath, selectedThreadId);
    }
  }

  static AgentThreadSummary? _threadById(
    ProjectThreadListState state,
    String threadId,
  ) {
    for (final thread in state.threads) {
      if (thread.id == threadId) {
        return thread;
      }
    }
    return null;
  }

  static AgentThreadRuntimeStatus? _effectiveListRuntimeStatus(
    AgentConversationThreadSnapshot snapshot,
  ) {
    final status = snapshot.runtimeStatus;
    if (status == null) {
      return null;
    }
    if (!snapshot.isTurnRunning &&
        status == AgentThreadRuntimeStatus.active &&
        !snapshot.waitingOnApproval &&
        !snapshot.waitingOnUserInput) {
      return AgentThreadRuntimeStatus.idle;
    }
    return status;
  }
}

import 'package:zeta/src/app/agent_management_slice/workspace_agent_runtime_fact_source.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'dart:async';

import 'package:zeta/src/app/logging/app_logging.dart';
import 'package:zeta/src/app/conversation_workspace_slice/agent_conversation_workspace_store.dart';
import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/agent/application/agent_provider_settings_port.dart';
import 'package:zeta/src/ui/core/system_file_manager.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_runtime_controller.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_restore_result.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_operations.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_state_builder.dart';
import 'package:zeta/src/features/ide_session/domain/ide_session_state.dart';
import 'package:zeta/src/features/ide_session/domain/ide_workbench_layout_state.dart';
import 'package:zeta/src/features/ide_session/domain/recent_project_summary.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_operations.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_session_snapshot_codec.dart';
import 'package:zeta/src/features/project_threads/domain/project_thread_list_state.dart';
import 'package:zeta/src/features/workspace/application/workspace_file_index_controller.dart';
import 'package:zeta/src/features/workspace/application/workspace_file_corpus_port.dart';
import 'package:zeta/src/features/workspace/application/workspace_notifier.dart';
import 'package:zeta/src/features/workspace/application/workspace_restore_snapshot.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';
import 'package:zeta/src/features/workspace/domain/workspace_project.dart';

final _log = loggerFor('zeta.app.ide_shell_controller');

typedef IdeShellStatusReporter = void Function(String message);

/// IDE shell 的应用级协调器。
///
/// 它承接项目打开、文件树状态、会话恢复/保存以及 Agent thread 选择同步，
/// 让页面只负责三栏布局和 UI 事件转发。
class IdeShellController {
  static const String _bootstrapProjectPath = '';

  IdeShellController({
    required WorkspaceNotifier workspace,
    required WorkspaceFileCorpusPort workspaceFileCorpus,
    required WorkspaceFileIndexController workspaceFileIndexController,
    required this.ideSessionOperations,
    required this.projectThreadsController,
    required void Function() Function(void Function()) subscribeProjectThreads,
    required AgentConversationBindingManager bindingManager,
    required this.agentProviderGlobalRuntime,
    required AgentProviderSettingsPort agentProviderSettingsPort,
    required Future<AgentModelCatalogLoadResult> Function()
    activeModelCatalogLoader,
    this._projectLocationOpener = openPathInSystemFileManager,
    this._statusReporter,
    required this.agentProviderRuntimeRegistry,
    AgentFrameScheduler Function()? agentUiFrameSchedulerFactory,
    void Function(AgentTurnTerminalSignal)? onAgentTurnTerminal,
    void Function(AgentWorkspaceAttention)? onAgentAttention,
    AgentTurnContextStore? turnContextStore,
    this.agentUiTextCatalog = const FallbackAgentUiTextCatalog(),
    this.metrics = noopZetaMetricsPort,
    this.providerMetricLabel = ZetaMetricLabel.hashed,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    _workspace = workspace;
    _fileIndexController = workspaceFileIndexController;
    _fileIndexController.addListener(_handleFileIndexChanged);
    agentProviderController = agentProviderSettingsPort;
    _loadActiveModelCatalog = activeModelCatalogLoader;
    _workspaceFileCorpus = workspaceFileCorpus;
    agentConversationWorkspaceStore = AgentConversationWorkspaceStore(
      providerController: agentProviderController,
      bindingManager: bindingManager,
      workspaceFileCorpus: _workspaceFileCorpus,
      runtimeRegistry: agentProviderRuntimeRegistry,
      globalRuntime: agentProviderGlobalRuntime,
      onTurnTerminal: onAgentTurnTerminal,
      onAttention: onAgentAttention,
      onCreatedThread: _openCreatedThread,
      uiFrameSchedulerFactory: agentUiFrameSchedulerFactory,
      turnContextStore: turnContextStore,
      textCatalog: agentUiTextCatalog,
      metrics: metrics,
      providerMetricLabel: providerMetricLabel,
    );
    agentRuntimeFactSource = WorkspaceAgentRuntimeFactSource(
      agentConversationWorkspaceStore,
    )..start();
    _bootstrapAgentEntry = agentConversationWorkspaceStore.ensureDraftEntry(
      projectPath: _bootstrapProjectPath,
      providerId: agentProviderController.activeProviderId,
    );
    agentConversationWorkspaceStore.selectEntry(_bootstrapAgentEntry.entryId);
    agentConversationWorkspaceStore.addListener(
      _handleAgentConversationWorkspaceChanged,
    );
    agentConversationWorkspaceStore.addEntryChangedListener(
      _handleConversationWorkspaceEntryChanged,
    );
    _unsubscribeProjectThreads = subscribeProjectThreads(
      _handleProjectThreadsChanged,
    );
    _syncAllConversationWorkspaceEntries();
    unawaited(agentProviderController.loadSettings());
    unawaited(selectedAgentController.loadSettings());
    unawaited(_prewarmActiveModelCatalog());
    unawaited(_restoreSession());
    projectThreadsController.onActiveThreadCleared = _handleActiveThreadCleared;
  }

  Future<void> _prewarmActiveModelCatalog() async {
    try {
      await _loadActiveModelCatalog();
    } catch (error) {
      _log.t(
        'Could not prewarm active Agent model catalog (${error.runtimeType})',
      );
    }
  }

  final ProjectLocationOpener _projectLocationOpener;
  final IdeShellStatusReporter? _statusReporter;
  final IdeSessionSliceOperations ideSessionOperations;
  final DateTime Function() _now;

  late final AgentProviderRuntimeRegistry agentProviderRuntimeRegistry;
  late final AgentProviderGlobalRuntime agentProviderGlobalRuntime;
  late final WorkspaceNotifier _workspace;
  late final WorkspaceFileIndexController _fileIndexController;
  late final WorkspaceFileCorpusPort _workspaceFileCorpus;
  late final AgentProviderSettingsPort agentProviderController;
  late final Future<AgentModelCatalogLoadResult> Function()
  _loadActiveModelCatalog;
  late final AgentConversationWorkspaceStore agentConversationWorkspaceStore;
  late final WorkspaceAgentRuntimeFactSource agentRuntimeFactSource;
  late final AgentThreadWorkspaceEntry _bootstrapAgentEntry;
  late final ProjectThreadsOperations projectThreadsController;
  late final void Function() _unsubscribeProjectThreads;
  final AgentUiTextCatalog agentUiTextCatalog;

  /// app 组合层注入的脱敏指标端口；默认 no-op，探针只剩常量分支。
  final ZetaMetricsPort metrics;
  final ZetaMetricLabel Function(String providerId) providerMetricLabel;

  int _homeRefreshToken = 0;
  bool _isDisposed = false;

  List<AgentThreadWorkspaceEntry> get agentWorkspaceEntries =>
      agentConversationWorkspaceStore.entries;

  String? get selectedAgentWorkspaceEntryId =>
      agentConversationWorkspaceStore.selectedEntryId;

  /// 当前是否在活动项目的不带 Composer 首页。
  bool get isProjectHomeActive =>
      agentConversationWorkspaceStore.projectHomeActive &&
      activeProjectPath != null;

  AgentConversationRuntimeController get selectedAgentController =>
      agentConversationWorkspaceStore.selectedEntry?.controller ??
      _bootstrapAgentEntry.controller;

  /// Shell 自维护的 listener 列表（纯 Dart）。
  ///
  /// 不再继承 `ChangeNotifier`：Shell 是跨 feature 的 workflow 协调器，
  /// 不该因为要通知变化就变成一个 Flutter Widget 通知源（G6 / 目标架构 §12.5）。
  final List<void Function()> _stateListeners = <void Function()>[];

  void addListener(void Function() listener) {
    _stateListeners.add(listener);
  }

  void removeListener(void Function() listener) {
    _stateListeners.remove(listener);
  }

  WorkspaceState get workspaceState => _workspace.currentState;

  List<String> get projects => _workspace.currentState.projectPaths;

  /// 当前应用级 Workbench 布局偏好。
  IdeWorkbenchLayoutState get workbenchLayout =>
      ideSessionOperations.state.workbenchLayout;

  /// 提交整个合并左栏的显隐偏好。
  void setLeftSidebarVisible(bool visible) {
    _setWorkbenchLayout(workbenchLayout.copyWith(leftSidebarVisible: visible));
  }

  /// 提交左栏逻辑像素宽度；传空恢复 UI 默认宽度。
  void setLeftSidebarWidth(double? width) {
    _setWorkbenchLayout(workbenchLayout.copyWith(leftSidebarWidth: width));
  }

  /// 初始会话恢复已完成；此后无活动项目时可以稳定展示全局首页。
  bool get initialRestoreCompleted =>
      ideSessionOperations.state.initialRestoreCompleted;

  /// 等待启动会话恢复收敛，供冷启动通知定位避免与恢复竞态。
  Future<void> get initialRestoreDone =>
      ideSessionOperations.initialRestoreDone;

  /// 近期项目按最后访问时间排序；旧数据没有时间时保持原项目顺序。
  List<RecentProjectSummary> get recentProjects {
    final projectPaths = projects;
    final lastOpenedAtByPath =
        _workspace.currentState.projectLastOpenedAtByPath;
    final indexed = <({int index, RecentProjectSummary project})>[
      for (final (index, path) in projectPaths.indexed)
        (
          index: index,
          project: RecentProjectSummary(
            path: path,
            lastOpenedAt: lastOpenedAtByPath[path],
          ),
        ),
    ];
    indexed.sort((left, right) {
      final leftTime = left.project.lastOpenedAt;
      final rightTime = right.project.lastOpenedAt;
      if (leftTime != null && rightTime != null) {
        final byTime = rightTime.compareTo(leftTime);
        if (byTime != 0) {
          return byTime;
        }
      } else if (leftTime != null) {
        return -1;
      } else if (rightTime != null) {
        return 1;
      }
      return left.index.compareTo(right.index);
    });
    return List<RecentProjectSummary>.unmodifiable(
      indexed.map((entry) => entry.project),
    );
  }

  String? get activeProjectPath => _workspace.currentState.activeProjectPath;

  List<WorkspaceNode> get workspaceTree => _workspace.activeFileTree.tree;

  Set<String> get expandedDirectoryPaths =>
      _workspace.activeFileTree.expandedDirectoryPaths;

  String? get selectedTreePath => _workspace.activeFileTree.selectedTreePath;

  bool get isLoadingProject => _workspace.activeFileTree.isLoading;

  String? get _currentWorkspaceFilePath =>
      _workspace.activeFileTree.currentFilePath;

  ProjectThreadListState projectThreadStateFor(String projectPath) {
    return projectThreadsController.stateFor(projectPath);
  }

  /// 清除侧栏 thread 的「后台执行完毕」绿色提示。
  void dismissCompletedProjectThread(String projectPath, String threadId) {
    projectThreadsController.dismissCompletedThread(
      projectPath: projectPath,
      threadId: threadId,
    );
  }

  Future<void> openProject() async {
    _cancelPendingSessionRestore();
    try {
      final path = await _workspace.openProject();
      if (path == null || _isDisposed) {
        return;
      }
      await _onProjectActivated(path, activateThreads: true);
    } catch (error, stackTrace) {
      _log.w(
        'Could not open project folder',
        error: error,
        stackTrace: stackTrace,
      );
      _statusReporter?.call('Could not open folder: $error');
      _releaseInitialRestoreWait();
      if (!_isDisposed) {
        _notifyStateChanged();
      }
    }
  }

  /// 无活动项目时预热近期项目的会话列表，供左侧 Projects 栏直接取用。
  ///
  /// 预热的是 `projectThreadsController` 的缓存：项目卡片靠它显示运行中会话
  /// 的徽标，展开时也不用再等一次加载。一旦有活动项目就立即停下，把带宽让给
  /// 当前项目。
  Future<void> refreshRecentHomeData({int projectLimit = 5}) async {
    final token = ++_homeRefreshToken;
    final paths = recentProjects
        .take(projectLimit)
        .map((project) => project.path)
        .toList(growable: false);
    for (final path in paths) {
      if (_isDisposed ||
          token != _homeRefreshToken ||
          activeProjectPath != null) {
        return;
      }
      await projectThreadsController.loadInitial(path);
    }
  }

  Future<void> selectKnownProject(String path) async {
    _cancelPendingSessionRestore();
    if (path != activeProjectPath) {
      await _loadProject(path, activateThreads: false);
    }
    if (activeProjectPath == path) {
      _markProjectOpened(path);
    }
    await projectThreadsController.toggleProject(path);
    _requestSessionSave();
  }

  Future<void> loadMoreThreads(String projectPath) {
    return projectThreadsController.loadMore(projectPath);
  }

  Future<void> retryThreads(String projectPath) {
    return projectThreadsController.loadInitial(projectPath);
  }

  Future<void> renameProjectThread(
    String projectPath,
    String threadId,
    String name,
  ) {
    if (!_canMutateAgentHistory()) {
      return Future<void>.value();
    }
    return projectThreadsController.renameThread(
      projectPath: projectPath,
      threadId: threadId,
      name: name,
    );
  }

  Future<void> archiveProjectThread(
    String projectPath,
    AgentThreadSummary thread,
  ) {
    if (!_canMutateAgentHistory()) {
      return Future<void>.value();
    }
    return projectThreadsController.archiveThread(
      projectPath: projectPath,
      threadId: thread.id,
    );
  }

  Future<void> unarchiveProjectThread(
    String projectPath,
    AgentThreadSummary thread,
  ) {
    if (!_canMutateAgentHistory()) {
      return Future<void>.value();
    }
    return projectThreadsController.unarchiveThread(
      projectPath: projectPath,
      threadId: thread.id,
    );
  }

  Future<void> deleteProjectThread(
    String projectPath,
    AgentThreadSummary thread,
  ) {
    if (!_canMutateAgentHistory()) {
      return Future<void>.value();
    }
    return projectThreadsController.deleteThread(
      projectPath: projectPath,
      threadId: thread.id,
    );
  }

  Future<void> forkProjectThread(
    String projectPath,
    AgentThreadSummary thread,
  ) async {
    if (!_canMutateAgentHistory()) {
      return;
    }
    final sourceEntry = agentConversationWorkspaceStore.entryForThread(
      providerId: thread.providerId,
      threadId: thread.id,
    );
    final session = await projectThreadsController.forkThread(
      projectPath: projectPath,
      threadId: thread.id,
      permissionSnapshot: sourceEntry?.controller.permissionSnapshotForThread(
        thread.id,
      ),
    );
    if (session == null) {
      return;
    }
    await _openCreatedThread(
      session: session,
      context: AgentContext(projectPath: projectPath),
    );
  }

  Future<void> startNewThreadForProject(
    String projectPath, {
    required String providerId,
  }) async {
    if (!_canMutateAgentHistory(providerId: providerId)) {
      return;
    }
    _cancelPendingSessionRestore();

    // workspace-scoped provider 在切换时不能先于项目上下文初始化。
    if (projectPath != activeProjectPath) {
      await _loadProject(projectPath, activateThreads: false);
      if (activeProjectPath != projectPath) {
        return;
      }
    }
    _markProjectOpened(projectPath);
    try {
      await _selectWorkspaceDraftEntry(
        projectPath: projectPath,
        providerId: providerId,
      );
    } catch (_) {
      return;
    }
  }

  Future<void> openProjectInSystemFileManager(String projectPath) async {
    try {
      await _projectLocationOpener(projectPath);
    } catch (error, stackTrace) {
      _log.w(
        'Could not open project location in system file manager: $projectPath',
        error: error,
        stackTrace: stackTrace,
      );
      _statusReporter?.call('Could not open project location: $error');
    }
  }

  Future<void> removeProject(String path) async {
    final currentProjects = projects;
    final index = currentProjects.indexOf(path);
    if (index == -1) {
      return;
    }

    _cancelPendingSessionRestore();
    final wasActive = path == activeProjectPath;
    final nextProjectPath = wasActive && index + 1 < currentProjects.length
        ? currentProjects[index + 1]
        : null;

    _workspace.removeProject(path);
    _workspace.discardClosedProject(path);
    agentConversationWorkspaceStore.removeThreadMapping(path);
    projectThreadsController.retainProjects(projects);
    agentConversationWorkspaceStore.removeEntriesForProject(path);

    if (!wasActive) {
      _requestSessionSave();
      _notifyStateChanged();
      return;
    }

    if (nextProjectPath != null) {
      await _loadProject(nextProjectPath, activateThreads: false);
      if (activeProjectPath == nextProjectPath) {
        return;
      }
    }

    _clearActiveWorkspace();
  }

  Future<void> selectProjectThread(
    String projectPath,
    AgentThreadSummary thread,
  ) async {
    if (projectPath != activeProjectPath) {
      await _loadProject(projectPath, activateThreads: false);
    }
    if (activeProjectPath != projectPath) {
      return;
    }
    _markProjectOpened(projectPath);
    await _selectWorkspaceThreadEntry(
      projectPath: projectPath,
      thread: thread,
      persistSelection: true,
    );
  }

  /// 从系统通知恢复并选中对应的 Provider thread。
  Future<bool> activateAgentThread({
    required String providerId,
    required String threadId,
  }) async {
    AgentThreadSummary? target;
    String? projectPath;
    for (final path in projects) {
      for (final thread in projectThreadsController.stateFor(path).threads) {
        if (thread.providerId == providerId && thread.id == threadId) {
          target = thread;
          projectPath = path;
          break;
        }
      }
      if (target != null) {
        break;
      }
    }

    final openEntry = agentConversationWorkspaceStore.entryForThread(
      providerId: providerId,
      threadId: threadId,
    );
    if (target == null &&
        openEntry != null &&
        openEntry.projectPath.isNotEmpty) {
      final now = _now();
      projectPath = openEntry.projectPath;
      target = AgentThreadSummary(
        id: threadId,
        providerId: providerId,
        projectPath: projectPath,
        title: openEntry.controller.currentThreadTitle,
        preview: openEntry.controller.currentThreadTitle,
        createdAt: now,
        updatedAt: now,
        status:
            openEntry.threadSnapshot.runtimeStatus ??
            AgentThreadRuntimeStatus.idle,
      );
    }
    if (target == null || projectPath == null) {
      return false;
    }
    await selectProjectThread(projectPath, target);
    final selected = agentConversationWorkspaceStore.selectedEntry;
    return selected?.providerId == providerId && selected?.threadId == threadId;
  }

  void handleTreeExpansionChanged(String key, bool expanded) {
    final node = _findTreeNode(key);
    if (node == null || !node.isDirectory) {
      return;
    }
    _workspace.setDirectoryExpanded(key, expanded);
    _notifyStateChanged();
    _requestSessionSave();
  }

  void handleTreeNodeTap(String key) {
    final node = _findTreeNode(key);
    if (node == null) {
      return;
    }

    _workspace.selectTreeNode(key);
    if (node.isDirectory) {
      _notifyStateChanged();
      _requestSessionSave();
      return;
    }

    _syncProjectEntryContexts(activeProjectPath);
    _notifyStateChanged();
    _requestSessionSave();
  }

  void _cancelPendingSessionRestore() {
    ideSessionOperations.cancelPendingRestore();
  }

  void _releaseInitialRestoreWait() {
    ideSessionOperations.releaseInitialRestoreWait();
  }

  Future<void> saveNow() {
    final snapshot = _currentSessionState();
    return ideSessionOperations.saveNow(snapshot);
  }

  /// 外部 application 切片已经提交会话字段后，请求保存完整 Shell 快照。
  void requestSessionSave() => _requestSessionSave();

  Future<void> _loadProject(String path, {bool activateThreads = true}) async {
    _homeRefreshToken += 1;
    _log.i('Opening project folder: $path');
    _notifyStateChanged();

    try {
      final loaded = await _workspace.openOrActivate(path);
      if (!loaded || _isDisposed || activeProjectPath != path) {
        return;
      }

      await _onProjectActivated(path, activateThreads: activateThreads);
    } catch (error, stackTrace) {
      _log.w(
        'Could not open project folder: $path',
        error: error,
        stackTrace: stackTrace,
      );
      _statusReporter?.call('Could not open folder: $error');
    } finally {
      _releaseInitialRestoreWait();
      if (!_isDisposed) {
        _notifyStateChanged();
      }
    }
  }

  Future<void> _restoreSession() async {
    try {
      final result = await ideSessionOperations.restore();
      if (_isDisposed) {
        return;
      }

      switch (result.status) {
        case IdeSessionRestoreStatus.cancelled:
        case IdeSessionRestoreStatus.empty:
          return;
        case IdeSessionRestoreStatus.failed:
          _workspace.clearCurrentFile();
          await _syncSelectedAgentWorkspace();
          _notifyStateChanged();
          if (result.shouldRequestSave) {
            _requestSessionSave();
          }
          return;
        case IdeSessionRestoreStatus.restored:
          break;
      }

      final session = result.snapshot;
      if (session == null) {
        return;
      }

      await _workspace.restore(
        WorkspaceRestoreSnapshot(
          projects: session.projectPaths,
          activeProjectPath: session.activeProjectPath,
          currentFilePath: session.currentFilePath,
          expandedDirectoryPaths: session.expandedDirectoryPaths,
          selectedTreePath: session.selectedTreeKey,
          projectLastOpenedAtByPath: session.projectLastOpenedAtByPath,
        ),
      );
      agentConversationWorkspaceStore.restoreThreadMappings(
        session.agentThreadIdsByProject,
      );
      ideSessionOperations.setWorkbenchLayout(session.workbenchLayout);

      projectThreadsController.restoreSession(
        projectPaths: session.projectPaths,
        activeProjectPath: session.activeProjectPath,
        snapshot: projectThreadsSessionSnapshotFromIdeSessionState(session),
      );
      for (final entry
          in agentConversationWorkspaceStore.threadIdsByProject.entries
              .toList()) {
        final thread = _threadSummaryFor(entry.key, entry.value);
        if (thread == null) {
          // provider 归属只存在于完整摘要；缺失时不能猜测 active provider。
          _log.w(
            'Discarding restored thread ${entry.value} without provider ownership',
          );
          agentConversationWorkspaceStore.removeThreadMapping(entry.key);
          projectThreadsController.clearSelectedThread(entry.key);
          continue;
        }
        projectThreadsController.registerThreadMapping(entry.key, thread.id);
      }
      if (activeProjectPath != null) {
        // 启动只恢复项目上下文和会话列表，避免自动进入上次打开的会话详情。
        _enterProjectHome(refreshThreads: true);
      } else {
        await _syncSelectedAgentWorkspace();
      }
      _log.i(
        'Restored IDE session with ${session.projectPaths.length} projects',
      );
      if (result.shouldRequestSave) {
        _requestSessionSave();
      }
      _notifyStateChanged();
    } finally {
      _releaseInitialRestoreWait();
      if (!_isDisposed) {
        ideSessionOperations.completeInitialRestore();
        _notifyStateChanged();
      }
    }
  }

  void _requestSessionSave() {
    final snapshot = _currentSessionState();
    ideSessionOperations.requestSave(snapshot);
  }

  void _clearActiveWorkspace() {
    _homeRefreshToken += 1;
    _workspace.clearActiveProject();
    agentConversationWorkspaceStore.selectEntry(_bootstrapAgentEntry.entryId);
    _bootstrapAgentEntry.controller.updateContext(
      projectPath: null,
      contextFilePath: null,
    );
    _requestSessionSave();
    _notifyStateChanged();
  }

  IdeSessionState _currentSessionState() {
    final selectedAgentController = this.selectedAgentController;
    final workspaceState = _workspace.currentState;
    return buildIdeSessionState(
      projectPaths: projects,
      activeProjectPath: activeProjectPath,
      currentFilePath: _currentWorkspaceFilePath,
      expandedDirectoryPaths: _currentExpandedDirectoryPaths(),
      selectedTreeKey: selectedTreePath,
      activeAgentProviderId: selectedAgentController.activeProviderId,
      agentThreadIdsByProject:
          agentConversationWorkspaceStore.threadIdsByProject,
      projectLastOpenedAtByPath: workspaceState.projectLastOpenedAtByPath,
      projectThreadsSessionSnapshot: projectThreadsController.sessionSnapshot,
      currentProjectPath: activeProjectPath,
      currentSessionId: isProjectHomeActive
          ? null
          : selectedAgentController.sessionId,
      projectHomeActive: isProjectHomeActive,
      workbenchLayout: workbenchLayout,
    );
  }

  void _setWorkbenchLayout(IdeWorkbenchLayoutState next) {
    if (next == workbenchLayout) {
      return;
    }
    ideSessionOperations.setWorkbenchLayout(next);
    _notifyStateChanged();
    _requestSessionSave();
  }

  Set<String> _currentExpandedDirectoryPaths() {
    return expandedDirectoryPaths;
  }

  void _enterProjectHome({required bool refreshThreads}) {
    final projectPath = activeProjectPath;
    if (projectPath == null) {
      return;
    }

    agentConversationWorkspaceStore.enterProjectHome();
    projectThreadsController.clearAllSelectedThreads();
    if (refreshThreads) {
      // 首页与侧栏共享未归档首屏；保留缓存并在后台刷新最新五条。
      unawaited(projectThreadsController.loadInitial(projectPath));
    }
  }

  void _markProjectOpened(String path) {
    _workspace.markProjectOpened(path, _now());
  }

  WorkspaceNode? _findTreeNode(String path) {
    return WorkspaceNode.findByPath(workspaceTree, path);
  }

  Future<void> _syncSelectedAgentWorkspace() async {
    final projectPath = activeProjectPath;
    if (projectPath == null) {
      agentConversationWorkspaceStore.selectEntry(_bootstrapAgentEntry.entryId);
      _bootstrapAgentEntry.applyDraftIdentity(
        projectPath: _bootstrapProjectPath,
        providerId: _bootstrapAgentEntry.providerId,
      );
      _bootstrapAgentEntry.controller.updateContext(
        projectPath: null,
        contextFilePath: null,
      );
      return;
    }

    var restoredSessionId =
        agentConversationWorkspaceStore.threadIdsByProject[projectPath];
    var restoredThread = restoredSessionId == null
        ? null
        : _threadSummaryFor(projectPath, restoredSessionId);
    if (restoredSessionId != null && restoredThread == null) {
      _log.w('Discarding thread $restoredSessionId without provider ownership');
      agentConversationWorkspaceStore.removeThreadMapping(projectPath);
      projectThreadsController.clearSelectedThread(projectPath);
      restoredSessionId = null;
    }
    if (restoredThread != null) {
      projectThreadsController.registerThreadMapping(
        projectPath,
        restoredThread.id,
      );
      await _selectWorkspaceThreadEntry(
        projectPath: projectPath,
        thread: restoredThread,
        persistSelection: false,
      );
      return;
    }

    try {
      await _selectWorkspaceDraftEntry(
        projectPath: projectPath,
        providerId: _preferredDraftProviderId(),
        persistSelection: false,
      );
    } catch (error, stackTrace) {
      _log.w(
        'Could not restore draft workspace for $projectPath',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<AgentThreadWorkspaceEntry> _selectWorkspaceDraftEntry({
    required String projectPath,
    required String providerId,
    bool persistSelection = true,
  }) async {
    final entry = agentConversationWorkspaceStore.ensureDraftEntry(
      projectPath: projectPath,
      providerId: providerId,
    );
    entry.applyDraftIdentity(projectPath: projectPath, providerId: providerId);
    agentConversationWorkspaceStore.selectEntry(entry.entryId);
    await entry.controller.loadSettings();
    if (entry.controller.activeProviderId != providerId) {
      try {
        await entry.controller.switchActiveProvider(providerId);
      } catch (error, stackTrace) {
        _log.w(
          'Could not select provider $providerId for project draft $projectPath',
          error: error,
          stackTrace: stackTrace,
        );
        _statusReporter?.call('Could not select Agent provider: $error');
        rethrow;
      }
    }
    entry.controller.updateContext(
      projectPath: projectPath,
      contextFilePath: _currentWorkspaceFilePath,
    );
    projectThreadsController.clearSelectedThread(projectPath);
    agentConversationWorkspaceStore.removeThreadMapping(projectPath);
    unawaited(entry.controller.loadModels());
    if (persistSelection) {
      _requestSessionSave();
      _notifyStateChanged();
    }
    return entry;
  }

  Future<AgentThreadWorkspaceEntry> _selectWorkspaceThreadEntry({
    required String projectPath,
    required AgentThreadSummary thread,
    bool persistSelection = true,
  }) async {
    final existingEntry = agentConversationWorkspaceStore.entryForThread(
      providerId: thread.providerId,
      threadId: thread.id,
    );
    final entry = agentConversationWorkspaceStore.ensureThreadEntry(
      projectPath: projectPath,
      thread: thread,
    );
    agentConversationWorkspaceStore.selectEntry(entry.entryId);
    entry.controller.updateContext(
      projectPath: projectPath,
      contextFilePath: _currentWorkspaceFilePath,
    );
    projectThreadsController.registerThreadMapping(projectPath, thread.id);
    projectThreadsController.selectThread(projectPath, thread);
    agentConversationWorkspaceStore.setThreadMapping(projectPath, thread.id);
    if (existingEntry == null ||
        entry.controller.threadOpenPhase ==
            AgentThreadOpenPhase.loadingHistory) {
      await entry.controller.initialization;
    } else if (entry.controller.threadOpenPhase ==
        AgentThreadOpenPhase.openFailed) {
      await entry.controller.retryOpenThread();
    } else {
      unawaited(entry.controller.loadModels());
    }
    _syncSelectedThreadTitleFromList();
    if (persistSelection) {
      _requestSessionSave();
      _notifyStateChanged();
    }
    return entry;
  }

  void _syncProjectEntryContexts(String? projectPath) {
    if (projectPath == null) {
      return;
    }
    for (final entry in agentConversationWorkspaceStore.entriesForProject(
      projectPath,
    )) {
      entry.controller.updateContext(
        projectPath: projectPath,
        contextFilePath: _currentWorkspaceFilePath,
      );
    }
  }

  String _preferredDraftProviderId() {
    final preferred = selectedAgentController.threadProviderId;
    if (agentProviderController.isProviderEnabled(preferred)) {
      return preferred;
    }
    return agentProviderController.activeProviderId;
  }

  void _handleAgentConversationWorkspaceChanged() {
    if (_isDisposed) {
      return;
    }
    _requestSessionSave();
    _notifyStateChanged();
  }

  void _handleConversationWorkspaceEntryChanged(
    AgentThreadWorkspaceEntry entry,
  ) {
    if (_isDisposed) {
      return;
    }
    _syncWorkspaceEntryState(entry);
    if (entry.entryId == selectedAgentWorkspaceEntryId) {
      _notifyStateChanged();
    }
    _requestSessionSave();
  }

  void _syncAllConversationWorkspaceEntries() {
    for (final entry in agentConversationWorkspaceStore.entries) {
      _syncWorkspaceEntryState(entry);
    }
  }

  void _syncWorkspaceEntryState(AgentThreadWorkspaceEntry entry) {
    final projectPath = entry.projectPath;
    if (projectPath.isEmpty) {
      return;
    }

    final snapshot = entry.threadSnapshot;
    final sessionId = snapshot.sessionId;
    final state = projectThreadsController.stateFor(projectPath);
    final currentSession = entry.controller.currentSession;
    final hasProviderSummary =
        sessionId == null ||
        state.threads.any(
          (thread) =>
              thread.id == sessionId &&
              thread.providerId == snapshot.providerId,
        );
    if (currentSession != null && !hasProviderSummary) {
      projectThreadsController.registerSession(
        projectPath,
        currentSession,
        preview: _provisionalThreadPreview(entry.controller),
        markRunning: snapshot.isTurnRunning,
      );
    }
    if (sessionId != null) {
      projectThreadsController.registerThreadMapping(projectPath, sessionId);
      projectThreadsController.syncRuntimeSnapshot(
        projectPath: projectPath,
        snapshot: snapshot,
      );
    }

    if (entry.entryId != selectedAgentWorkspaceEntryId ||
        projectPath != activeProjectPath) {
      return;
    }

    if (sessionId == null) {
      projectThreadsController.clearSelectedThread(projectPath);
      agentConversationWorkspaceStore.removeThreadMapping(projectPath);
      return;
    }

    agentConversationWorkspaceStore.setThreadMapping(projectPath, sessionId);
    projectThreadsController.selectThreadId(projectPath, sessionId);
    _syncSelectedThreadTitleFromList();
  }

  Future<void> _openCreatedThread({
    required AgentSession session,
    required AgentContext context,
    String? initialMessage,
  }) async {
    final projectPath = context.projectPath?.trim();
    if (projectPath == null || projectPath.isEmpty) {
      throw StateError('Created thread ${session.id} has no project context');
    }
    final trimmedMessage = initialMessage?.trim();
    final thread = projectThreadsController.registerSession(
      projectPath,
      session,
      preview: trimmedMessage == null || trimmedMessage.isEmpty
          ? session.title
          : trimmedMessage,
    );
    await selectProjectThread(projectPath, thread);

    final entry = agentConversationWorkspaceStore.selectedEntry;
    if (entry?.providerId != session.providerId ||
        entry?.threadId != session.id ||
        entry?.controller.threadOpenPhase != AgentThreadOpenPhase.idle) {
      throw StateError('Could not open created thread ${session.id}');
    }
    entry!.controller.updateContext(
      projectPath: projectPath,
      contextFilePath: context.filePath,
    );
    if (trimmedMessage != null && trimmedMessage.isNotEmpty) {
      await entry.controller.sendMessage(trimmedMessage);
    }
  }

  /// 从当前时间线取首条用户消息，作为新 thread 的临时列表 preview。
  String? _provisionalThreadPreview(
    AgentConversationRuntimeController controller,
  ) {
    for (final message in controller.messages) {
      if (message.role != AgentMessageRole.user) {
        continue;
      }
      final text = message.text.trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
    return null;
  }

  AgentThreadSummary? _threadSummaryFor(String projectPath, String threadId) {
    for (final thread
        in projectThreadsController.stateFor(projectPath).threads) {
      if (thread.id == threadId) {
        return thread;
      }
    }
    return null;
  }

  void _handleProjectThreadsChanged() {
    // 列表标题可能因 thread/name/updated 或刷新而变化；详情头栏需同步。
    _syncSelectedThreadTitleFromList();
    _requestSessionSave();
  }

  /// 将当前会话在列表中的**正式**标题同步到 Agent 详情头栏。
  ///
  /// 仅使用 summary.title（generated_title / 手动重命名），不用 preview，
  /// 也不用占位「New thread」。这样刷新列表拿到正式标题后，停留在详情也能
  /// 更新；又不会把首条用户消息临时标题冲回占位文案。
  void _syncSelectedThreadTitleFromList() {
    final projectPath = activeProjectPath;
    final controller = selectedAgentController;
    final sessionId = controller.sessionId;
    if (projectPath == null || sessionId == null) {
      return;
    }
    final summary = _threadSummaryFor(projectPath, sessionId);
    if (summary == null) {
      return;
    }
    final title = summary.title?.trim();
    if (isAgentThreadTitlePlaceholder(title)) {
      return;
    }
    controller.syncThreadTitleIfCurrent(sessionId, title!);
  }

  void _handleActiveThreadCleared(String projectPath, String threadId) {
    if (agentConversationWorkspaceStore.threadIdsByProject[projectPath] ==
        threadId) {
      agentConversationWorkspaceStore.removeThreadMapping(projectPath);
    }
    final removedEntries = <String>[
      for (final entry in agentConversationWorkspaceStore.entriesForProject(
        projectPath,
      ))
        if (entry.threadId == threadId) entry.entryId,
    ];
    final removedSelected = removedEntries.contains(
      selectedAgentWorkspaceEntryId,
    );
    for (final entryId in removedEntries) {
      agentConversationWorkspaceStore.removeEntry(entryId);
    }
    if (removedSelected && projectPath == activeProjectPath) {
      _enterProjectHome(refreshThreads: true);
    }
    _requestSessionSave();
    _notifyStateChanged();
  }

  bool _canMutateAgentHistory({String? providerId}) {
    final targetProviderId =
        providerId ?? agentProviderController.activeProviderConfig.id;
    if (agentProviderController.isProviderEnabled(targetProviderId)) {
      return true;
    }
    final providerName =
        agentProviderController
            .providerConfigById(targetProviderId)
            ?.displayName ??
        targetProviderId;
    _statusReporter?.call(agentUiTextCatalog.threadDisabled(providerName));
    return false;
  }

  void _notifyStateChanged() {
    if (!_isDisposed) {
      // 复制一份再遍历：listener 内部可能同步增删订阅。
      for (final listener in List<void Function()>.of(_stateListeners)) {
        listener();
      }
    }
  }

  /// 后台文件语料就绪/失效时刷新 shell 状态，并让 @mention 等监听者拿到新语料。
  void _handleFileIndexChanged() {
    _notifyStateChanged();
  }

  Future<void> _onProjectActivated(
    String path, {
    required bool activateThreads,
  }) async {
    projectThreadsController.retainProjects(projects);
    if (activateThreads) {
      projectThreadsController.activateProject(path);
    }
    _enterProjectHome(refreshThreads: true);
    _requestSessionSave();
    _log.i('Opened project folder: $path');
    _notifyStateChanged();
  }

  void dispose() {
    if (_isDisposed) {
      return;
    }
    unawaited(saveNow());
    _isDisposed = true;
    _homeRefreshToken += 1;
    agentConversationWorkspaceStore.removeListener(
      _handleAgentConversationWorkspaceChanged,
    );
    agentConversationWorkspaceStore.removeEntryChangedListener(
      _handleConversationWorkspaceEntryChanged,
    );
    _unsubscribeProjectThreads();
    projectThreadsController.onActiveThreadCleared = null;
    agentRuntimeFactSource.close();
    agentConversationWorkspaceStore.dispose();
    // 在 workspace 条目释放后再拆索引监听，避免 popover 仍挂在 listenable 上。
    _fileIndexController.removeListener(_handleFileIndexChanged);
    _stateListeners.clear();
  }
}

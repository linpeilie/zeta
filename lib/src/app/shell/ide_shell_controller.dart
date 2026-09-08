import 'package:zeta/src/features/agent/application/agent_command_outcome.dart';
import 'package:zeta/src/app/conversation_workspace_slice/conversation_slice_lifetime_coordinator.dart';
import 'package:zeta/src/app/conversation_workspace_slice/agent_conversation_entry_resources.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'dart:async';

import 'package:zeta/src/app/logging/app_logging.dart';
import 'package:zeta/src/app/conversation_workspace_slice/agent_conversation_workspace_notifier.dart';
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
import 'package:zeta/src/app/router/app_route_location.dart';
import 'package:zeta/src/app/router/project_id_mapping.dart';
import 'package:zeta/src/app/router/route_reconcile_host.dart';
import 'package:zeta/src/features/workspace/domain/workspace_project.dart';

final _log = loggerFor('zeta.app.ide_shell_controller');

typedef IdeShellStatusReporter = void Function(String message);

/// IDE shell 的应用级协调器。
///
/// 它承接项目打开、文件树状态、会话恢复/保存以及 Agent thread 选择同步，
/// 让页面只负责三栏布局和 UI 事件转发。
class IdeShellController implements RouteReconcileHost {
  static const String _bootstrapProjectPath = '';

  IdeShellController({
    required WorkspaceNotifier workspace,
    required WorkspaceFileCorpusPort workspaceFileCorpus,
    required WorkspaceFileIndexController workspaceFileIndexController,
    required this.ideSessionOperations,
    required this.projectThreadsController,
    required this.subscribeProjectThreads,
    required this.agentConversationWorkspace,
    required this.lifetimes,
    required this.subscribeConversationWorkspace,
    required this.agentProviderGlobalRuntime,
    required AgentProviderSettingsPort agentProviderSettingsPort,
    required Future<AgentModelCatalogLoadResult> Function()
    activeModelCatalogLoader,
    this._projectLocationOpener = openPathInSystemFileManager,
    this._statusReporter,
    required this.agentProviderRuntimeRegistry,
    this.agentUiTextCatalog = const FallbackAgentUiTextCatalog(),
    this.metrics = noopZetaMetricsPort,
    this.providerMetricLabel = ZetaMetricLabel.hashed,
    this.navigationPort,
    this.projectIdMapping,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    _workspace = workspace;
    _fileIndexController = workspaceFileIndexController;
    agentProviderController = agentProviderSettingsPort;
    _loadActiveModelCatalog = activeModelCatalogLoader;
  }

  final ConversationSliceLifetimeCoordinator lifetimes;
  final void Function() Function(void Function())
  subscribeConversationWorkspace;
  final void Function() Function(void Function()) subscribeProjectThreads;
  void Function()? _unsubscribeConversationWorkspace;
  bool _started = false;
  late final AgentConversationEntryCallbacks entryCallbacks =
      AgentConversationEntryCallbacks(
        onCreatedThread: _openCreatedThread,
        ensureSlice: lifetimes.ensureSlice,
        onProjectionUnobserved: lifetimes.onProjectionUnobserved,
        onEntryChanged: _handleConversationWorkspaceEntryChanged,
      );

  void start() {
    if (_started || _isDisposed) return;
    _started = true;
    _fileIndexController.addListener(_handleFileIndexChanged);
    _bootstrapAgentEntry = agentConversationWorkspace.ensureDraftEntry(
      callbacks: entryCallbacks,
      projectPath: _bootstrapProjectPath,
      providerId: agentProviderController.activeProviderId,
    );
    agentConversationWorkspace.selectEntry(_bootstrapAgentEntry.entryId);
    _unsubscribeConversationWorkspace = subscribeConversationWorkspace(
      _handleAgentConversationWorkspaceChanged,
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
  late final AgentProviderSettingsPort agentProviderController;
  late final Future<AgentModelCatalogLoadResult> Function()
  _loadActiveModelCatalog;
  late final AgentConversationWorkspaceNotifier agentConversationWorkspace;
  late final AgentConversationEntryResources _bootstrapAgentEntry;
  late final ProjectThreadsOperations projectThreadsController;
  void Function()? _unsubscribeProjectThreads;
  final AgentUiTextCatalog agentUiTextCatalog;

  /// app 组合层注入的脱敏指标端口；默认 no-op，探针只剩常量分支。
  final ZetaMetricsPort metrics;
  final ZetaMetricLabel Function(String providerId) providerMetricLabel;
  final AppNavigationPort? navigationPort;
  final ProjectIdMapping? projectIdMapping;

  int _homeRefreshToken = 0;
  bool _isDisposed = false;

  List<AgentConversationEntryResources> get agentWorkspaceEntries =>
      agentConversationWorkspace.entries;

  String? get selectedAgentWorkspaceEntryId =>
      agentConversationWorkspace.selectedEntryId;

  /// 当前是否在活动项目的不带 Composer 首页。
  bool get isProjectHomeActive =>
      agentConversationWorkspace.projectHomeActive && activeProjectPath != null;

  AgentConversationRuntimeController get selectedAgentController =>
      agentConversationWorkspace.selectedEntry?.controller ??
      _bootstrapAgentEntry.controller;

  /// Shell 自维护的 listener 列表（纯 Dart）。
  ///
  /// 不再继承 `ChangeNotifier`：Shell 是跨 feature 的 workflow 协调器，
  /// 不该因为要通知变化就变成一个 Flutter Widget 通知源（G6 / 目标架构 §12.5）。
  final List<void Function()> _stateListeners = <void Function()>[];

  void addListener(void Function() listener) {
    if (_isDisposed) return;
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
    if (_isDisposed) return;
    _setWorkbenchLayout(workbenchLayout.copyWith(leftSidebarVisible: visible));
  }

  /// 提交左栏逻辑像素宽度；传空恢复 UI 默认宽度。
  void setLeftSidebarWidth(double? width) {
    if (_isDisposed) return;
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
    if (_isDisposed) return;
    projectThreadsController.dismissCompletedThread(
      projectPath: projectPath,
      threadId: threadId,
    );
  }

  Future<void> openProject() async {
    if (_isDisposed) return;
    _cancelPendingSessionRestore();
    try {
      final path = await _workspace.openProject();
      if (path == null || _isDisposed) {
        return;
      }
      // 用户已接管启动恢复：解锁 redirect，否则会一直停在 `/` 转圈。
      ideSessionOperations.completeInitialRestore();
      await _onProjectActivated(path, activateThreads: true);
      if (_isDisposed) return;
      final mapping = projectIdMapping;
      if (mapping != null) {
        mapping.syncProjects(projects);
        final projectId = mapping.idForPath(path);
        if (projectId != null) {
          navigationPort?.go(ProjectHomeLocation(projectId));
        }
      }
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
    if (_isDisposed) return;
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
    if (_isDisposed) return;
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
    if (_isDisposed) return Future<void>.value();
    return projectThreadsController.loadMore(projectPath);
  }

  Future<void> retryThreads(String projectPath) {
    if (_isDisposed) return Future<void>.value();
    return projectThreadsController.loadInitial(projectPath);
  }

  Future<void> renameProjectThread(
    String projectPath,
    String threadId,
    String name,
  ) {
    if (_isDisposed) return Future<void>.value();
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
    if (_isDisposed) return Future<void>.value();
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
    if (_isDisposed) return Future<void>.value();
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
    if (_isDisposed) return Future<void>.value();
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
    if (_isDisposed) return;
    if (!_canMutateAgentHistory()) {
      return;
    }
    final sourceEntry = agentConversationWorkspace.entryForThread(
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

  @override
  Future<void> startNewThreadForProject(
    String projectPath, {
    required String providerId,
  }) async {
    if (_isDisposed) return;
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

  @override
  Future<void> openProjectHomeFromRoute(String projectPath) async {
    if (_isDisposed) return;
    if (projectPath != activeProjectPath) {
      await _loadProject(projectPath, activateThreads: false);
    }
    if (_isDisposed || activeProjectPath != projectPath) return;
    _markProjectOpened(projectPath);
    final needRefresh = !projectThreadsController
        .stateFor(projectPath)
        .hasLoaded;
    _enterProjectHome(refreshThreads: needRefresh);
  }

  /// 由 (providerId 可选提示, threadId) 解析打开目标：先列表，后已开 entry 合成。
  ({String projectPath, AgentThreadSummary thread})? resolveThreadTarget({
    required String threadId,
    String? providerIdHint,
    String? projectPathHint,
  }) {
    final paths = projectPathHint != null
        ? <String>[projectPathHint]
        : projects;
    for (final path in paths) {
      for (final thread in projectThreadsController.stateFor(path).threads) {
        if (thread.id == threadId &&
            (providerIdHint == null || thread.providerId == providerIdHint)) {
          return (projectPath: path, thread: thread);
        }
      }
    }
    for (final entry in agentConversationWorkspace.entries) {
      if (entry.threadId == threadId &&
          (providerIdHint == null || entry.providerId == providerIdHint) &&
          entry.projectPath.isNotEmpty) {
        final now = _now();
        return (
          projectPath: entry.projectPath,
          thread: AgentThreadSummary(
            id: threadId,
            providerId: entry.providerId,
            projectPath: entry.projectPath,
            title: entry.controller.currentThreadTitle,
            preview: entry.controller.currentThreadTitle,
            createdAt: now,
            updatedAt: now,
            status:
                entry.threadSnapshot.runtimeStatus ??
                AgentThreadRuntimeStatus.idle,
          ),
        );
      }
    }
    return null;
  }

  @override
  Future<bool> openThreadFromRoute(String projectPath, String threadId) async {
    if (_isDisposed) return false;
    final target = resolveThreadTarget(
      threadId: threadId,
      projectPathHint: projectPath,
    );
    if (target == null) return false;
    await selectProjectThread(target.projectPath, target.thread);
    if (_isDisposed) return false;
    return agentConversationWorkspace.selectedEntry?.threadId == threadId;
  }

  Future<void> openProjectInSystemFileManager(String projectPath) async {
    if (_isDisposed) return;
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
    if (_isDisposed) return;
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
    agentConversationWorkspace.removeThreadMapping(path);
    projectThreadsController.retainProjects(projects);
    await Future.wait<void>([
      for (final entry
          in agentConversationWorkspace.entriesForProject(path).toList())
        lifetimes.closeEntry(entry.ownerKey),
    ], eagerError: false);

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
    if (_isDisposed) return;
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
    final target = resolveThreadTarget(
      threadId: threadId,
      providerIdHint: providerId,
    );
    if (target == null) {
      return false;
    }
    await selectProjectThread(target.projectPath, target.thread);
    final selected = agentConversationWorkspace.selectedEntry;
    return selected?.providerId == providerId && selected?.threadId == threadId;
  }

  void handleTreeExpansionChanged(String key, bool expanded) {
    if (_isDisposed) return;
    final node = _findTreeNode(key);
    if (node == null || !node.isDirectory) {
      return;
    }
    _workspace.setDirectoryExpanded(key, expanded);
    _notifyStateChanged();
    _requestSessionSave();
  }

  void handleTreeNodeTap(String key) {
    if (_isDisposed) return;
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
    if (_isDisposed) return;
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
      if (_isDisposed) return;
      agentConversationWorkspace.restoreThreadMappings(
        session.agentThreadIdsByProject,
      );
      ideSessionOperations.setWorkbenchLayout(session.workbenchLayout);

      projectThreadsController.restoreSession(
        projectPaths: session.projectPaths,
        activeProjectPath: session.activeProjectPath,
        snapshot: projectThreadsSessionSnapshotFromIdeSessionState(session),
      );
      for (final entry
          in agentConversationWorkspace.threadIdsByProject.entries.toList()) {
        final thread = _threadSummaryFor(entry.key, entry.value);
        if (thread == null) {
          // provider 归属只存在于完整摘要；缺失时不能猜测 active provider。
          _log.w(
            'Discarding restored thread ${entry.value} without provider ownership',
          );
          agentConversationWorkspace.removeThreadMapping(entry.key);
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
    agentConversationWorkspace.selectEntry(_bootstrapAgentEntry.entryId);
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
      agentThreadIdsByProject: agentConversationWorkspace.threadIdsByProject,
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

    agentConversationWorkspace.enterProjectHome();
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
      agentConversationWorkspace.selectEntry(_bootstrapAgentEntry.entryId);
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
        agentConversationWorkspace.threadIdsByProject[projectPath];
    var restoredThread = restoredSessionId == null
        ? null
        : _threadSummaryFor(projectPath, restoredSessionId);
    if (restoredSessionId != null && restoredThread == null) {
      _log.w('Discarding thread $restoredSessionId without provider ownership');
      agentConversationWorkspace.removeThreadMapping(projectPath);
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

  Future<AgentConversationEntryResources> _selectWorkspaceDraftEntry({
    required String projectPath,
    required String providerId,
    bool persistSelection = true,
  }) async {
    final entry = agentConversationWorkspace.ensureDraftEntry(
      callbacks: entryCallbacks,
      projectPath: projectPath,
      providerId: providerId,
    );
    entry.applyDraftIdentity(projectPath: projectPath, providerId: providerId);
    agentConversationWorkspace.selectEntry(entry.entryId);
    await entry.controller.loadSettings();
    if (_isDisposed || entry.closing) return entry;
    if (entry.controller.activeProviderId != providerId) {
      try {
        await lifetimes
            .actionsForOwner(entry.ownerKey)
            .switchActiveProvider(providerId);
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
    agentConversationWorkspace.removeThreadMapping(projectPath);
    // Entry bootstrap only; user catalog requests go through Actions.
    unawaited(entry.controller.loadModels());
    if (persistSelection) {
      _requestSessionSave();
      _notifyStateChanged();
    }
    return entry;
  }

  Future<AgentConversationEntryResources> _selectWorkspaceThreadEntry({
    required String projectPath,
    required AgentThreadSummary thread,
    bool persistSelection = true,
  }) async {
    final existingEntry = agentConversationWorkspace.entryForThread(
      providerId: thread.providerId,
      threadId: thread.id,
    );
    final entry = agentConversationWorkspace.ensureThreadEntry(
      callbacks: entryCallbacks,
      projectPath: projectPath,
      thread: thread,
    );
    agentConversationWorkspace.selectEntry(entry.entryId);
    entry.controller.updateContext(
      projectPath: projectPath,
      contextFilePath: _currentWorkspaceFilePath,
    );
    projectThreadsController.registerThreadMapping(projectPath, thread.id);
    projectThreadsController.selectThread(projectPath, thread);
    agentConversationWorkspace.setThreadMapping(projectPath, thread.id);
    if (existingEntry == null ||
        entry.controller.threadOpenPhase ==
            AgentThreadOpenPhase.loadingHistory) {
      await entry.controller.initialization;
    } else if (entry.controller.threadOpenPhase ==
        AgentThreadOpenPhase.openFailed) {
      await lifetimes.actionsForOwner(entry.ownerKey).retryOpenThread();
    } else {
      // Entry bootstrap only; user catalog requests go through Actions.
      unawaited(entry.controller.loadModels());
    }
    if (_isDisposed || entry.closing) return entry;
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
    for (final entry in agentConversationWorkspace.entriesForProject(
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
    AgentConversationEntryResources entry,
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
    for (final entry in agentConversationWorkspace.entries) {
      _syncWorkspaceEntryState(entry);
    }
  }

  void _syncWorkspaceEntryState(AgentConversationEntryResources entry) {
    final projectPath = entry.projectPath;
    if (projectPath.isEmpty) {
      return;
    }

    final snapshot = entry.threadSnapshot;
    final currentSession = entry.controller.currentSession;
    final sessionId = currentSession?.id ?? snapshot.sessionId;
    final providerId = currentSession?.providerId ?? snapshot.providerId;
    final state = projectThreadsController.stateFor(projectPath);
    final hasProviderSummary =
        sessionId == null ||
        state.threads.any(
          (thread) => thread.id == sessionId && thread.providerId == providerId,
        );
    var registeredNewSession = false;
    if (currentSession != null && !hasProviderSummary) {
      projectThreadsController.registerSession(
        projectPath,
        currentSession,
        preview: _provisionalThreadPreview(entry.controller),
        markRunning: snapshot.isTurnRunning,
      );
      registeredNewSession = true;
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
      agentConversationWorkspace.removeThreadMapping(projectPath);
      return;
    }

    agentConversationWorkspace.setThreadMapping(projectPath, sessionId);
    projectThreadsController.selectThreadId(projectPath, sessionId);
    _syncSelectedThreadTitleFromList();

    if (registeredNewSession) {
      final projectId = projectIdMapping?.idForPath(projectPath);
      if (projectId != null) {
        navigationPort?.replace(ThreadLocation(projectId, sessionId));
      }
    }
  }

  Future<AgentCommandOutcome> _openCreatedThread({
    required AgentSession session,
    required AgentContext context,
    String? initialMessage,
  }) async {
    if (_isDisposed) throw StateError('Workbench is closing');
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
    if (_isDisposed) throw StateError('Workbench is closing');

    final projectId = projectIdMapping?.idForPath(projectPath);
    if (projectId != null) {
      navigationPort?.replace(ThreadLocation(projectId, session.id));
    }

    final entry = agentConversationWorkspace.selectedEntry;
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
      return lifetimes
          .actionsForOwner(entry.ownerKey)
          .sendMessage(trimmedMessage);
    }
    return const AgentCommandOutcome.succeeded();
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
    if (agentConversationWorkspace.threadIdsByProject[projectPath] ==
        threadId) {
      agentConversationWorkspace.removeThreadMapping(projectPath);
    }
    final removedEntries = <String>[
      for (final entry in agentConversationWorkspace.entriesForProject(
        projectPath,
      ))
        if (entry.threadId == threadId) entry.entryId,
    ];
    final removedSelected = removedEntries.contains(
      selectedAgentWorkspaceEntryId,
    );
    for (final entryId in removedEntries) {
      final entry = agentConversationWorkspace.entryById(entryId);
      unawaited(
        lifetimes.closeEntry(entry.ownerKey).onError((error, trace) {
          _log.e('Conversation entry release failed');
        }),
      );
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

  /// 停止新入口和后台 restore 回流；资源由 app 按反序显式关闭。
  void stopAcceptingCommands() {
    if (_isDisposed) return;
    _isDisposed = true;
    _homeRefreshToken += 1;
    _cancelPendingSessionRestore();
    _unsubscribeConversationWorkspace?.call();
    _unsubscribeProjectThreads?.call();
    projectThreadsController.onActiveThreadCleared = null;
    _fileIndexController.removeListener(_handleFileIndexChanged);
    _stateListeners.clear();
  }
}

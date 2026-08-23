import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:zeta/src/app/logging/app_logging.dart';
import 'package:zeta/src/app/project_threads_slice/project_threads_slice_composition.dart';
import 'package:zeta/src/app/workspace_slice/workspace_slice_composition.dart';
import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/agent/application/agent_model_catalog_repository.dart';
import 'package:zeta/src/features/agent/application/agent_provider_settings_controller.dart';
import 'package:zeta/src/features/agent/application/agent_provider_settings_port.dart';
import 'package:zeta/src/features/agent/application/agent_thread_workspace_controller.dart';
import 'package:zeta/src/ui/core/system_file_manager.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_view_model.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_restore_result.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_operations.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_state_builder.dart';
import 'package:zeta/src/features/ide_session/domain/ide_session_state.dart';
import 'package:zeta/src/features/ide_session/domain/ide_workbench_layout_state.dart';
import 'package:zeta/src/features/ide_session/domain/recent_project_summary.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_operations.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_slice/project_threads_slice_store.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_session_snapshot_codec.dart';
import 'package:zeta/src/features/project_threads/domain/project_thread_list_state.dart';
import 'package:zeta/src/features/workspace/application/workspace_file_index_controller.dart';
import 'package:zeta/src/features/workspace/application/workspace_file_corpus_port.dart';
import 'package:zeta/src/features/workspace/application/workspace_slice/workspace_slice_state.dart';
import 'package:zeta/src/features/workspace/application/workspace_slice/workspace_slice_store.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';

final _log = loggerFor('zeta.app.ide_shell_controller');

typedef IdeDirectoryPicker = Future<String?> Function();
typedef IdeShellStatusReporter = void Function(String message);

/// IDE shell 的应用级协调器。
///
/// 它承接项目打开、文件树状态、会话恢复/保存以及 Agent thread 选择同步，
/// 让页面只负责三栏布局和 UI 事件转发。
class IdeShellController extends ChangeNotifier {
  static const String _bootstrapProjectPath = '';

  IdeShellController({
    required this._directoryPicker,
    required this.ideSessionOperations,
    required AgentProviderBundleFactory agentProviderFactory,
    required AgentProviderConfigStore agentProviderConfigStore,
    this._projectLocationOpener = openPathInSystemFileManager,
    this._statusReporter,
    AgentModelCatalogRepository? agentModelCatalogRepository,
    WorkspaceFileIndexController? workspaceFileIndexController,
    AgentProviderRuntimeRegistry? agentProviderRuntimeRegistry,
    AgentFrameScheduler Function()? agentUiFrameSchedulerFactory,
    ValueChanged<AgentTurnTerminalSignal>? onAgentTurnTerminal,
    ValueChanged<AgentWorkspaceAttention>? onAgentAttention,
    this._onAgentUsageProviderRestored,
    AgentTurnContextStore? turnContextStore,
    this.agentUiTextCatalog = const FallbackAgentUiTextCatalog(),
    this.metrics = noopZetaMetricsPort,
    this.conversationSliceEnabled = false,
    AgentProviderSettingsPort? agentProviderSettingsPort,
    Future<AgentModelCatalogLoadResult> Function()? activeModelCatalogLoader,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    this.agentProviderRuntimeRegistry =
        agentProviderRuntimeRegistry ??
        AgentProviderRuntimeRegistry(
          providerFactory: agentProviderFactory,
          metrics: metrics,
          providerMetricLabel: AgentMetricLabels.forProviderId,
        );
    agentProviderGlobalRuntime = AgentProviderGlobalRuntime(
      runtimeRegistry: this.agentProviderRuntimeRegistry,
    );
    _ownsAgentProviderRuntimeRegistry = agentProviderRuntimeRegistry == null;
    _ownsFileIndexController = workspaceFileIndexController == null;
    _fileIndexController =
        workspaceFileIndexController ?? WorkspaceFileIndexController();
    _fileIndexController.addListener(_handleFileIndexChanged);
    _workspaceSliceComposition = WorkspaceSliceComposition.create(
      fileIndexController: _fileIndexController,
      now: _now,
    );
    workspaceSliceStore = _workspaceSliceComposition.store;
    workspaceSliceStore.addListener(_handleWorkspaceSliceChanged);
    if (agentProviderSettingsPort == null) {
      final controller = AgentProviderSettingsController(
        configStore: agentProviderConfigStore,
        modelCatalogRepository: agentModelCatalogRepository,
        runtimeRegistry: this.agentProviderRuntimeRegistry,
        globalRuntime: agentProviderGlobalRuntime,
        staticCapabilitiesFor: AgentProviderStaticCapabilities.forKind,
      );
      agentProviderController = controller;
      _disposeAgentProviderController = controller.dispose;
      _loadActiveModelCatalog = controller.loadActiveModelCatalog;
    } else {
      if (activeModelCatalogLoader == null) {
        throw ArgumentError(
          'activeModelCatalogLoader is required with '
          'agentProviderSettingsPort',
        );
      }
      agentProviderController = agentProviderSettingsPort;
      _disposeAgentProviderController = null;
      _loadActiveModelCatalog = activeModelCatalogLoader;
    }
    _workspaceFileCorpus = CallbackWorkspaceFileCorpusPort(
      filesProvider: () {
        // @mention 候选优先用后台预建的完整语料；未就绪时回退惰性目录树。
        final root = activeProjectPath;
        if (root != null) {
          final ready = _fileIndexController.filesFor(root);
          if (ready != null) {
            return ready;
          }
        }
        return workspaceTree;
      },
      isReadyProvider: () {
        final root = activeProjectPath;
        return root == null || _fileIndexController.isReady(root);
      },
      addListenerCallback: _fileIndexController.addListener,
      removeListenerCallback: _fileIndexController.removeListener,
    );
    agentWorkspaceController = AgentThreadWorkspaceController(
      providerController: agentProviderController,
      workspaceFileCorpus: _workspaceFileCorpus,
      runtimeRegistry: this.agentProviderRuntimeRegistry,
      globalRuntime: agentProviderGlobalRuntime,
      onTurnTerminal: onAgentTurnTerminal,
      onAttention: onAgentAttention,
      onCreatedThread: _openCreatedThread,
      uiFrameSchedulerFactory: agentUiFrameSchedulerFactory,
      turnContextStore: turnContextStore,
      textCatalog: agentUiTextCatalog,
      metrics: metrics,
      conversationSliceEnabled: conversationSliceEnabled,
    );
    _bootstrapAgentEntry = agentWorkspaceController.ensureDraftEntry(
      projectPath: _bootstrapProjectPath,
      providerId: defaultAgentProviderId,
    );
    agentWorkspaceController.selectEntry(_bootstrapAgentEntry.entryId);
    final projectThreadsComposition = ProjectThreadsSliceComposition.create(
      providerController: agentProviderController,
      globalRuntime: agentProviderGlobalRuntime,
      bindingManager: agentWorkspaceController.bindingManager,
      textCatalog: agentUiTextCatalog,
      now: _now,
    );
    projectThreadsController = projectThreadsComposition.store;
    projectThreadsSliceStore = projectThreadsComposition.store;
    projectThreadsController.onActiveThreadCleared = _handleActiveThreadCleared;
    agentWorkspaceController.addListener(_handleAgentWorkspaceChanged);
    _unsubscribeProjectThreads = projectThreadsSliceStore.subscribe(
      _handleProjectThreadsChanged,
    );
    _refreshWorkspaceEntryBindings();
    _bindSelectedWorkspaceRuntime();
    unawaited(agentProviderController.loadSettings());
    unawaited(selectedAgentViewModel.loadSettings());
    unawaited(_prewarmActiveModelCatalog());
    unawaited(_restoreSession());
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

  final IdeDirectoryPicker _directoryPicker;
  final ProjectLocationOpener _projectLocationOpener;
  final IdeShellStatusReporter? _statusReporter;
  final ValueChanged<String?>? _onAgentUsageProviderRestored;
  final IdeSessionSliceOperations ideSessionOperations;
  final DateTime Function() _now;

  late final AgentProviderRuntimeRegistry agentProviderRuntimeRegistry;
  late final AgentProviderGlobalRuntime agentProviderGlobalRuntime;
  late final bool _ownsAgentProviderRuntimeRegistry;
  late final WorkspaceFileIndexController _fileIndexController;
  late final bool _ownsFileIndexController;
  late final WorkspaceSliceComposition _workspaceSliceComposition;
  late final WorkspaceFileCorpusPort _workspaceFileCorpus;
  late final WorkspaceSliceStore workspaceSliceStore;
  late final AgentProviderSettingsPort agentProviderController;
  late final VoidCallback? _disposeAgentProviderController;
  late final Future<AgentModelCatalogLoadResult> Function()
  _loadActiveModelCatalog;
  late final AgentThreadWorkspaceController agentWorkspaceController;
  late final AgentThreadWorkspaceEntry _bootstrapAgentEntry;
  late final ProjectThreadsOperations projectThreadsController;
  late final ProjectThreadsSliceStore projectThreadsSliceStore;
  late final void Function() _unsubscribeProjectThreads;
  final AgentUiTextCatalog agentUiTextCatalog;

  /// app 组合层注入的脱敏指标端口；默认 no-op，探针只剩常量分支。
  final ZetaMetricsPort metrics;

  /// Phase 2 切片的 feature flag（全局）：所有 workspace entry 是否走切片路径。
  ///
  /// false = 走旧 ViewModel 直连路径（测试默认）。
  final bool conversationSliceEnabled;

  final Map<String, ({AgentThreadWorkspaceEntry entry, VoidCallback listener})>
  _workspaceEntryListeners =
      <String, ({AgentThreadWorkspaceEntry entry, VoidCallback listener})>{};

  ({
    ValueListenable<AgentConversationThreadSnapshot> snapshotListenable,
    VoidCallback listener,
  })?
  _selectedWorkspaceThreadSnapshotBinding;

  final Map<String, String> _agentThreadIdsByProject = <String, String>{};
  bool _projectHomeActive = false;
  int _homeRefreshToken = 0;
  bool _isDisposed = false;

  List<AgentThreadWorkspaceEntry> get agentWorkspaceEntries =>
      agentWorkspaceController.entries;

  String? get selectedAgentWorkspaceEntryId =>
      agentWorkspaceController.selectedEntryId;

  /// 当前是否在活动项目的不带 Composer 首页。
  bool get isProjectHomeActive =>
      _projectHomeActive && activeProjectPath != null;

  AgentConversationViewModel get selectedAgentViewModel =>
      agentWorkspaceController.selectedEntry?.viewModel ??
      _bootstrapAgentEntry.viewModel;

  /// 兼容旧调用点；请优先改用 [selectedAgentViewModel]。
  AgentConversationViewModel get agentViewModel => selectedAgentViewModel;

  List<String> get projects => workspaceSliceStore.state.projects;

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

  /// 提交统计面板关注的 Provider id；传空清除偏好。
  void setSelectedAgentUsageProviderId(String? providerId) {
    _setWorkbenchLayout(
      workbenchLayout.copyWith(selectedAgentUsageProviderId: providerId),
    );
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
        workspaceSliceStore.state.projectLastOpenedAtByPath;
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

  String? get activeProjectPath => workspaceSliceStore.state.activeProjectPath;

  List<WorkspaceNode> get workspaceTree => workspaceSliceStore.state.tree;

  Set<String> get expandedDirectoryPaths =>
      workspaceSliceStore.state.expandedDirectoryPaths;

  String? get selectedTreePath => workspaceSliceStore.state.selectedTreePath;

  bool get isLoadingProject => workspaceSliceStore.state.isLoadingProject;

  String? get _currentWorkspaceFilePath =>
      workspaceSliceStore.state.currentFilePath;

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
    final path = await _directoryPicker();
    if (path == null || path.trim().isEmpty) {
      return;
    }

    _cancelPendingSessionRestore();
    await _loadProject(path);
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
    final sourceEntry = agentWorkspaceController.entryForThread(
      providerId: thread.providerId,
      threadId: thread.id,
    );
    final session = await projectThreadsController.forkThread(
      projectPath: projectPath,
      threadId: thread.id,
      permissionSnapshot: sourceEntry?.viewModel.permissionSnapshotForThread(
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

    workspaceSliceStore.removeProject(path);
    _agentThreadIdsByProject.remove(path);
    projectThreadsController.retainProjects(projects);
    agentWorkspaceController.removeEntriesForProject(path);

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

    final openEntry = agentWorkspaceController.entryForThread(
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
        title: openEntry.viewModel.currentThreadTitle,
        preview: openEntry.viewModel.currentThreadTitle,
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
    final selected = agentWorkspaceController.selectedEntry;
    return selected?.providerId == providerId && selected?.threadId == threadId;
  }

  void handleTreeExpansionChanged(String key, bool expanded) {
    final node = _findTreeNode(key);
    if (node == null || !node.isDirectory) {
      return;
    }
    workspaceSliceStore.setDirectoryExpanded(key, expanded);
    _notifyStateChanged();
    _requestSessionSave();
  }

  void handleTreeNodeTap(String key) {
    final node = _findTreeNode(key);
    if (node == null) {
      return;
    }

    workspaceSliceStore.selectTreeNode(key);
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

  Future<void> _loadProject(String path, {bool activateThreads = true}) async {
    _homeRefreshToken += 1;
    _log.i('Opening project folder: $path');
    _notifyStateChanged();

    try {
      final loaded = await workspaceSliceStore.loadProject(path);
      if (!loaded || _isDisposed || activeProjectPath != path) {
        return;
      }

      projectThreadsController.retainProjects(projects);
      if (activateThreads) {
        projectThreadsController.activateProject(path);
      }
      _enterProjectHome(refreshThreads: true);
      _requestSessionSave();
      _log.i('Opened project folder: $path');
      _notifyStateChanged();
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
          workspaceSliceStore.clearCurrentFile();
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

      await workspaceSliceStore.restore(
        WorkspaceRestoreSnapshot(
          projects: session.projectPaths,
          activeProjectPath: session.activeProjectPath,
          currentFilePath: session.currentFilePath,
          expandedDirectoryPaths: session.expandedDirectoryPaths,
          selectedTreePath: session.selectedTreeKey,
          projectLastOpenedAtByPath: session.projectLastOpenedAtByPath,
        ),
      );
      _agentThreadIdsByProject
        ..clear()
        ..addAll(session.agentThreadIdsByProject);
      ideSessionOperations.setWorkbenchLayout(session.workbenchLayout);
      _onAgentUsageProviderRestored?.call(
        session.workbenchLayout.selectedAgentUsageProviderId,
      );

      projectThreadsController.restoreSession(
        projectPaths: session.projectPaths,
        activeProjectPath: session.activeProjectPath,
        snapshot: projectThreadsSessionSnapshotFromIdeSessionState(session),
      );
      for (final entry in _agentThreadIdsByProject.entries.toList()) {
        final thread = _threadSummaryFor(entry.key, entry.value);
        if (thread == null) {
          // provider 归属只存在于完整摘要；缺失时不能猜测 active provider。
          _log.w(
            'Discarding restored thread ${entry.value} without provider ownership',
          );
          _agentThreadIdsByProject.remove(entry.key);
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
    workspaceSliceStore.clearActiveWorkspace();
    _projectHomeActive = false;
    agentWorkspaceController.selectEntry(_bootstrapAgentEntry.entryId);
    _bootstrapAgentEntry.viewModel.updateContext(
      projectPath: null,
      contextFilePath: null,
    );
    _requestSessionSave();
    _notifyStateChanged();
  }

  IdeSessionState _currentSessionState() {
    final selectedAgentViewModel = this.selectedAgentViewModel;
    final workspaceState = workspaceSliceStore.state;
    return buildIdeSessionState(
      projectPaths: projects,
      activeProjectPath: activeProjectPath,
      currentFilePath: _currentWorkspaceFilePath,
      expandedDirectoryPaths: _currentExpandedDirectoryPaths(),
      selectedTreeKey: selectedTreePath,
      activeAgentProviderId: selectedAgentViewModel.activeProviderId,
      agentThreadIdsByProject: _agentThreadIdsByProject,
      projectLastOpenedAtByPath: workspaceState.projectLastOpenedAtByPath,
      projectThreadsSessionSnapshot: projectThreadsController.sessionSnapshot,
      currentProjectPath: activeProjectPath,
      currentSessionId: isProjectHomeActive
          ? null
          : selectedAgentViewModel.sessionId,
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

    _projectHomeActive = true;
    agentWorkspaceController.clearSelection();
    projectThreadsController.clearAllSelectedThreads();
    if (refreshThreads) {
      // 首页与侧栏共享未归档首屏；保留缓存并在后台刷新最新五条。
      unawaited(projectThreadsController.loadInitial(projectPath));
    }
  }

  void _markProjectOpened(String path) {
    workspaceSliceStore.markProjectOpened(path, _now());
  }

  WorkspaceNode? _findTreeNode(String path) {
    return WorkspaceNode.findByPath(workspaceTree, path);
  }

  Future<void> _syncSelectedAgentWorkspace() async {
    final projectPath = activeProjectPath;
    if (projectPath == null) {
      _projectHomeActive = false;
      agentWorkspaceController.selectEntry(_bootstrapAgentEntry.entryId);
      _bootstrapAgentEntry.applyDraftIdentity(
        projectPath: _bootstrapProjectPath,
        providerId: _bootstrapAgentEntry.providerId,
      );
      _bootstrapAgentEntry.viewModel.updateContext(
        projectPath: null,
        contextFilePath: null,
      );
      return;
    }

    var restoredSessionId = _agentThreadIdsByProject[projectPath];
    var restoredThread = restoredSessionId == null
        ? null
        : _threadSummaryFor(projectPath, restoredSessionId);
    if (restoredSessionId != null && restoredThread == null) {
      _log.w('Discarding thread $restoredSessionId without provider ownership');
      _agentThreadIdsByProject.remove(projectPath);
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
    _projectHomeActive = false;
    final entry = agentWorkspaceController.ensureDraftEntry(
      projectPath: projectPath,
      providerId: providerId,
    );
    entry.applyDraftIdentity(projectPath: projectPath, providerId: providerId);
    agentWorkspaceController.selectEntry(entry.entryId);
    await entry.viewModel.loadSettings();
    if (entry.viewModel.activeProviderId != providerId) {
      try {
        await entry.viewModel.switchActiveProvider(providerId);
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
    entry.viewModel.updateContext(
      projectPath: projectPath,
      contextFilePath: _currentWorkspaceFilePath,
    );
    projectThreadsController.clearSelectedThread(projectPath);
    _agentThreadIdsByProject.remove(projectPath);
    unawaited(entry.viewModel.loadModels());
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
    _projectHomeActive = false;
    final existingEntry = agentWorkspaceController.entryForThread(
      providerId: thread.providerId,
      threadId: thread.id,
    );
    final entry = agentWorkspaceController.ensureThreadEntry(
      projectPath: projectPath,
      thread: thread,
    );
    agentWorkspaceController.selectEntry(entry.entryId);
    entry.viewModel.updateContext(
      projectPath: projectPath,
      contextFilePath: _currentWorkspaceFilePath,
    );
    projectThreadsController.registerThreadMapping(projectPath, thread.id);
    projectThreadsController.selectThread(projectPath, thread);
    _agentThreadIdsByProject[projectPath] = thread.id;
    if (existingEntry == null ||
        entry.viewModel.threadOpenPhase ==
            AgentThreadOpenPhase.loadingHistory) {
      await entry.viewModel.initialization;
    } else if (entry.viewModel.threadOpenPhase ==
        AgentThreadOpenPhase.openFailed) {
      await entry.viewModel.retryOpenThread();
    } else {
      unawaited(entry.viewModel.loadModels());
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
    for (final entry in agentWorkspaceController.entriesForProject(
      projectPath,
    )) {
      entry.viewModel.updateContext(
        projectPath: projectPath,
        contextFilePath: _currentWorkspaceFilePath,
      );
    }
  }

  String _preferredDraftProviderId() {
    final preferred = selectedAgentViewModel.threadProviderId;
    if (agentProviderController.isProviderEnabled(preferred)) {
      return preferred;
    }
    return agentProviderController.activeProviderId;
  }

  void _handleAgentWorkspaceChanged() {
    if (_isDisposed) {
      return;
    }
    _refreshWorkspaceEntryBindings();
    _bindSelectedWorkspaceRuntime();
    _syncAllWorkspaceEntries();
    _requestSessionSave();
    _notifyStateChanged();
  }

  void _refreshWorkspaceEntryBindings() {
    final activeIds = agentWorkspaceController.entries
        .map((entry) => entry.entryId)
        .toSet();
    for (final staleId
        in _workspaceEntryListeners.keys
            .where((entryId) => !activeIds.contains(entryId))
            .toList()) {
      _workspaceEntryListeners.remove(staleId);
    }
    for (final entry in agentWorkspaceController.entries) {
      if (_workspaceEntryListeners.containsKey(entry.entryId)) {
        continue;
      }
      void listener() => _handleWorkspaceEntryChanged(entry.entryId);
      entry.addListener(listener);
      _workspaceEntryListeners[entry.entryId] = (
        entry: entry,
        listener: listener,
      );
      _syncWorkspaceEntryState(entry);
    }
  }

  void _bindSelectedWorkspaceRuntime() {
    final selectedEntry = agentWorkspaceController.selectedEntry;
    final selectedSnapshotListenable =
        selectedEntry?.viewModel.threadSnapshotListenable;

    final currentSnapshotBinding = _selectedWorkspaceThreadSnapshotBinding;
    if (currentSnapshotBinding != null &&
        !identical(
          currentSnapshotBinding.snapshotListenable,
          selectedSnapshotListenable,
        )) {
      currentSnapshotBinding.snapshotListenable.removeListener(
        currentSnapshotBinding.listener,
      );
      _selectedWorkspaceThreadSnapshotBinding = null;
    }
    if (selectedSnapshotListenable != null &&
        _selectedWorkspaceThreadSnapshotBinding == null) {
      final listener = _handleSelectedWorkspaceThreadSnapshotChanged;
      selectedSnapshotListenable.addListener(listener);
      _selectedWorkspaceThreadSnapshotBinding = (
        snapshotListenable: selectedSnapshotListenable,
        listener: listener,
      );
    }
  }

  void _handleWorkspaceEntryChanged(String entryId) {
    if (_isDisposed) {
      return;
    }
    final binding = _workspaceEntryListeners[entryId];
    if (binding == null) {
      return;
    }
    _syncWorkspaceEntryState(binding.entry);
    if (entryId == selectedAgentWorkspaceEntryId) {
      _notifyStateChanged();
    }
    _requestSessionSave();
  }

  void _syncAllWorkspaceEntries() {
    for (final entry in agentWorkspaceController.entries) {
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
    final currentSession = entry.viewModel.currentSession;
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
        preview: _provisionalThreadPreview(entry.viewModel),
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
      _agentThreadIdsByProject.remove(projectPath);
      return;
    }

    _agentThreadIdsByProject[projectPath] = sessionId;
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

    final entry = agentWorkspaceController.selectedEntry;
    if (entry?.providerId != session.providerId ||
        entry?.threadId != session.id ||
        entry?.viewModel.threadOpenPhase != AgentThreadOpenPhase.idle) {
      throw StateError('Could not open created thread ${session.id}');
    }
    entry!.viewModel.updateContext(
      projectPath: projectPath,
      contextFilePath: context.filePath,
    );
    if (trimmedMessage != null && trimmedMessage.isNotEmpty) {
      await entry.viewModel.sendMessage(trimmedMessage);
    }
  }

  void _handleSelectedWorkspaceThreadSnapshotChanged() {
    _notifyStateChanged();
  }

  /// 从当前时间线取首条用户消息，作为新 thread 的临时列表 preview。
  String? _provisionalThreadPreview(AgentConversationViewModel viewModel) {
    for (final message in viewModel.messages) {
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
    final viewModel = selectedAgentViewModel;
    final sessionId = viewModel.sessionId;
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
    viewModel.syncThreadTitleIfCurrent(sessionId, title!);
  }

  void _handleActiveThreadCleared(String projectPath, String threadId) {
    if (_agentThreadIdsByProject[projectPath] == threadId) {
      _agentThreadIdsByProject.remove(projectPath);
    }
    final removedEntries = <String>[
      for (final entry in agentWorkspaceController.entriesForProject(
        projectPath,
      ))
        if (entry.threadId == threadId) entry.entryId,
    ];
    final removedSelected = removedEntries.contains(
      selectedAgentWorkspaceEntryId,
    );
    for (final entryId in removedEntries) {
      agentWorkspaceController.removeEntry(entryId);
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
      notifyListeners();
    }
  }

  /// 后台文件语料就绪/失效时刷新 shell 状态，并让 @mention 等监听者拿到新语料。
  void _handleFileIndexChanged() {
    _notifyStateChanged();
  }

  /// Workspace owner 的只读变化继续由 Shell 向跨 feature 消费方投影。
  void _handleWorkspaceSliceChanged() {
    _notifyStateChanged();
  }

  @override
  void dispose() {
    if (_isDisposed) {
      return;
    }
    unawaited(saveNow());
    _isDisposed = true;
    _homeRefreshToken += 1;
    workspaceSliceStore.removeListener(_handleWorkspaceSliceChanged);
    agentWorkspaceController.removeListener(_handleAgentWorkspaceChanged);
    _unsubscribeProjectThreads();
    final selectedSnapshotBinding = _selectedWorkspaceThreadSnapshotBinding;
    if (selectedSnapshotBinding != null) {
      selectedSnapshotBinding.snapshotListenable.removeListener(
        selectedSnapshotBinding.listener,
      );
      _selectedWorkspaceThreadSnapshotBinding = null;
    }
    projectThreadsController.dispose();
    agentWorkspaceController.dispose();
    _workspaceSliceComposition.dispose();
    _disposeAgentProviderController?.call();
    // 在 workspace 条目释放后再拆索引监听，避免 popover 仍挂在 listenable 上。
    _fileIndexController.removeListener(_handleFileIndexChanged);
    if (_ownsFileIndexController) {
      _fileIndexController.dispose();
    }
    if (_ownsAgentProviderRuntimeRegistry) {
      unawaited(agentProviderRuntimeRegistry.close());
    }
    super.dispose();
  }
}

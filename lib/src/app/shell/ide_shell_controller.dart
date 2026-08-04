import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_thread_snapshot.dart';
import 'package:zeta/src/features/agent/application/agent_model_catalog_repository.dart';
import 'package:zeta/src/features/agent/application/agent_provider_runtime_registry.dart';
import 'package:zeta/src/features/agent/application/agent_thread_workspace_controller.dart';
import 'package:zeta/src/features/agent/application/agent_ui_update_port.dart';
import 'package:zeta/src/core/utils/system_file_manager.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_view_model.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_persistence_coordinator.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_restore_result.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_state_builder.dart';
import 'package:zeta/src/features/ide_session/data/ide_session_store.dart';
import 'package:zeta/src/features/ide_session/domain/ide_session_state.dart';
import 'package:zeta/src/features/ide_session/domain/recent_project_summary.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_controller.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_session_snapshot_codec.dart';
import 'package:zeta/src/features/project_threads/domain/project_thread_list_state.dart';
import 'package:zeta/src/features/project_threads/presentation/project_threads_view_model.dart';
import 'package:zeta/src/features/workspace/application/workspace_file_index_controller.dart';
import 'package:zeta/src/features/workspace/application/workspace_tree_builder.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';
import 'package:zeta/src/ui/features/ide/view_models/active_agent_provider_controller.dart';
import 'package:zeta/src/app/app_constants.dart';

final _log = loggerFor('zeta.app.ide_shell_controller');

typedef IdeDirectoryPicker = Future<String?> Function();
typedef IdeShellStatusReporter = void Function(String message);

int _compareThreadRecency(AgentThreadSummary left, AgentThreadSummary right) {
  final leftTime = left.lastActiveAt;
  final rightTime = right.lastActiveAt;
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
  final byProvider = left.providerId.compareTo(right.providerId);
  return byProvider != 0 ? byProvider : left.id.compareTo(right.id);
}

/// IDE shell 的应用级协调器。
///
/// 它承接项目打开、文件树状态、会话恢复/保存以及 Agent thread 选择同步，
/// 让页面只负责三栏布局和 UI 事件转发。
class IdeShellController extends ChangeNotifier {
  static const String _bootstrapProjectPath = '';

  IdeShellController({
    required this._directoryPicker,
    required IdeSessionStore sessionStore,
    required AgentProviderFactory agentProviderFactory,
    required AgentProviderConfigStore agentProviderConfigStore,
    this._projectLocationOpener = openPathInSystemFileManager,
    this._statusReporter,
    AgentModelCatalogRepository? agentModelCatalogRepository,
    WorkspaceFileIndexController? workspaceFileIndexController,
    AgentProviderRuntimeRegistry? agentProviderRuntimeRegistry,
    AgentFrameScheduler Function()? agentUiFrameSchedulerFactory,
    VoidCallback? onAgentTurnCompleted,
    ValueChanged<AgentWorkspaceAttention>? onAgentAttention,
    DateTime Function()? now,
  }) : projectThreadsViewModel = ProjectThreadsViewModel(),
       _sessionCoordinator = IdeSessionPersistenceCoordinator(
         store: sessionStore,
         saveDelay: sessionSaveDelay,
       ),
       _now = now ?? DateTime.now {
    this.agentProviderRuntimeRegistry =
        agentProviderRuntimeRegistry ??
        AgentProviderRuntimeRegistry(providerFactory: agentProviderFactory);
    _ownsAgentProviderRuntimeRegistry = agentProviderRuntimeRegistry == null;
    _ownsFileIndexController = workspaceFileIndexController == null;
    _fileIndexController =
        workspaceFileIndexController ?? WorkspaceFileIndexController();
    _fileIndexController.addListener(_handleFileIndexChanged);
    agentProviderController = ActiveAgentProviderController(
      providerFactory: agentProviderFactory,
      configStore: agentProviderConfigStore,
      modelCatalogRepository: agentModelCatalogRepository,
      runtimeRegistry: this.agentProviderRuntimeRegistry,
    );
    agentWorkspaceController = AgentThreadWorkspaceController(
      providerFactory: agentProviderFactory,
      configStore: agentProviderConfigStore,
      workspaceFilesProvider: () {
        // @mention 候选优先用后台预建的完整语料；未就绪时回退惰性目录树。
        final root = _projectPath;
        if (root != null) {
          final ready = _fileIndexController.filesFor(root);
          if (ready != null) {
            return ready;
          }
        }
        return _workspaceTree;
      },
      workspaceFilesListenable: _fileIndexController,
      workspaceFilesIndexReady: () {
        final root = _projectPath;
        if (root == null) {
          return true;
        }
        return _fileIndexController.isReady(root);
      },
      modelCatalogRepository: agentProviderController.modelCatalogRepository,
      runtimeRegistry: this.agentProviderRuntimeRegistry,
      onTurnCompleted: onAgentTurnCompleted,
      onAttention: onAgentAttention,
      uiFrameSchedulerFactory: agentUiFrameSchedulerFactory,
    );
    _bootstrapAgentEntry = agentWorkspaceController.ensureDraftEntry(
      projectPath: _bootstrapProjectPath,
      providerId: defaultAgentProviderId,
    );
    agentWorkspaceController.selectEntry(_bootstrapAgentEntry.entryId);
    projectThreadsController = ProjectThreadsController(
      providerController: agentProviderController,
      viewModel: projectThreadsViewModel,
    );
    projectThreadsController.onActiveThreadCleared = _handleActiveThreadCleared;
    agentWorkspaceController.addListener(_handleAgentWorkspaceChanged);
    projectThreadsViewModel.addListener(_handleProjectThreadsChanged);
    _refreshWorkspaceEntryBindings();
    _bindSelectedWorkspaceRuntime();
    unawaited(agentProviderController.loadSettings());
    unawaited(selectedAgentViewModel.loadSettings());
    unawaited(_prewarmActiveModelCatalog());
    unawaited(_restoreSession());
  }

  Future<void> _prewarmActiveModelCatalog() async {
    try {
      await agentProviderController.loadActiveModelCatalog();
    } catch (error) {
      _log.fine(
        'Could not prewarm active Agent model catalog (${error.runtimeType})',
      );
    }
  }

  final IdeDirectoryPicker _directoryPicker;
  final ProjectLocationOpener _projectLocationOpener;
  final IdeShellStatusReporter? _statusReporter;
  final IdeSessionPersistenceCoordinator _sessionCoordinator;
  final DateTime Function() _now;

  late final AgentProviderRuntimeRegistry agentProviderRuntimeRegistry;
  late final bool _ownsAgentProviderRuntimeRegistry;
  late final WorkspaceFileIndexController _fileIndexController;
  late final bool _ownsFileIndexController;
  late final ActiveAgentProviderController agentProviderController;
  late final AgentThreadWorkspaceController agentWorkspaceController;
  late final AgentThreadWorkspaceEntry _bootstrapAgentEntry;
  late final ProjectThreadsController projectThreadsController;
  final ProjectThreadsViewModel projectThreadsViewModel;
  final Map<String, ({AgentThreadWorkspaceEntry entry, VoidCallback listener})>
  _workspaceEntryListeners =
      <String, ({AgentThreadWorkspaceEntry entry, VoidCallback listener})>{};

  ({
    ValueListenable<AgentConversationThreadSnapshot> snapshotListenable,
    VoidCallback listener,
  })?
  _selectedWorkspaceThreadSnapshotBinding;
  ({ActiveAgentProviderController providerController, VoidCallback listener})?
  _selectedProviderControllerBinding;

  List<WorkspaceNode> _workspaceTree = const <WorkspaceNode>[];
  Set<String> _expandedDirectoryPaths = <String>{};
  final List<String> _projects = <String>[];
  final Map<String, String> _agentThreadIdsByProject = <String, String>{};
  final Map<String, DateTime> _projectLastOpenedAtByPath = <String, DateTime>{};
  String? _projectPath;
  String? _currentFilePath;
  String? _selectedTreePath;
  bool _isLoadingProject = false;
  bool _projectHomeActive = false;
  bool _initialRestoreCompleted = false;
  final Completer<void> _initialRestoreCompleter = Completer<void>();
  int _homeRefreshToken = 0;
  bool _isDisposed = false;

  List<AgentThreadWorkspaceEntry> get agentWorkspaceEntries =>
      agentWorkspaceController.entries;

  String? get selectedAgentWorkspaceEntryId =>
      agentWorkspaceController.selectedEntryId;

  /// 当前是否在活动项目的不带 Composer 首页。
  bool get isProjectHomeActive => _projectHomeActive && _projectPath != null;

  AgentConversationViewModel get selectedAgentViewModel =>
      agentWorkspaceController.selectedEntry?.viewModel ??
      _bootstrapAgentEntry.viewModel;

  /// 兼容旧调用点；请优先改用 [selectedAgentViewModel]。
  AgentConversationViewModel get agentViewModel => selectedAgentViewModel;

  List<String> get projects => List<String>.unmodifiable(_projects);

  /// 初始会话恢复已完成；此后无活动项目时可以稳定展示全局首页。
  bool get initialRestoreCompleted => _initialRestoreCompleted;

  /// 等待启动会话恢复收敛，供冷启动通知定位避免与恢复竞态。
  Future<void> get initialRestoreDone => _initialRestoreCompleter.future;

  /// 近期项目按最后访问时间排序；旧数据没有时间时保持原项目顺序。
  List<RecentProjectSummary> get recentProjects {
    final indexed = <({int index, RecentProjectSummary project})>[
      for (final (index, path) in _projects.indexed)
        (
          index: index,
          project: RecentProjectSummary(
            path: path,
            lastOpenedAt: _projectLastOpenedAtByPath[path],
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

  /// 所有已知项目缓存中的近期未归档会话，按最近活跃时间降序。
  List<AgentThreadSummary> get recentThreads {
    final byIdentity = <String, AgentThreadSummary>{};
    for (final projectPath in _projects) {
      final state = projectThreadsController.stateFor(projectPath);
      if (state.archived) {
        continue;
      }
      for (final thread in state.threads) {
        final key = '${thread.providerId}\u0000${thread.id}';
        final existing = byIdentity[key];
        if (existing == null || _compareThreadRecency(thread, existing) < 0) {
          byIdentity[key] = thread;
        }
      }
    }
    final threads = byIdentity.values.toList(growable: false)
      ..sort(_compareThreadRecency);
    return List<AgentThreadSummary>.unmodifiable(threads);
  }

  /// 首页近期会话是否仍在后台刷新。
  bool get isRefreshingRecentHomeData => recentProjects
      .take(5)
      .any((project) => projectThreadStateFor(project.path).isLoadingInitial);

  /// 首页近期项目刷新中最后一个非阻断错误。
  String? get recentHomeRefreshError {
    for (final project in recentProjects.take(5)) {
      final error = projectThreadStateFor(project.path).errorMessage;
      if (error != null && error.isNotEmpty) {
        return error;
      }
    }
    return null;
  }

  String? get activeProjectPath => _projectPath;

  List<WorkspaceNode> get workspaceTree =>
      List<WorkspaceNode>.unmodifiable(_workspaceTree);

  Set<String> get expandedDirectoryPaths =>
      Set<String>.unmodifiable(_expandedDirectoryPaths);

  String? get selectedTreePath => _selectedTreePath;

  bool get isLoadingProject => _isLoadingProject;

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

    _sessionCoordinator.cancelPendingRestore();
    await _loadProject(path);
  }

  /// 从全局首页打开一个已知项目，不改变左侧项目树的展开状态。
  Future<void> openRecentProject(String path) async {
    if (!_projects.contains(path)) {
      return;
    }
    _sessionCoordinator.cancelPendingRestore();
    await _loadProject(path, activateThreads: false);
  }

  /// 使用缓存先显策略，顺序刷新首页可见的近期项目会话。
  Future<void> refreshRecentHomeData({int projectLimit = 5}) async {
    final token = ++_homeRefreshToken;
    final paths = recentProjects
        .take(projectLimit)
        .map((project) => project.path)
        .toList(growable: false);
    for (final path in paths) {
      if (_isDisposed || token != _homeRefreshToken || _projectPath != null) {
        return;
      }
      await projectThreadsController.loadInitial(path);
    }
  }

  Future<void> selectKnownProject(String path) async {
    _sessionCoordinator.cancelPendingRestore();
    if (path != _projectPath) {
      await _loadProject(path, activateThreads: false);
    }
    if (_projectPath == path) {
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
    final session = await projectThreadsController.forkThread(
      projectPath: projectPath,
      threadId: thread.id,
    );
    if (session == null) {
      return;
    }

    final state = projectThreadsController.stateFor(projectPath);
    AgentThreadSummary? forkedThread;
    for (final candidate in state.threads) {
      if (candidate.id == session.id) {
        forkedThread = candidate;
        break;
      }
    }
    forkedThread ??= AgentThreadSummary(
      id: session.id,
      providerId: session.providerId,
      projectPath: projectPath,
      title: session.title,
      preview: session.title ?? '',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      status: AgentThreadRuntimeStatus.idle,
    );
    await selectProjectThread(projectPath, forkedThread);
  }

  Future<void> startNewThreadForProject(
    String projectPath, {
    required String providerId,
  }) async {
    if (!_canMutateAgentHistory(providerId: providerId)) {
      return;
    }
    _sessionCoordinator.cancelPendingRestore();

    // workspace-scoped provider 在切换时不能先于项目上下文初始化。
    if (projectPath != _projectPath) {
      await _loadProject(projectPath, activateThreads: false);
      if (_projectPath != projectPath) {
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
      _log.warning(
        'Could not open project location in system file manager: $projectPath',
        error,
        stackTrace,
      );
      _statusReporter?.call('Could not open project location: $error');
    }
  }

  Future<void> removeProject(String path) async {
    final index = _projects.indexOf(path);
    if (index == -1) {
      return;
    }

    _sessionCoordinator.cancelPendingRestore();
    final wasActive = path == _projectPath;
    final nextProjectPath = wasActive && index + 1 < _projects.length
        ? _projects[index + 1]
        : null;

    _projects.removeAt(index);
    _agentThreadIdsByProject.remove(path);
    _projectLastOpenedAtByPath.remove(path);
    projectThreadsController.retainProjects(_projects);
    agentWorkspaceController.removeEntriesForProject(path);

    if (!wasActive) {
      _requestSessionSave();
      _notifyStateChanged();
      return;
    }

    if (nextProjectPath != null) {
      await _loadProject(nextProjectPath, activateThreads: false);
      if (_projectPath == nextProjectPath) {
        return;
      }
    }

    _clearActiveWorkspace();
  }

  Future<void> selectProjectThread(
    String projectPath,
    AgentThreadSummary thread,
  ) async {
    if (projectPath != _projectPath) {
      await _loadProject(projectPath, activateThreads: false);
    }
    if (_projectPath != projectPath) {
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
    for (final path in _projects) {
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
    _setDirectoryExpanded(key, expanded);
    _notifyStateChanged();
    _requestSessionSave();
  }

  void handleTreeNodeTap(String key) {
    final node = _findTreeNode(key);
    if (node == null) {
      return;
    }

    _selectedTreePath = key;
    if (node.isDirectory) {
      _setDirectoryExpanded(key, !_expandedDirectoryPaths.contains(key));
      _notifyStateChanged();
      _requestSessionSave();
      return;
    }

    _currentFilePath = node.path;
    _syncProjectEntryContexts(_projectPath);
    _notifyStateChanged();
    _requestSessionSave();
  }

  Future<void> saveNow() {
    return _sessionCoordinator.saveNow(_currentSessionState());
  }

  Future<void> _loadProject(String path, {bool activateThreads = true}) async {
    _homeRefreshToken += 1;
    _log.info('Opening project folder: $path');
    _isLoadingProject = true;
    _notifyStateChanged();

    try {
      final directory = Directory(path);
      if (!await directory.exists()) {
        throw FileSystemException('Directory does not exist', path);
      }
      if (_isDisposed) {
        return;
      }

      final projectChildren = buildWorkspaceDirectoryChildren(directory);
      if (_isDisposed) {
        return;
      }

      _projectPath = path;
      _currentFilePath = null;
      _selectedTreePath = null;
      _expandedDirectoryPaths = <String>{};
      _workspaceTree = projectChildren;
      if (!_projects.contains(path)) {
        _projects.insert(0, path);
      }
      _markProjectOpened(path);

      unawaited(_fileIndexController.index(path));
      projectThreadsController.retainProjects(_projects);
      if (activateThreads) {
        projectThreadsController.activateProject(path);
      }
      _enterProjectHome(refreshThreads: true);
      _requestSessionSave();
      _log.info('Opened project folder: $path');
      _notifyStateChanged();
    } catch (error, stackTrace) {
      _log.warning('Could not open project folder: $path', error, stackTrace);
      _statusReporter?.call('Could not open folder: $error');
    } finally {
      if (!_initialRestoreCompleter.isCompleted) {
        _initialRestoreCompleter.complete();
      }
      if (!_isDisposed) {
        _isLoadingProject = false;
        _notifyStateChanged();
      }
    }
  }

  Future<void> _restoreSession() async {
    try {
      final result = await _sessionCoordinator.restore();
      if (_isDisposed) {
        return;
      }

      switch (result.status) {
        case IdeSessionRestoreStatus.cancelled:
        case IdeSessionRestoreStatus.empty:
          return;
        case IdeSessionRestoreStatus.failed:
          _currentFilePath = null;
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

      var tree = const <WorkspaceNode>[];
      var selectedTreePath = session.selectedTreeKey;
      if (session.activeProjectPath != null) {
        // 文件树按需加载，只恢复用户已经展开过的目录。
        final projectChildren = buildWorkspaceDirectoryChildren(
          Directory(session.activeProjectPath!),
          expandedPaths: session.expandedDirectoryPaths,
        );
        tree = projectChildren;

        if (selectedTreePath == session.activeProjectPath) {
          selectedTreePath = null;
        } else if (selectedTreePath != null &&
            WorkspaceNode.findByPath(projectChildren, selectedTreePath) ==
                null) {
          selectedTreePath = null;
        }
      }

      _projects
        ..clear()
        ..addAll(session.projectPaths);
      _projectPath = session.activeProjectPath;
      if (session.activeProjectPath != null) {
        unawaited(_fileIndexController.index(session.activeProjectPath!));
      }
      _workspaceTree = tree;
      _expandedDirectoryPaths = Set<String>.from(
        session.expandedDirectoryPaths,
      );
      _currentFilePath = session.currentFilePath;
      _selectedTreePath = selectedTreePath;
      _agentThreadIdsByProject
        ..clear()
        ..addAll(session.agentThreadIdsByProject);
      _projectLastOpenedAtByPath
        ..clear()
        ..addAll(session.projectLastOpenedAtByPath);

      projectThreadsController.restoreSession(
        projectPaths: session.projectPaths,
        activeProjectPath: session.activeProjectPath,
        snapshot: projectThreadsSessionSnapshotFromIdeSessionState(session),
      );
      for (final entry in _agentThreadIdsByProject.entries.toList()) {
        final thread = _threadSummaryFor(entry.key, entry.value);
        if (thread == null) {
          // provider 归属只存在于完整摘要；缺失时不能猜测 active provider。
          _log.warning(
            'Discarding restored thread ${entry.value} without provider ownership',
          );
          _agentThreadIdsByProject.remove(entry.key);
          projectThreadsController.clearSelectedThread(entry.key);
          continue;
        }
        projectThreadsController.registerThreadMapping(entry.key, thread.id);
      }
      if (_projectPath != null) {
        // 启动只恢复项目上下文和会话列表，避免自动进入上次打开的会话详情。
        _enterProjectHome(refreshThreads: true);
      } else {
        await _syncSelectedAgentWorkspace();
      }
      _log.info(
        'Restored IDE session with ${session.projectPaths.length} projects',
      );
      if (result.shouldRequestSave) {
        _requestSessionSave();
      }
      _notifyStateChanged();
    } finally {
      if (!_isDisposed) {
        _initialRestoreCompleted = true;
        _notifyStateChanged();
      }
    }
  }

  void _setDirectoryExpanded(String path, bool expanded) {
    if (expanded) {
      _expandedDirectoryPaths = <String>{..._expandedDirectoryPaths, path};
      _workspaceTree = WorkspaceNode.updateNode(
        _workspaceTree,
        path,
        _loadDirectoryChildrenIfNeeded,
      );
      return;
    }

    final nextExpandedPaths = <String>{..._expandedDirectoryPaths};
    nextExpandedPaths.remove(path);
    _expandedDirectoryPaths = nextExpandedPaths;
  }

  WorkspaceNode _loadDirectoryChildrenIfNeeded(WorkspaceNode node) {
    if (!node.isDirectory || node.childrenLoaded) {
      return node;
    }
    // 首次展开目录时才读取下一层，避免打开项目时递归扫描整个仓库。
    return node.copyWith(
      childrenLoaded: true,
      children: buildWorkspaceDirectoryChildren(
        Directory(node.path),
        expandedPaths: _expandedDirectoryPaths,
      ),
    );
  }

  void _requestSessionSave() {
    _sessionCoordinator.requestSave(_currentSessionState());
  }

  void _clearActiveWorkspace() {
    _homeRefreshToken += 1;
    final root = _projectPath;
    if (root != null) {
      _fileIndexController.invalidate(root);
    }
    _projectPath = null;
    _projectHomeActive = false;
    _currentFilePath = null;
    _selectedTreePath = null;
    _expandedDirectoryPaths = <String>{};
    _workspaceTree = const <WorkspaceNode>[];
    agentWorkspaceController.selectEntry(_bootstrapAgentEntry.entryId);
    _bootstrapAgentEntry.viewModel.updateWorkspace(
      projectPath: null,
      contextFilePath: null,
      resetConversation: true,
    );
    _requestSessionSave();
    _notifyStateChanged();
  }

  IdeSessionState _currentSessionState() {
    final selectedAgentViewModel = this.selectedAgentViewModel;
    return buildIdeSessionState(
      projectPaths: _projects,
      activeProjectPath: _projectPath,
      currentFilePath: _currentFilePath,
      expandedDirectoryPaths: _currentExpandedDirectoryPaths(),
      selectedTreeKey: _selectedTreePath,
      activeAgentProviderId: selectedAgentViewModel.activeProviderId,
      agentThreadIdsByProject: _agentThreadIdsByProject,
      projectLastOpenedAtByPath: _projectLastOpenedAtByPath,
      projectThreadsSessionSnapshot: projectThreadsController.sessionSnapshot,
      currentProjectPath: _projectPath,
      currentSessionId: isProjectHomeActive
          ? null
          : selectedAgentViewModel.sessionId,
      projectHomeActive: isProjectHomeActive,
    );
  }

  Set<String> _currentExpandedDirectoryPaths() {
    return Set<String>.unmodifiable(_expandedDirectoryPaths);
  }

  void _enterProjectHome({required bool refreshThreads}) {
    final projectPath = _projectPath;
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
    _projectLastOpenedAtByPath[path] = _now();
  }

  WorkspaceNode? _findTreeNode(String path) {
    return WorkspaceNode.findByPath(_workspaceTree, path);
  }

  Future<void> _syncSelectedAgentWorkspace() async {
    final projectPath = _projectPath;
    if (projectPath == null) {
      _projectHomeActive = false;
      agentWorkspaceController.selectEntry(_bootstrapAgentEntry.entryId);
      _bootstrapAgentEntry.applyDraftIdentity(
        projectPath: _bootstrapProjectPath,
        providerId: _bootstrapAgentEntry.providerId,
      );
      _bootstrapAgentEntry.viewModel.updateWorkspace(
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
      _log.warning(
        'Discarding thread $restoredSessionId without provider ownership',
      );
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
      _log.warning(
        'Could not restore draft workspace for $projectPath',
        error,
        stackTrace,
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
        _log.warning(
          'Could not select provider $providerId for project draft $projectPath',
          error,
          stackTrace,
        );
        _statusReporter?.call('Could not select Agent provider: $error');
        rethrow;
      }
    }
    entry.viewModel.updateWorkspace(
      projectPath: projectPath,
      contextFilePath: _currentFilePath,
      resetConversation: false,
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
    final entry = agentWorkspaceController.ensureThreadEntry(
      projectPath: projectPath,
      providerId: thread.providerId,
      threadId: thread.id,
    );
    entry.bindThreadIdentity(
      projectPath: projectPath,
      providerId: thread.providerId,
      threadId: thread.id,
    );
    agentWorkspaceController.selectEntry(entry.entryId);
    entry.viewModel.updateWorkspace(
      projectPath: projectPath,
      contextFilePath: _currentFilePath,
    );
    projectThreadsController.registerThreadMapping(projectPath, thread.id);
    projectThreadsController.selectThread(projectPath, thread);
    _agentThreadIdsByProject[projectPath] = thread.id;
    if (_shouldLoadWorkspaceThreadEntry(entry, thread)) {
      await entry.viewModel.switchThread(thread);
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

  bool _shouldLoadWorkspaceThreadEntry(
    AgentThreadWorkspaceEntry entry,
    AgentThreadSummary thread,
  ) {
    if (entry.viewModel.sessionId != thread.id) {
      return true;
    }
    if (entry.viewModel.threadOpenPhase == AgentThreadOpenPhase.openFailed) {
      return true;
    }
    if (entry.viewModel.currentSession != null) {
      return false;
    }
    if (entry.viewModel.visibleHistoryTurns.isNotEmpty ||
        entry.viewModel.liveTurnState != null) {
      return false;
    }
    return entry.viewModel.threadOpenPhase != AgentThreadOpenPhase.idle;
  }

  void _syncProjectEntryContexts(String? projectPath) {
    if (projectPath == null) {
      return;
    }
    for (final entry in agentWorkspaceController.entriesForProject(
      projectPath,
    )) {
      entry.viewModel.updateWorkspace(
        projectPath: projectPath,
        contextFilePath: _currentFilePath,
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

    final currentProviderBinding = _selectedProviderControllerBinding;
    if (currentProviderBinding != null &&
        !identical(
          currentProviderBinding.providerController,
          selectedEntry?.providerController,
        )) {
      currentProviderBinding.providerController.removeListener(
        currentProviderBinding.listener,
      );
      _selectedProviderControllerBinding = null;
    }
    if (selectedEntry != null && _selectedProviderControllerBinding == null) {
      final listener = _handleSelectedProviderControllerChanged;
      selectedEntry.providerController.addListener(listener);
      _selectedProviderControllerBinding = (
        providerController: selectedEntry.providerController,
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
        projectPath != _projectPath) {
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

  void _handleSelectedWorkspaceThreadSnapshotChanged() {
    _notifyStateChanged();
  }

  void _handleSelectedProviderControllerChanged() {
    unawaited(agentProviderController.reloadSettings());
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
    _notifyStateChanged();
    _requestSessionSave();
  }

  /// 将当前会话在列表中的**正式**标题同步到 Agent 详情头栏。
  ///
  /// 仅使用 summary.title（generated_title / 手动重命名），不用 preview。
  /// 这样刷新列表拿到正式标题后，停留在详情也能更新；又不会把首条
  /// 用户消息 preview 误当成最终标题。
  void _syncSelectedThreadTitleFromList() {
    final projectPath = _projectPath;
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
    if (title == null || title.isEmpty) {
      return;
    }
    viewModel.syncThreadTitleIfCurrent(sessionId, title);
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
    if (removedSelected && projectPath == _projectPath) {
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
    _statusReporter?.call('$providerName 已禁用或不可用；无法修改会话。');
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

  @override
  void dispose() {
    if (_isDisposed) {
      return;
    }
    unawaited(saveNow());
    _isDisposed = true;
    _homeRefreshToken += 1;
    _sessionCoordinator.dispose();
    agentWorkspaceController.removeListener(_handleAgentWorkspaceChanged);
    projectThreadsViewModel.removeListener(_handleProjectThreadsChanged);
    final selectedSnapshotBinding = _selectedWorkspaceThreadSnapshotBinding;
    if (selectedSnapshotBinding != null) {
      selectedSnapshotBinding.snapshotListenable.removeListener(
        selectedSnapshotBinding.listener,
      );
      _selectedWorkspaceThreadSnapshotBinding = null;
    }
    final selectedProviderBinding = _selectedProviderControllerBinding;
    if (selectedProviderBinding != null) {
      selectedProviderBinding.providerController.removeListener(
        selectedProviderBinding.listener,
      );
      _selectedProviderControllerBinding = null;
    }
    projectThreadsController.dispose();
    projectThreadsViewModel.dispose();
    agentWorkspaceController.dispose();
    agentProviderController.dispose();
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

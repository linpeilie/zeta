import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:zeta/src/core/logging/app_logging.dart';
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
import 'package:zeta/src/features/project_threads/application/project_threads_controller.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_session_snapshot_codec.dart';
import 'package:zeta/src/features/project_threads/domain/project_thread_list_state.dart';
import 'package:zeta/src/features/project_threads/presentation/project_threads_view_model.dart';
import 'package:zeta/src/features/workspace/application/workspace_tree_builder.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';
import 'package:zeta/src/ui/features/ide/view_models/active_agent_provider_controller.dart';
import 'package:zeta/src/app/app_constants.dart';

final _log = loggerFor('zeta.app.ide_shell_controller');

typedef IdeDirectoryPicker = Future<String?> Function();
typedef IdeShellStatusReporter = void Function(String message);

/// IDE shell 的应用级协调器。
///
/// 它承接项目打开、文件树状态、会话恢复/保存以及 Agent thread 选择同步，
/// 让页面只负责三栏布局和 UI 事件转发。
class IdeShellController extends ChangeNotifier {
  IdeShellController({
    required this._directoryPicker,
    required IdeSessionStore sessionStore,
    required AgentProviderFactory agentProviderFactory,
    required AgentProviderConfigStore agentProviderConfigStore,
    this._projectLocationOpener = openPathInSystemFileManager,
    this._statusReporter,
  }) : agentProviderController = ActiveAgentProviderController(
         providerFactory: agentProviderFactory,
         configStore: agentProviderConfigStore,
       ),
       projectThreadsViewModel = ProjectThreadsViewModel(),
       _sessionCoordinator = IdeSessionPersistenceCoordinator(
         store: sessionStore,
         saveDelay: sessionSaveDelay,
       ) {
    agentViewModel = AgentConversationViewModel(
      providerController: agentProviderController,
      workspaceFilesProvider: () => _workspaceTree,
    );
    projectThreadsController = ProjectThreadsController(
      providerController: agentProviderController,
      viewModel: projectThreadsViewModel,
    );
    projectThreadsController.onActiveThreadCleared = _handleActiveThreadCleared;
    agentViewModel.addListener(_handleAgentChanged);
    projectThreadsViewModel.addListener(_handleProjectThreadsChanged);
    unawaited(agentViewModel.loadSettings());
    unawaited(_restoreSession());
  }

  final IdeDirectoryPicker _directoryPicker;
  final ProjectLocationOpener _projectLocationOpener;
  final IdeShellStatusReporter? _statusReporter;
  final IdeSessionPersistenceCoordinator _sessionCoordinator;

  final ActiveAgentProviderController agentProviderController;
  late final AgentConversationViewModel agentViewModel;
  late final ProjectThreadsController projectThreadsController;
  final ProjectThreadsViewModel projectThreadsViewModel;

  List<WorkspaceNode> _workspaceTree = const <WorkspaceNode>[];
  Set<String> _expandedDirectoryPaths = <String>{};
  final List<String> _projects = <String>[];
  final Map<String, String> _agentThreadIdsByProject = <String, String>{};
  String? _projectPath;
  String? _currentFilePath;
  String? _selectedTreePath;
  bool _isLoadingProject = false;
  bool _isDisposed = false;

  List<String> get projects => List<String>.unmodifiable(_projects);

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

  Future<void> openProject() async {
    final path = await _directoryPicker();
    if (path == null || path.trim().isEmpty) {
      return;
    }

    _sessionCoordinator.cancelPendingRestore();
    await _loadProject(path);
  }

  Future<void> selectKnownProject(String path) async {
    _sessionCoordinator.cancelPendingRestore();
    if (path != _projectPath) {
      await _loadProject(path, activateThreads: false);
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
    return projectThreadsController.archiveThread(
      projectPath: projectPath,
      threadId: thread.id,
    );
  }

  Future<void> unarchiveProjectThread(
    String projectPath,
    AgentThreadSummary thread,
  ) {
    return projectThreadsController.unarchiveThread(
      projectPath: projectPath,
      threadId: thread.id,
    );
  }

  Future<void> deleteProjectThread(
    String projectPath,
    AgentThreadSummary thread,
  ) {
    return projectThreadsController.deleteThread(
      projectPath: projectPath,
      threadId: thread.id,
    );
  }

  Future<void> forkProjectThread(
    String projectPath,
    AgentThreadSummary thread,
  ) async {
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

  Future<void> startNewThreadForProject(String projectPath) async {
    _sessionCoordinator.cancelPendingRestore();
    if (projectPath != _projectPath) {
      await _loadProject(projectPath, activateThreads: false);
      if (_projectPath != projectPath) {
        return;
      }
    }

    projectThreadsController.clearSelectedThread(projectPath);
    _agentThreadIdsByProject.remove(projectPath);
    agentViewModel.updateWorkspace(
      projectPath: projectPath,
      contextFilePath: _currentFilePath,
      resetConversation: true,
    );
    _requestSessionSave();
    _notifyStateChanged();
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
    projectThreadsController.retainProjects(_projects);

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

    projectThreadsController.registerThreadMapping(projectPath, thread.id);
    projectThreadsController.selectThread(projectPath, thread);
    _agentThreadIdsByProject[projectPath] = thread.id;
    _requestSessionSave();
    await agentViewModel.switchThread(thread);
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
    _syncAgentWorkspace();
    _notifyStateChanged();
    _requestSessionSave();
  }

  Future<void> saveNow() {
    return _sessionCoordinator.saveNow(_currentSessionState());
  }

  Future<void> _loadProject(String path, {bool activateThreads = true}) async {
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

      projectThreadsController.retainProjects(_projects);
      if (activateThreads) {
        projectThreadsController.activateProject(path);
      }
      _syncAgentWorkspace();
      _requestSessionSave();
      _log.info('Opened project folder: $path');
      _notifyStateChanged();
    } catch (error, stackTrace) {
      _log.warning('Could not open project folder: $path', error, stackTrace);
      _statusReporter?.call('Could not open folder: $error');
    } finally {
      if (!_isDisposed) {
        _isLoadingProject = false;
        _notifyStateChanged();
      }
    }
  }

  Future<void> _restoreSession() async {
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
        _syncAgentWorkspace();
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
          WorkspaceNode.findByPath(projectChildren, selectedTreePath) == null) {
        selectedTreePath = null;
      }
    }

    _projects
      ..clear()
      ..addAll(session.projectPaths);
    _projectPath = session.activeProjectPath;
    _workspaceTree = tree;
    _expandedDirectoryPaths = Set<String>.from(session.expandedDirectoryPaths);
    _currentFilePath = session.currentFilePath;
    _selectedTreePath = selectedTreePath;
    _agentThreadIdsByProject
      ..clear()
      ..addAll(session.agentThreadIdsByProject);

    projectThreadsController.restoreSession(
      projectPaths: session.projectPaths,
      activeProjectPath: session.activeProjectPath,
      snapshot: projectThreadsSessionSnapshotFromIdeSessionState(session),
    );
    for (final entry in _agentThreadIdsByProject.entries) {
      projectThreadsController.registerThreadMapping(entry.key, entry.value);
    }
    _syncAgentWorkspace();
    _log.info(
      'Restored IDE session with ${session.projectPaths.length} projects',
    );
    if (result.shouldRequestSave) {
      _requestSessionSave();
    }
    _notifyStateChanged();
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
    _projectPath = null;
    _currentFilePath = null;
    _selectedTreePath = null;
    _expandedDirectoryPaths = <String>{};
    _workspaceTree = const <WorkspaceNode>[];
    _syncAgentWorkspace();
    _requestSessionSave();
    _notifyStateChanged();
  }

  IdeSessionState _currentSessionState() {
    return buildIdeSessionState(
      projectPaths: _projects,
      activeProjectPath: _projectPath,
      currentFilePath: _currentFilePath,
      expandedDirectoryPaths: _currentExpandedDirectoryPaths(),
      selectedTreeKey: _selectedTreePath,
      activeAgentProviderId: agentViewModel.activeProviderId,
      agentThreadIdsByProject: _agentThreadIdsByProject,
      projectThreadsSessionSnapshot: projectThreadsController.sessionSnapshot,
      currentProjectPath: _projectPath,
      currentSessionId: agentViewModel.sessionId,
    );
  }

  Set<String> _currentExpandedDirectoryPaths() {
    return Set<String>.unmodifiable(_expandedDirectoryPaths);
  }

  WorkspaceNode? _findTreeNode(String path) {
    return WorkspaceNode.findByPath(_workspaceTree, path);
  }

  void _syncAgentWorkspace() {
    final projectPath = _projectPath;
    final restoredSessionId = projectPath == null
        ? null
        : _agentThreadIdsByProject[projectPath];
    if (projectPath != null && restoredSessionId != null) {
      projectThreadsController.registerThreadMapping(
        projectPath,
        restoredSessionId,
      );
    }
    // Agent 上下文只传项目路径和当前文件路径；不会读取文件内容。
    agentViewModel.updateWorkspace(
      projectPath: projectPath,
      contextFilePath: _currentFilePath,
      restoredSessionId: restoredSessionId,
    );
    // 项目就绪后预加载模型列表，使输入框下方控件在发送前可用。
    if (projectPath != null) {
      unawaited(agentViewModel.loadModels());
    }
  }

  void _handleAgentChanged() {
    final projectPath = _projectPath;
    final sessionId = agentViewModel.sessionId;
    if (projectPath == null || sessionId == null) {
      return;
    }
    if (_agentThreadIdsByProject[projectPath] == sessionId) {
      return;
    }

    // Agent 创建或恢复 thread 后，把 thread id 写回项目级映射。
    _agentThreadIdsByProject[projectPath] = sessionId;
    projectThreadsController.registerThreadMapping(projectPath, sessionId);
    projectThreadsController.selectThreadId(projectPath, sessionId);
    _requestSessionSave();
  }

  void _handleProjectThreadsChanged() {
    _notifyStateChanged();
    _requestSessionSave();
  }

  void _handleActiveThreadCleared(String projectPath, String threadId) {
    if (_agentThreadIdsByProject[projectPath] == threadId) {
      _agentThreadIdsByProject.remove(projectPath);
    }
    if (projectPath == _projectPath) {
      agentViewModel.updateWorkspace(
        projectPath: projectPath,
        contextFilePath: _currentFilePath,
        resetConversation: true,
      );
    }
    _requestSessionSave();
    _notifyStateChanged();
  }

  void _notifyStateChanged() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_isDisposed) {
      return;
    }
    unawaited(saveNow());
    _isDisposed = true;
    _sessionCoordinator.dispose();
    projectThreadsViewModel.removeListener(_handleProjectThreadsChanged);
    agentViewModel.removeListener(_handleAgentChanged);
    projectThreadsController.dispose();
    projectThreadsViewModel.dispose();
    agentViewModel.dispose();
    agentProviderController.dispose();
    super.dispose();
  }
}

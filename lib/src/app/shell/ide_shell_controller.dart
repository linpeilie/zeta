import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_treeview/flutter_treeview.dart' as tree;

import 'package:zeta/src/core/logging/app_logging.dart';
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
import 'package:zeta/src/features/workspace/presentation/file_node_data.dart';
import 'package:zeta/src/features/workspace/presentation/tree_view_file_node_mapper.dart';
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
    );
    projectThreadsController = ProjectThreadsController(
      providerController: agentProviderController,
      viewModel: projectThreadsViewModel,
    );
    agentViewModel.addListener(_handleAgentChanged);
    projectThreadsViewModel.addListener(_handleProjectThreadsChanged);
    unawaited(agentViewModel.loadSettings());
    unawaited(_restoreSession());
  }

  final IdeDirectoryPicker _directoryPicker;
  final IdeShellStatusReporter? _statusReporter;
  final IdeSessionPersistenceCoordinator _sessionCoordinator;

  final ActiveAgentProviderController agentProviderController;
  late final AgentConversationViewModel agentViewModel;
  late final ProjectThreadsController projectThreadsController;
  final ProjectThreadsViewModel projectThreadsViewModel;

  tree.TreeViewController _treeController = tree.TreeViewController();
  final List<String> _projects = <String>[];
  final Map<String, String> _agentThreadIdsByProject = <String, String>{};
  String? _projectPath;
  String? _currentFilePath;
  bool _isLoadingProject = false;
  bool _isDisposed = false;

  List<String> get projects => List<String>.unmodifiable(_projects);

  String? get activeProjectPath => _projectPath;

  tree.TreeViewController get treeController => _treeController;

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
    final node = _treeController.getNode<FileNodeData>(key);
    if (node == null) {
      return;
    }
    final updatedNode = _nodeWithExpansion(node, expanded);
    _treeController = _treeController
        .withUpdateNode<FileNodeData>(key, updatedNode)
        .copyWith(selectedKey: _treeController.selectedKey);
    _notifyStateChanged();
    _requestSessionSave();
  }

  void handleTreeNodeTap(String key) {
    final node = _treeController.getNode<FileNodeData>(key);
    final data = node?.data;
    if (node == null || data == null) {
      return;
    }

    if (data.isDirectory) {
      final updatedNode = _nodeWithExpansion(node, !node.expanded);
      _treeController = _treeController
          .withUpdateNode<FileNodeData>(key, updatedNode)
          .copyWith(selectedKey: key);
      _notifyStateChanged();
      _requestSessionSave();
      return;
    }

    _treeController = _treeController.copyWith(selectedKey: key);
    _currentFilePath = data.path;
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

      final projectChildren = buildDirectoryChildren(directory);
      if (_isDisposed) {
        return;
      }

      _projectPath = path;
      _currentFilePath = null;
      _treeController = tree.TreeViewController(children: projectChildren);
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

    var treeController = tree.TreeViewController();
    if (session.activeProjectPath != null) {
      // 文件树按需加载，只恢复用户已经展开过的目录。
      final projectChildren = buildDirectoryChildren(
        Directory(session.activeProjectPath!),
        expandedPaths: session.expandedDirectoryPaths,
      );
      treeController = tree.TreeViewController(children: projectChildren);

      final selectedTreeKey = session.selectedTreeKey;
      if (selectedTreeKey != null &&
          selectedTreeKey != session.activeProjectPath &&
          treeController.getNode<FileNodeData>(selectedTreeKey) != null) {
        treeController = treeController.copyWith(selectedKey: selectedTreeKey);
      }
    }

    _projects
      ..clear()
      ..addAll(session.projectPaths);
    _projectPath = session.activeProjectPath;
    _treeController = treeController;
    _currentFilePath = session.currentFilePath;
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

  tree.Node<FileNodeData> _nodeWithExpansion(
    tree.Node<FileNodeData> node,
    bool expanded,
  ) {
    final data = node.data;
    if (expanded && data != null && data.isDirectory && !data.childrenLoaded) {
      // 首次展开目录时才读取下一层，避免打开项目时递归扫描整个仓库。
      return buildDirectoryNode(Directory(data.path), expanded: true);
    }
    return node.copyWith(expanded: expanded);
  }

  void _requestSessionSave() {
    _sessionCoordinator.requestSave(_currentSessionState());
  }

  IdeSessionState _currentSessionState() {
    return buildIdeSessionState(
      projectPaths: _projects,
      activeProjectPath: _projectPath,
      currentFilePath: _currentFilePath,
      expandedDirectoryPaths: _expandedDirectoryPaths(),
      selectedTreeKey: _treeController.selectedKey,
      activeAgentProviderId: agentViewModel.activeProviderId,
      agentThreadIdsByProject: _agentThreadIdsByProject,
      projectThreadsSessionSnapshot: projectThreadsController.sessionSnapshot,
      currentProjectPath: _projectPath,
      currentSessionId: agentViewModel.sessionId,
    );
  }

  Set<String> _expandedDirectoryPaths() {
    final paths = <String>{};

    void visit(List<tree.Node> nodes) {
      for (final node in nodes) {
        final data = node.data as FileNodeData?;
        if ((data?.isDirectory ?? node.isParent) && node.expanded) {
          paths.add(node.key);
        }
        visit(node.children);
      }
    }

    visit(_treeController.children);
    return paths;
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

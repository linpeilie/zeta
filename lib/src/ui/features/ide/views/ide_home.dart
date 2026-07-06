import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_treeview/flutter_treeview.dart' as tree;
import 'package:multi_split_view/multi_split_view.dart';

import '../../../../app/app_constants.dart';
import '../../../../app/menu_action_bridge.dart';
import '../../../../core/logging/app_logging.dart';
import '../../../../data/agent/agent_provider_config_store.dart';
import '../../../../data/file_system/file_node_data.dart';
import '../../../../data/file_system/file_tree_builder.dart';
import '../../../../data/file_system/path_utils.dart';
import '../../../../data/session/ide_session_state.dart';
import '../../../../data/session/ide_session_store.dart';
import '../../../../domain/agent/agent_models.dart';
import '../../../../domain/agent/agent_provider.dart';
import '../../../core/app_theme.dart';
import '../../../core/pane_widgets.dart';
import '../../../core/window_frame.dart';
import '../view_models/active_agent_provider_controller.dart';
import '../view_models/agent_conversation_view_model.dart';
import '../view_models/project_threads_view_model.dart';
import 'agent_pane.dart';
import 'file_tree_pane.dart';
import 'project_list_pane.dart';

final _log = loggerFor('zeta.ui.ide_home');

/// IDE 主界面。
///
/// 当前布局是 Projects / Agent / Files 三栏；中间栏通过 [AgentConversationViewModel]
/// 连接 provider 层，右侧文件树只负责选择当前上下文文件。
class IdeHome extends StatefulWidget {
  const IdeHome({
    required this.directoryPicker,
    required this.enableNativeWindowFrame,
    required this.sessionStore,
    required this.agentProviderFactory,
    required this.agentProviderConfigStore,
    super.key,
  });

  final Future<String?> Function() directoryPicker;
  final bool enableNativeWindowFrame;
  final IdeSessionStore sessionStore;
  final AgentProviderFactory agentProviderFactory;
  final AgentProviderConfigStore agentProviderConfigStore;

  @override
  State<IdeHome> createState() => _IdeHomeState();
}

class _IdeHomeState extends State<IdeHome> {
  late final ActiveAgentProviderController _agentProviderController;
  late final AgentConversationViewModel _agentViewModel;
  late final ProjectThreadsViewModel _projectThreadsViewModel;
  late final MultiSplitViewController _splitController;
  Timer? _sessionSaveTimer;

  /// 会话恢复令牌。
  ///
  /// 用户在慢恢复期间手动打开项目时递增，防止旧恢复结果覆盖用户新选择。
  int _sessionRestoreToken = 0;

  tree.TreeViewController _treeController = tree.TreeViewController();
  final List<String> _projects = <String>[];

  /// 每个项目最近关联的 Agent thread id。
  final Map<String, String> _agentThreadIdsByProject = <String, String>{};
  String? _projectPath;
  String? _currentFilePath;
  bool _isLoadingProject = false;
  bool _isRestoringSession = false;
  bool _shouldSaveSessionAfterRestore = false;

  @override
  void initState() {
    super.initState();
    _agentProviderController = ActiveAgentProviderController(
      providerFactory: widget.agentProviderFactory,
      configStore: widget.agentProviderConfigStore,
    );
    _agentViewModel = AgentConversationViewModel(
      providerController: _agentProviderController,
    );
    _projectThreadsViewModel = ProjectThreadsViewModel(
      providerController: _agentProviderController,
    );
    _agentViewModel.addListener(_handleAgentChanged);
    _projectThreadsViewModel.addListener(_handleProjectThreadsChanged);
    unawaited(_agentViewModel.loadSettings());
    _splitController = MultiSplitViewController(
      areas: [
        Area(id: 'projects', size: 220, min: 180, max: 340),
        Area(id: 'agent', flex: 1, min: 360),
        Area(id: 'files', size: 280, min: 220, max: 460),
      ],
    );
    unawaited(_restoreSession(++_sessionRestoreToken));
    // 生产环境注册原生菜单的「打开项目」回调，与工具栏按钮走同一逻辑。
    if (widget.enableNativeWindowFrame) {
      MenuActionBridge.instance.setOpenProject(_handleMenuOpenProject);
    }
  }

  @override
  void dispose() {
    _sessionSaveTimer?.cancel();
    unawaited(_saveSessionState());
    if (widget.enableNativeWindowFrame) {
      MenuActionBridge.instance.setOpenProject(null);
    }
    _projectThreadsViewModel.removeListener(_handleProjectThreadsChanged);
    _agentViewModel.removeListener(_handleAgentChanged);
    _projectThreadsViewModel.dispose();
    _agentViewModel.dispose();
    _agentProviderController.dispose();
    _splitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = WindowFrame(
      enableNativeWindowFrame: widget.enableNativeWindowFrame,
      child: Padding(
        padding: const EdgeInsets.only(
          left: idePanelGap,
          right: idePanelGap,
          bottom: idePanelGap,
        ),
        child: MultiSplitViewTheme(
          data: MultiSplitViewThemeData(
            dividerThickness: idePanelGap,
            dividerPainter: DividerPainters.background(
              color: ideFrameColor,
              highlightedColor: ideFrameColor,
            ),
          ),
          child: MultiSplitView(
            controller: _splitController,
            axis: Axis.horizontal,
            pushDividers: true,
            builder: _buildSplitArea,
          ),
        ),
      ),
    );

    return Scaffold(body: body);
  }

  Widget _buildSplitArea(BuildContext context, Area area) {
    return switch (area.id) {
      'projects' => PanelCard(
        key: const ValueKey('projects-panel-card'),
        child: ProjectListPane(
          projects: _projects,
          activeProject: _projectPath,
          threadStateFor: _projectThreadsViewModel.stateFor,
          onOpenProject: _openProject,
          onSelectProject: _selectKnownProject,
          onSelectThread: (projectPath, thread) {
            unawaited(_selectProjectThread(projectPath, thread));
          },
          onLoadMoreThreads: (projectPath) {
            unawaited(_projectThreadsViewModel.loadMore(projectPath));
          },
          onRetryThreads: (projectPath) {
            unawaited(_projectThreadsViewModel.loadInitial(projectPath));
          },
        ),
      ),
      'files' => PanelCard(
        key: const ValueKey('files-panel-card'),
        child: FileTreePane(
          controller: _treeController,
          projectPath: _projectPath,
          isLoading: _isLoadingProject,
          onNodeTap: _handleTreeNodeTap,
          onExpansionChanged: _handleTreeExpansionChanged,
        ),
      ),
      _ => ColoredBox(
        key: const ValueKey('agent-pane-host'),
        color: ideFrameColor,
        child: AgentPane(viewModel: _agentViewModel),
      ),
    };
  }

  Future<void> _openProject() async {
    final path = await widget.directoryPicker();
    if (path == null || path.trim().isEmpty) {
      return;
    }

    _cancelPendingSessionRestore();
    await _loadProject(path);
  }

  /// 原生菜单「文件 - 打开项目」入口，与工具栏按钮一致。
  void _handleMenuOpenProject() {
    unawaited(_openProject());
  }

  Future<void> _selectKnownProject(String path) async {
    _cancelPendingSessionRestore();
    if (path != _projectPath) {
      await _loadProject(path, activateThreads: false);
    }
    await _projectThreadsViewModel.toggleProject(path);
    _scheduleSessionSave();
  }

  Future<void> _loadProject(String path, {bool activateThreads = true}) async {
    _log.info('Opening project folder: $path');
    setState(() {
      _isLoadingProject = true;
    });

    try {
      final directory = Directory(path);
      if (!await directory.exists()) {
        throw FileSystemException('Directory does not exist', path);
      }

      final projectChildren = buildDirectoryChildren(directory);
      if (!mounted) {
        return;
      }

      setState(() {
        _projectPath = path;
        _currentFilePath = null;
        _treeController = tree.TreeViewController(children: projectChildren);
        if (!_projects.contains(path)) {
          _projects.insert(0, path);
        }
      });
      _projectThreadsViewModel.retainProjects(_projects);
      if (activateThreads) {
        _projectThreadsViewModel.activateProject(path);
      }
      // 项目切换后立即同步 Agent 上下文，避免旧文件路径继续出现在中间栏。
      _syncAgentWorkspace();
      _scheduleSessionSave();
      _log.info('Opened project folder: $path');
    } catch (error, stackTrace) {
      _log.warning('Could not open project folder: $path', error, stackTrace);
      if (mounted) {
        _showStatus('Could not open folder: $error');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingProject = false;
        });
      }
    }
  }

  void _handleTreeExpansionChanged(String key, bool expanded) {
    final node = _treeController.getNode<FileNodeData>(key);
    if (node == null) {
      return;
    }
    final updatedNode = _nodeWithExpansion(node, expanded);
    setState(() {
      _treeController = _treeController
          .withUpdateNode<FileNodeData>(key, updatedNode)
          .copyWith(selectedKey: _treeController.selectedKey);
    });
    _scheduleSessionSave();
  }

  void _handleTreeNodeTap(String key) {
    final node = _treeController.getNode<FileNodeData>(key);
    final data = node?.data;
    if (node == null || data == null) {
      return;
    }

    if (data.isDirectory) {
      final updatedNode = _nodeWithExpansion(node, !node.expanded);
      setState(() {
        _treeController = _treeController
            .withUpdateNode<FileNodeData>(key, updatedNode)
            .copyWith(selectedKey: key);
      });
      _scheduleSessionSave();
      return;
    }

    setState(() {
      _treeController = _treeController.copyWith(selectedKey: key);
      _currentFilePath = data.path;
    });
    // 文件树选择只更新 Agent 上下文，不再打开编辑器或保存文件内容。
    _syncAgentWorkspace();
    _scheduleSessionSave();
  }

  /// 恢复上次 IDE 会话。
  ///
  /// 恢复时会清理不存在的项目/文件；如果期间用户主动打开了别的项目，令牌检查会
  /// 让这次恢复结果失效。
  Future<void> _restoreSession(int restoreToken) async {
    _isRestoringSession = true;
    var shouldSaveCleanedState = false;

    try {
      final session = await widget.sessionStore.load();
      if (!_isActiveSessionRestore(restoreToken) || session == null) {
        return;
      }
      shouldSaveCleanedState = true;

      final existingProjects = existingDirectoryPaths(session.projectPaths);
      final activeProjectPath =
          existingProjects.contains(session.activeProjectPath)
          ? session.activeProjectPath
          : null;

      var treeController = tree.TreeViewController();
      String? currentFilePath;
      final agentThreadIdsByProject = Map<String, String>.from(
        session.agentThreadIdsByProject,
      );

      if (activeProjectPath != null) {
        // 文件树依旧按需加载，只恢复用户已经展开过的目录。
        final projectChildren = buildDirectoryChildren(
          Directory(activeProjectPath),
          expandedPaths: session.expandedDirectoryPaths,
        );
        treeController = tree.TreeViewController(children: projectChildren);

        final selectedTreeKey = session.selectedTreeKey;
        if (selectedTreeKey != null &&
            selectedTreeKey != activeProjectPath &&
            treeController.getNode<FileNodeData>(selectedTreeKey) != null) {
          treeController = treeController.copyWith(
            selectedKey: selectedTreeKey,
          );
        }

        final restoredFilePath = session.currentFilePath;
        if (restoredFilePath != null && File(restoredFilePath).existsSync()) {
          currentFilePath = restoredFilePath;
        }
      }

      if (!_isActiveSessionRestore(restoreToken)) {
        return;
      }

      setState(() {
        _projects
          ..clear()
          ..addAll(existingProjects);
        _projectPath = activeProjectPath;
        _treeController = treeController;
        _currentFilePath = currentFilePath;
        _agentThreadIdsByProject
          ..clear()
          ..addAll(agentThreadIdsByProject);
      });
      final selectedThreadIds = Map<String, String>.from(
        session.selectedThreadIdsByProject,
      );
      for (final entry in agentThreadIdsByProject.entries) {
        selectedThreadIds.putIfAbsent(entry.key, () => entry.value);
      }
      _projectThreadsViewModel.restoreSession(
        projectPaths: existingProjects,
        activeProjectPath: activeProjectPath,
        expansionByProject: session.projectThreadExpansionByProject,
        cachedThreadsByProject: session.cachedThreadsByProject,
        selectedThreadIdsByProject: selectedThreadIds,
      );
      _syncAgentWorkspace();
      _log.info(
        'Restored IDE session with ${existingProjects.length} projects',
      );
    } catch (error, stackTrace) {
      _log.warning('Could not restore IDE session', error, stackTrace);
      if (!_isActiveSessionRestore(restoreToken)) {
        return;
      }
      setState(() {
        _currentFilePath = null;
      });
      _syncAgentWorkspace();
      shouldSaveCleanedState = true;
    } finally {
      _isRestoringSession = false;
      final isCurrentRestore = restoreToken == _sessionRestoreToken;
      final shouldSave =
          (isCurrentRestore && shouldSaveCleanedState) ||
          _shouldSaveSessionAfterRestore;
      _shouldSaveSessionAfterRestore = false;
      if (shouldSave) {
        _scheduleSessionSave();
      }
    }
  }

  bool _isActiveSessionRestore(int restoreToken) {
    return mounted && restoreToken == _sessionRestoreToken;
  }

  void _cancelPendingSessionRestore() {
    if (_isRestoringSession) {
      _sessionRestoreToken += 1;
    }
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

  void _scheduleSessionSave() {
    if (_isRestoringSession) {
      // 恢复期间的状态变化先延后保存，避免把半恢复状态写入持久化。
      _shouldSaveSessionAfterRestore = true;
      return;
    }

    _sessionSaveTimer?.cancel();
    _sessionSaveTimer = Timer(sessionSaveDelay, () {
      unawaited(_saveSessionState());
    });
  }

  Future<void> _saveSessionState() async {
    if (_isRestoringSession) {
      return;
    }

    try {
      await widget.sessionStore.save(_currentSessionState());
    } catch (error, stackTrace) {
      _log.warning('Could not save IDE session', error, stackTrace);
      // 会话恢复只是便利功能，持久化失败不应该打断当前工作区。
    }
  }

  IdeSessionState _currentSessionState() {
    final agentThreadIds = Map<String, String>.from(_agentThreadIdsByProject);
    final selectedThreadIds = Map<String, String>.from(
      _projectThreadsViewModel.selectedThreadIdsByProject,
    );
    final projectPath = _projectPath;
    final sessionId = _agentViewModel.sessionId;
    if (projectPath != null && sessionId != null) {
      // 保存当前项目对应的 Agent thread，方便下次启动尝试恢复同一会话。
      agentThreadIds[projectPath] = sessionId;
      selectedThreadIds[projectPath] = sessionId;
    }

    return IdeSessionState(
      projectPaths: List<String>.unmodifiable(_projects),
      activeProjectPath: _projectPath,
      currentFilePath: _currentFilePath,
      expandedDirectoryPaths: _expandedDirectoryPaths(),
      selectedTreeKey: _treeController.selectedKey,
      activeAgentProviderId: _agentViewModel.activeProviderId,
      agentThreadIdsByProject: agentThreadIds,
      projectThreadExpansionByProject:
          _projectThreadsViewModel.projectExpansionByProject,
      cachedThreadsByProject: _projectThreadsViewModel.cachedThreadsByProject,
      selectedThreadIdsByProject: selectedThreadIds,
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
    // Agent 上下文只传项目路径和当前文件路径；不会读取文件内容。
    _agentViewModel.updateWorkspace(
      projectPath: projectPath,
      contextFilePath: _currentFilePath,
      restoredSessionId: projectPath == null
          ? null
          : _agentThreadIdsByProject[projectPath],
    );
    // 项目就绪后预加载模型列表，使输入框下方的模型/思考/速率控件在发送前就可用。
    // loadModels 内部幂等，重复调用只会命中缓存。
    if (projectPath != null) {
      unawaited(_agentViewModel.loadModels());
    }
  }

  void _handleAgentChanged() {
    final projectPath = _projectPath;
    final sessionId = _agentViewModel.sessionId;
    if (projectPath == null || sessionId == null) {
      return;
    }
    if (_agentThreadIdsByProject[projectPath] == sessionId) {
      return;
    }
    // Agent 创建或恢复 thread 后，把 thread id 写回项目级映射。
    _agentThreadIdsByProject[projectPath] = sessionId;
    _projectThreadsViewModel.selectThreadId(projectPath, sessionId);
    _scheduleSessionSave();
  }

  void _handleProjectThreadsChanged() {
    if (mounted) {
      setState(() {});
    }
    _scheduleSessionSave();
  }

  Future<void> _selectProjectThread(
    String projectPath,
    AgentThreadSummary thread,
  ) async {
    if (projectPath != _projectPath) {
      await _loadProject(projectPath, activateThreads: false);
    }

    _projectThreadsViewModel.selectThread(projectPath, thread);
    _agentThreadIdsByProject[projectPath] = thread.id;
    _scheduleSessionSave();
    await _agentViewModel.switchThread(thread);
  }

  void _showStatus(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:window_manager/window_manager.dart';

import 'package:zeta/src/app/menu_action_bridge.dart';
import 'package:zeta/src/app/shell/ide_shell_controller.dart';
import 'package:zeta/src/core/utils/system_file_manager.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_controller.dart';
import 'package:zeta/src/features/agent_management/data/codex_agent_management_repository.dart';
import 'package:zeta/src/features/agent_management/data/grok_agent_management_repository.dart';
import 'package:zeta/src/features/agent_management/domain/agent_cli_management_repository.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';
import 'package:zeta/src/features/ide_session/data/ide_session_store.dart';
import 'package:zeta/src/features/settings/application/appearance_settings_controller.dart';
import 'package:zeta/src/features/settings/presentation/settings_page.dart';
import 'package:zeta/src/features/usage_statistics/application/usage_statistics_controller.dart';
import 'package:zeta/src/features/usage_statistics/data/codex_usage_statistics_repository.dart';
import 'package:zeta/src/features/usage_statistics/data/usage_statistics_index_store.dart';
import 'package:zeta/src/features/usage_statistics/presentation/usage_statistics_page.dart';
import 'package:zeta/src/features/agent/presentation/agent_pane.dart';
import 'package:zeta/src/features/workspace/presentation/file_tree_pane.dart';
import 'package:zeta/src/ui/core/ide_activity_rail.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/ide_resize_handle.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/ide_toast.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';
import 'package:zeta/src/ui/core/window_frame.dart';
import 'package:zeta/src/ui/core/workbench/ide_workbench_scaffold.dart';
import 'package:zeta/src/ui/features/ide/views/project_home_page.dart';
import 'package:zeta/src/ui/features/ide/views/project_list_pane.dart';

typedef AgentProviderAvailabilityLoader =
    Future<List<AgentProviderConfig>> Function();

/// IDE 主界面。
///
/// 当前布局是左右图标栏、左右活动面板与中间 Agent 主编辑区组成的五列结构；
/// 具体项目、会话和 Agent thread 编排由 [IdeShellController] 承接。
class IdeHome extends StatefulWidget {
  const IdeHome({
    required this.directoryPicker,
    required this.enableNativeWindowFrame,
    required this.sessionStore,
    required this.agentProviderFactory,
    required this.agentProviderConfigStore,
    required this.usageStatisticsIndexStore,
    required this.projectLocationOpener,
    required this.appearanceController,
    this.agentProviderAvailabilityLoader,
    this.showWindowControls = true,
    super.key,
  });

  final Future<String?> Function() directoryPicker;
  final bool enableNativeWindowFrame;
  final IdeSessionStore sessionStore;
  final AgentProviderFactory agentProviderFactory;
  final AgentProviderConfigStore agentProviderConfigStore;
  final UsageStatisticsIndexStore usageStatisticsIndexStore;
  final ProjectLocationOpener projectLocationOpener;
  final AppearanceSettingsController appearanceController;
  final AgentProviderAvailabilityLoader? agentProviderAvailabilityLoader;
  final bool showWindowControls;

  @override
  State<IdeHome> createState() => _IdeHomeState();
}

class _IdeHomeState extends State<IdeHome> {
  static const double _initialPanelWidth = IdeMetrics.sidePaneDefaultWidth;
  static const double _minPanelWidth = IdeMetrics.sidePaneMinWidth;
  static const double _maxPanelWidth = IdeMetrics.sidePaneMaxWidth;
  static const double _initialPanelRatio = 0.5;
  static const double _minPanelRatio = 0.1;
  static const double _maxPanelRatio = 0.9;

  late final IdeShellController _shellController;
  late final AgentManagementController _agentManagementController;
  late final UsageStatisticsController _usageStatisticsController;

  bool _leftTopVisible = true;
  bool _leftBottomVisible = false;
  bool _rightTopVisible = false;
  bool _rightBottomVisible = false;
  bool _settingsPageMounted = false;
  bool _usageStatisticsPageMounted = false;
  IdeWorkbenchOverlay? _activeOverlay;
  FocusNode? _overlayTriggerFocusNode;
  double _leftPanelWidth = _initialPanelWidth;
  double _rightPanelWidth = _initialPanelWidth;
  double _leftTopRatio = _initialPanelRatio;
  double _rightTopRatio = _initialPanelRatio;
  sf.ToastOverlay? _statusToast;
  _IdeHomePage _page = _IdeHomePage.home;
  SettingsSection _settingsSection = SettingsSection.appearance;
  final FocusNode _leftProjectsFocusNode = FocusNode(
    debugLabel: 'LeftProjectsRailAction',
  );
  final FocusNode _leftContextFocusNode = FocusNode(
    debugLabel: 'LeftContextRailAction',
  );
  final FocusNode _rightFilesFocusNode = FocusNode(
    debugLabel: 'RightFilesRailAction',
  );
  final FocusNode _rightToolsFocusNode = FocusNode(
    debugLabel: 'RightToolsRailAction',
  );
  final FocusNode _settingsNavigationFocusNode = FocusNode(
    debugLabel: 'SettingsNavigationRailAction',
  );
  final GlobalKey<SettingsPageCanvasState> _settingsCanvasKey =
      GlobalKey<SettingsPageCanvasState>();

  @override
  void initState() {
    super.initState();
    unawaited(widget.appearanceController.load());
    _shellController = IdeShellController(
      directoryPicker: widget.directoryPicker,
      sessionStore: widget.sessionStore,
      agentProviderFactory: widget.agentProviderFactory,
      agentProviderConfigStore: widget.agentProviderConfigStore,
      projectLocationOpener: widget.projectLocationOpener,
      statusReporter: _showStatus,
    )..addListener(_handleShellChanged);
    _agentManagementController = AgentManagementController(
      repositories: <String, AgentCliManagementRepository>{
        AgentDefinition.codex.id: CodexAgentManagementRepository(
          providerFactory: widget.agentProviderFactory,
        ),
        AgentDefinition.grok.id: GrokAgentManagementRepository(
          providerFactory: widget.agentProviderFactory,
        ),
      },
      providerController: _shellController.agentProviderController,
      runtimeStateProvider: _managementRuntimeState,
      runtimeListenable: _shellController,
    );
    _usageStatisticsController = UsageStatisticsController(
      repository: CodexUsageStatisticsRepository(
        providerLoader: _shellController.agentProviderController.activeProvider,
        indexStore: widget.usageStatisticsIndexStore,
      ),
    );
    // 生产环境注册原生菜单的「打开项目」回调，与工具栏按钮走同一逻辑。
    if (widget.enableNativeWindowFrame) {
      MenuActionBridge.instance.setOpenProject(_handleMenuOpenProject);
    }
  }

  @override
  void dispose() {
    if (widget.enableNativeWindowFrame) {
      MenuActionBridge.instance.setOpenProject(null);
    }
    _shellController.removeListener(_handleShellChanged);
    _usageStatisticsController.dispose();
    _agentManagementController.dispose();
    _shellController.dispose();
    _leftProjectsFocusNode.dispose();
    _leftContextFocusNode.dispose();
    _rightFilesFocusNode.dispose();
    _rightToolsFocusNode.dispose();
    _settingsNavigationFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = WindowFrame(
      key: const ValueKey('ide-window-frame'),
      enableNativeWindowFrame: widget.enableNativeWindowFrame,
      menus: _windowMenus,
      titleBarActions: <WindowTitleBarAction>[
        WindowTitleBarAction(
          key: const ValueKey('titlebar-usage-statistics-action'),
          icon: Icons.query_stats_rounded,
          tooltip: 'Usage statistics',
          semanticLabel: 'Open usage statistics page',
          active: _page == _IdeHomePage.usageStatistics,
          onPressed: _openUsageStatisticsPage,
        ),
        WindowTitleBarAction(
          key: const ValueKey('titlebar-settings-action'),
          icon: Icons.settings_rounded,
          tooltip: 'Settings',
          semanticLabel: 'Open settings page',
          active: _page == _IdeHomePage.settings,
          onPressed: _openSettingsPage,
        ),
      ],
      showWindowControls: widget.showWindowControls,
      child: Padding(
        padding: const EdgeInsets.all(IdeSpacing.space8),
        child: _buildWorkbench(),
      ),
    );

    return body;
  }

  List<WindowMenu> get _windowMenus {
    if (!widget.enableNativeWindowFrame ||
        !(Platform.isWindows || Platform.isLinux)) {
      return const <WindowMenu>[];
    }
    return [
      WindowMenu(
        key: const ValueKey('window-menu-file'),
        label: '文件',
        items: [
          WindowMenuItem(
            key: const ValueKey('window-menu-open-project'),
            label: '打开项目',
            onPressed: _handleMenuOpenProject,
          ),
          WindowMenuItem(
            key: const ValueKey('window-menu-exit'),
            label: '退出',
            onPressed: _handleMenuExit,
          ),
        ],
      ),
    ];
  }

  /// 所有主要页面共享一个 Workbench：
  ///
  /// - Agent 首页：Wide/Medium 内联 Navigation，Inspector 仅 Wide 内联；其余
  ///   模式通过 Workbench Overlay 展示对应 Pane。
  /// - 设置与 Agent 管理：Wide/Medium 内联设置 Navigation，Compact 按需打开
  ///   Navigation Overlay，不提供 Inspector。
  /// - 使用统计：只提供 Canvas，左右 Rail 仍保留在同一骨架中。
  Widget _buildWorkbench() {
    final homePage = _page == _IdeHomePage.home;
    final settingsPage = _page == _IdeHomePage.settings;
    final navigationVisible = settingsPage
        ? true
        : homePage && (_leftTopVisible || _leftBottomVisible);
    final inspectorVisible =
        homePage && (_rightTopVisible || _rightBottomVisible);
    return IdeWorkbenchScaffold(
      key: const ValueKey('ide-workbench'),
      leadingRailBuilder: _buildLeadingRail,
      navigationPane: settingsPage
          ? SettingsNavigationPane(
              activeSection: _settingsSection,
              showAgentManagement: true,
              onBackPressed: () {
                unawaited(_closeSettingsPage());
              },
              onSectionSelected: (section) {
                unawaited(_selectSettingsSection(section));
              },
            )
          : homePage
          ? _buildLeftPanel()
          : null,
      navigationResizeHandle: navigationVisible
          ? _buildNavigationResizeHandle()
          : null,
      navigationVisible: navigationVisible,
      navigationWidth: _leftPanelWidth,
      canvas: _buildRetainedCanvasStack(),
      inspectorPane: homePage ? _buildRightPanel() : null,
      inspectorResizeHandle: inspectorVisible
          ? _buildInspectorResizeHandle()
          : null,
      inspectorVisible: inspectorVisible,
      inspectorWidth: _rightPanelWidth,
      trailingRailBuilder: _buildTrailingRail,
      activeOverlay: _activeOverlay,
      onDismissOverlay: _closeActiveOverlay,
      overlayTriggerFocusNode: _overlayTriggerFocusNode,
    );
  }

  Widget _buildRetainedCanvasStack() {
    return IndexedStack(
      key: const ValueKey('workbench-page-stack'),
      index: _page.index,
      children: [
        TickerMode(
          enabled: _page == _IdeHomePage.home,
          child: KeyedSubtree(
            key: const ValueKey('agent-pane-host'),
            child: _buildRetainedAgentPaneStack(),
          ),
        ),
        TickerMode(
          enabled: _page == _IdeHomePage.settings,
          child: _settingsPageMounted
              ? SettingsPageCanvas(
                  key: _settingsCanvasKey,
                  activeSection: _settingsSection,
                  appearanceController: widget.appearanceController,
                  agentManagementController: _agentManagementController,
                )
              : const SizedBox.shrink(),
        ),
        TickerMode(
          enabled: _page == _IdeHomePage.usageStatistics,
          child: _usageStatisticsPageMounted
              ? UsageStatisticsPage(
                  key: const ValueKey('usage-statistics-page-host'),
                  controller: _usageStatisticsController,
                  onBackPressed: _closeUsageStatisticsPage,
                  onOpenAgentManagement: _openAgentManagementFromUsage,
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildRetainedAgentPaneStack() {
    final entries = _shellController.agentWorkspaceEntries;
    final projectPath = _shellController.activeProjectPath;
    if (entries.isEmpty && projectPath == null) {
      return const SizedBox.shrink();
    }
    final selectedEntryId = _shellController.selectedAgentWorkspaceEntryId;
    final selectedEntryIndex = entries.indexWhere(
      (entry) => entry.entryId == selectedEntryId,
    );
    final selectedIndex = _shellController.isProjectHomeActive
        ? 0
        : selectedEntryIndex < 0
        ? 0
        : selectedEntryIndex + 1;
    return IndexedStack(
      key: const ValueKey('agent-pane-entry-stack'),
      index: selectedIndex,
      children: [
        projectPath == null || !_shellController.isProjectHomeActive
            ? const SizedBox.shrink()
            : KeyedSubtree(
                key: ValueKey<String>('project-home-$projectPath'),
                child: ProjectHomePage(
                  projectPath: projectPath,
                  threadState: _shellController.projectThreadStateFor(
                    projectPath,
                  ),
                  loadAvailableProviders: _loadAvailableAgentProviders,
                  onNewThread: (providerId) {
                    unawaited(
                      _shellController.startNewThreadForProject(
                        projectPath,
                        providerId: providerId,
                      ),
                    );
                  },
                  onSelectThread: (thread) {
                    unawaited(
                      _shellController.selectProjectThread(projectPath, thread),
                    );
                  },
                  onRetryThreads: () {
                    unawaited(_shellController.retryThreads(projectPath));
                  },
                ),
              ),
        for (final entry in entries)
          KeyedSubtree(
            key: ValueKey<String>('agent-pane-entry-${entry.entryId}'),
            child: AgentPane(viewModel: entry.viewModel),
          ),
      ],
    );
  }

  Widget _buildLeadingRail(BuildContext context, IdeWorkbenchLayoutMode mode) {
    if (_page == _IdeHomePage.settings) {
      final compact = mode == IdeWorkbenchLayoutMode.compact;
      return IdeActivityRail(
        leadingActions: [
          IdeRailAction(
            key: const ValueKey('settings-navigation-action'),
            icon: Icons.tune_rounded,
            tooltip: 'Settings navigation',
            semanticLabel: 'Toggle settings navigation',
            active:
                !compact || _activeOverlay == IdeWorkbenchOverlay.navigation,
            focusNode: _settingsNavigationFocusNode,
            onPressed: () {
              if (compact) {
                _toggleSettingsNavigationOverlay();
              }
            },
          ),
        ],
      );
    }
    if (_page == _IdeHomePage.usageStatistics) {
      return IdeActivityRail(
        leadingActions: [
          IdeRailAction(
            key: const ValueKey('usage-home-action'),
            icon: Icons.smart_toy_outlined,
            tooltip: 'Agent',
            semanticLabel: 'Return to Agent page',
            active: false,
            onPressed: _closeUsageStatisticsPage,
          ),
        ],
      );
    }

    final useOverlay = mode == IdeWorkbenchLayoutMode.compact;
    return IdeActivityRail(
      leadingActions: [
        IdeRailAction(
          key: const ValueKey('left-projects-action'),
          icon: Icons.account_tree_rounded,
          tooltip: 'Projects',
          semanticLabel: 'Toggle projects panel',
          active:
              _leftTopVisible &&
              (!useOverlay || _activeOverlay == IdeWorkbenchOverlay.navigation),
          focusNode: _leftProjectsFocusNode,
          onPressed: () {
            _toggleLeftPanel(
              isTop: true,
              useOverlay: useOverlay,
              triggerFocusNode: _leftProjectsFocusNode,
            );
          },
        ),
      ],
      trailingActions: [
        IdeRailAction(
          key: const ValueKey('left-context-action'),
          icon: Icons.data_object_rounded,
          tooltip: 'Context',
          semanticLabel: 'Toggle context panel',
          active:
              _leftBottomVisible &&
              (!useOverlay || _activeOverlay == IdeWorkbenchOverlay.navigation),
          focusNode: _leftContextFocusNode,
          onPressed: () {
            _toggleLeftPanel(
              isTop: false,
              useOverlay: useOverlay,
              triggerFocusNode: _leftContextFocusNode,
            );
          },
        ),
      ],
    );
  }

  Widget _buildTrailingRail(BuildContext context, IdeWorkbenchLayoutMode mode) {
    if (_page != _IdeHomePage.home) {
      return const IdeActivityRail(leadingActions: <IdeRailAction>[]);
    }
    final useOverlay = mode != IdeWorkbenchLayoutMode.wide;
    return IdeActivityRail(
      leadingActions: [
        IdeRailAction(
          key: const ValueKey('right-files-action'),
          icon: Icons.folder_rounded,
          tooltip: 'Files',
          semanticLabel: 'Toggle files panel',
          active:
              _rightTopVisible &&
              (!useOverlay || _activeOverlay == IdeWorkbenchOverlay.inspector),
          focusNode: _rightFilesFocusNode,
          onPressed: () {
            _toggleRightPanel(
              isTop: true,
              useOverlay: useOverlay,
              triggerFocusNode: _rightFilesFocusNode,
            );
          },
        ),
      ],
      trailingActions: [
        IdeRailAction(
          key: const ValueKey('right-tools-action'),
          icon: Icons.build_circle_rounded,
          tooltip: 'Tools',
          semanticLabel: 'Toggle tools panel',
          active:
              _rightBottomVisible &&
              (!useOverlay || _activeOverlay == IdeWorkbenchOverlay.inspector),
          focusNode: _rightToolsFocusNode,
          onPressed: () {
            _toggleRightPanel(
              isTop: false,
              useOverlay: useOverlay,
              triggerFocusNode: _rightToolsFocusNode,
            );
          },
        ),
      ],
    );
  }

  Widget _buildNavigationResizeHandle() {
    return IdeResizeHandle(
      key: const ValueKey('left-width-resize-handle'),
      axis: IdeResizeHandleAxis.horizontal,
      semanticLabel: 'Resize left panel width',
      onDragUpdate: (details) {
        setState(() {
          _leftPanelWidth = (_leftPanelWidth + details.delta.dx).clamp(
            _minPanelWidth,
            _maxPanelWidth,
          );
        });
      },
    );
  }

  Widget _buildInspectorResizeHandle() {
    return IdeResizeHandle(
      key: const ValueKey('right-width-resize-handle'),
      axis: IdeResizeHandleAxis.horizontal,
      semanticLabel: 'Resize right panel width',
      onDragUpdate: (details) {
        setState(() {
          _rightPanelWidth = (_rightPanelWidth - details.delta.dx).clamp(
            _minPanelWidth,
            _maxPanelWidth,
          );
        });
      },
    );
  }

  Widget _buildProjectsPanel() {
    return PanelCard(
      key: const ValueKey('projects-panel-card'),
      showBorder: false,
      child: ProjectListPane(
        projects: _shellController.projects,
        activeProject: _shellController.activeProjectPath,
        threadStateFor: _shellController.projectThreadStateFor,
        onOpenProject: _openProject,
        onSelectProject: (path) {
          unawaited(_shellController.selectKnownProject(path));
        },
        onSelectThread: (projectPath, thread) {
          unawaited(_shellController.selectProjectThread(projectPath, thread));
        },
        onLoadMoreThreads: (projectPath) {
          unawaited(_shellController.loadMoreThreads(projectPath));
        },
        onRetryThreads: (projectPath) {
          unawaited(_shellController.retryThreads(projectPath));
        },
        loadAvailableProviders: _loadAvailableAgentProviders,
        capabilitiesForProvider:
            _shellController.agentProviderController.capabilitiesForProviderId,
        onNewThread: (projectPath, providerId) {
          unawaited(
            _shellController.startNewThreadForProject(
              projectPath,
              providerId: providerId,
            ),
          );
        },
        onOpenProjectLocation: (projectPath) {
          unawaited(
            _shellController.openProjectInSystemFileManager(projectPath),
          );
        },
        onRemoveProject: (projectPath) {
          unawaited(_shellController.removeProject(projectPath));
        },
        onRenameThread: (projectPath, threadId, name) {
          unawaited(
            _shellController.renameProjectThread(projectPath, threadId, name),
          );
        },
        onArchiveThread: (projectPath, thread) {
          unawaited(_shellController.archiveProjectThread(projectPath, thread));
        },
        onUnarchiveThread: (projectPath, thread) {
          unawaited(
            _shellController.unarchiveProjectThread(projectPath, thread),
          );
        },
        onDeleteThread: (projectPath, thread) {
          unawaited(_shellController.deleteProjectThread(projectPath, thread));
        },
        onForkThread: (projectPath, thread) {
          unawaited(_shellController.forkProjectThread(projectPath, thread));
        },
        onDismissCompletedThread: (projectPath, threadId) {
          _shellController.dismissCompletedProjectThread(projectPath, threadId);
        },
      ),
    );
  }

  Widget _buildLeftPanel() {
    return _ResizableColumn(
      topVisible: _leftTopVisible,
      bottomVisible: _leftBottomVisible,
      topRatio: _leftTopRatio,
      onTopRatioChanged: (ratio) {
        setState(() {
          _leftTopRatio = ratio.clamp(_minPanelRatio, _maxPanelRatio);
        });
      },
      heightHandleKey: const ValueKey('left-height-resize-handle'),
      top: _buildProjectsPanel(),
      bottom: _buildPlaceholderPanel(
        key: const ValueKey('context-panel-card'),
        title: 'Context',
        icon: Icons.hub_rounded,
        message: 'No file context',
      ),
    );
  }

  Widget _buildFilesPanel() {
    return PanelCard(
      key: const ValueKey('files-panel-card'),
      showBorder: false,
      child: FileTreePane(
        nodes: _shellController.workspaceTree,
        expandedPaths: _shellController.expandedDirectoryPaths,
        selectedPath: _shellController.selectedTreePath,
        projectPath: _shellController.activeProjectPath,
        isLoading: _shellController.isLoadingProject,
        onNodeTap: _shellController.handleTreeNodeTap,
        onExpansionChanged: _shellController.handleTreeExpansionChanged,
      ),
    );
  }

  Widget _buildRightPanel() {
    return _ResizableColumn(
      topVisible: _rightTopVisible,
      bottomVisible: _rightBottomVisible,
      topRatio: _rightTopRatio,
      onTopRatioChanged: (ratio) {
        setState(() {
          _rightTopRatio = ratio.clamp(_minPanelRatio, _maxPanelRatio);
        });
      },
      heightHandleKey: const ValueKey('right-height-resize-handle'),
      top: _buildFilesPanel(),
      bottom: _buildPlaceholderPanel(
        key: const ValueKey('tools-panel-card'),
        title: 'Tools',
        icon: Icons.terminal_rounded,
        message: 'No tools running',
      ),
    );
  }

  Widget _buildPlaceholderPanel({
    required Key key,
    required String title,
    required IconData icon,
    required String message,
  }) {
    final colors = IdeColors.of(context);
    return PanelCard(
      key: key,
      showBorder: false,
      child: Pane(
        title: title,
        trailing: Icon(icon, size: 16, color: colors.mutedText),
        child: EmptyState(text: message),
      ),
    );
  }

  void _openProject() {
    unawaited(_shellController.openProject());
  }

  Future<List<AgentProviderConfig>> _loadAvailableAgentProviders() async {
    final injectedLoader = widget.agentProviderAvailabilityLoader;
    if (injectedLoader != null) {
      return injectedLoader();
    }
    return _agentManagementController.loadAvailableThreadProviders();
  }

  void _toggleLeftPanel({
    required bool isTop,
    required bool useOverlay,
    required FocusNode triggerFocusNode,
  }) {
    setState(() {
      if (!useOverlay) {
        if (_activeOverlay == IdeWorkbenchOverlay.navigation) {
          _activeOverlay = null;
          _overlayTriggerFocusNode = null;
        }
        if (isTop) {
          _leftTopVisible = !_leftTopVisible;
        } else {
          _leftBottomVisible = !_leftBottomVisible;
        }
        return;
      }

      final currentlyVisible = isTop ? _leftTopVisible : _leftBottomVisible;
      final otherVisible = isTop ? _leftBottomVisible : _leftTopVisible;
      final overlayOpen = _activeOverlay == IdeWorkbenchOverlay.navigation;
      if (overlayOpen && currentlyVisible && !otherVisible) {
        if (isTop) {
          _leftTopVisible = false;
        } else {
          _leftBottomVisible = false;
        }
        _activeOverlay = null;
        _overlayTriggerFocusNode = null;
        return;
      }

      if (overlayOpen && currentlyVisible) {
        if (isTop) {
          _leftTopVisible = false;
        } else {
          _leftBottomVisible = false;
        }
        if (!_leftTopVisible && !_leftBottomVisible) {
          _activeOverlay = null;
          _overlayTriggerFocusNode = null;
        }
        return;
      }

      if (isTop) {
        _leftTopVisible = true;
      } else {
        _leftBottomVisible = true;
      }
      _activeOverlay = IdeWorkbenchOverlay.navigation;
      _overlayTriggerFocusNode = triggerFocusNode;
    });
  }

  void _closeActiveOverlay() {
    if (_activeOverlay == null) {
      return;
    }
    setState(() {
      _activeOverlay = null;
      _overlayTriggerFocusNode = null;
    });
  }

  void _toggleRightPanel({
    required bool isTop,
    required bool useOverlay,
    required FocusNode triggerFocusNode,
  }) {
    setState(() {
      if (!useOverlay) {
        if (_activeOverlay == IdeWorkbenchOverlay.inspector) {
          _activeOverlay = null;
          _overlayTriggerFocusNode = null;
        }
        if (isTop) {
          _rightTopVisible = !_rightTopVisible;
        } else {
          _rightBottomVisible = !_rightBottomVisible;
        }
        return;
      }

      final currentlyVisible = isTop ? _rightTopVisible : _rightBottomVisible;
      final otherVisible = isTop ? _rightBottomVisible : _rightTopVisible;
      final overlayOpen = _activeOverlay == IdeWorkbenchOverlay.inspector;
      if (overlayOpen && currentlyVisible && !otherVisible) {
        if (isTop) {
          _rightTopVisible = false;
        } else {
          _rightBottomVisible = false;
        }
        _activeOverlay = null;
        _overlayTriggerFocusNode = null;
        return;
      }

      if (overlayOpen && currentlyVisible) {
        if (isTop) {
          _rightTopVisible = false;
        } else {
          _rightBottomVisible = false;
        }
        if (!_rightTopVisible && !_rightBottomVisible) {
          _activeOverlay = null;
          _overlayTriggerFocusNode = null;
        }
        return;
      }

      if (isTop) {
        _rightTopVisible = true;
      } else {
        _rightBottomVisible = true;
      }
      _activeOverlay = IdeWorkbenchOverlay.inspector;
      _overlayTriggerFocusNode = triggerFocusNode;
    });
  }

  /// 标题栏 / 原生菜单「文件 - 打开项目」入口，与工具栏按钮一致。
  void _handleMenuOpenProject() {
    _openProject();
  }

  void _handleMenuExit() {
    unawaited(windowManager.close());
  }

  void _handleShellChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _showStatus(String message) {
    if (!mounted) {
      return;
    }
    // 连续状态提示只保留最新一条，避免右下角堆叠。
    _statusToast?.close();
    _statusToast = showIdeToast(
      context,
      message: message,
      showDuration: const Duration(seconds: 2),
    );
  }

  AgentRuntimeState _managementRuntimeState() {
    return switch (_shellController.selectedAgentViewModel.status.state) {
      AgentProviderConnectionState.idle => AgentRuntimeState.notRunning,
      AgentProviderConnectionState.connecting => AgentRuntimeState.starting,
      AgentProviderConnectionState.ready => AgentRuntimeState.idle,
      AgentProviderConnectionState.running => AgentRuntimeState.running,
      AgentProviderConnectionState.unavailable => AgentRuntimeState.unavailable,
      AgentProviderConnectionState.error => AgentRuntimeState.error,
    };
  }

  void _openSettingsPage() {
    if (_page == _IdeHomePage.settings) {
      return;
    }
    setState(() {
      _settingsPageMounted = true;
      _page = _IdeHomePage.settings;
      _settingsSection = SettingsSection.appearance;
      _activeOverlay = null;
      _overlayTriggerFocusNode = null;
    });
  }

  void _openUsageStatisticsPage() {
    if (_page == _IdeHomePage.usageStatistics) {
      return;
    }
    setState(() {
      _usageStatisticsPageMounted = true;
      _page = _IdeHomePage.usageStatistics;
      _activeOverlay = null;
      _overlayTriggerFocusNode = null;
    });
  }

  void _closeUsageStatisticsPage() {
    if (_page != _IdeHomePage.usageStatistics) {
      return;
    }
    setState(() {
      _page = _IdeHomePage.home;
      _activeOverlay = null;
      _overlayTriggerFocusNode = null;
    });
  }

  void _openAgentManagementFromUsage() {
    setState(() {
      _settingsPageMounted = true;
      _page = _IdeHomePage.settings;
      _settingsSection = SettingsSection.agents;
      _activeOverlay = null;
      _overlayTriggerFocusNode = null;
    });
  }

  Future<void> _selectSettingsSection(SettingsSection section) async {
    if (section == _settingsSection ||
        !(await _settingsCanvasKey.currentState?.confirmCanLeave() ?? true) ||
        !mounted) {
      return;
    }
    setState(() {
      _settingsSection = section;
    });
  }

  Future<void> _closeSettingsPage() async {
    if (_page != _IdeHomePage.settings ||
        !(await _settingsCanvasKey.currentState?.confirmCanLeave() ?? true) ||
        !mounted) {
      return;
    }
    setState(() {
      _page = _IdeHomePage.home;
      _activeOverlay = null;
      _overlayTriggerFocusNode = null;
    });
  }

  void _toggleSettingsNavigationOverlay() {
    setState(() {
      final navigationOpen = _activeOverlay == IdeWorkbenchOverlay.navigation;
      _activeOverlay = navigationOpen ? null : IdeWorkbenchOverlay.navigation;
      _overlayTriggerFocusNode = navigationOpen
          ? null
          : _settingsNavigationFocusNode;
    });
  }
}

enum _IdeHomePage { home, settings, usageStatistics }

class _ResizableColumn extends StatelessWidget {
  const _ResizableColumn({
    required this.topVisible,
    required this.bottomVisible,
    required this.topRatio,
    required this.onTopRatioChanged,
    required this.top,
    required this.bottom,
    required this.heightHandleKey,
  });

  final bool topVisible;
  final bool bottomVisible;
  final double topRatio;
  final ValueChanged<double> onTopRatioChanged;
  final Widget top;
  final Widget bottom;
  final Key heightHandleKey;

  @override
  Widget build(BuildContext context) {
    if (topVisible && !bottomVisible) {
      return SizedBox.expand(child: top);
    }
    if (!topVisible && bottomVisible) {
      return SizedBox.expand(child: bottom);
    }
    if (!topVisible && !bottomVisible) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final resizableHeight = constraints.maxHeight - IdeSpacing.space8;
        final topHeight = resizableHeight * topRatio.clamp(0.1, 0.9);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: topHeight, child: top),
            IdeResizeHandle(
              key: heightHandleKey,
              axis: IdeResizeHandleAxis.vertical,
              semanticLabel: 'Resize panel height',
              onDragUpdate: (details) {
                onTopRatioChanged(
                  (topHeight + details.delta.dy) / resizableHeight,
                );
              },
            ),
            Expanded(child: bottom),
          ],
        );
      },
    );
  }
}

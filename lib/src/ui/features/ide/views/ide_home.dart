import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:window_manager/window_manager.dart';

import 'package:zeta/src/app/menu_action_bridge.dart';
import 'package:zeta/src/app/shell/ide_shell_controller.dart';
import 'package:zeta/src/core/utils/system_file_manager.dart';
import 'package:zeta/src/features/agent/application/agent_model_catalog_repository.dart';
import 'package:zeta/src/features/agent/application/agent_provider_runtime_registry.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/agent/domain/agent_turn_terminal_signal.dart';
import 'package:zeta/src/features/desktop_notifications/application/desktop_attention_controller.dart';
import 'package:zeta/src/features/desktop_notifications/data/flutter_desktop_notification_service.dart';
import 'package:zeta/src/features/desktop_notifications/data/method_channel_desktop_attention_indicator.dart';
import 'package:zeta/src/features/desktop_notifications/domain/desktop_attention_models.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_controller.dart';
import 'package:zeta/src/features/agent_management/data/claude_code_agent_management_repository.dart';
import 'package:zeta/src/features/agent_management/data/codex_agent_management_repository.dart';
import 'package:zeta/src/features/agent_management/data/grok_agent_management_repository.dart';
import 'package:zeta/src/features/agent_management/domain/agent_cli_management_repository.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';
import 'package:zeta/src/features/ide_session/data/ide_session_store.dart';
import 'package:zeta/src/features/settings/application/appearance_settings_controller.dart';
import 'package:zeta/src/features/settings/application/general_settings_controller.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';
import 'package:zeta/src/features/settings/presentation/settings_page.dart';
import 'package:zeta/src/features/usage_statistics/application/agent_usage_panel_controller.dart';
import 'package:zeta/src/features/usage_statistics/application/agent_usage_refresh_coordinator.dart';
import 'package:zeta/src/features/usage_statistics/application/usage_statistics_controller.dart';
import 'package:zeta/src/features/usage_statistics/presentation/agent_usage_panel.dart';
import 'package:zeta/src/features/usage_statistics/presentation/usage_statistics_page.dart';
import 'package:zeta/src/features/agent/presentation/agent_pane.dart';
import 'package:zeta/src/features/workspace/presentation/file_tree_pane.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/ide_resize_handle.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/ide_toast.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';
import 'package:zeta/src/ui/core/window_frame.dart';
import 'package:zeta/src/ui/core/workbench/ide_retained_page_view.dart';
import 'package:zeta/src/ui/core/workbench/ide_workbench_scaffold.dart';
import 'package:zeta/src/ui/features/ide/views/global_home_page.dart';
import 'package:zeta/src/ui/features/ide/views/project_home_page.dart';
import 'package:zeta/src/ui/features/ide/views/project_agent_sidebar.dart';
import 'package:zeta/src/ui/features/ide/views/project_list_pane.dart';

typedef AgentProviderAvailabilityLoader =
    Future<List<AgentProviderConfig>> Function();

typedef HomeProviderDetectionLoader = Future<List<ManagedAgent>> Function();

/// IDE 主界面。
///
/// 首页由标题栏入口控制 Projects / Agent 统计合并栏，中央保留 Agent 主编辑区；
/// 具体项目、会话和 Agent thread 编排由 [IdeShellController] 承接。
class IdeHome extends StatefulWidget {
  const IdeHome({
    required this.directoryPicker,
    required this.enableNativeWindowFrame,
    required this.sessionStore,
    required this.agentProviderFactory,
    required this.agentProviderConfigStore,
    required this.usageStatisticsDependencies,
    required this.projectLocationOpener,
    required this.appearanceController,
    required this.generalSettingsController,
    required this.agentModelCatalogRepository,
    required this.agentProviderRuntimeRegistry,
    this.enableAgentUsageAutoRefresh = true,
    this.agentProviderAvailabilityLoader,
    this.homeProviderDetectionLoader,
    this.showWindowControls = true,
    this.desktopNotificationService,
    this.desktopAttentionIndicator,
    super.key,
  });

  final Future<String?> Function() directoryPicker;
  final bool enableNativeWindowFrame;
  final IdeSessionStore sessionStore;
  final AgentProviderFactory agentProviderFactory;
  final AgentProviderConfigStore agentProviderConfigStore;
  final IdeShellUsageStatisticsDependencies usageStatisticsDependencies;
  final ProjectLocationOpener projectLocationOpener;
  final AppearanceSettingsController appearanceController;
  final GeneralSettingsController generalSettingsController;
  final AgentModelCatalogRepository agentModelCatalogRepository;
  final AgentProviderRuntimeRegistry agentProviderRuntimeRegistry;

  /// 是否在启动及每个回合结束后通过事件消息刷新 Agent 用量。
  final bool enableAgentUsageAutoRefresh;
  final AgentProviderAvailabilityLoader? agentProviderAvailabilityLoader;
  final HomeProviderDetectionLoader? homeProviderDetectionLoader;
  final bool showWindowControls;
  final DesktopNotificationService? desktopNotificationService;
  final DesktopAttentionIndicator? desktopAttentionIndicator;

  @override
  State<IdeHome> createState() => _IdeHomeState();
}

class _IdeHomeState extends State<IdeHome> with WindowListener {
  static const double _initialPanelWidth = IdeMetrics.sidePaneDefaultWidth;
  static const double _minPanelWidth = IdeMetrics.sidePaneMinWidth;
  static const double _maxPanelWidth = IdeMetrics.sidePaneMaxWidth;

  late final IdeShellController _shellController;
  late final AgentManagementController _agentManagementController;
  late final UsageStatisticsController _usageStatisticsController;
  late final AgentUsagePanelController _agentUsagePanelController;
  late final AgentUsageRefreshCoordinator _agentUsageRefreshCoordinator;
  late final DesktopAttentionController _desktopAttentionController;
  bool _windowFocused = true;

  bool _rightSidebarVisible = false;
  bool _settingsPageMounted = false;
  bool _usageStatisticsPageMounted = false;
  bool _globalHomeLoadRequested = false;
  bool _homeProvidersLoading = false;
  List<HomeProviderSummary> _installedHomeProviders =
      const <HomeProviderSummary>[];
  String? _homeProviderError;
  int _globalHomeLoadToken = 0;
  IdeWorkbenchOverlay? _activeOverlay;
  FocusNode? _overlayTriggerFocusNode;
  double _leftPanelWidth = _initialPanelWidth;
  bool _leftPanelWidthDragging = false;
  double _rightPanelWidth = _initialPanelWidth;
  sf.ToastOverlay? _statusToast;
  _IdeHomePage _page = _IdeHomePage.home;
  SettingsSection _settingsSection = SettingsSection.general;
  final FocusNode _leftSidebarFocusNode = FocusNode(
    debugLabel: 'TitleBarLeftSidebarAction',
  );
  final FocusNode _rightSidebarFocusNode = FocusNode(
    debugLabel: 'TitleBarRightSidebarAction',
  );
  final GlobalKey<SettingsPageCanvasState> _settingsCanvasKey =
      GlobalKey<SettingsPageCanvasState>();

  @override
  void initState() {
    super.initState();
    unawaited(widget.appearanceController.load());
    unawaited(widget.generalSettingsController.load());
    final notificationService =
        widget.desktopNotificationService ??
        (widget.enableNativeWindowFrame
            ? FlutterDesktopNotificationService()
            : const NoopDesktopNotificationService());
    final attentionIndicator =
        widget.desktopAttentionIndicator ??
        (widget.enableNativeWindowFrame
            ? MethodChannelDesktopAttentionIndicator()
            : const NoopDesktopAttentionIndicator());
    _desktopAttentionController = DesktopAttentionController(
      notificationService: notificationService,
      indicator: attentionIndicator,
      generalSettingsController: widget.generalSettingsController,
      activateTarget: _activateAttentionTarget,
    );
    _shellController = IdeShellController(
      directoryPicker: widget.directoryPicker,
      sessionStore: widget.sessionStore,
      agentProviderFactory: widget.agentProviderFactory,
      agentProviderConfigStore: widget.agentProviderConfigStore,
      projectLocationOpener: widget.projectLocationOpener,
      statusReporter: _showStatus,
      agentModelCatalogRepository: widget.agentModelCatalogRepository,
      agentProviderRuntimeRegistry: widget.agentProviderRuntimeRegistry,
      onAgentTurnTerminal: _handleAgentTurnTerminal,
      onAgentAttention: (attention) {
        unawaited(_desktopAttentionController.handleAttention(attention));
      },
      usageStatistics: widget.usageStatisticsDependencies,
    )..addListener(_handleShellChanged);
    if (widget.enableNativeWindowFrame) {
      windowManager.addListener(this);
    }
    unawaited(_desktopAttentionController.initialize());
    _agentManagementController = AgentManagementController(
      repositories: <String, AgentCliManagementRepository>{
        AgentDefinition.codex.id: CodexAgentManagementRepository(
          modelCatalogRepository: widget.agentModelCatalogRepository,
          runtimeRegistry: widget.agentProviderRuntimeRegistry,
        ),
        AgentDefinition.grok.id: GrokAgentManagementRepository(
          modelCatalogRepository: widget.agentModelCatalogRepository,
          runtimeRegistry: widget.agentProviderRuntimeRegistry,
        ),
        AgentDefinition.claudeCode.id: ClaudeCodeAgentManagementRepository(),
      },
      providerController: _shellController.agentProviderController,
      runtimeStateProvider: _managementRuntimeState,
      runtimeListenable: _shellController,
    )..addListener(_handleAgentManagementChanged);
    _usageStatisticsController = _shellController.usageStatisticsController;
    _agentUsagePanelController = _shellController.agentUsagePanelController;
    _agentUsageRefreshCoordinator = AgentUsageRefreshCoordinator(
      // turn 完成 / 启动预热走静默刷新：已有数据时不闪加载横条。
      refresh: () => _agentUsagePanelController.refresh(showLoading: false),
    );
    if (widget.enableAgentUsageAutoRefresh) {
      _scheduleInitialAgentUsageRefresh();
    }
    // 生产环境注册原生菜单的「打开项目」回调，与工具栏按钮走同一逻辑。
    if (widget.enableNativeWindowFrame) {
      MenuActionBridge.instance.setOpenProject(_handleMenuOpenProject);
    }
  }

  @override
  void dispose() {
    if (widget.enableNativeWindowFrame) {
      MenuActionBridge.instance.setOpenProject(null);
      windowManager.removeListener(this);
    }
    _shellController.removeListener(_handleShellChanged);
    _agentUsageRefreshCoordinator.dispose();
    _agentManagementController.removeListener(_handleAgentManagementChanged);
    _agentManagementController.dispose();
    _shellController.dispose();
    _desktopAttentionController.dispose();
    _leftSidebarFocusNode.dispose();
    _rightSidebarFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final homePage = _page == _IdeHomePage.home;
    final leftSidebarVisible =
        homePage && _shellController.workbenchLayout.leftSidebarVisible;
    final workbenchWidth =
        (MediaQuery.sizeOf(context).width - IdeSpacing.space8)
            .clamp(0.0, double.infinity)
            .toDouble();
    final rightSidebarUsesOverlay =
        homePage &&
        resolveEffectiveWorkbenchLayoutMode(
              width: workbenchWidth,
              navigationAvailable: leftSidebarVisible,
              inspectorAvailable: true,
              leadingRailAvailable: false,
              trailingRailAvailable: false,
              navigationWidth: _leftPanelWidth,
              inspectorWidth: _rightPanelWidth,
            ) !=
            IdeWorkbenchLayoutMode.wide;
    final rightSidebarExpanded =
        homePage &&
        _rightSidebarVisible &&
        (!rightSidebarUsesOverlay ||
            _activeOverlay == IdeWorkbenchOverlay.inspector);
    final body = WindowFrame(
      key: const ValueKey('ide-window-frame'),
      enableNativeWindowFrame: widget.enableNativeWindowFrame,
      menus: _windowMenus,
      titleBarLeadingActions: _page == _IdeHomePage.home
          ? <WindowTitleBarAction>[
              WindowTitleBarAction(
                key: const ValueKey('titlebar-left-sidebar-action'),
                icon: Icons.view_sidebar_outlined,
                tooltip: leftSidebarVisible ? '隐藏左侧栏' : '显示左侧栏',
                semanticLabel: leftSidebarVisible ? '隐藏左侧栏' : '显示左侧栏',
                active: leftSidebarVisible,
                focusNode: _leftSidebarFocusNode,
                onPressed: () => _toggleLeftSidebar(_leftSidebarFocusNode),
              ),
            ]
          : const <WindowTitleBarAction>[],
      titleBarActions: <WindowTitleBarAction>[
        WindowTitleBarAction(
          key: const ValueKey('titlebar-usage-statistics-action'),
          icon: sf.LucideIcons.chartLine,
          tooltip: 'Usage statistics',
          semanticLabel: 'Open usage statistics page',
          active: _page == _IdeHomePage.usageStatistics,
          onPressed: _openUsageStatisticsPage,
        ),
        WindowTitleBarAction(
          key: const ValueKey('titlebar-settings-action'),
          icon: sf.RadixIcons.mixerHorizontal,
          tooltip: 'Settings',
          semanticLabel: 'Open settings page',
          active: _page == _IdeHomePage.settings,
          onPressed: _openSettingsPage,
        ),
        if (homePage)
          WindowTitleBarAction(
            key: const ValueKey('titlebar-right-sidebar-action'),
            icon: sf.LucideIcons.panelRight,
            tooltip: rightSidebarExpanded ? '隐藏右侧栏' : '显示右侧栏',
            semanticLabel: rightSidebarExpanded ? '隐藏右侧栏' : '显示右侧栏',
            active: rightSidebarExpanded,
            focusNode: _rightSidebarFocusNode,
            onPressed: () => _toggleRightSidebar(
              useOverlay: rightSidebarUsesOverlay,
              triggerFocusNode: _rightSidebarFocusNode,
            ),
          ),
      ],
      showWindowControls: widget.showWindowControls,
      // 工作台外圈统一保留 space4，让左右 Pane 与窗口边缘保持稳定呼吸感。
      child: Padding(
        padding: const EdgeInsets.all(IdeSpacing.space4),
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
  /// - 设置与 Agent 管理：不显示 Activity Rail，设置 Navigation 在所有模式下
  ///   保持内联，不提供 Inspector。
  /// - 使用统计：不显示 Activity Rail，只提供 Canvas。
  Widget _buildWorkbench() {
    final homePage = _page == _IdeHomePage.home;
    final settingsPage = _page == _IdeHomePage.settings;
    final workbenchLayout = _shellController.workbenchLayout;
    final navigationVisible = settingsPage
        ? true
        : homePage && workbenchLayout.leftSidebarVisible;
    final inspectorVisible = homePage && _rightSidebarVisible;
    final activeOverlay = _activeOverlay == IdeWorkbenchOverlay.inspector
        ? IdeWorkbenchOverlay.inspector
        : homePage && workbenchLayout.leftSidebarVisible
        ? IdeWorkbenchOverlay.navigation
        : null;
    return IdeWorkbenchScaffold(
      key: const ValueKey('ide-workbench'),
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
      navigationInlineInCompact: settingsPage,
      navigationWidth: _leftPanelWidth,
      canvas: _buildRetainedCanvasStack(),
      inspectorPane: homePage ? _buildFilesPanel() : null,
      inspectorResizeHandle: inspectorVisible
          ? _buildInspectorResizeHandle()
          : null,
      inspectorVisible: inspectorVisible,
      inspectorWidth: _rightPanelWidth,
      activeOverlay: activeOverlay,
      onDismissOverlay: _closeActiveOverlay,
      overlayTriggerFocusNode: _overlayTriggerFocusNode,
    );
  }

  /// 页面级保留容器：只布局当前 Home / Settings / Usage，已访问页 keep-alive。
  Widget _buildRetainedCanvasStack() {
    return IdeRetainedPageView(
      key: const ValueKey('workbench-page-stack'),
      selectedId: _page.name,
      pages: <IdeRetainedPage>[
        IdeRetainedPage(
          id: _IdeHomePage.home.name,
          child: TickerMode(
            enabled: _page == _IdeHomePage.home,
            child: KeyedSubtree(
              key: const ValueKey('agent-pane-host'),
              child: _buildRetainedAgentPaneStack(),
            ),
          ),
        ),
        IdeRetainedPage(
          id: _IdeHomePage.settings.name,
          child: TickerMode(
            enabled: _page == _IdeHomePage.settings,
            child: _settingsPageMounted
                ? SettingsPageCanvas(
                    key: _settingsCanvasKey,
                    activeSection: _settingsSection,
                    appearanceController: widget.appearanceController,
                    generalSettingsController: widget.generalSettingsController,
                    agentManagementController: _agentManagementController,
                  )
                : const SizedBox.shrink(),
          ),
        ),
        IdeRetainedPage(
          id: _IdeHomePage.usageStatistics.name,
          child: TickerMode(
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
        ),
      ],
    );
  }

  /// 会话级保留容器：Project Home + 各 Agent 会话，仅布局当前选中项。
  Widget _buildRetainedAgentPaneStack() {
    final entries = _shellController.agentWorkspaceEntries;
    final projectPath = _shellController.activeProjectPath;
    if (projectPath == null) {
      if (!_shellController.initialRestoreCompleted) {
        return _buildGlobalHomeRestoringState();
      }
      return GlobalHomePage(
        recentProjects: _shellController.recentProjects,
        recentThreads: _shellController.recentThreads,
        installedProviders: _installedHomeProviders,
        onOpenProject: _openProject,
        onSelectProject: (path) {
          unawaited(_shellController.openRecentProject(path));
        },
        onSelectThread: (thread) {
          unawaited(
            _shellController.selectProjectThread(thread.projectPath, thread),
          );
        },
        isLoadingRecentThreads: _shellController.isRefreshingRecentHomeData,
        recentThreadsError: _shellController.recentHomeRefreshError,
        isLoadingProviders: _homeProvidersLoading,
        providerError: _homeProviderError,
      );
    }

    const projectHomeId = 'project-home';
    final selectedEntryId = _shellController.selectedAgentWorkspaceEntryId;
    final selectedId = _shellController.isProjectHomeActive
        ? projectHomeId
        : (selectedEntryId ??
              (entries.isNotEmpty ? entries.first.entryId : projectHomeId));

    return ValueListenableBuilder<GeneralSettings>(
      valueListenable: widget.generalSettingsController.listenable,
      builder: (context, generalSettings, _) {
        return IdeRetainedPageView(
          key: const ValueKey('agent-pane-entry-stack'),
          selectedId: selectedId,
          pages: <IdeRetainedPage>[
            IdeRetainedPage(
              id: projectHomeId,
              child: !_shellController.isProjectHomeActive
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
                            _shellController.selectProjectThread(
                              projectPath,
                              thread,
                            ),
                          );
                        },
                        onRetryThreads: () {
                          unawaited(_shellController.retryThreads(projectPath));
                        },
                      ),
                    ),
            ),
            for (final entry in entries)
              IdeRetainedPage(
                id: entry.entryId,
                child: KeyedSubtree(
                  key: ValueKey<String>('agent-pane-entry-${entry.entryId}'),
                  child: AgentPane(
                    viewModel: entry.viewModel,
                    isActive: entry.entryId == selectedId,
                    messageSendShortcut: generalSettings.sendMessageShortcut,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildGlobalHomeRestoringState() {
    final colors = IdeColors.of(context);
    return ColoredBox(
      key: const ValueKey<String>('global-home-restoring'),
      color: colors.canvasSurface,
      child: Center(child: IdeBusySpinner(size: 20, color: colors.accent)),
    );
  }

  Widget _buildNavigationResizeHandle() {
    return IdeResizeHandle(
      key: const ValueKey('left-width-resize-handle'),
      axis: IdeResizeHandleAxis.horizontal,
      semanticLabel: 'Resize left panel width',
      onDragStart: (_) {
        _leftPanelWidthDragging = true;
      },
      onDragUpdate: (details) {
        setState(() {
          _leftPanelWidth = (_leftPanelWidth + details.delta.dx).clamp(
            _minPanelWidth,
            _maxPanelWidth,
          );
        });
      },
      onDragEnd: (_) {
        _leftPanelWidthDragging = false;
        _shellController.setLeftSidebarWidth(_leftPanelWidth);
      },
      onDragCancel: () {
        setState(() {
          _leftPanelWidthDragging = false;
          _leftPanelWidth = _effectiveLeftPanelWidth;
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

  Widget _buildProjectsContent() {
    return ProjectListPane(
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
        unawaited(_shellController.openProjectInSystemFileManager(projectPath));
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
        unawaited(_shellController.unarchiveProjectThread(projectPath, thread));
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
    );
  }

  Widget _buildLeftPanel() {
    final workbenchLayout = _shellController.workbenchLayout;
    return ProjectAgentSidebar(
      projects: _buildProjectsContent(),
      agentUsage: AgentUsagePanelContent(
        controller: _agentUsagePanelController,
        mode: workbenchLayout.agentUsageExpanded
            ? AgentUsagePanelMode.expanded
            : AgentUsagePanelMode.collapsed,
        onModeChanged: (mode) {
          _shellController.setAgentUsageExpanded(
            mode == AgentUsagePanelMode.expanded,
          );
        },
      ),
      agentUsageExpanded: workbenchLayout.agentUsageExpanded,
      agentUsageHeightFraction: workbenchLayout.agentUsageHeightFraction,
      onAgentUsageHeightFractionChanged:
          _shellController.setAgentUsageHeightFraction,
    );
  }

  Widget _buildFilesPanel() {
    return PanelCard(
      key: const ValueKey('files-panel-card'),
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

  void _scheduleInitialAgentUsageRefresh() {
    // 先交付首帧，再提交统一的低优先级刷新请求，避免抢占启动渲染。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestAgentUsageRefresh();
    });
  }

  void _handleAgentTurnTerminal(AgentTurnTerminalSignal signal) {
    _agentUsagePanelController.selectProviderFromTurn(signal.providerId);
    _requestAgentUsageRefresh();
  }

  void _requestAgentUsageRefresh() {
    if (!mounted || !widget.enableAgentUsageAutoRefresh) {
      return;
    }
    _agentUsageRefreshCoordinator.requestRefresh();
  }

  void _toggleLeftSidebar(FocusNode triggerFocusNode) {
    final visible = _shellController.workbenchLayout.leftSidebarVisible;
    if (!visible) {
      // 标题栏位于 Workbench 快捷键作用域之外；打开浮层时先释放按钮焦点，
      // 让 Overlay 的 Esc 作用域接管，关闭后再由 Scaffold 恢复到该按钮。
      triggerFocusNode.unfocus();
      setState(() {
        _activeOverlay = null;
        _overlayTriggerFocusNode = triggerFocusNode;
      });
    } else {
      _overlayTriggerFocusNode = null;
    }
    _shellController.setLeftSidebarVisible(!visible);
  }

  void _closeActiveOverlay() {
    if (_activeOverlay == IdeWorkbenchOverlay.inspector) {
      setState(() {
        _activeOverlay = null;
        _overlayTriggerFocusNode = null;
      });
      return;
    }
    if (_page == _IdeHomePage.home &&
        _shellController.workbenchLayout.leftSidebarVisible) {
      _overlayTriggerFocusNode = null;
      _shellController.setLeftSidebarVisible(false);
    }
  }

  void _toggleRightSidebar({
    required bool useOverlay,
    required FocusNode triggerFocusNode,
  }) {
    setState(() {
      if (!useOverlay) {
        if (_activeOverlay == IdeWorkbenchOverlay.inspector) {
          _activeOverlay = null;
          _overlayTriggerFocusNode = null;
        }
        _rightSidebarVisible = !_rightSidebarVisible;
        return;
      }

      final overlayOpen = _activeOverlay == IdeWorkbenchOverlay.inspector;
      if (overlayOpen && _rightSidebarVisible) {
        _rightSidebarVisible = false;
        _activeOverlay = null;
        _overlayTriggerFocusNode = null;
        return;
      }

      triggerFocusNode.unfocus();
      _rightSidebarVisible = true;
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
    _maybeStartGlobalHomeLoad();
    _updateDesktopAttentionVisibility();
    if (!_leftPanelWidthDragging) {
      _leftPanelWidth = _effectiveLeftPanelWidth;
    }
    if (mounted) {
      setState(() {});
    }
  }

  double get _effectiveLeftPanelWidth =>
      (_shellController.workbenchLayout.leftSidebarWidth ?? _initialPanelWidth)
          .clamp(_minPanelWidth, _maxPanelWidth);

  @override
  void onWindowFocus() {
    _windowFocused = true;
    _updateDesktopAttentionVisibility();
  }

  @override
  void onWindowBlur() {
    _windowFocused = false;
    _updateDesktopAttentionVisibility();
  }

  @override
  void onWindowMinimize() {
    _windowFocused = false;
    _updateDesktopAttentionVisibility();
  }

  @override
  void onWindowRestore() {
    _windowFocused = true;
    _updateDesktopAttentionVisibility();
  }

  void _updateDesktopAttentionVisibility() {
    final entry = _shellController.agentWorkspaceController.selectedEntry;
    _desktopAttentionController.updateVisibility(
      DesktopAttentionVisibility(
        windowFocused: _windowFocused,
        agentCanvasVisible:
            _page == _IdeHomePage.home && !_shellController.isProjectHomeActive,
        providerId: entry?.providerId,
        threadId: entry?.threadId,
      ),
    );
  }

  Future<bool> _activateAttentionTarget(
    String providerId,
    String threadId,
  ) async {
    await _shellController.initialRestoreDone;
    if (!mounted) {
      return false;
    }
    if (widget.enableNativeWindowFrame) {
      if (await windowManager.isMinimized()) {
        await windowManager.restore();
      }
      await windowManager.show();
      await windowManager.focus();
    }
    final activated = await _shellController.activateAgentThread(
      providerId: providerId,
      threadId: threadId,
    );
    if (!mounted) {
      return activated;
    }
    setState(() {
      _page = _IdeHomePage.home;
      _activeOverlay = null;
      _overlayTriggerFocusNode = null;
    });
    if (!activated) {
      showIdeToast(
        context,
        message: '无法打开通知对应的会话：该会话可能已被删除或不在当前项目列表中。',
        tone: IdeToastTone.error,
      );
    }
    _updateDesktopAttentionVisibility();
    return activated;
  }

  void _maybeStartGlobalHomeLoad() {
    final globalHomeVisible =
        _shellController.initialRestoreCompleted &&
        _shellController.activeProjectPath == null;
    if (!globalHomeVisible) {
      if (_shellController.activeProjectPath != null) {
        _globalHomeLoadRequested = false;
        _globalHomeLoadToken += 1;
      }
      return;
    }
    if (_globalHomeLoadRequested) {
      return;
    }
    _globalHomeLoadRequested = true;
    final token = ++_globalHomeLoadToken;
    unawaited(_shellController.refreshRecentHomeData());
    unawaited(_loadHomeProviders(token));
  }

  Future<void> _loadHomeProviders(int token) async {
    if (!mounted || token != _globalHomeLoadToken) {
      return;
    }
    setState(() {
      _homeProvidersLoading = true;
      _homeProviderError = null;
    });

    final cachedProviders = List<HomeProviderSummary>.from(
      _installedHomeProviders,
    );
    try {
      final injectedLoader = widget.homeProviderDetectionLoader;
      if (injectedLoader != null) {
        final agents = await injectedLoader();
        if (!mounted || token != _globalHomeLoadToken) {
          return;
        }
        _setInstalledHomeProviders(agents);
      } else {
        await _agentManagementController.initialize();
        if (!mounted || token != _globalHomeLoadToken) {
          return;
        }
        _setInstalledHomeProviders(_agentManagementController.agents);
        cachedProviders
          ..clear()
          ..addAll(_installedHomeProviders);
        setState(() {});

        await _agentManagementController.detect();
        if (!mounted || token != _globalHomeLoadToken) {
          return;
        }
        final detectionError = _agentManagementController.operationError;
        if (detectionError == null) {
          _setInstalledHomeProviders(_agentManagementController.agents);
        } else {
          _installedHomeProviders = List<HomeProviderSummary>.unmodifiable(
            cachedProviders,
          );
          _homeProviderError = detectionError;
        }
      }
    } catch (error) {
      if (!mounted || token != _globalHomeLoadToken) {
        return;
      }
      _installedHomeProviders = List<HomeProviderSummary>.unmodifiable(
        cachedProviders,
      );
      _homeProviderError = '无法检测 Provider：$error';
    } finally {
      if (mounted && token == _globalHomeLoadToken) {
        setState(() {
          _homeProvidersLoading = false;
        });
      }
    }
  }

  void _setInstalledHomeProviders(Iterable<ManagedAgent> agents) {
    _installedHomeProviders = List<HomeProviderSummary>.unmodifiable(
      agents
          .where(
            (agent) =>
                agent.installationState == AgentInstallationState.installed,
          )
          .map(HomeProviderSummary.fromManagedAgent),
    );
  }

  void _handleAgentManagementChanged() {
    if (!mounted ||
        _homeProvidersLoading ||
        widget.homeProviderDetectionLoader != null) {
      return;
    }
    setState(() {
      _setInstalledHomeProviders(_agentManagementController.agents);
    });
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
      _settingsSection = SettingsSection.general;
      _activeOverlay = null;
      _overlayTriggerFocusNode = null;
    });
    _updateDesktopAttentionVisibility();
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
    _updateDesktopAttentionVisibility();
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
    _updateDesktopAttentionVisibility();
  }

  void _openAgentManagementFromUsage() {
    setState(() {
      _settingsPageMounted = true;
      _page = _IdeHomePage.settings;
      _settingsSection = SettingsSection.agents;
      _activeOverlay = null;
      _overlayTriggerFocusNode = null;
    });
    _updateDesktopAttentionVisibility();
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
    _updateDesktopAttentionVisibility();
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
    _updateDesktopAttentionVisibility();
  }
}

enum _IdeHomePage { home, settings, usageStatistics }

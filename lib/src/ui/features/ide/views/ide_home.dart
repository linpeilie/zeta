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
import 'package:zeta/src/features/desktop_notifications/application/desktop_attention_controller.dart';
import 'package:zeta/src/features/desktop_notifications/data/flutter_desktop_notification_service.dart';
import 'package:zeta/src/features/desktop_notifications/data/method_channel_desktop_attention_indicator.dart';
import 'package:zeta/src/features/desktop_notifications/domain/desktop_attention_models.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_controller.dart';
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
import 'package:zeta/src/features/usage_statistics/data/codex_usage_statistics_repository.dart';
import 'package:zeta/src/features/usage_statistics/data/composite_usage_statistics_repository.dart';
import 'package:zeta/src/features/usage_statistics/data/grok_usage_statistics_repository.dart';
import 'package:zeta/src/features/usage_statistics/data/provider_agent_usage_panel_repository.dart';
import 'package:zeta/src/features/usage_statistics/data/usage_statistics_index_store.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_panel_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_repository.dart';
import 'package:zeta/src/features/usage_statistics/presentation/agent_usage_panel.dart';
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
import 'package:zeta/src/ui/core/workbench/ide_retained_page_view.dart';
import 'package:zeta/src/ui/core/workbench/ide_workbench_scaffold.dart';
import 'package:zeta/src/ui/features/ide/views/global_home_page.dart';
import 'package:zeta/src/ui/features/ide/views/project_home_page.dart';
import 'package:zeta/src/ui/features/ide/views/project_list_pane.dart';

typedef AgentProviderAvailabilityLoader =
    Future<List<AgentProviderConfig>> Function();

typedef HomeProviderDetectionLoader = Future<List<ManagedAgent>> Function();

/// IDE 主界面。
///
/// 当前布局是左右图标栏、左右活动面板与中间 Agent 主编辑区组成的五列结构；
/// 具体项目、会话和 Agent thread 编排由 [IdeShellController] 承接。
///
/// Trailing Rail（Files/Tools）暂时关闭；加回时将 [_trailingRailEnabled]
/// 设为 `true` 并移除 [debugShowTrailingRail]。
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
    required this.generalSettingsController,
    required this.agentModelCatalogRepository,
    required this.agentProviderRuntimeRegistry,
    this.enableAgentUsageAutoRefresh = true,
    this.agentProviderAvailabilityLoader,
    this.homeProviderDetectionLoader,
    this.agentUsagePanelRepository,
    this.showWindowControls = true,
    this.desktopNotificationService,
    this.desktopAttentionIndicator,
    super.key,
  });

  /// 生产路径是否装配 Trailing Rail；暂时关闭以便后续一次性加回。
  static const bool _trailingRailEnabled = false;

  /// 测试专用：为仍覆盖 Inspector 行为的用例临时显示 Trailing Rail。
  @visibleForTesting
  static bool debugShowTrailingRail = false;

  final Future<String?> Function() directoryPicker;
  final bool enableNativeWindowFrame;
  final IdeSessionStore sessionStore;
  final AgentProviderFactory agentProviderFactory;
  final AgentProviderConfigStore agentProviderConfigStore;
  final UsageStatisticsIndexStore usageStatisticsIndexStore;
  final ProjectLocationOpener projectLocationOpener;
  final AppearanceSettingsController appearanceController;
  final GeneralSettingsController generalSettingsController;
  final AgentModelCatalogRepository agentModelCatalogRepository;
  final AgentProviderRuntimeRegistry agentProviderRuntimeRegistry;

  /// 是否在启动及每个回合结束后通过事件消息刷新 Agent 用量。
  final bool enableAgentUsageAutoRefresh;
  final AgentProviderAvailabilityLoader? agentProviderAvailabilityLoader;
  final HomeProviderDetectionLoader? homeProviderDetectionLoader;
  final AgentUsagePanelRepository? agentUsagePanelRepository;
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
  static const double _initialPanelRatio = 0.5;
  static const double _minPanelRatio = 0.1;
  static const double _maxPanelRatio = 0.9;

  late final IdeShellController _shellController;
  late final AgentManagementController _agentManagementController;
  late final UsageStatisticsController _usageStatisticsController;
  late final AgentUsagePanelController _agentUsagePanelController;
  late final AgentUsageRefreshCoordinator _agentUsageRefreshCoordinator;
  late final DesktopAttentionController _desktopAttentionController;
  bool _windowFocused = true;

  bool _leftTopVisible = true;
  bool _leftBottomVisible = false;
  bool _rightTopVisible = false;
  bool _rightBottomVisible = false;
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
  double _rightPanelWidth = _initialPanelWidth;
  double _leftTopRatio = _initialPanelRatio;
  double _rightTopRatio = _initialPanelRatio;
  sf.ToastOverlay? _statusToast;
  _IdeHomePage _page = _IdeHomePage.home;
  SettingsSection _settingsSection = SettingsSection.general;
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
      onAgentTurnCompleted: _handleAgentTurnCompleted,
      onAgentAttention: (attention) {
        unawaited(_desktopAttentionController.handleAttention(attention));
      },
    )..addListener(_handleShellChanged);
    if (widget.enableNativeWindowFrame) {
      windowManager.addListener(this);
    }
    unawaited(_desktopAttentionController.initialize());
    _agentManagementController = AgentManagementController(
      repositories: <String, AgentCliManagementRepository>{
        AgentDefinition.codex.id: CodexAgentManagementRepository(
          providerFactory: widget.agentProviderFactory,
          modelCatalogRepository: widget.agentModelCatalogRepository,
          runtimeRegistry: widget.agentProviderRuntimeRegistry,
        ),
        AgentDefinition.grok.id: GrokAgentManagementRepository(
          providerFactory: widget.agentProviderFactory,
          modelCatalogRepository: widget.agentModelCatalogRepository,
          runtimeRegistry: widget.agentProviderRuntimeRegistry,
        ),
      },
      providerController: _shellController.agentProviderController,
      runtimeStateProvider: _managementRuntimeState,
      runtimeListenable: _shellController,
    )..addListener(_handleAgentManagementChanged);
    // 使用统计聚合所有内置支持 Provider 的本地历史，不绑定当前激活 Agent。
    // 身份由各数据源固定为 codex / grok；扫描本机 ~/.codex 与 ~/.grok。
    _usageStatisticsController = UsageStatisticsController(
      repository: CompositeUsageStatisticsRepository(
        sources: <UsageStatisticsRepository>[
          CodexUsageStatisticsRepository(
            indexStore: widget.usageStatisticsIndexStore,
            // 不启动 CLI：仅读本地 rollout；套餐额度由侧栏用量面板负责。
            includeQuota: false,
          ),
          GrokUsageStatisticsRepository(includeQuota: false),
        ],
      ),
    );
    _agentUsagePanelController = AgentUsagePanelController(
      repository:
          widget.agentUsagePanelRepository ??
          ProviderAgentUsagePanelRepository(
            enabledProviderLoader: _loadEnabledAgentProviders,
            providerLeaseLoader:
                _shellController.agentProviderController.acquireProvider,
            seedIndexStore: widget.usageStatisticsIndexStore,
          ),
    );
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
    _usageStatisticsController.dispose();
    _agentUsageRefreshCoordinator.dispose();
    _agentUsagePanelController.dispose();
    _agentManagementController.removeListener(_handleAgentManagementChanged);
    _agentManagementController.dispose();
    _shellController.dispose();
    _desktopAttentionController.dispose();
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
      ],
      showWindowControls: widget.showWindowControls,
      // 工作台外圈 space4：与 rail 内侧 gap（space4）对称，图标条视觉居中。
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
      trailingRailBuilder:
          (IdeHome._trailingRailEnabled || IdeHome.debugShowTrailingRail)
          ? _buildTrailingRail
          : null,
      activeOverlay: _activeOverlay,
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
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colors.accent,
          ),
        ),
      ),
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
          icon: sf.BootstrapIcons.slack,
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
          icon: sf.LucideIcons.chartPie,
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

  /// Files/Tools 右侧活动栏；由 [_trailingRailEnabled] / [IdeHome.debugShowTrailingRail]
  /// 控制是否装配，实现保留以便加回。
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
      bottom: AgentUsagePanel(controller: _agentUsagePanelController),
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

  Future<List<AgentProviderConfig>> _loadEnabledAgentProviders() async {
    final controller = _shellController.agentProviderController;
    await controller.loadSettings();
    return controller.enabledProviders;
  }

  void _scheduleInitialAgentUsageRefresh() {
    // 先交付首帧，再提交统一的低优先级刷新请求，避免抢占启动渲染。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestAgentUsageRefresh();
    });
  }

  void _handleAgentTurnCompleted() {
    _requestAgentUsageRefresh();
  }

  void _requestAgentUsageRefresh() {
    if (!mounted || !widget.enableAgentUsageAutoRefresh) {
      return;
    }
    _agentUsageRefreshCoordinator.requestRefresh();
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
    _maybeStartGlobalHomeLoad();
    _updateDesktopAttentionVisibility();
    if (mounted) {
      setState(() {});
    }
  }

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

class _ResizableColumn extends StatefulWidget {
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
  State<_ResizableColumn> createState() => _ResizableColumnState();
}

class _ResizableColumnState extends State<_ResizableColumn> {
  double? _dragStartTopHeight;
  double? _dragStartGlobalY;

  void _startDrag(DragStartDetails details, double resizableHeight) {
    _dragStartTopHeight = resizableHeight * widget.topRatio.clamp(0.1, 0.9);
    _dragStartGlobalY = details.globalPosition.dy;
  }

  void _updateDrag(DragUpdateDetails details, double resizableHeight) {
    // 固定一次拖拽的起点，避免同一帧内的多次 update 都从旧布局高度计算。
    _dragStartTopHeight ??= resizableHeight * widget.topRatio.clamp(0.1, 0.9);
    _dragStartGlobalY ??= details.globalPosition.dy - details.delta.dy;
    final topHeight =
        _dragStartTopHeight! + details.globalPosition.dy - _dragStartGlobalY!;
    widget.onTopRatioChanged(topHeight / resizableHeight);
  }

  void _finishDrag() {
    _dragStartTopHeight = null;
    _dragStartGlobalY = null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.topVisible && !widget.bottomVisible) {
      return SizedBox.expand(child: widget.top);
    }
    if (!widget.topVisible && widget.bottomVisible) {
      return SizedBox.expand(child: widget.bottom);
    }
    if (!widget.topVisible && !widget.bottomVisible) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final resizableHeight = constraints.maxHeight - IdeSpacing.space8;
        final topHeight = resizableHeight * widget.topRatio.clamp(0.1, 0.9);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: topHeight, child: widget.top),
            IdeResizeHandle(
              key: widget.heightHandleKey,
              axis: IdeResizeHandleAxis.vertical,
              semanticLabel: 'Resize panel height',
              onDragStart: (details) => _startDrag(details, resizableHeight),
              onDragUpdate: (details) => _updateDrag(details, resizableHeight),
              onDragEnd: (_) => _finishDrag(),
              onDragCancel: _finishDrag,
            ),
            Expanded(child: widget.bottom),
          ],
        );
      },
    );
  }
}

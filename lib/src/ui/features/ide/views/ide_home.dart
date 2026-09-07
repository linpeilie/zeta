import 'package:zeta/src/features/agent_management/application/agent_management_home_state.dart';
import 'package:zeta/src/app/composition/workbench_session_providers.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_slice/project_threads_slice_notifier.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_notifier.dart';
import 'package:zeta/src/app/composition/zeta_environment_providers.dart';
import 'package:zeta/src/app/window/zeta_window_host.dart';
import 'package:zeta/src/app/window/zeta_window_surface.dart';
import 'package:zeta/src/app/app_constants.dart';
import 'package:zeta/src/app/desktop_attention_slice/desktop_attention_providers.dart';
import 'package:zeta/src/app/conversation_workspace_slice/agent_conversation_workspace_notifier.dart';
import 'package:zeta/src/app/conversation_workspace_slice/agent_conversation_entry_resources.dart';
import 'package:zeta/src/app/menu_action_bridge.dart';
import 'package:zeta/src/app/shell/ide_shell_controller.dart';
import 'package:zeta/src/app/usage_statistics_slice/usage_statistics_providers.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/desktop_notifications/application/desktop_attention_slice_notifier.dart';
import 'package:zeta/src/features/desktop_notifications/domain/desktop_attention_models.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_operations.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_notifier.dart';
import 'package:zeta/src/features/project_threads/domain/project_thread_list_state.dart';
import 'package:zeta/src/features/project_threads/presentation/project_threads_slice/project_threads_slice_providers.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';
import 'package:zeta/src/features/settings/domain/settings_section.dart';
import 'package:zeta/src/features/settings/presentation/settings_page.dart';
import 'package:zeta/src/features/settings/presentation/settings_slice/settings_slice_providers.dart';
import 'package:zeta/src/features/usage_statistics/application/agent_usage_panel_slice/agent_usage_panel_slice_store.dart';
import 'package:zeta/src/features/usage_statistics/application/agent_usage_refresh_coordinator.dart';
import 'package:zeta/src/features/usage_statistics/presentation/agent_usage_panel.dart';
import 'package:zeta/src/features/usage_statistics/presentation/usage_statistics_page.dart';
import 'package:zeta/src/features/agent/presentation/agent_pane.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';
import 'package:zeta/src/features/workspace/presentation/file_tree_pane.dart';
import 'package:zeta_ui/zeta_ui.dart';
import 'package:zeta/src/ui/localization/app_localizations_x.dart';
import 'package:zeta/src/ui/features/ide/views/global_home_page.dart';
import 'package:zeta/src/ui/features/ide/views/project_home_page.dart';
import 'package:zeta/src/ui/features/ide/views/project_agent_sidebar.dart';
import 'package:zeta/src/ui/features/ide/views/project_list_pane.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta/src/features/workspace/application/workspace_notifier.dart';

/// IDE 主界面。
///
/// 首页由标题栏入口控制 Projects / Agent 统计合并栏，中央保留 Agent 主编辑区；
/// 具体项目、会话和 Agent thread 编排由 [IdeShellController] 承接。
///
/// 页面读取应用已启动的 Workbench，只拥有订阅和局部界面状态。
/// entry、会话 owner、Shell 和运行资源都由组合根显式关闭。
class IdeHome extends ConsumerStatefulWidget {
  const IdeHome({super.key});

  @override
  ConsumerState<IdeHome> createState() => _IdeHomeState();
}

class _IdeHomeState extends ConsumerState<IdeHome> {
  static const double _initialPanelWidth = IdeMetrics.sidePaneDefaultWidth;
  static const double _minPanelWidth = IdeMetrics.sidePaneMinWidth;
  static const double _maxPanelWidth = IdeMetrics.sidePaneMaxWidth;

  late final IdeShellController _shellController;
  late final _IdeHomeUiMemory _uiMemory;
  StreamSubscription<String>? _statusSubscription;
  StreamSubscription<AgentTurnTerminalSignal>? _terminalSubscription;

  /// 窗口宿主：原生标题栏、菜单与抢前台都经它；测试里通常什么都不做。
  ///
  /// 在 `initState` 取一次并留住：`dispose()` 里还可能用到，而那时
  /// `ref` 已经不能再读了。窗口事件本身走 [zetaWindowSurfaceProvider]。
  late final ZetaWindowHost _windowHost = ref.read(zetaWindowHostProvider);

  /// 是否在启动及每个回合结束后通过事件消息刷新 Agent 用量。
  late final bool _agentUsageAutoRefreshEnabled = ref.read(
    agentUsageAutoRefreshEnabledProvider,
  );

  /// 首页探测端口；null 表示由首页走自己的默认实现。
  late final AgentProviderAvailabilityLoader? _agentProviderAvailabilityLoader =
      ref.read(agentProviderAvailabilityLoaderProvider);

  late final void Function() _unsubscribeProviderSettings;
  late final AgentUsagePanelSliceNotifier _agentUsagePanelController;
  late final AgentUsageRefreshCoordinator _agentUsageRefreshCoordinator;
  late final DesktopAttentionSliceNotifier _desktopAttention = ref.read(
    desktopAttentionSliceProvider.notifier,
  );
  late final DesktopAttentionTargetActivatorRelay
  _desktopAttentionTargetActivatorRelay = ref.read(
    desktopAttentionTargetActivatorRelayProvider,
  );
  late final DesktopAttentionTargetActivator _desktopAttentionTargetActivator;
  bool _nativeMenuConfigured = false;

  bool _rightSidebarVisible = false;

  /// Agent 统计弹层是否展开；弹层是临时 UI，不写入会话。
  bool _agentUsageExpanded = false;
  bool _settingsPageMounted = false;
  bool _usageStatisticsPageMounted = false;
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

  AgentManagementOperations get _agentManagementOperations =>
      ref.read(agentManagementOperationsProvider);

  @override
  void initState() {
    super.initState();
    _desktopAttentionTargetActivator = _activateAttentionTarget;
    _desktopAttentionTargetActivatorRelay.bind(
      _desktopAttentionTargetActivator,
    );
    _agentUsagePanelController = ref.read(
      agentUsagePanelSliceProvider.notifier,
    );
    _uiMemory = ref.read(_ideHomeUiMemoryProvider);
    _rightSidebarVisible = _uiMemory.rightSidebarVisible;
    _rightPanelWidth = _uiMemory.rightPanelWidth;
    final workbench = ref.read(workbenchSessionProvider);
    _shellController = workbench.shell;
    _leftPanelWidth = _effectiveLeftPanelWidth;
    _statusSubscription = workbench.events.status.listen(_showStatus);
    _terminalSubscription = workbench.events.terminals.listen(
      _handleAgentTurnTerminal,
    );
    ref.listenManual(
      agentConversationWorkspaceProvider,
      (_, _) => _handleConversationWorkspaceChanged(),
    );
    _unsubscribeProviderSettings = _shellController.agentProviderController
        .subscribe(_handleAgentProviderSettingsUsageChanged);
    unawaited(_desktopAttention.initialize());
    _agentUsageRefreshCoordinator = AgentUsageRefreshCoordinator(
      // turn 完成 / 启动预热走静默刷新：已有数据时不闪加载横条。
      refresh: () => _agentUsagePanelController.refresh(showLoading: false),
    );
    if (_agentUsageAutoRefreshEnabled) {
      _scheduleInitialAgentUsageRefresh();
    }
    // 打开项目只走菜单栏（原生 File 菜单或标题栏菜单），不在项目列表放入口。
    MenuActionBridge.instance.setOpenProject(_handleMenuOpenProject);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_nativeMenuConfigured && _windowHost.rendersNativeChrome) {
      _nativeMenuConfigured = true;
      final l10n = context.l10n;
      unawaited(
        _windowHost.configureNativeMenu(
          fileMenuLabel: l10n.workbenchMenuFile,
          openProjectLabel: l10n.workbenchMenuOpenProject,
        ),
      );
    }
  }

  @override
  void dispose() {
    _uiMemory.rightSidebarVisible = _rightSidebarVisible;
    _uiMemory.rightPanelWidth = _rightPanelWidth;
    MenuActionBridge.instance.setOpenProject(null);
    unawaited(_statusSubscription?.cancel());
    unawaited(_terminalSubscription?.cancel());
    _unsubscribeProviderSettings();
    _agentUsageRefreshCoordinator.dispose();
    _desktopAttentionTargetActivatorRelay.unbind(
      _desktopAttentionTargetActivator,
    );
    _leftSidebarFocusNode.dispose();
    _rightSidebarFocusNode.dispose();
    super.dispose();
  }

  /// Provider 配置更新可能增删侧栏目录；只在目录已发现后做无闪烁同步。
  void _handleAgentProviderSettingsUsageChanged() {
    if (!_agentUsagePanelController.hasDiscoveredProviders) {
      return;
    }
    unawaited(_agentUsagePanelController.synchronizeProviders());
  }

  @override
  Widget build(BuildContext context) {
    // 只订阅 IDE Session 的轻量 UI 投影；持久化 DTO 不进入 Riverpod。
    ref.watch(
      ideSessionSliceProvider.select(
        (state) => (state.workbenchLayout, state.initialRestoreCompleted),
      ),
    );
    // 侧栏宽度与首页预热是状态变化的副作用，不是渲染输入，因此走 listen。
    ref.watch(workspaceProvider);
    ref.listen(ideSessionSliceProvider, (_, _) => _handleIdeSessionChanged());
    ref.listen(
      ideSessionSliceProvider.select(
        (state) => (
          initialRestoreCompleted: state.initialRestoreCompleted,
          providerId: state.workbenchLayout.selectedAgentUsageProviderId,
        ),
      ),
      (previous, next) {
        if (_agentUsagePanelController.preferredProviderId != next.providerId) {
          _agentUsagePanelController.restorePreferredProviderId(
            next.providerId,
          );
        }
        if (previous == null ||
            previous.providerId == next.providerId ||
            !next.initialRestoreCompleted) {
          return;
        }
        // Panel runner 只提交 Workbench typed state；Shell 在这里补齐完整会话
        // 快照并交给既有 debounce coordinator 落盘。
        _shellController.requestSessionSave();
      },
    );
    ref.listen(workspaceProvider, (_, _) => _handleWorkspaceChanged());
    ref.listen(zetaWindowSurfaceProvider.select((state) => state.focused), (
      previous,
      next,
    ) {
      if (previous == next) {
        return;
      }
      _updateDesktopAttentionVisibility();
    });
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
      // 品牌资产由根 app 拥有并声明；zeta_ui 只负责尺寸盒与无障碍标签。
      brandLogo: SvgPicture.asset(brandingLogoAsset),
      key: const ValueKey('ide-window-frame'),
      enableNativeWindowFrame: _windowHost.rendersNativeChrome,
      menus: _windowMenus(context),
      titleBarLeadingActions: switch (_page) {
        _IdeHomePage.home => <WindowTitleBarAction>[
          WindowTitleBarAction(
            key: const ValueKey('titlebar-left-sidebar-action'),
            icon: leftSidebarVisible
                ? sf.LucideIcons.panelLeftClose
                : sf.LucideIcons.panelLeftOpen,
            tooltip: leftSidebarVisible
                ? context.l10n.workbenchHideLeftSidebar
                : context.l10n.workbenchShowLeftSidebar,
            semanticLabel: leftSidebarVisible
                ? context.l10n.workbenchHideLeftSidebar
                : context.l10n.workbenchShowLeftSidebar,
            active: leftSidebarVisible,
            focusNode: _leftSidebarFocusNode,
            onPressed: () => _toggleLeftSidebar(_leftSidebarFocusNode),
          ),
        ],
        // 设置页 / 使用统计页脱离主界面栈，标题栏折叠位改为返回主界面。
        _IdeHomePage.settings => <WindowTitleBarAction>[
          WindowTitleBarAction(
            key: const ValueKey('titlebar-back-action'),
            icon: Icons.arrow_back_rounded,
            tooltip: context.l10n.workbenchBackToHome,
            semanticLabel: context.l10n.workbenchBackToHome,
            onPressed: () => unawaited(_closeSettingsPage()),
          ),
        ],
        _IdeHomePage.usageStatistics => <WindowTitleBarAction>[
          WindowTitleBarAction(
            key: const ValueKey('titlebar-back-action'),
            icon: Icons.arrow_back_rounded,
            tooltip: context.l10n.workbenchBackToHome,
            semanticLabel: context.l10n.workbenchBackToHome,
            onPressed: _closeUsageStatisticsPage,
          ),
        ],
      },
      titleBarActions: <WindowTitleBarAction>[
        WindowTitleBarAction(
          key: const ValueKey('titlebar-usage-statistics-action'),
          icon: sf.LucideIcons.chartLine,
          tooltip: context.l10n.workbenchUsageStatistics,
          semanticLabel: context.l10n.workbenchOpenUsageStatistics,
          active: _page == _IdeHomePage.usageStatistics,
          onPressed: _openUsageStatisticsPage,
        ),
        WindowTitleBarAction(
          key: const ValueKey('titlebar-settings-action'),
          icon: sf.RadixIcons.mixerHorizontal,
          tooltip: 'Settings',
          semanticLabel: context.l10n.workbenchOpenSettings,
          active: _page == _IdeHomePage.settings,
          onPressed: _openSettingsPage,
        ),
        WindowTitleBarAction(
          key: const ValueKey('titlebar-right-sidebar-action'),
          icon: rightSidebarExpanded
              ? sf.LucideIcons.panelRightClose
              : sf.LucideIcons.panelRightOpen,
          tooltip: homePage
              ? (rightSidebarExpanded
                    ? context.l10n.workbenchHideRightSidebar
                    : context.l10n.workbenchShowRightSidebar)
              : context.l10n.workbenchRightSidebarHomeOnly,
          semanticLabel: homePage
              ? (rightSidebarExpanded
                    ? context.l10n.workbenchHideRightSidebar
                    : context.l10n.workbenchShowRightSidebar)
              : context.l10n.workbenchRightSidebarHomeOnly,
          active: rightSidebarExpanded,
          enabled: homePage,
          focusNode: homePage ? _rightSidebarFocusNode : null,
          onPressed: () => _toggleRightSidebar(
            useOverlay: rightSidebarUsesOverlay,
            triggerFocusNode: _rightSidebarFocusNode,
          ),
        ),
      ],
      showWindowControls: _windowHost.showsWindowControls,
      // 左右/底 space8 让 Pane 与窗口边缘保持呼吸感；顶部 space0 与标题栏贴齐，
      // 中间不再画分隔线。
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          IdeSpacing.space8,
          IdeSpacing.space0,
          IdeSpacing.space8,
          IdeSpacing.space8,
        ),
        child: _buildWorkbench(),
      ),
    );

    return body;
  }

  List<WindowMenu> _windowMenus(BuildContext context) {
    if (!_windowHost.rendersNativeChrome) {
      return const <WindowMenu>[];
    }
    final l10n = context.l10n;
    return [
      WindowMenu(
        key: const ValueKey('window-menu-file'),
        label: l10n.workbenchMenuFile,
        items: [
          WindowMenuItem(
            key: const ValueKey('window-menu-open-project'),
            label: l10n.workbenchMenuOpenProject,
            onPressed: _handleMenuOpenProject,
          ),
          WindowMenuItem(
            key: const ValueKey('window-menu-exit'),
            label: l10n.workbenchMenuQuit,
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
                    showAgentManagement: true,
                  )
                : const SizedBox.shrink(),
          ),
        ),
        IdeRetainedPage(
          id: _IdeHomePage.usageStatistics.name,
          child: TickerMode(
            enabled: _page == _IdeHomePage.usageStatistics,
            child: _usageStatisticsPageMounted
                ? _buildUsageStatisticsPage()
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

  /// 会话级保留容器：Project Home + 各 Agent 会话，仅布局当前选中项。
  Widget _buildRetainedAgentPaneStack() {
    final projectPath = _shellController.activeProjectPath;
    if (projectPath == null) {
      if (!_shellController.initialRestoreCompleted) {
        return _buildGlobalHomeRestoringState();
      }
      return Consumer(
        builder: (context, ref, _) {
          final home = ref.watch(agentManagementHomeProvider);
          return GlobalHomePage(
            installedProviders: home.installedProviders,
            onOpenProject: _openProject,
            isLoadingProviders: home.isLoading,
            providerError: home.detectionFailure == null
                ? null
                : context.l10n.workbenchProviderDetectionFailed(
                    context.l10n.mgmtUnknownError,
                  ),
          );
        },
      );
    }

    return Consumer(
      builder: (context, ref, _) {
        final workspaceState = ref.watch(agentConversationWorkspaceProvider);
        final workspaceStore = ref.read(
          agentConversationWorkspaceProvider.notifier,
        );
        final entries = <AgentConversationEntryResources>[
          for (final entryState in workspaceState.entries)
            workspaceStore.entryById(entryState.entryId),
        ];
        const projectHomeId = 'project-home';
        final selectedId = workspaceState.projectHomeActive
            ? projectHomeId
            : (workspaceState.selectedEntryId ??
                  (entries.isNotEmpty ? entries.first.entryId : projectHomeId));
        final projectThreadState = ref.watch(
          projectThreadListStateProvider(projectPath),
        );
        final generalSettings = ref.watch(generalSettingsSliceValueProvider);
        return _buildAgentEntryPages(
          entries: entries,
          projectPath: projectPath,
          projectHomeId: projectHomeId,
          selectedId: selectedId,
          projectHomeActive: workspaceState.projectHomeActive,
          generalSettings: generalSettings,
          projectThreadState: projectThreadState,
        );
      },
    );
  }

  Widget _buildAgentEntryPages({
    required List<AgentConversationEntryResources> entries,
    required String projectPath,
    required String projectHomeId,
    required String selectedId,
    required bool projectHomeActive,
    required GeneralSettings generalSettings,
    required ProjectThreadListState projectThreadState,
  }) {
    return IdeRetainedPageView(
      key: const ValueKey('agent-pane-entry-stack'),
      selectedId: selectedId,
      pages: <IdeRetainedPage>[
        IdeRetainedPage(
          id: projectHomeId,
          child: !projectHomeActive
              ? const SizedBox.shrink()
              : KeyedSubtree(
                  key: ValueKey<String>('project-home-$projectPath'),
                  child: ProjectHomePage(
                    projectPath: projectPath,
                    threadState: projectThreadState,
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
                controller: entry.controller,
                isActive: entry.entryId == selectedId,
                messageSendShortcut: generalSettings.sendMessageShortcut,
              ),
            ),
          ),
      ],
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
      semanticLabel: context.l10n.workbenchResizeLeftPanel,
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
      semanticLabel: context.l10n.workbenchResizeRightPanel,
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
    return Consumer(
      builder: (context, ref, _) {
        final projectThreadsState = ref.watch(projectThreadsSliceProvider);
        final workspace = ref.watch(workspaceProvider);
        return ProjectListPane(
          projects: workspace.projectPaths,
          activeProject: workspace.activeProjectPath,
          threadStateFor: projectThreadsState.stateFor,
          onSelectProject: (path) {
            unawaited(_shellController.selectKnownProject(path));
          },
          onSelectThread: (projectPath, thread) {
            unawaited(
              _shellController.selectProjectThread(projectPath, thread),
            );
          },
          onLoadMoreThreads: (projectPath) {
            unawaited(_shellController.loadMoreThreads(projectPath));
          },
          onRetryThreads: (projectPath) {
            unawaited(_shellController.retryThreads(projectPath));
          },
          loadAvailableProviders: _loadAvailableAgentProviders,
          capabilitiesForProvider: _shellController
              .agentProviderController
              .capabilitiesForProviderId,
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
            unawaited(
              _shellController.archiveProjectThread(projectPath, thread),
            );
          },
          onUnarchiveThread: (projectPath, thread) {
            unawaited(
              _shellController.unarchiveProjectThread(projectPath, thread),
            );
          },
          onDeleteThread: (projectPath, thread) {
            unawaited(
              _shellController.deleteProjectThread(projectPath, thread),
            );
          },
          onForkThread: (projectPath, thread) {
            unawaited(_shellController.forkProjectThread(projectPath, thread));
          },
          onDismissCompletedThread: (projectPath, threadId) {
            _shellController.dismissCompletedProjectThread(
              projectPath,
              threadId,
            );
          },
        );
      },
    );
  }

  Widget _buildLeftPanel() {
    return ProjectAgentSidebar(
      projects: _buildProjectsContent(),
      agentUsage: _buildAgentUsagePanel(),
    );
  }

  Widget _buildUsageStatisticsPage() {
    return UsageStatisticsPage(
      key: const ValueKey('usage-statistics-page-host'),
      onOpenAgentManagement: _openAgentManagementFromUsage,
    );
  }

  Widget _buildAgentUsagePanel() {
    return AgentUsagePanelContent(
      mode: _agentUsageExpanded
          ? AgentUsagePanelMode.expanded
          : AgentUsagePanelMode.collapsed,
      onModeChanged: (mode) {
        setState(() {
          _agentUsageExpanded = mode == AgentUsagePanelMode.expanded;
        });
      },
    );
  }

  Widget _buildFilesPanel() {
    Widget buildPanel({
      required List<WorkspaceNode> nodes,
      required Set<String> expandedPaths,
      required String? selectedPath,
      required String? projectPath,
      required bool isLoading,
    }) {
      return PanelCard(
        key: const ValueKey('files-panel-card'),
        child: FileTreePane(
          nodes: nodes,
          expandedPaths: expandedPaths,
          selectedPath: selectedPath,
          projectPath: projectPath,
          isLoading: isLoading,
          onNodeTap: _shellController.handleTreeNodeTap,
          onExpansionChanged: _shellController.handleTreeExpansionChanged,
        ),
      );
    }

    return Consumer(
      builder: (context, ref, _) {
        final projectPath = ref.watch(
          workspaceProvider.select((state) => state.activeProjectPath),
        );
        final tree = ref.watch(activeWorkspaceFileTreeProvider);
        return buildPanel(
          nodes: tree.tree,
          expandedPaths: tree.expandedDirectoryPaths,
          selectedPath: tree.selectedTreePath,
          projectPath: projectPath,
          isLoading: tree.isLoading,
        );
      },
    );
  }

  void _openProject() {
    unawaited(_shellController.openProject());
  }

  Future<List<AgentProviderConfig>> _loadAvailableAgentProviders() async {
    final injectedLoader = _agentProviderAvailabilityLoader;
    if (injectedLoader != null) {
      return injectedLoader();
    }
    return _agentManagementOperations.loadAvailableThreadProviders();
  }

  void _scheduleInitialAgentUsageRefresh() {
    // 先交付首帧，再提交统一的低优先级刷新请求，避免抢占启动渲染。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refreshInitialAgentUsageAfterRestore());
    });
  }

  Future<void> _refreshInitialAgentUsageAfterRestore() async {
    // 会话恢复会写入上次选中的统计 Tab；等待它收敛，避免先误载默认 Provider。
    await _shellController.initialRestoreDone;
    if (!mounted) {
      return;
    }
    _agentUsagePanelController.restorePreferredProviderId(
      ref
          .read(ideSessionSliceProvider.notifier)
          .state
          .workbenchLayout
          .selectedAgentUsageProviderId,
    );
    _requestAgentUsageRefresh();
  }

  void _handleAgentTurnTerminal(AgentTurnTerminalSignal signal) {
    _agentUsagePanelController.selectProviderFromTurn(signal.providerId);
    _requestAgentUsageRefresh();
  }

  void _requestAgentUsageRefresh() {
    if (!mounted || !_agentUsageAutoRefreshEnabled) {
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

  /// 标题栏 / 原生菜单「文件 - 打开项目」入口。
  void _handleMenuOpenProject() {
    _openProject();
  }

  void _handleMenuExit() {
    unawaited(_windowHost.closeWindow());
  }

  /// IDE Session 变化：面板宽度来自 workbenchLayout，首页预热看 initialRestoreCompleted。
  void _handleIdeSessionChanged() {
    if (!_leftPanelWidthDragging) {
      _leftPanelWidth = _effectiveLeftPanelWidth;
    }
    _rebuild();
  }

  /// Workspace 变化：activeProjectPath 同时影响首页预热与 Attention 可见性。
  void _handleWorkspaceChanged() {
    _updateDesktopAttentionVisibility();
    _rebuild();
  }

  /// Conversation Workspace 变化：当前会话决定 Attention 的 provider/thread。
  void _handleConversationWorkspaceChanged() {
    _updateDesktopAttentionVisibility();
    _rebuild();
  }

  void _rebuild() {
    if (mounted) {
      setState(() {});
    }
  }

  double get _effectiveLeftPanelWidth =>
      (_shellController.workbenchLayout.leftSidebarWidth ?? _initialPanelWidth)
          .clamp(_minPanelWidth, _maxPanelWidth);

  void _updateDesktopAttentionVisibility() {
    final entry = _shellController.agentConversationWorkspace.selectedEntry;
    unawaited(
      _desktopAttention.updateVisibility(
        DesktopAttentionVisibility(
          windowFocused: ref.read(zetaWindowSurfaceProvider).focused,
          agentCanvasVisible:
              _page == _IdeHomePage.home &&
              !_shellController.isProjectHomeActive,
          providerId: entry?.providerId,
          threadId: entry?.threadId,
        ),
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
    await _windowHost.revealWindow();
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
        message: context.l10n.workbenchCannotOpenNotificationThread,
        tone: IdeToastTone.error,
      );
    }
    _updateDesktopAttentionVisibility();
    return activated;
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

/// 仅窗口表现偏好；无业务 owner、controller 或输入正文。
final _ideHomeUiMemoryProvider = Provider((ref) => _IdeHomeUiMemory());

final class _IdeHomeUiMemory {
  bool rightSidebarVisible = false;
  double rightPanelWidth = IdeMetrics.sidePaneDefaultWidth;
}

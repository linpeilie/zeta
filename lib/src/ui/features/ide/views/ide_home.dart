import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:window_manager/window_manager.dart';

import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta/src/app/agent_management_slice/agent_management_slice_composition.dart';
import 'package:zeta/src/app/agent_management_slice/agent_management_slice_runner.dart';
import 'package:zeta/src/app/app_constants.dart';
import 'package:zeta/src/app/composition/zeta_state_snapshot.dart';
import 'package:zeta/src/app/desktop_attention_slice/desktop_attention_slice_composition.dart';
import 'package:zeta/src/app/conversation_workspace_slice/agent_conversation_workspace_providers.dart';
import 'package:zeta/src/app/conversation_workspace_slice/agent_conversation_workspace_store.dart';
import 'package:zeta/src/app/menu_action_bridge.dart';
import 'package:zeta/src/app/shell/ide_shell_controller.dart';
import 'package:zeta/src/ui/core/system_file_manager.dart';
import 'package:zeta/src/features/agent/application/agent_model_catalog_repository.dart';
import 'package:zeta/src/features/agent/application/agent_provider_settings_port.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_store_registry.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/desktop_notifications/application/desktop_attention_slice_store.dart';
import 'package:zeta/src/features/desktop_notifications/domain/desktop_attention_models.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_controller.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_operations.dart';
import 'package:zeta/src/features/agent_management/data/claude_code_agent_management_repository.dart';
import 'package:zeta/src/features/agent_management/data/codex_agent_management_repository.dart';
import 'package:zeta/src/features/agent_management/data/grok_agent_management_repository.dart';
import 'package:zeta/src/features/agent_management/domain/agent_cli_management_repository.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_text_catalog.dart';
import 'package:zeta/src/features/agent_management/domain/fallback_agent_management_text_catalog.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_operations.dart';
import 'package:zeta/src/features/ide_session/presentation/ide_session_slice/ide_session_slice_providers.dart';
import 'package:zeta/src/features/project_threads/domain/project_thread_list_state.dart';
import 'package:zeta/src/features/project_threads/presentation/project_threads_slice/project_threads_slice_providers.dart';
import 'package:zeta/src/features/settings/application/appearance_settings_controller.dart';
import 'package:zeta/src/features/settings/application/general_settings_controller.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';
import 'package:zeta/src/features/settings/presentation/settings_page.dart';
import 'package:zeta/src/features/settings/presentation/settings_slice/settings_slice_providers.dart';
import 'package:zeta/src/features/usage_statistics/application/agent_usage_panel_operations.dart';
import 'package:zeta/src/features/usage_statistics/application/agent_usage_refresh_coordinator.dart';
import 'package:zeta/src/features/usage_statistics/application/usage_statistics_operations.dart';
import 'package:zeta/src/features/usage_statistics/presentation/agent_usage_panel.dart';
import 'package:zeta/src/features/usage_statistics/presentation/usage_statistics_page.dart';
import 'package:zeta/src/features/usage_statistics/presentation/usage_statistics_slice/usage_statistics_slice_providers.dart';
import 'package:zeta/src/app/usage_statistics_slice/usage_statistics_slice_composition.dart';
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
import 'package:zeta/src/features/workspace/presentation/workspace_slice/workspace_slice_providers.dart';

typedef AgentProviderAvailabilityLoader =
    Future<List<AgentProviderConfig>> Function();

typedef HomeProviderDetectionLoader = Future<List<ManagedAgent>> Function();

/// IDE 主界面。
///
/// 首页由标题栏入口控制 Projects / Agent 统计合并栏，中央保留 Agent 主编辑区；
/// 具体项目、会话和 Agent thread 编排由 [IdeShellController] 承接。
class IdeHome extends ConsumerStatefulWidget {
  const IdeHome({
    required this.directoryPicker,
    required this.enableNativeWindowFrame,
    required this.ideSessionOperations,
    required this.shellStateSnapshotRelay,
    required this.agentProviderFactory,
    required this.agentProviderConfigStore,
    required this.usageStatisticsSliceComposition,
    required this.projectLocationOpener,
    required this.appearanceController,
    required this.generalSettingsController,
    required this.desktopAttentionSliceComposition,
    required this.desktopAttentionTargetActivatorRelay,
    required this.conversationSliceStoreRegistry,
    required this.conversationWorkspaceStoreRegistry,
    required this.agentModelCatalogRepository,
    required this.agentProviderRuntimeRegistry,
    this.agentProviderSettingsPort,
    this.activeModelCatalogLoader,
    this.enableAgentUsageAutoRefresh = true,
    this.agentProviderAvailabilityLoader,
    this.homeProviderDetectionLoader,
    this.showWindowControls = true,
    this.turnContextStore,
    this.agentUiTextCatalog = const FallbackAgentUiTextCatalog(),
    this.metrics = noopZetaMetricsPort,
    this.providerManagementSliceEnabled = false,
    this.agentManagementTextCatalog =
        const FallbackAgentManagementTextCatalog(),
    super.key,
  });

  final Future<String?> Function() directoryPicker;
  final bool enableNativeWindowFrame;
  final IdeSessionSliceOperations ideSessionOperations;
  final ZetaShellStateSnapshotRelay shellStateSnapshotRelay;
  final AgentProviderBundleFactory agentProviderFactory;
  final AgentProviderConfigStore agentProviderConfigStore;
  final UsageStatisticsSliceComposition usageStatisticsSliceComposition;
  final ProjectLocationOpener projectLocationOpener;
  final AppearanceSettingsController appearanceController;
  final GeneralSettingsController generalSettingsController;
  final DesktopAttentionSliceComposition desktopAttentionSliceComposition;
  final DesktopAttentionTargetActivatorRelay
  desktopAttentionTargetActivatorRelay;
  final AgentConversationSliceStoreRegistry conversationSliceStoreRegistry;
  final AgentConversationWorkspaceStoreRegistry
  conversationWorkspaceStoreRegistry;
  final AgentModelCatalogRepository agentModelCatalogRepository;
  final AgentProviderRuntimeRegistry agentProviderRuntimeRegistry;

  /// 第 2 批 flag 开启时由 app 根注入；null 时 shell 创建旧 controller。
  final AgentProviderSettingsPort? agentProviderSettingsPort;

  /// 与 [agentProviderSettingsPort] 成对注入的 active 模型目录查询入口。
  final Future<AgentModelCatalogLoadResult> Function()?
  activeModelCatalogLoader;

  /// 是否在启动及每个回合结束后通过事件消息刷新 Agent 用量。
  final bool enableAgentUsageAutoRefresh;
  final AgentProviderAvailabilityLoader? agentProviderAvailabilityLoader;
  final HomeProviderDetectionLoader? homeProviderDetectionLoader;
  final bool showWindowControls;
  final AgentTurnContextStore? turnContextStore;

  /// app 组合层注入的脱敏指标端口；默认 no-op。
  final ZetaMetricsPort metrics;

  /// Phase 3 第 2 批：true 时只创建 management page store，false 时只创建旧
  /// controller。生产翻旗由 app 根统一控制。
  final bool providerManagementSliceEnabled;

  final AgentUiTextCatalog agentUiTextCatalog;
  final AgentManagementTextCatalog agentManagementTextCatalog;

  @override
  ConsumerState<IdeHome> createState() => _IdeHomeState();
}

class _IdeHomeState extends ConsumerState<IdeHome> with WindowListener {
  static const double _initialPanelWidth = IdeMetrics.sidePaneDefaultWidth;
  static const double _minPanelWidth = IdeMetrics.sidePaneMinWidth;
  static const double _maxPanelWidth = IdeMetrics.sidePaneMaxWidth;

  late final IdeShellController _shellController;
  late final AgentManagementController? _agentManagementController;
  late final AgentManagementSliceComposition? _agentManagementComposition;
  late final UsageStatisticsOperations _usageStatisticsController;
  late final AgentUsagePanelOperations _agentUsagePanelController;
  late final AgentUsageRefreshCoordinator _agentUsageRefreshCoordinator;
  late final DesktopAttentionSliceStore _desktopAttentionStore;
  late final DesktopAttentionTargetActivator _desktopAttentionTargetActivator;
  late final ZetaShellStateSnapshotReader _shellStateSnapshotReader;
  bool _windowFocused = true;
  bool _nativeMenuConfigured = false;

  bool _rightSidebarVisible = false;

  /// Agent 统计弹层是否展开；弹层是临时 UI，不写入会话。
  bool _agentUsageExpanded = false;
  bool _settingsPageMounted = false;
  bool _usageStatisticsPageMounted = false;
  bool _globalHomeLoadRequested = false;
  bool _homeProvidersLoading = false;
  bool _agentManagementHomeRefreshScheduled = false;
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

  AgentManagementOperations get _agentManagementOperations =>
      _agentManagementController ?? _agentManagementComposition!.store;

  @override
  void initState() {
    super.initState();
    _desktopAttentionStore = widget.desktopAttentionSliceComposition.store;
    _desktopAttentionTargetActivator = _activateAttentionTarget;
    widget.desktopAttentionTargetActivatorRelay.bind(
      _desktopAttentionTargetActivator,
    );
    _usageStatisticsController =
        widget.usageStatisticsSliceComposition.usageStatisticsStore;
    _agentUsagePanelController =
        widget.usageStatisticsSliceComposition.agentUsagePanelStore;
    _shellController = IdeShellController(
      directoryPicker: widget.directoryPicker,
      ideSessionOperations: widget.ideSessionOperations,
      agentProviderFactory: widget.agentProviderFactory,
      agentProviderConfigStore: widget.agentProviderConfigStore,
      projectLocationOpener: widget.projectLocationOpener,
      statusReporter: _showStatus,
      agentModelCatalogRepository: widget.agentModelCatalogRepository,
      agentProviderRuntimeRegistry: widget.agentProviderRuntimeRegistry,
      onAgentTurnTerminal: _handleAgentTurnTerminal,
      onAgentAttention: (attention) {
        unawaited(_desktopAttentionStore.handleAttention(attention));
      },
      onAgentUsageProviderRestored:
          _agentUsagePanelController.restorePreferredProviderId,
      turnContextStore: widget.turnContextStore,
      agentUiTextCatalog: widget.agentUiTextCatalog,
      metrics: widget.metrics,
      agentProviderSettingsPort: widget.agentProviderSettingsPort,
      activeModelCatalogLoader: widget.activeModelCatalogLoader,
    )..addListener(_handleShellChanged);
    widget.conversationWorkspaceStoreRegistry.bind(
      _shellController.agentConversationWorkspaceStore,
    );
    widget.conversationSliceStoreRegistry.bind(
      _shellController.agentConversationWorkspaceStore.sliceStoreForBinding,
    );
    widget.usageStatisticsSliceComposition.bindSelectionPersistence(
      _shellController.setSelectedAgentUsageProviderId,
    );
    _shellController.agentProviderController.addListener(
      _handleAgentProviderSettingsUsageChanged,
    );
    if (widget.enableNativeWindowFrame) {
      windowManager.addListener(this);
    }
    unawaited(widget.desktopAttentionSliceComposition.initialize());
    final managementRepositories = <String, AgentCliManagementRepository>{
      AgentDefinition.codex.id: CodexAgentManagementRepository(
        modelCatalogRepository: widget.agentModelCatalogRepository,
        runtimeRegistry: widget.agentProviderRuntimeRegistry,
        textCatalog: widget.agentManagementTextCatalog,
      ),
      AgentDefinition.grok.id: GrokAgentManagementRepository(
        modelCatalogRepository: widget.agentModelCatalogRepository,
        runtimeRegistry: widget.agentProviderRuntimeRegistry,
        textCatalog: widget.agentManagementTextCatalog,
      ),
      AgentDefinition.claudeCode.id: ClaudeCodeAgentManagementRepository(
        textCatalog: widget.agentManagementTextCatalog,
      ),
    };
    if (widget.providerManagementSliceEnabled) {
      final settingsPort = widget.agentProviderSettingsPort;
      if (settingsPort == null) {
        throw StateError(
          'providerManagementSliceEnabled requires agentProviderSettingsPort',
        );
      }
      _agentManagementController = null;
      _agentManagementComposition = AgentManagementSliceComposition.create(
        repositories: managementRepositories,
        providerSettings: settingsPort,
        runtimeListenable: _shellController,
        runtimeSnapshotProvider: _managementRuntimeSnapshot,
        textCatalog: widget.agentManagementTextCatalog,
      );
      _agentManagementComposition!.store.addListener(
        _handleAgentManagementChanged,
      );
    } else {
      _agentManagementComposition = null;
      _agentManagementController = AgentManagementController(
        repositories: managementRepositories,
        providerController: _shellController.agentProviderController,
        runtimeStateProvider: _managementRuntimeState,
        runtimeListenable: _shellController,
        textCatalog: widget.agentManagementTextCatalog,
      )..addListener(_handleAgentManagementChanged);
    }
    _agentUsageRefreshCoordinator = AgentUsageRefreshCoordinator(
      // turn 完成 / 启动预热走静默刷新：已有数据时不闪加载横条。
      refresh: () => _agentUsagePanelController.refresh(showLoading: false),
    );
    _shellStateSnapshotReader = _takeShellStateSnapshot;
    widget.shellStateSnapshotRelay.bind(_shellStateSnapshotReader);
    if (widget.enableAgentUsageAutoRefresh) {
      _scheduleInitialAgentUsageRefresh();
    }
    // 打开项目只走菜单栏（原生 File 菜单或标题栏菜单），不在项目列表放入口。
    MenuActionBridge.instance.setOpenProject(_handleMenuOpenProject);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_nativeMenuConfigured && widget.enableNativeWindowFrame) {
      _nativeMenuConfigured = true;
      final l10n = context.l10n;
      unawaited(
        MenuActionBridge.instance.configure(
          fileMenuLabel: l10n.workbenchMenuFile,
          openProjectLabel: l10n.workbenchMenuOpenProject,
        ),
      );
    }
  }

  /// 诊断与恢复测试使用的无正文 Shell 投影。
  ///
  /// 这里刻意同步读取各唯一 owner，既不缓存也不注册 listener；生产 Widget 仍只
  /// watch 各自的 feature selector。
  ZetaShellStateSnapshot _takeShellStateSnapshot() {
    final threadStates = _shellController.projectThreadsSliceStore.state;
    final projectThreads = <String, ZetaProjectThreadsStateSnapshot>{
      for (final entry in threadStates.statesByProject.entries)
        entry.key: ZetaProjectThreadsStateSnapshot.fromState(
          entry.key,
          entry.value,
        ),
    };
    final entries = _shellController.agentWorkspaceEntries;
    final selectedEntryId = _shellController.selectedAgentWorkspaceEntryId;
    final conversations = <String, ZetaConversationStateSnapshot>{};
    for (final entry in entries) {
      final slice = entry.sliceStore.state;
      final pendingInteractions = slice.pendingInteractions;
      conversations[entry.entryId] = ZetaConversationStateSnapshot(
        entryId: entry.entryId,
        projectPath: entry.projectPath,
        providerId: entry.providerId,
        threadId: entry.threadId,
        isDraft: entry.isDraft,
        isSelected: entry.entryId == selectedEntryId,
        sliceAvailable: true,
        threadOpenPhase: slice.header.threadOpenPhase,
        runtimeStatus: entry.threadSnapshot.runtimeStatus,
        isTurnRunning: slice.header.isTurnRunning,
        isReadOnly: slice.header.isReadOnly,
        visibleTurnCount: slice.history.visibleTurns.length,
        pendingInteractionCount:
            pendingInteractions.permissions.length +
            pendingInteractions.questions.length +
            pendingInteractions.planApprovals.length +
            (pendingInteractions.planExecutionHandoff == null ? 0 : 1),
        pendingOperationCount: slice.pendingOperations.length,
      );
    }
    final managementState = _agentManagementComposition?.store.state;
    return ZetaShellStateSnapshot(
      workspace: _shellController.workspaceSliceStore.state,
      projectThreadsByProjectPath: projectThreads,
      orderedConversationEntryIds: <String>[
        for (final entry in entries) entry.entryId,
      ],
      conversationsByEntryId: conversations,
      selectedConversationEntryId: selectedEntryId,
      projectHomeActive: _shellController.isProjectHomeActive,
      agentManagement: managementState == null
          ? null
          : ZetaAgentManagementStateSnapshot.fromState(managementState),
    );
  }

  @override
  void dispose() {
    MenuActionBridge.instance.setOpenProject(null);
    widget.shellStateSnapshotRelay.unbind(_shellStateSnapshotReader);
    if (widget.enableNativeWindowFrame) {
      windowManager.removeListener(this);
    }
    _shellController.removeListener(_handleShellChanged);
    _shellController.agentProviderController.removeListener(
      _handleAgentProviderSettingsUsageChanged,
    );
    widget.usageStatisticsSliceComposition.bindSelectionPersistence(null);
    _agentUsageRefreshCoordinator.dispose();
    final legacyManagement = _agentManagementController;
    if (legacyManagement != null) {
      legacyManagement.removeListener(_handleAgentManagementChanged);
      legacyManagement.dispose();
    }
    final managementComposition = _agentManagementComposition;
    if (managementComposition != null) {
      managementComposition.store.removeListener(_handleAgentManagementChanged);
      managementComposition.close();
    }
    widget.conversationSliceStoreRegistry.unbind();
    widget.conversationWorkspaceStoreRegistry.unbind(
      _shellController.agentConversationWorkspaceStore,
    );
    _shellController.dispose();
    widget.desktopAttentionTargetActivatorRelay.unbind(
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
      enableNativeWindowFrame: widget.enableNativeWindowFrame,
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
      showWindowControls: widget.showWindowControls,
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

    return ProviderScope(
      overrides: [
        projectThreadsSliceStoreProvider.overrideWithValue(
          _shellController.projectThreadsSliceStore,
        ),
        workspaceSliceStoreProvider.overrideWithValue(
          _shellController.workspaceSliceStore,
        ),
      ],
      child: body,
    );
  }

  List<WindowMenu> _windowMenus(BuildContext context) {
    if (!widget.enableNativeWindowFrame) {
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
                    appearanceController: widget.appearanceController,
                    generalSettingsController: widget.generalSettingsController,
                    agentManagementController: _agentManagementController,
                    agentManagementSliceStore:
                        _agentManagementComposition?.store,
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
      return GlobalHomePage(
        installedProviders: _installedHomeProviders,
        onOpenProject: _openProject,
        isLoadingProviders: _homeProvidersLoading,
        providerError: _homeProviderError,
      );
    }

    return Consumer(
      builder: (context, ref, _) {
        final workspaceState = ref.watch(agentConversationWorkspaceProvider);
        final workspaceStore = ref.watch(
          agentConversationWorkspaceStoreProvider,
        );
        final entries = <AgentThreadWorkspaceEntry>[
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
        final sliceStore = ref.watch(generalSettingsSliceStoreProvider);
        if (sliceStore != null) {
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
        }
        return ValueListenableBuilder<GeneralSettings>(
          valueListenable: widget.generalSettingsController.listenable,
          builder: (context, generalSettings, _) => _buildAgentEntryPages(
            entries: entries,
            projectPath: projectPath,
            projectHomeId: projectHomeId,
            selectedId: selectedId,
            projectHomeActive: workspaceState.projectHomeActive,
            generalSettings: generalSettings,
            projectThreadState: projectThreadState,
          ),
        );
      },
    );
  }

  Widget _buildAgentEntryPages({
    required List<AgentThreadWorkspaceEntry> entries,
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
                viewModel: entry.viewModel,
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
        return ProjectListPane(
          projects: _shellController.projects,
          activeProject: _shellController.activeProjectPath,
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
    final page = UsageStatisticsPage(
      key: const ValueKey('usage-statistics-page-host'),
      controller: _usageStatisticsController,
      onOpenAgentManagement: _openAgentManagementFromUsage,
    );
    return Consumer(
      builder: (context, ref, _) {
        ref.watch(usageStatisticsSliceProvider);
        return page;
      },
    );
  }

  Widget _buildAgentUsagePanel() {
    Widget buildPanel() => AgentUsagePanelContent(
      controller: _agentUsagePanelController,
      mode: _agentUsageExpanded
          ? AgentUsagePanelMode.expanded
          : AgentUsagePanelMode.collapsed,
      onModeChanged: (mode) {
        setState(() {
          _agentUsageExpanded = mode == AgentUsagePanelMode.expanded;
        });
      },
    );
    return Consumer(
      builder: (context, ref, _) {
        ref.watch(agentUsagePanelSliceProvider);
        return buildPanel();
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
        final state = ref.watch(workspaceSliceProvider);
        return buildPanel(
          nodes: state.tree,
          expandedPaths: state.expandedDirectoryPaths,
          selectedPath: state.selectedTreePath,
          projectPath: state.activeProjectPath,
          isLoading: state.isLoadingProject,
        );
      },
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
    _requestAgentUsageRefresh();
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

  /// 标题栏 / 原生菜单「文件 - 打开项目」入口。
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
    final entry =
        _shellController.agentConversationWorkspaceStore.selectedEntry;
    unawaited(
      _desktopAttentionStore.updateVisibility(
        DesktopAttentionVisibility(
          windowFocused: _windowFocused,
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
        message: context.l10n.workbenchCannotOpenNotificationThread,
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
        await _agentManagementOperations.initialize();
        if (!mounted || token != _globalHomeLoadToken) {
          return;
        }
        _setInstalledHomeProviders(_agentManagementOperations.agents);
        cachedProviders
          ..clear()
          ..addAll(_installedHomeProviders);
        setState(() {});

        await _agentManagementOperations.detect();
        if (!mounted || token != _globalHomeLoadToken) {
          return;
        }
        final detectionError = _agentManagementOperations.operationError;
        if (detectionError == null) {
          _setInstalledHomeProviders(_agentManagementOperations.agents);
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
      _homeProviderError = context.l10n.workbenchProviderDetectionFailed(
        '$error',
      );
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
    if (_page != _IdeHomePage.home) {
      // 设置页会自行监听同一状态；这里只刷新隐藏首页的缓存，回到首页时
      // 页面切换本身会触发重建，无需让 Workbench 根节点在子页构建期标脏。
      _setInstalledHomeProviders(_agentManagementOperations.agents);
      return;
    }
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_agentManagementHomeRefreshScheduled) {
        return;
      }
      _agentManagementHomeRefreshScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _agentManagementHomeRefreshScheduled = false;
        if (!mounted ||
            _homeProvidersLoading ||
            widget.homeProviderDetectionLoader != null) {
          return;
        }
        if (_page != _IdeHomePage.home) {
          _setInstalledHomeProviders(_agentManagementOperations.agents);
          return;
        }
        setState(() {
          _setInstalledHomeProviders(_agentManagementOperations.agents);
        });
      });
      return;
    }
    setState(() {
      _setInstalledHomeProviders(_agentManagementOperations.agents);
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

  AgentManagementRuntimeSnapshot _managementRuntimeSnapshot() => (
    activeAgentId: _shellController.agentProviderController.activeProviderId,
    runtimeState: _managementRuntimeState(),
  );

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

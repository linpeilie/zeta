import 'dart:async';

import 'package:zeta/src/app/provider_settings_slice/provider_settings_slice_composition.dart';
import 'package:zeta/src/app/ide_session_slice/ide_session_slice_overrides.dart';
import 'package:zeta/src/app/settings_slice/settings_slice_composition.dart';
import 'package:zeta/src/app/usage_statistics_slice/usage_statistics_slice_composition.dart';
import 'package:zeta/src/app/agent_management_slice/agent_management_slice_composition.dart';
import 'package:zeta/src/app/agent_management_slice/agent_management_slice_runner.dart';
import 'package:zeta/src/app/composition/ide_workbench_composition.dart';
import 'package:zeta/src/app/composition/zeta_application_composition.dart';
import 'package:zeta/src/app/composition/zeta_host_mode.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:window_manager/window_manager.dart';

import 'package:zeta/src/app/app_constants.dart';
import 'package:zeta/src/app/composition/agent_resource_shutdown.dart';
import 'package:zeta/src/app/composition/zeta_state_snapshot.dart';
import 'package:zeta/src/app/desktop_attention_slice/desktop_attention_slice_composition.dart';
import 'package:zeta/src/app/conversation_workspace_slice/agent_conversation_workspace_providers.dart';
import 'package:zeta/src/app/localization/zeta_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:zeta/src/app/composition/app_dependencies.dart';
import 'package:zeta/src/app/observability/zeta_observability.dart';
import 'package:zeta/src/app/plugins/zeta_plugin_catalog.dart';
import 'package:zeta/src/app/localization/zeta_text_catalogs.dart';
import 'package:zeta/src/app/window_bootstrap.dart';
import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta/src/core/storage/zeta_data_paths.dart';
import 'package:zeta/src/ui/core/system_file_manager.dart';
import 'package:zeta/src/features/agent/application/agent_model_catalog_repository.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_codec.dart';
import 'package:zeta/src/features/agent/presentation/provider_settings_slice/agent_model_catalog_projection_providers.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_store_registry.dart';
import 'package:zeta/src/features/agent/presentation/conversation_slice/agent_conversation_slice_providers.dart';
import 'package:zeta/src/features/agent/presentation/provider_settings_slice/agent_provider_settings_slice_providers.dart';
import 'package:zeta/src/features/desktop_notifications/domain/desktop_attention_models.dart';
import 'package:zeta/src/features/desktop_notifications/domain/desktop_attention_text_catalog.dart';
import 'package:zeta/src/features/desktop_notifications/data/flutter_desktop_notification_service.dart';
import 'package:zeta/src/features/desktop_notifications/data/method_channel_desktop_attention_indicator.dart';
import 'package:zeta/src/features/desktop_notifications/presentation/desktop_attention_slice_providers.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_text_catalog.dart';
import 'package:zeta/src/features/ide_session/data/ide_session_store.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_notifier.dart';
import 'package:zeta/src/features/settings/data/appearance_settings_store.dart';
import 'package:zeta/src/features/settings/data/general_settings_store.dart';
import 'package:zeta/src/features/settings/presentation/appearance_theme_mode_mapper.dart';
import 'package:zeta/src/features/settings/presentation/settings_slice/settings_slice_providers.dart';
import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_mapping.dart';
import 'package:zeta/src/features/settings/data/system_font_catalog_service.dart';
import 'package:zeta/src/features/settings/domain/app_language.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';
import 'package:zeta/src/features/usage_statistics/data/usage_statistics_partition_store.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_panel_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_text_catalog.dart';
import 'package:zeta/src/features/usage_statistics/presentation/usage_statistics_slice/usage_statistics_slice_providers.dart';
import 'package:zeta_ui/zeta_ui.dart';
import 'package:zeta/src/ui/features/ide/views/ide_home.dart';
import 'package:zeta/src/ui/localization/generated/app_localizations.dart';

/// 应用根组件。
///
/// 允许测试注入目录选择器、会话存储和 Agent provider 工厂；生产环境使用真实实现。
/// 全局设置由纯 Dart slice store 统一管理，并由 app 组合层持久化。
class MainApp extends StatefulWidget {
  const MainApp({
    super.key,
    this.directoryPicker,
    this.enableNativeWindowFrame = true,
    this.showWindowControls = true,
    this.hostMode = ZetaHostMode.local,
    this.ideSessionStore,
    this.agentProviderFactory,
    this.agentProviderConfigStore,
    this.agentProviderAvailabilityLoader,
    this.homeProviderDetectionLoader,
    this.projectLocationOpener,
    this.appearanceSettingsStore,
    this.initialAppearanceSettings,
    this.generalSettingsStore,
    this.systemFontCatalogService,
    this.fallbackLanguage = AppLanguage.simplifiedChinese,
    this.displayLanguageOverride,
    this.waitForGeneralSettings = false,
    this.dataPaths,
    this.usageStatisticsPartitionStore,
    this.agentUsagePanelRepository,
    this.agentModelCatalogRepository,
    this.agentProviderRuntimeRegistry,
    this.desktopNotificationService,
    this.desktopAttentionIndicator,
    this.turnContextStore,
    this.observability,
  });

  final Future<String?> Function()? directoryPicker;
  final bool enableNativeWindowFrame;

  /// 测试可关闭原生窗口控制按钮，避免依赖桌面平台通道。
  final bool showWindowControls;

  /// 宿主运行模式：决定持久化落盘还是留内存、是否允许访问本机 Agent CLI。
  final ZetaHostMode hostMode;

  /// 会话仓库；未注入时按 [hostMode] 选择文件或内存实现。
  final IdeSessionStore? ideSessionStore;
  final AgentProviderBundleFactory? agentProviderFactory;
  final AgentProviderConfigStore? agentProviderConfigStore;
  final AgentProviderAvailabilityLoader? agentProviderAvailabilityLoader;
  final HomeProviderDetectionLoader? homeProviderDetectionLoader;
  final ProjectLocationOpener? projectLocationOpener;

  /// 外观持久化端口注入点；测试可传内存实现避免触碰真实用户文件。
  final AppearanceSettingsStore? appearanceSettingsStore;

  /// 启动阶段已读入的外观偏好，供第一帧使用，避免先按默认 system 再跳变。
  final AppearanceSettings? initialAppearanceSettings;

  /// 常规设置持久化端口注入点；生产环境默认使用配置目录中的版本化 JSON。
  final GeneralSettingsStore? generalSettingsStore;

  /// 系统字体目录注入点；测试可传确定性实现。
  final SystemFontCatalogService? systemFontCatalogService;

  /// 常规设置文件缺失或损坏时使用的语言。
  final AppLanguage fallbackLanguage;

  /// 测试可强制显示语言。生产路径在常规设置加载后冻结 `settings.appLanguage`。
  final AppLanguage? displayLanguageOverride;

  /// 是否等到常规设置加载完成后再挂有文字的 UI。
  ///
  /// 生产 `main` 传 true；Widget 测试默认 false，避免多等一帧。
  final bool waitForGeneralSettings;

  /// app 级可观测性组合；默认关闭采集，探针退化为 no-op。
  final ZetaObservability? observability;

  /// 生产启动阶段解析并初始化的 Zeta 自有数据路径。
  ///
  /// 未传入时使用内存/回调存储，避免测试或嵌入式宿主意外写入真实 HOME。
  final ZetaDataPaths? dataPaths;

  /// 使用统计索引存储注入点；默认按 [dataPaths] 选择文件或内存实现。
  final UsageStatisticsPartitionStore? usageStatisticsPartitionStore;

  /// Context Agent 统计面板的数据注入点，供 Widget 测试隔离本机 Agent 历史。
  final AgentUsagePanelRepository? agentUsagePanelRepository;

  /// 应用级共享模型目录；生产默认持久化到 `~/.zeta/cache`。
  final AgentModelCatalogRepository? agentModelCatalogRepository;

  /// 应用级 Provider 运行时池；测试可注入以验证实例复用与退出回收。
  final AgentProviderRuntimeRegistry? agentProviderRuntimeRegistry;
  final DesktopNotificationService? desktopNotificationService;
  final DesktopAttentionIndicator? desktopAttentionIndicator;
  final AgentTurnContextStore? turnContextStore;

  @override
  State<MainApp> createState() => MainAppState();
}

class MainAppState extends State<MainApp>
    with WidgetsBindingObserver, WindowListener {
  /// Phase 3 第 1 批关批后的唯一 settings 组合。
  late final SettingsSliceComposition _settingsSliceComposition;

  /// 本地化与 Provider 插件目录就绪后创建的唯一 Provider settings 组合。
  ProviderSettingsSliceComposition? _providerSettingsSliceComposition;

  /// Phase 3 第 3 批 3b 组合；本地化运行时就绪后创建并成为唯一 owner。
  UsageStatisticsSliceComposition? _usageStatisticsSliceComposition;

  /// Phase 3 第 4 批 4b 组合；IDE Session 的唯一运行态 owner。
  /// MainApp 自持的 Riverpod 容器。
  ///
  /// 用 `UncontrolledProviderScope` 而不是 `ProviderScope`：组合根需要在 Widget
  /// 树之外读切片状态（见 [takeStateSnapshot]），这是 Riverpod 给组合根准备的
  /// 标准做法。overrides 定长且只在 `initState` 装配一次，容器整个 app session
  /// 存活，不再靠替换 ProviderScope 的 key 来换容器。
  late final ProviderContainer _container;

  /// Phase 3 第 5 批：Desktop Attention 的唯一状态与副作用组合。
  DesktopAttentionSliceComposition? _desktopAttentionSliceComposition;
  final DesktopAttentionTargetActivatorRelay
  _desktopAttentionTargetActivatorRelay =
      DesktopAttentionTargetActivatorRelay();

  /// 在 `IdeHome.initState` 同步接入 Workspace，保证首个会话 build 只有新路径。
  final AgentConversationSliceStoreRegistry _conversationSliceStoreRegistry =
      AgentConversationSliceStoreRegistry();
  final AgentConversationWorkspaceStoreRegistry
  _conversationWorkspaceStoreRegistry =
      AgentConversationWorkspaceStoreRegistry();

  /// 诊断/恢复测试按需读取 Shell 投影的桥；没有 listener，不参与 Widget rebuild。
  final ZetaShellStateSnapshotRelay _shellStateSnapshotRelay =
      ZetaShellStateSnapshotRelay();

  /// 三个显式 Provider 的编译期插件目录。
  ZetaPluginCatalog? _pluginCatalog;
  late AgentProviderBundleFactory _agentProviderFactory;
  late AgentProviderRuntimeRegistry _agentProviderRuntimeRegistry;
  late final AgentProviderDefinitionCatalog _agentProviderDefinitions;
  late final AgentProviderSettingsCodec _agentProviderSettingsCodec;
  late final AgentProviderConfigStore _agentProviderConfigStore;
  Future<void> Function()? _providerRuntimeShutdownHook;
  late final ZetaApplicationComposition _appComposition;
  bool _ownsAgentProviderRuntimeRegistry = false;
  AppLifecycleState? _appLifecycleState;
  bool _nativeWindowSuspended = false;
  var _generalSettingsReady = false;
  var _localeRuntimeReady = false;
  late Locale _frozenDisplayLocale;
  late AgentUiTextCatalog _agentUiTextCatalog;
  late AgentManagementTextCatalog _agentManagementTextCatalog;
  ZetaUiTextCatalog _zetaUiTextCatalog = const FallbackZetaUiTextCatalog();
  late DesktopAttentionTextCatalog _desktopAttentionTextCatalog;
  late UsageStatisticsTextCatalog _usageStatisticsTextCatalog;

  /// 按需读取当前逻辑状态树；生产 Widget 不得订阅或在 build 中调用。
  ZetaStateSnapshot takeStateSnapshot() {
    final usageComposition = _requiredUsageStatisticsComposition;
    return ZetaStateSnapshot(
      shell: _shellStateSnapshotRelay.read(),
      ideSession: _container.read(ideSessionSliceProvider),
      usageStatistics: usageComposition.usageStatisticsStore.state,
      agentUsagePanel: usageComposition.agentUsagePanelStore.state,
      desktopAttention: ZetaDesktopAttentionStateSnapshot.fromState(
        _requiredDesktopAttentionComposition.store.state,
      ),
      appearanceSettings: _settingsSliceComposition.appearanceStore.state,
      generalSettings: _settingsSliceComposition.generalStore.state,
      providerSettings: _requiredProviderSettingsComposition.store.state,
    );
  }

  /// 按依赖反序关闭本实例拥有的 Agent 资源。
  ///
  /// 顺序是硬要求：**runtime registry 先、plugin catalog 后**。插件贡献出的
  /// 工厂是 runtime 的上游依赖，先关插件会让仍在退出中的 runtime 失去依赖；
  /// 窗口关闭 hook 与 `dispose` 共用这一个入口，避免两条路径顺序不一致。
  ///
  /// 幂等：registry 与 catalog 的 `close()` 本身都可重复调用。
  Future<void> _shutdownOwnedAgentResources() {
    final pluginCatalog = _pluginCatalog;
    _pluginCatalog = null;
    return shutdownAgentResourcesInOrder(
      closeRuntimeRegistry: _ownsAgentProviderRuntimeRegistry
          ? _agentProviderRuntimeRegistry.close
          : null,
      closePluginCatalog: pluginCatalog?.close,
    );
  }

  /// 工作台组合工厂：把 Repository / registry / 文本目录闭包在 app 层。
  ///
  /// `IdeHome` 只补 Shell 派生的两个入参，因此 UI 层不再出现任何 Repository 类型。
  IdeWorkbenchComposition _createWorkbenchComposition({
    required AgentManagementRuntimeSubscribe subscribeRuntime,
    required AgentManagementRuntimeSnapshotProvider runtimeSnapshotProvider,
  }) {
    return IdeWorkbenchComposition.create(
      modelCatalogRepository: _appComposition.agentModelCatalogRepository,
      runtimeRegistry: _agentProviderRuntimeRegistry,
      providerSettings: _requiredProviderSettingsComposition.store,
      subscribeRuntime: subscribeRuntime,
      runtimeSnapshotProvider: runtimeSnapshotProvider,
      textCatalog: _agentManagementTextCatalog,
    );
  }

  /// 当前生效的脱敏指标端口；未注入 [MainApp.observability] 时为 no-op。
  ZetaMetricsPort get _metrics =>
      widget.observability?.metrics ?? noopZetaMetricsPort;

  @override
  void initState() {
    super.initState();
    _appLifecycleState = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
    if (widget.enableNativeWindowFrame) {
      windowManager.addListener(this);
    }
    _appComposition = ZetaApplicationComposition.create(
      hostMode: widget.hostMode,
      dataPaths: widget.dataPaths,
      ideSessionStore: widget.ideSessionStore,
      usageStatisticsPartitionStore: widget.usageStatisticsPartitionStore,
      agentModelCatalogRepository: widget.agentModelCatalogRepository,
      turnContextStore: widget.turnContextStore,
      agentProviderConfigStore: widget.agentProviderConfigStore,
    );
    _frozenDisplayLocale = ZetaLocalization.localeFor(
      widget.displayLanguageOverride ?? widget.fallbackLanguage,
    );
    final injectedFactory = widget.agentProviderFactory;
    if (injectedFactory != null) {
      _agentProviderFactory = injectedFactory;
    }
    final injectedRuntimeRegistry = widget.agentProviderRuntimeRegistry;
    if (injectedRuntimeRegistry != null) {
      _agentProviderRuntimeRegistry = injectedRuntimeRegistry;
      _ownsAgentProviderRuntimeRegistry = false;
      _providerRuntimeShutdownHook = _shutdownOwnedAgentResources;
    } else if (injectedFactory != null) {
      _agentProviderRuntimeRegistry = AgentProviderRuntimeRegistry(
        providerFactory: injectedFactory,
        metrics: _metrics,
        providerMetricLabel: AgentMetricLabels.forProviderId,
      );
      _ownsAgentProviderRuntimeRegistry = true;
      _providerRuntimeShutdownHook = _shutdownOwnedAgentResources;
      if (widget.enableNativeWindowFrame) {
        addDesktopWindowShutdownHook(_providerRuntimeShutdownHook!);
      }
    }
    _settingsSliceComposition = SettingsSliceComposition.create(
      useFilePersistence: _useFilePersistence,
      dataPaths: widget.dataPaths,
      fallbackLanguage: widget.fallbackLanguage,
      appearanceSettingsStore: widget.appearanceSettingsStore,
      generalSettingsStore: widget.generalSettingsStore,
      fontCatalog: widget.systemFontCatalogService,
      initialAppearanceSettings: widget.initialAppearanceSettings,
    );
    _container = ProviderContainer(
      observers: widget.observability?.providerObservers,
      overrides: _composeOverrides(),
    );
    final loadGeneralSettings = _settingsSliceComposition.generalSettingsReady;
    final overrideLanguage = widget.displayLanguageOverride;
    final shouldWait = widget.waitForGeneralSettings;
    if (overrideLanguage != null || !shouldWait) {
      _installLocaleDependentRuntime(
        overrideLanguage ?? widget.fallbackLanguage,
      );
    }
    if (shouldWait) {
      unawaited(
        loadGeneralSettings.then((settings) {
          if (!mounted || _generalSettingsReady) {
            return;
          }
          _installLocaleDependentRuntime(
            overrideLanguage ?? settings.appLanguage,
          );
          setState(() => _generalSettingsReady = true);
        }),
      );
    } else {
      _generalSettingsReady = true;
      unawaited(loadGeneralSettings);
    }
  }

  void _installLocaleDependentRuntime(AppLanguage language) {
    if (!_localeRuntimeReady) {
      _frozenDisplayLocale = ZetaLocalization.localeFor(language);
      final textCatalogs = ZetaTextCatalogs(
        lookupAppLocalizations(_frozenDisplayLocale),
      );
      _agentUiTextCatalog = textCatalogs.agentUi;
      _agentManagementTextCatalog = textCatalogs.agentManagement;
      _desktopAttentionTextCatalog = textCatalogs.desktopAttention;
      _usageStatisticsTextCatalog = textCatalogs.usageStatistics;
      _zetaUiTextCatalog = textCatalogs.zetaUi;
    }
    if (!_localeRuntimeReady) {
      final catalog = ZetaPluginCatalog.builtIn(
        claudeCodeSessionDecisionStoreFactory:
            _appComposition.claudeCodeSessionDecisionStoreFactory,
        claudeCodeHiddenThreadStore:
            _appComposition.claudeCodeHiddenThreadStore,
        textCatalog: _agentUiTextCatalog,
        metrics: _metrics,
      );
      final resolvedProviders = catalog.activateAndResolveAgentProviders();
      _pluginCatalog = catalog;
      _agentProviderDefinitions = resolvedProviders.definitions;
      _agentProviderSettingsCodec = AgentProviderSettingsCodec(
        providerDefinitions: _agentProviderDefinitions,
      );
      _agentProviderConfigStore = _appComposition
          .createAgentProviderConfigStore(_agentProviderSettingsCodec);
      if (widget.agentProviderFactory == null) {
        _agentProviderFactory = resolvedProviders.bundleFactory;
      }
    }
    if (widget.agentProviderRuntimeRegistry == null &&
        widget.agentProviderFactory == null &&
        !_localeRuntimeReady) {
      _agentProviderRuntimeRegistry = AgentProviderRuntimeRegistry(
        providerFactory: _agentProviderFactory,
        metrics: _metrics,
        providerMetricLabel: AgentMetricLabels.forProviderId,
      );
      _ownsAgentProviderRuntimeRegistry = true;
      _providerRuntimeShutdownHook = _shutdownOwnedAgentResources;
      if (widget.enableNativeWindowFrame) {
        addDesktopWindowShutdownHook(_providerRuntimeShutdownHook!);
      }
    }
    _providerSettingsSliceComposition ??=
        ProviderSettingsSliceComposition.create(
          configStore: _agentProviderConfigStore,
          modelCatalogRepository: _appComposition.agentModelCatalogRepository,
          runtimeRegistry: _agentProviderRuntimeRegistry,
          providerDefinitions: _agentProviderDefinitions,
        );
    _usageStatisticsSliceComposition ??= UsageStatisticsSliceComposition.create(
      loadEnabledProviders: _loadEnabledAgentUsageProviders,
      runtimeRegistry: _agentProviderRuntimeRegistry,
      partitionStore: _appComposition.usageStatisticsPartitionStore,
      agentUsagePanelRepository: widget.agentUsagePanelRepository,
      textCatalog: _usageStatisticsTextCatalog,
    );
    _desktopAttentionSliceComposition ??=
        DesktopAttentionSliceComposition.create(
          notificationService:
              widget.desktopNotificationService ??
              (widget.enableNativeWindowFrame
                  ? FlutterDesktopNotificationService(
                      linuxActionName: _desktopAttentionTextCatalog.linuxAction,
                    )
                  : const NoopDesktopNotificationService()),
          indicator:
              widget.desktopAttentionIndicator ??
              (widget.enableNativeWindowFrame
                  ? MethodChannelDesktopAttentionIndicator()
                  : const NoopDesktopAttentionIndicator()),
          notificationSettingsSource:
              _settingsSliceComposition.notificationSettingsSource,
          activateTarget: _desktopAttentionTargetActivatorRelay.call,
          textCatalog: _desktopAttentionTextCatalog,
        );
    _localeRuntimeReady = true;
  }

  @override
  void didUpdateWidget(covariant MainApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enableNativeWindowFrame == widget.enableNativeWindowFrame) {
      return;
    }
    if (widget.enableNativeWindowFrame) {
      windowManager.addListener(this);
      final hook = _providerRuntimeShutdownHook;
      if (hook != null) {
        addDesktopWindowShutdownHook(hook);
      }
      return;
    }
    windowManager.removeListener(this);
    final hook = _providerRuntimeShutdownHook;
    if (hook != null) {
      removeDesktopWindowShutdownHook(hook);
    }
    _nativeWindowSuspended = false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.enableNativeWindowFrame) {
      windowManager.removeListener(this);
      final hook = _providerRuntimeShutdownHook;
      if (hook != null) {
        removeDesktopWindowShutdownHook(hook);
      }
    }
    _usageStatisticsSliceComposition?.dispose();
    _usageStatisticsSliceComposition = null;
    _desktopAttentionSliceComposition?.dispose();
    _desktopAttentionSliceComposition = null;
    _providerSettingsSliceComposition?.dispose();
    _providerSettingsSliceComposition = null;
    unawaited(_shutdownOwnedAgentResources());
    _settingsSliceComposition.dispose();
    _container.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_appLifecycleState == state) {
      return;
    }
    setState(() => _appLifecycleState = state);
  }

  @override
  void onWindowMinimize() => _setNativeWindowSuspended(true);

  @override
  void onWindowRestore() => _resumeNativeWindowTickers();

  @override
  void onWindowMaximize() => _resumeNativeWindowTickers();

  @override
  void onWindowFocus() => _resumeNativeWindowTickers();

  @override
  void onWindowEnterFullScreen() => _resumeNativeWindowTickers();

  @override
  void onWindowEvent(String eventName) {
    // window_manager 0.5.x 会从 Windows WM_SHOWWINDOW 发出 show，
    // 但 WindowListener 尚无对应的强类型回调。
    if (eventName == 'show') {
      _resumeNativeWindowTickers();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 容器由 MainApp 自己持有，而不是放在 `main.dart`：那样每个 pump MainApp 的
    // 测试都要自己补一层 scope，接线一旦漏掉就是运行期 "No ProviderScope found"，
    // 而不是编译期错误。
    return UncontrolledProviderScope(
      container: _container,
      child: _buildApp(context),
    );
  }

  /// 组合根的全部 override。
  ///
  /// **定长且只装配一次。** 依赖延迟到 `overrideWith` 的闭包里读，因此语言持久化
  /// 完成后才建出来的三个切片组合不会改变 override 的数量——旧实现靠替换
  /// ProviderScope 的 key 来换容器，那会连带丢掉容器里已有的全部状态。
  /// 尚未组合就被读到时，`_requiredXxx` 会 fail-closed 抛错。
  List<Override> _composeOverrides() {
    return <Override>[
      zetaMetricsPortProvider.overrideWith((ref) => _metrics),
      ...ideSessionSliceOverrides(
        sessionStore: _appComposition.ideSessionStore,
      ),
      agentConversationSliceStoreRegistryProvider.overrideWithValue(
        _conversationSliceStoreRegistry,
      ),
      agentConversationWorkspaceStoreRegistryProvider.overrideWithValue(
        _conversationWorkspaceStoreRegistry,
      ),
      appearanceSettingsSliceStoreProvider.overrideWith(
        (ref) => _settingsSliceComposition.appearanceStore,
      ),
      generalSettingsSliceStoreProvider.overrideWith(
        (ref) => _settingsSliceComposition.generalStore,
      ),
      agentProviderSettingsSliceStoreProvider.overrideWith(
        (ref) => _requiredProviderSettingsComposition.store,
      ),
      agentModelCatalogProjectionSourceProvider.overrideWith(
        (ref) => _requiredProviderSettingsComposition,
      ),
      usageStatisticsSliceStoreProvider.overrideWith(
        (ref) => _requiredUsageStatisticsComposition.usageStatisticsStore,
      ),
      agentUsagePanelSliceStoreProvider.overrideWith(
        (ref) => _requiredUsageStatisticsComposition.agentUsagePanelStore,
      ),
      desktopAttentionSliceStoreProvider.overrideWith(
        (ref) => _requiredDesktopAttentionComposition.store,
      ),
    ];
  }

  Widget _buildApp(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) => _buildThemedApp(
        appearanceSettingsFromSlice(
          ref.watch(appearanceSettingsSliceValueProvider),
        ),
      ),
    );
  }

  Widget _buildThemedApp(AppearanceSettings settings) {
    {
      final lightIdeTheme = buildIdeThemeData(
        brightness: Brightness.light,
        uiFontFamily: settings.uiFontFamily,
        codeFontFamily: settings.codeFontFamily,
        uiFontSize: settings.uiFontSize,
        codeFontSize: settings.codeFontSize,
      );
      final darkIdeTheme = buildIdeThemeData(
        brightness: Brightness.dark,
        uiFontFamily: settings.uiFontFamily,
        codeFontFamily: settings.codeFontFamily,
        uiFontSize: settings.uiFontSize,
        codeFontSize: settings.codeFontSize,
      );
      final flutterThemeMode = themeModeForPreference(settings.themeMode);
      final materialBrightness = resolveBrightnessForThemeMode(
        flutterThemeMode,
      );
      final materialIdeTheme = materialBrightness == Brightness.dark
          ? darkIdeTheme
          : lightIdeTheme;
      return TickerMode(
        enabled: _tickersEnabled,
        // 设计系统自有文案（无障碍标签、滚动条提示等）不经 generated l10n，
        // 由组合层在这里注入一次；未注入时 zeta_ui 回退英文。
        child: IdeUiTextScope(
          catalog: _zetaUiTextCatalog,
          child: IdeThemeScope(
            themeMode: flutterThemeMode,
            lightTheme: lightIdeTheme,
            darkTheme: darkIdeTheme,
            child: sf.ShadcnApp(
              debugShowCheckedModeBanner: false,
              title: appTitle,
              locale: _frozenDisplayLocale,
              supportedLocales: ZetaLocalization.supportedLocales,
              localizationsDelegates: ZetaLocalization.delegates,
              popoverHandler: ideStablePopoverOverlayHandler,
              tooltipHandler: ideStablePopoverOverlayHandler,
              menuHandler: ideStablePopoverOverlayHandler,
              theme: buildShadcnTheme(lightIdeTheme),
              darkTheme: buildShadcnTheme(darkIdeTheme),
              materialTheme: buildMaterialTheme(materialIdeTheme),
              themeMode: resolveShadcnThemeMode(flutterThemeMode),
              home: _generalSettingsReady
                  ? IdeHome(
                      key: const ValueKey<String>('zeta.ide-home'),
                      directoryPicker:
                          widget.directoryPicker ?? getDirectoryPath,
                      enableNativeWindowFrame: widget.enableNativeWindowFrame,
                      showWindowControls: widget.showWindowControls,
                      shellStateSnapshotRelay: _shellStateSnapshotRelay,
                      agentProviderFactory: _agentProviderFactory,
                      agentProviderRuntimeRegistry:
                          _agentProviderRuntimeRegistry,
                      desktopAttentionSliceComposition:
                          _requiredDesktopAttentionComposition,
                      desktopAttentionTargetActivatorRelay:
                          _desktopAttentionTargetActivatorRelay,
                      conversationSliceStoreRegistry:
                          _conversationSliceStoreRegistry,
                      conversationWorkspaceStoreRegistry:
                          _conversationWorkspaceStoreRegistry,
                      agentProviderSettingsPort:
                          _requiredProviderSettingsComposition.store,
                      activeModelCatalogLoader: () =>
                          _requiredProviderSettingsComposition
                              .loadActiveModelCatalog(),
                      agentProviderAvailabilityLoader:
                          widget.agentProviderAvailabilityLoader,
                      homeProviderDetectionLoader:
                          widget.homeProviderDetectionLoader ??
                          (_blocksLocalCliAccess
                              ? _loadNoInstalledHomeProviders
                              : null),
                      projectLocationOpener:
                          widget.projectLocationOpener ??
                          openPathInSystemFileManager,
                      usageStatisticsSliceComposition:
                          _requiredUsageStatisticsComposition,
                      workbenchCompositionFactory: _createWorkbenchComposition,
                      turnContextStore: _appComposition.turnContextStore,
                      agentUiTextCatalog: _agentUiTextCatalog,
                      metrics: _metrics,
                      providerMetricLabel: AgentMetricLabels.forProviderId,
                      agentManagementTextCatalog: _agentManagementTextCatalog,
                      // 回调存储用于测试/嵌入宿主；未显式注入统计仓储时不读取本机 CLI 历史。
                      enableAgentUsageAutoRefresh:
                          !_blocksLocalCliAccess ||
                          widget.agentUsagePanelRepository != null,
                    )
                  : ColoredBox(
                      key: const ValueKey<String>('zeta.localization-loading'),
                      color: materialIdeTheme.colors.frame,
                    ),
            ),
          ),
        ),
      );
    }
  }

  bool get _tickersEnabled {
    final state = _appLifecycleState;
    final lifecycleAllowsTickers =
        state == null ||
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    return lifecycleAllowsTickers && !_nativeWindowSuspended;
  }

  UsageStatisticsSliceComposition get _requiredUsageStatisticsComposition =>
      _usageStatisticsSliceComposition ??
      (throw StateError('Usage Statistics composition is not ready'));

  DesktopAttentionSliceComposition get _requiredDesktopAttentionComposition =>
      _desktopAttentionSliceComposition ??
      (throw StateError('Desktop Attention composition is not ready'));

  ProviderSettingsSliceComposition get _requiredProviderSettingsComposition =>
      _providerSettingsSliceComposition ??
      (throw StateError('Provider Settings composition is not ready'));

  Future<List<AgentProviderConfig>> _loadEnabledAgentUsageProviders() async {
    final providerSettings = _requiredProviderSettingsComposition.store;
    await providerSettings.loadSettings();
    return providerSettings.enabledProviders;
  }

  void _resumeNativeWindowTickers() {
    // Windows 从“最小化前为最大化/全屏”恢复时，平台事件
    // 可能是 maximize/enter-full-screen 而不是 restore。
    _setNativeWindowSuspended(false);
  }

  void _setNativeWindowSuspended(bool suspended) {
    if (_nativeWindowSuspended == suspended || !mounted) {
      return;
    }
    setState(() => _nativeWindowSuspended = suspended);
  }

  /// 是否把持久化落到本机文件。语义现在只由宿主模式与 dataPaths 决定。
  bool get _useFilePersistence => _appComposition.usesFilePersistence;

  /// 是否禁止访问本机 Agent CLI（安装探测与用量历史）。
  bool get _blocksLocalCliAccess => !widget.hostMode.allowsLocalCliAccess;
}

Future<List<ManagedAgent>> _loadNoInstalledHomeProviders() async =>
    const <ManagedAgent>[];

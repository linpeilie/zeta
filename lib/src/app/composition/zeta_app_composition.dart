import 'dart:async';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';
import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta_ui/zeta_ui.dart';

import 'package:zeta/src/app/agent_management_slice/agent_management_slice_composition.dart';
import 'package:zeta/src/app/agent_management_slice/agent_management_slice_runner.dart';
import 'package:zeta/src/app/composition/agent_resource_shutdown.dart';
import 'package:zeta/src/app/composition/app_dependencies.dart';
import 'package:zeta/src/app/composition/ide_workbench_composition.dart';
import 'package:zeta/src/app/composition/zeta_host_mode.dart';
import 'package:zeta/src/app/composition/zeta_state_snapshot.dart';
import 'package:zeta/src/app/conversation_workspace_slice/agent_conversation_workspace_providers.dart';
import 'package:zeta/src/app/desktop_attention_slice/desktop_attention_slice_composition.dart';
import 'package:zeta/src/app/ide_session_slice/ide_session_slice_overrides.dart';
import 'package:zeta/src/app/localization/zeta_localization.dart';
import 'package:zeta/src/app/localization/zeta_text_catalogs.dart';
import 'package:zeta/src/app/observability/zeta_observability.dart';
import 'package:zeta/src/app/plugins/zeta_plugin_catalog.dart';
import 'package:zeta/src/app/provider_settings_slice/provider_settings_slice_composition.dart';
import 'package:zeta/src/app/settings_slice/settings_slice_notification_source.dart';
import 'package:zeta/src/app/settings_slice/settings_slice_overrides.dart';
import 'package:zeta/src/app/storage/zeta_storage_bindings.dart';
import 'package:zeta/src/app/storage/zeta_store_providers.dart';
import 'package:zeta/src/app/usage_statistics_slice/usage_statistics_slice_composition.dart';
import 'package:zeta/src/app/window_bootstrap.dart';
import 'package:zeta/src/app/workspace_slice/workspace_overrides.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_store_registry.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_codec.dart';
import 'package:zeta/src/features/agent/presentation/conversation_slice/agent_conversation_slice_providers.dart';
import 'package:zeta/src/features/agent/presentation/provider_settings_slice/agent_model_catalog_projection_providers.dart';
import 'package:zeta/src/features/agent/presentation/provider_settings_slice/agent_provider_settings_slice_providers.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_text_catalog.dart';
import 'package:zeta/src/features/desktop_notifications/data/flutter_desktop_notification_service.dart';
import 'package:zeta/src/features/desktop_notifications/data/method_channel_desktop_attention_indicator.dart';
import 'package:zeta/src/features/desktop_notifications/domain/desktop_attention_models.dart';
import 'package:zeta/src/features/desktop_notifications/domain/desktop_attention_text_catalog.dart';
import 'package:zeta/src/features/desktop_notifications/presentation/desktop_attention_slice_providers.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_notifier.dart';
import 'package:zeta/src/features/settings/application/appearance_settings_notifier.dart';
import 'package:zeta/src/features/settings/data/system_font_catalog_service.dart';
import 'package:zeta/src/features/settings/domain/app_language.dart';
import 'package:zeta/src/features/settings/presentation/settings_slice/settings_slice_providers.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_panel_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_text_catalog.dart';
import 'package:zeta/src/features/usage_statistics/presentation/usage_statistics_slice/usage_statistics_slice_providers.dart';
import 'package:zeta/src/ui/core/system_file_manager.dart';
import 'package:zeta/src/ui/features/ide/views/ide_home.dart';
import 'package:zeta/src/ui/localization/generated/app_localizations.dart';

/// Zeta 的组合根。
///
/// 这是 Riverpod 的标准形状：**容器由组合根创建，Widget 只消费**。生产入口和测试
/// 各自建一份 [ZetaAppComposition]，`MainApp` 不再自持容器，也就不必为了注入假实现
/// 而长出一排构造参数——任何已经是 provider 的依赖都用 [create] 的 `overrides`
/// 替换。
///
/// 生命周期：**谁创建谁 [dispose]**。生产入口交给进程退出与窗口关闭 hook，测试用
/// `addTearDown`。
///
/// 持有的对象分两批：容器建出来就能用的（storage、metrics），以及必须等显示语言
/// 定下来之后才组合的（文本目录、插件目录、Provider 定义与 codec、三个切片组合）。
/// 第二批由 [installLocaleDependentRuntime] 装配，容器里对应的 override 用闭包
/// 延迟读，因此容器不必等它们就能建出来；尚未装配就被读到时 fail-closed 抛错。
final class ZetaAppComposition {
  ZetaAppComposition._({
    required this.hostMode,
    required this.enableNativeWindowFrame,
    required this.showWindowControls,
    required this.fallbackLanguage,
    required this.displayLanguageOverride,
    required this.waitForGeneralSettings,
    required this.observability,
    required this.agentProviderAvailabilityLoader,
    required this.homeProviderDetectionLoader,
    required this.agentUsagePanelRepository,
    required this.desktopNotificationService,
    required this.desktopAttentionIndicator,
    required this._projectLocationOpener,
    required AgentProviderBundleFactory? injectedProviderFactory,
    required AgentProviderRuntimeRegistry? injectedRuntimeRegistry,
    required ZetaStorageBindings? storageBindings,
    required List<Override> overrides,
  }) : _injectedProviderFactory = injectedProviderFactory,
       _injectedRuntimeRegistry = injectedRuntimeRegistry {
    _storageBindings =
        storageBindings ??
        (hostMode.usesFilePersistence
            ? throw StateError(
                'ZetaHostMode.local requires storageBindings from the composition root',
              )
            : ZetaStorageBindings.memory());
    // 容器先于任何切片组合建出来：feature data 现在全部从 provider 取，
    // 组合根不再手工把 StorageService 往下传。
    container = ProviderContainer(
      observers: observability?.providerObservers,
      overrides: _composeOverrides(overrides),
    );
    _frozenDisplayLocale = ZetaLocalization.localeFor(
      displayLanguageOverride ?? fallbackLanguage,
    );
    if (injectedProviderFactory != null) {
      _agentProviderFactory = injectedProviderFactory;
    }
    if (injectedRuntimeRegistry != null) {
      _agentProviderRuntimeRegistry = injectedRuntimeRegistry;
      _ownsAgentProviderRuntimeRegistry = false;
      _providerRuntimeShutdownHook = shutdownOwnedAgentResources;
    } else if (injectedProviderFactory != null) {
      _agentProviderRuntimeRegistry = AgentProviderRuntimeRegistry(
        providerFactory: injectedProviderFactory,
        metrics: metrics,
        providerMetricLabel: AgentMetricLabels.forProviderId,
      );
      _ownsAgentProviderRuntimeRegistry = true;
      _providerRuntimeShutdownHook = shutdownOwnedAgentResources;
      if (enableNativeWindowFrame) {
        addDesktopWindowShutdownHook(_providerRuntimeShutdownHook!);
      }
    }
    _start();
  }

  /// 建出组合根并立即开始装配。
  ///
  /// [overrides] 追加在内部装配之后，用来替换任何已经是 provider 的依赖（会话仓库、
  /// Provider 配置仓库、常规设置仓库、外观仓库、字体目录、统计分区仓库、模型目录、
  /// turn 上下文仓库、首帧外观偏好……）。**不得覆盖本对象内部已经装过的 provider**：
  /// Riverpod 对同一容器内的重复 override 直接抛 `AssertionError`。
  ///
  /// [ZetaHostMode.ephemeral] 不装任何触碰本机的平台实现（目录选择器、外观落盘仓库、
  /// 系统字体目录），调用方必须自己经 [overrides] 提供——这样测试才有位置塞 fake。
  factory ZetaAppComposition.create({
    ZetaHostMode hostMode = ZetaHostMode.local,
    bool enableNativeWindowFrame = true,
    bool showWindowControls = true,
    AppLanguage fallbackLanguage = AppLanguage.simplifiedChinese,
    AppLanguage? displayLanguageOverride,
    bool waitForGeneralSettings = false,
    ZetaObservability? observability,
    ZetaStorageBindings? storageBindings,
    AgentProviderBundleFactory? agentProviderFactory,
    AgentProviderRuntimeRegistry? agentProviderRuntimeRegistry,
    AgentProviderAvailabilityLoader? agentProviderAvailabilityLoader,
    HomeProviderDetectionLoader? homeProviderDetectionLoader,
    ProjectLocationOpener? projectLocationOpener,
    AgentUsagePanelRepository? agentUsagePanelRepository,
    DesktopNotificationService? desktopNotificationService,
    DesktopAttentionIndicator? desktopAttentionIndicator,
    List<Override> overrides = const <Override>[],
  }) {
    return ZetaAppComposition._(
      hostMode: hostMode,
      enableNativeWindowFrame: enableNativeWindowFrame,
      showWindowControls: showWindowControls,
      fallbackLanguage: fallbackLanguage,
      displayLanguageOverride: displayLanguageOverride,
      waitForGeneralSettings: waitForGeneralSettings,
      observability: observability,
      storageBindings: storageBindings,
      injectedProviderFactory: agentProviderFactory,
      injectedRuntimeRegistry: agentProviderRuntimeRegistry,
      agentProviderAvailabilityLoader: agentProviderAvailabilityLoader,
      homeProviderDetectionLoader: homeProviderDetectionLoader,
      projectLocationOpener: projectLocationOpener,
      agentUsagePanelRepository: agentUsagePanelRepository,
      desktopNotificationService: desktopNotificationService,
      desktopAttentionIndicator: desktopAttentionIndicator,
      overrides: overrides,
    );
  }

  /// 宿主运行模式：决定持久化落盘还是留内存、是否允许访问本机 Agent CLI。
  final ZetaHostMode hostMode;

  /// 是否接管原生窗口：窗口关闭 hook、原生通知与任务栏指示。
  final bool enableNativeWindowFrame;

  /// 是否渲染窗口控制按钮；测试可关闭以避免依赖桌面平台通道。
  final bool showWindowControls;

  /// 常规设置文件缺失或损坏时使用的语言。
  final AppLanguage fallbackLanguage;

  /// 强制显示语言。生产路径在常规设置加载后冻结 `settings.appLanguage`。
  final AppLanguage? displayLanguageOverride;

  /// 是否等到常规设置加载完成后再挂有文字的 UI。
  final bool waitForGeneralSettings;

  /// app 级可观测性组合；未注入时探针退化为 no-op。
  final ZetaObservability? observability;

  final AgentProviderAvailabilityLoader? agentProviderAvailabilityLoader;
  final HomeProviderDetectionLoader? homeProviderDetectionLoader;

  /// Agent 统计面板数据源，供宿主隔离本机 Agent 历史。
  final AgentUsagePanelRepository? agentUsagePanelRepository;

  final DesktopNotificationService? desktopNotificationService;
  final DesktopAttentionIndicator? desktopAttentionIndicator;

  /// 组合根持有的 Riverpod 容器。
  late final ProviderContainer container;

  final AgentProviderBundleFactory? _injectedProviderFactory;
  final AgentProviderRuntimeRegistry? _injectedRuntimeRegistry;
  final ProjectLocationOpener? _projectLocationOpener;
  late final ZetaStorageBindings _storageBindings;

  /// 本地化与 Provider 插件目录就绪后创建的唯一 Provider settings 组合。
  ProviderSettingsSliceComposition? _providerSettingsSliceComposition;
  UsageStatisticsSliceComposition? _usageStatisticsSliceComposition;
  DesktopAttentionSliceComposition? _desktopAttentionSliceComposition;

  final DesktopAttentionTargetActivatorRelay
  desktopAttentionTargetActivatorRelay = DesktopAttentionTargetActivatorRelay();

  /// 在 `IdeHome.initState` 同步接入 Workspace，保证首个会话 build 只有新路径。
  final AgentConversationSliceStoreRegistry conversationSliceStoreRegistry =
      AgentConversationSliceStoreRegistry();
  final AgentConversationWorkspaceStoreRegistry
  conversationWorkspaceStoreRegistry =
      AgentConversationWorkspaceStoreRegistry();

  /// 诊断/恢复测试按需读取 Shell 投影的桥；没有 listener，不参与 Widget rebuild。
  final ZetaShellStateSnapshotRelay shellStateSnapshotRelay =
      ZetaShellStateSnapshotRelay();

  ZetaPluginCatalog? _pluginCatalog;
  late AgentProviderBundleFactory _agentProviderFactory;
  late AgentProviderRuntimeRegistry _agentProviderRuntimeRegistry;
  late final AgentProviderDefinitionCatalog _agentProviderDefinitions;
  late final AgentProviderSettingsCodec _agentProviderSettingsCodec;
  late final AgentProviderConfigStore _agentProviderConfigStore;
  Future<void> Function()? _providerRuntimeShutdownHook;
  bool _ownsAgentProviderRuntimeRegistry = false;
  var _generalSettingsReady = false;
  var _localeRuntimeReady = false;
  var _disposed = false;
  late Locale _frozenDisplayLocale;
  late AgentUiTextCatalog _agentUiTextCatalog;
  late AgentManagementTextCatalog _agentManagementTextCatalog;
  ZetaUiTextCatalog _zetaUiTextCatalog = const FallbackZetaUiTextCatalog();
  late DesktopAttentionTextCatalog _desktopAttentionTextCatalog;
  late UsageStatisticsTextCatalog _usageStatisticsTextCatalog;
  final Completer<void> _ready = Completer<void>();

  /// 有文字的 UI 是否可以挂载（常规设置已加载，或本次不需要等待）。
  bool get isReady => _generalSettingsReady;

  /// [isReady] 变 true 时完成。
  Future<void> get ready => _ready.future;

  Locale get frozenDisplayLocale => _frozenDisplayLocale;
  AgentUiTextCatalog get agentUiTextCatalog => _agentUiTextCatalog;
  AgentManagementTextCatalog get agentManagementTextCatalog =>
      _agentManagementTextCatalog;
  ZetaUiTextCatalog get zetaUiTextCatalog => _zetaUiTextCatalog;

  AgentProviderBundleFactory get agentProviderFactory => _agentProviderFactory;
  AgentProviderRuntimeRegistry get agentProviderRuntimeRegistry =>
      _agentProviderRuntimeRegistry;

  /// 当前生效的脱敏指标端口；未注入 [observability] 时为 no-op。
  ZetaMetricsPort get metrics => observability?.metrics ?? noopZetaMetricsPort;

  /// 是否禁止访问本机 Agent CLI（安装探测与用量历史）。
  bool get blocksLocalCliAccess => !hostMode.allowsLocalCliAccess;

  /// 打开项目所在目录的方式；未注入时使用本机文件管理器。
  ProjectLocationOpener get projectLocationOpener =>
      _projectLocationOpener ?? openPathInSystemFileManager;

  /// 首页 Provider 探测；ephemeral 宿主用无安装结果顶掉，避免扫本机 CLI。
  HomeProviderDetectionLoader? get resolvedHomeProviderDetectionLoader =>
      homeProviderDetectionLoader ??
      (blocksLocalCliAccess ? _loadNoInstalledHomeProviders : null);

  /// 是否自动刷新 Agent 用量；显式注入统计仓储时即便 ephemeral 也放行。
  bool get enableAgentUsageAutoRefresh =>
      !blocksLocalCliAccess || agentUsagePanelRepository != null;

  UsageStatisticsSliceComposition get usageStatisticsComposition =>
      _usageStatisticsSliceComposition ??
      (throw StateError('Usage Statistics composition is not ready'));

  DesktopAttentionSliceComposition get desktopAttentionComposition =>
      _desktopAttentionSliceComposition ??
      (throw StateError('Desktop Attention composition is not ready'));

  ProviderSettingsSliceComposition get providerSettingsComposition =>
      _providerSettingsSliceComposition ??
      (throw StateError('Provider Settings composition is not ready'));

  /// 按需读取当前逻辑状态树；生产 Widget 不得订阅或在 build 中调用。
  ZetaStateSnapshot takeStateSnapshot() {
    final usageComposition = usageStatisticsComposition;
    return ZetaStateSnapshot(
      shell: shellStateSnapshotRelay.read(),
      ideSession: container.read(ideSessionSliceProvider),
      usageStatistics: usageComposition.usageStatisticsStore.state,
      agentUsagePanel: usageComposition.agentUsagePanelStore.state,
      desktopAttention: ZetaDesktopAttentionStateSnapshot.fromState(
        desktopAttentionComposition.store.state,
      ),
      appearanceSettings: container.read(appearanceSettingsProvider),
      generalSettings: container.read(generalSettingsSliceStoreProvider).state,
      providerSettings: providerSettingsComposition.store.state,
    );
  }

  /// 工作台组合工厂：把 Repository / registry / 文本目录闭包在 app 层。
  ///
  /// `IdeHome` 只补 Shell 派生的两个入参，因此 UI 层不再出现任何 Repository 类型。
  IdeWorkbenchComposition createWorkbenchComposition({
    required AgentManagementRuntimeSubscribe subscribeRuntime,
    required AgentManagementRuntimeSnapshotProvider runtimeSnapshotProvider,
  }) {
    return IdeWorkbenchComposition.create(
      modelCatalogRepository: container.read(
        agentModelCatalogRepositoryProvider,
      ),
      runtimeRegistry: _agentProviderRuntimeRegistry,
      providerSettings: providerSettingsComposition.store,
      subscribeRuntime: subscribeRuntime,
      runtimeSnapshotProvider: runtimeSnapshotProvider,
      textCatalog: _agentManagementTextCatalog,
    );
  }

  /// 按依赖反序关闭本实例拥有的 Agent 资源。
  ///
  /// 顺序是硬要求：**runtime registry 先、plugin catalog 后**。插件贡献出的工厂是
  /// runtime 的上游依赖，先关插件会让仍在退出中的 runtime 失去依赖；窗口关闭 hook
  /// 与 [dispose] 共用这一个入口，避免两条路径顺序不一致。
  ///
  /// 幂等：registry 与 catalog 的 `close()` 本身都可重复调用。
  Future<void> shutdownOwnedAgentResources() {
    final pluginCatalog = _pluginCatalog;
    _pluginCatalog = null;
    return shutdownAgentResourcesInOrder(
      closeRuntimeRegistry: _ownsAgentProviderRuntimeRegistry
          ? _agentProviderRuntimeRegistry.close
          : null,
      closePluginCatalog: pluginCatalog?.close,
    );
  }

  /// 关闭组合根。谁创建谁调用；重复调用安全。
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    final hook = _providerRuntimeShutdownHook;
    if (enableNativeWindowFrame && hook != null) {
      removeDesktopWindowShutdownHook(hook);
    }
    _usageStatisticsSliceComposition?.dispose();
    _usageStatisticsSliceComposition = null;
    _desktopAttentionSliceComposition?.dispose();
    _desktopAttentionSliceComposition = null;
    _providerSettingsSliceComposition?.dispose();
    _providerSettingsSliceComposition = null;
    unawaited(shutdownOwnedAgentResources());
    // 两个 settings 切片 store 由 provider 拥有，`ref.onDispose` 随容器一起关。
    container.dispose();
  }

  void _start() {
    final loadGeneralSettings = container
        .read(generalSettingsSliceStoreProvider)
        .initialLoad;
    final overrideLanguage = displayLanguageOverride;
    if (overrideLanguage != null || !waitForGeneralSettings) {
      installLocaleDependentRuntime(overrideLanguage ?? fallbackLanguage);
    }
    if (waitForGeneralSettings) {
      unawaited(
        loadGeneralSettings.then((settings) {
          if (_disposed || _generalSettingsReady) {
            return;
          }
          installLocaleDependentRuntime(
            overrideLanguage ?? settings.appLanguage,
          );
          _markReady();
        }),
      );
    } else {
      _markReady();
      unawaited(loadGeneralSettings);
    }
  }

  void _markReady() {
    if (_generalSettingsReady) {
      return;
    }
    _generalSettingsReady = true;
    if (!_ready.isCompleted) {
      _ready.complete();
    }
  }

  /// 装配所有依赖显示语言的运行时：文本目录、插件目录、三个切片组合。
  ///
  /// 幂等：只有第一次调用真正装配。
  void installLocaleDependentRuntime(AppLanguage language) {
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
        claudeCodeSessionDecisionStoreFactory: container.read(
          claudeCodeSessionDecisionStoreFactoryProvider,
        ),
        claudeCodeHiddenThreadStore: container.read(
          claudeCodeHiddenThreadStoreProvider,
        ),
        textCatalog: _agentUiTextCatalog,
        metrics: metrics,
      );
      final resolvedProviders = catalog.activateAndResolveAgentProviders();
      _pluginCatalog = catalog;
      _agentProviderDefinitions = resolvedProviders.definitions;
      _agentProviderSettingsCodec = AgentProviderSettingsCodec(
        providerDefinitions: _agentProviderDefinitions,
      );
      // codec 已就绪，`agentProviderConfigStoreProvider` 现在可以安全解析。
      _agentProviderConfigStore = container.read(
        agentProviderConfigStoreProvider,
      );
      if (_injectedProviderFactory == null) {
        _agentProviderFactory = resolvedProviders.bundleFactory;
      }
    }
    if (_injectedRuntimeRegistry == null &&
        _injectedProviderFactory == null &&
        !_localeRuntimeReady) {
      _agentProviderRuntimeRegistry = AgentProviderRuntimeRegistry(
        providerFactory: _agentProviderFactory,
        metrics: metrics,
        providerMetricLabel: AgentMetricLabels.forProviderId,
      );
      _ownsAgentProviderRuntimeRegistry = true;
      _providerRuntimeShutdownHook = shutdownOwnedAgentResources;
      if (enableNativeWindowFrame) {
        addDesktopWindowShutdownHook(_providerRuntimeShutdownHook!);
      }
    }
    _providerSettingsSliceComposition ??=
        ProviderSettingsSliceComposition.create(
          configStore: _agentProviderConfigStore,
          modelCatalogRepository: container.read(
            agentModelCatalogRepositoryProvider,
          ),
          runtimeRegistry: _agentProviderRuntimeRegistry,
          providerDefinitions: _agentProviderDefinitions,
        );
    _usageStatisticsSliceComposition ??= UsageStatisticsSliceComposition.create(
      loadEnabledProviders: _loadEnabledAgentUsageProviders,
      runtimeRegistry: _agentProviderRuntimeRegistry,
      partitionStore: container.read(usageStatisticsPartitionStoreProvider),
      agentUsagePanelRepository: agentUsagePanelRepository,
      textCatalog: _usageStatisticsTextCatalog,
    );
    _desktopAttentionSliceComposition ??=
        DesktopAttentionSliceComposition.create(
          notificationService:
              desktopNotificationService ??
              (enableNativeWindowFrame
                  ? FlutterDesktopNotificationService(
                      linuxActionName: _desktopAttentionTextCatalog.linuxAction,
                    )
                  : const NoopDesktopNotificationService()),
          indicator:
              desktopAttentionIndicator ??
              (enableNativeWindowFrame
                  ? MethodChannelDesktopAttentionIndicator()
                  : const NoopDesktopAttentionIndicator()),
          notificationSettingsSource: GeneralSettingsSliceNotificationSource(
            sliceStore: container.read(generalSettingsSliceStoreProvider),
          ),
          activateTarget: desktopAttentionTargetActivatorRelay.call,
          textCatalog: _desktopAttentionTextCatalog,
        );
    _localeRuntimeReady = true;
  }

  Future<List<AgentProviderConfig>> _loadEnabledAgentUsageProviders() async {
    final providerSettings = providerSettingsComposition.store;
    await providerSettings.loadSettings();
    return providerSettings.enabledProviders;
  }

  /// 组合根的全部 override。
  ///
  /// **只在构造时装配一次。** 依赖延迟到 `overrideWith` 的闭包里读，因此语言持久化
  /// 完成后才建出来的三个切片组合不会引起重新装配。尚未组合就被读到时会 fail-closed
  /// 抛错。[extra] 排在最后，装的是这里不装的端口。
  List<Override> _composeOverrides(List<Override> extra) {
    return <Override>[
      ..._storageBindings.providerOverrides,
      settingsFallbackLanguageProvider.overrideWithValue(fallbackLanguage),
      // codec 要等插件目录解析出 Provider definitions，而那要等本地化运行时；
      // 用闭包延迟读，容器不必等它就能建出来。
      agentProviderSettingsCodecProvider.overrideWith(
        (ref) => _agentProviderSettingsCodec,
      ),
      zetaMetricsPortProvider.overrideWith((ref) => metrics),
      ...ideSessionSliceOverrides(),
      ...settingsSliceOverrides(),
      ...workspaceOverrides(),
      // 触碰本机的平台实现只有 local 宿主装。ephemeral 不装不是为测试开的洞：装了
      // 之后调用方就再也覆盖不掉这些 provider（同容器重复 override 会被 Riverpod
      // 直接断言拦下），fake 也就没地方进来。
      if (hostMode.usesNativeDialogs) systemDirectoryPickerOverride(),
      if (hostMode.usesFilePersistence) appearanceSettingsRepositoryOverride(),
      if (hostMode.usesNativeDialogs)
        appearanceFontCatalogProvider.overrideWith(
          (ref) => DesktopSystemFontCatalogService(),
        ),
      agentConversationSliceStoreRegistryProvider.overrideWithValue(
        conversationSliceStoreRegistry,
      ),
      agentConversationWorkspaceStoreRegistryProvider.overrideWithValue(
        conversationWorkspaceStoreRegistry,
      ),
      agentProviderSettingsSliceStoreProvider.overrideWith(
        (ref) => providerSettingsComposition.store,
      ),
      agentModelCatalogProjectionSourceProvider.overrideWith(
        (ref) => providerSettingsComposition,
      ),
      usageStatisticsSliceStoreProvider.overrideWith(
        (ref) => usageStatisticsComposition.usageStatisticsStore,
      ),
      agentUsagePanelSliceStoreProvider.overrideWith(
        (ref) => usageStatisticsComposition.agentUsagePanelStore,
      ),
      desktopAttentionSliceStoreProvider.overrideWith(
        (ref) => desktopAttentionComposition.store,
      ),
      ...extra,
    ];
  }
}

Future<List<ManagedAgent>> _loadNoInstalledHomeProviders() async =>
    const <ManagedAgent>[];

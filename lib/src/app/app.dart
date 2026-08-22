import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:window_manager/window_manager.dart';

import 'package:zeta/src/app/app_constants.dart';
import 'package:zeta/src/app/localization/zeta_localization.dart';
import 'package:zeta/src/app/observability/zeta_observability.dart';
import 'package:zeta/src/app/plugins/zeta_plugin_catalog.dart';
import 'package:zeta/src/app/localization/zeta_text_catalogs.dart';
import 'package:zeta/src/app/shell/ide_shell_controller.dart';
import 'package:zeta/src/app/window_bootstrap.dart';
import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta/src/core/storage/zeta_data_paths.dart';
import 'package:zeta/src/core/utils/system_file_manager.dart';
import 'package:zeta/src/features/agent/application/agent_model_catalog_repository.dart';
import 'package:zeta/src/features/agent/application/agent_provider_runtime_registry.dart';
import 'package:zeta/src/features/agent/data/agent_model_catalog_cache_store.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_codec.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/data/agent_turn_context_store.dart';
import 'package:zeta/src/features/agent/data/agent_provider_permission_migration.dart';
import 'package:zeta/src/features/agent/data/default_agent_provider_factory.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_hidden_thread_store.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_permission_policy_adapter.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider_bundle.dart';
import 'package:zeta/src/features/desktop_notifications/domain/desktop_attention_models.dart';
import 'package:zeta/src/features/desktop_notifications/domain/desktop_attention_text_catalog.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';
import 'package:zeta/src/features/ide_session/data/ide_session_store.dart';
import 'package:zeta/src/features/settings/application/appearance_settings_controller.dart';
import 'package:zeta/src/features/settings/application/general_settings_controller.dart';
import 'package:zeta/src/features/settings/data/appearance_settings_store.dart';
import 'package:zeta/src/features/settings/data/general_settings_store.dart';
import 'package:zeta/src/features/settings/data/system_font_catalog_service.dart';
import 'package:zeta/src/features/settings/domain/app_language.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';
import 'package:zeta/src/features/usage_statistics/data/usage_statistics_partition_store.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_panel_models.dart';
import 'package:zeta_ui/zeta_ui.dart';
import 'package:zeta/src/ui/features/ide/views/ide_home.dart';
import 'package:zeta/src/ui/localization/generated/app_localizations.dart';

/// 应用根组件。
///
/// 允许测试注入目录选择器、会话存储和 Agent provider 工厂；生产环境使用真实实现。
/// 全局外观偏好由 [AppearanceSettingsController] 统一管理，覆盖主题模式、
/// 界面字体与代码字体，并持久化到本地存储。
class MainApp extends StatefulWidget {
  const MainApp({
    super.key,
    this.directoryPicker,
    this.enableNativeWindowFrame = true,
    this.showWindowControls = true,
    this.sessionLoader,
    this.sessionSaver,
    this.agentProviderFactory,
    this.agentProviderConfigStore,
    this.agentProviderAvailabilityLoader,
    this.homeProviderDetectionLoader,
    this.projectLocationOpener,
    this.appearanceController,
    this.initialAppearanceSettings,
    this.generalSettingsController,
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
  final Future<String?> Function()? sessionLoader;
  final Future<void> Function(String value)? sessionSaver;
  final AgentProviderBundleFactory? agentProviderFactory;
  final AgentProviderConfigStore? agentProviderConfigStore;
  final AgentProviderAvailabilityLoader? agentProviderAvailabilityLoader;
  final HomeProviderDetectionLoader? homeProviderDetectionLoader;
  final ProjectLocationOpener? projectLocationOpener;

  /// 全局外观控制器。测试可注入内存版本以避免触碰真实用户文件；
  /// 生产环境由 [MainAppState.appearanceController] 自动创建并加载持久化偏好。
  final AppearanceSettingsController? appearanceController;

  /// 启动阶段已读入的外观偏好，供第一帧使用，避免先按默认 system 再跳变。
  final AppearanceSettings? initialAppearanceSettings;

  /// 全局常规设置控制器。测试可注入内存版本；生产环境自动使用
  /// `~/.zeta/config/general.json`。
  final GeneralSettingsController? generalSettingsController;

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
  late final AppearanceSettingsController _appearanceController;
  late final GeneralSettingsController _generalSettingsController;

  /// 编译期插件目录；仅在应用自己构造 Provider 工厂时创建。
  ZetaPluginCatalog? _pluginCatalog;
  late AgentProviderBundleFactory _agentProviderFactory;
  late AgentProviderRuntimeRegistry _agentProviderRuntimeRegistry;
  late final AgentProviderSettingsCodec _agentProviderSettingsCodec;
  Future<void> Function()? _providerRuntimeShutdownHook;
  late final UsageStatisticsPartitionStore _usageStatisticsPartitionStore;
  late final AgentModelCatalogRepository _agentModelCatalogRepository;
  late final AgentTurnContextStore _turnContextStore;
  bool _ownsAppearanceController = false;
  bool _ownsGeneralSettingsController = false;
  bool _ownsAgentProviderRuntimeRegistry = false;
  AppLifecycleState? _appLifecycleState;
  bool _nativeWindowSuspended = false;
  var _generalSettingsReady = false;
  var _localeRuntimeReady = false;
  late Locale _frozenDisplayLocale;
  late AgentUiTextCatalog _agentUiTextCatalog;
  ZetaUiTextCatalog _zetaUiTextCatalog = const FallbackZetaUiTextCatalog();
  late DesktopAttentionTextCatalog _desktopAttentionTextCatalog;

  /// 全局外观控制器引用，供设置面板和主题构建共享。
  AppearanceSettingsController get appearanceController =>
      _appearanceController;

  /// 全局常规设置控制器引用，供设置页面和 Agent 输入框共享。
  GeneralSettingsController get generalSettingsController =>
      _generalSettingsController;

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
    final useFilePersistence = _useFilePersistence;
    final dataPaths = widget.dataPaths;
    _frozenDisplayLocale = ZetaLocalization.localeFor(
      widget.displayLanguageOverride ?? widget.fallbackLanguage,
    );
    _agentProviderSettingsCodec = AgentProviderSettingsCodec(
      migrationRegistry: AgentProviderPermissionMigrationRegistry(
        <AgentProviderKind, AgentProviderPermissionPreferenceMigrator>{
          AgentProviderKind.codexAppServer:
              const CodexPermissionPreferenceMigrator(),
          AgentProviderKind.acp: const GrokPermissionPreferenceMigrator(),
        },
      ),
    );
    final injectedFactory = widget.agentProviderFactory;
    if (injectedFactory != null) {
      _agentProviderFactory = injectedFactory;
    }
    final injectedRuntimeRegistry = widget.agentProviderRuntimeRegistry;
    if (injectedRuntimeRegistry != null) {
      _agentProviderRuntimeRegistry = injectedRuntimeRegistry;
      _ownsAgentProviderRuntimeRegistry = false;
      _providerRuntimeShutdownHook = _agentProviderRuntimeRegistry.close;
    } else if (injectedFactory != null) {
      _agentProviderRuntimeRegistry = AgentProviderRuntimeRegistry(
        providerFactory: injectedFactory,
        metrics: _metrics,
      );
      _ownsAgentProviderRuntimeRegistry = true;
      _providerRuntimeShutdownHook = _agentProviderRuntimeRegistry.close;
      if (widget.enableNativeWindowFrame) {
        addDesktopWindowShutdownHook(_agentProviderRuntimeRegistry.close);
      }
    }
    _usageStatisticsPartitionStore =
        widget.usageStatisticsPartitionStore ??
        (useFilePersistence
            ? FileUsageStatisticsPartitionStore(
                file: dataPaths!.usageStatisticsIndexFile,
              )
            : MemoryUsageStatisticsPartitionStore());
    _agentModelCatalogRepository =
        widget.agentModelCatalogRepository ??
        AgentModelCatalogRepository(
          store: useFilePersistence
              ? FileAgentModelCatalogCacheStore(
                  file: dataPaths!.agentModelCatalogCacheFile,
                )
              : MemoryAgentModelCatalogCacheStore(),
        );
    _turnContextStore =
        widget.turnContextStore ??
        (useFilePersistence
            ? FileAgentTurnContextStore(
                rootDirectory: dataPaths!.sessionStateDirectory,
              )
            : MemoryAgentTurnContextStore());
    if (widget.appearanceController != null) {
      _appearanceController = widget.appearanceController!;
      _ownsAppearanceController = false;
    } else {
      // 测试通过 sessionLoader/sessionSaver 注入会话回调时，避免读写真实
      // ~/.zeta；生产环境走默认文件持久化。
      final store = useFilePersistence
          ? FileAppearanceSettingsStore(file: dataPaths!.appearanceFile)
          : MemoryAppearanceSettingsStore();
      _appearanceController = AppearanceSettingsController(
        store: store,
        fontCatalog: DesktopSystemFontCatalogService(),
        initialSettings: widget.initialAppearanceSettings,
      );
      _ownsAppearanceController = true;
    }
    if (widget.generalSettingsController != null) {
      _generalSettingsController = widget.generalSettingsController!;
      _ownsGeneralSettingsController = false;
    } else {
      final store = useFilePersistence
          ? FileGeneralSettingsStore(
              file: dataPaths!.generalSettingsFile,
              fallbackLanguage: widget.fallbackLanguage,
            )
          : MemoryGeneralSettingsStore(null, widget.fallbackLanguage);
      _generalSettingsController = GeneralSettingsController(store: store);
      _ownsGeneralSettingsController = true;
    }
    unawaited(_appearanceController.load());
    final loadGeneralSettings = _generalSettingsController.load();
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
      _desktopAttentionTextCatalog = textCatalogs.desktopAttention;
      _zetaUiTextCatalog = textCatalogs.zetaUi;
    }
    if (widget.agentProviderFactory == null && !_localeRuntimeReady) {
      final dataPaths = widget.dataPaths;
      final useFilePersistence = _useFilePersistence;
      final defaultFactory = DefaultAgentProviderFactory(
        claudeCodeSessionDecisionStoreFactory: useFilePersistence
            ? (sessionId) => FileClaudeCodeSessionDecisionStore(
                file: _claudeCodeSessionDecisionFile(dataPaths!, sessionId),
              )
            : null,
        claudeCodeHiddenThreadStore: useFilePersistence
            ? FileClaudeCodeHiddenThreadStore(
                file: _claudeCodeHiddenThreadsFile(dataPaths!),
              )
            : null,
        textCatalog: _agentUiTextCatalog,
      );
      // 阶段 1：工厂改由编译期插件目录交付，内部分派逻辑一字未动。
      final catalog = ZetaPluginCatalog.compatibility(
        bundleFactory: defaultFactory,
        metrics: _metrics,
      );
      catalog.activate();
      _pluginCatalog = catalog;
      _agentProviderFactory = catalog.resolveAgentProviderBundleFactory();
    }
    if (widget.agentProviderRuntimeRegistry == null &&
        widget.agentProviderFactory == null &&
        !_localeRuntimeReady) {
      _agentProviderRuntimeRegistry = AgentProviderRuntimeRegistry(
        providerFactory: _agentProviderFactory,
        metrics: _metrics,
      );
      _ownsAgentProviderRuntimeRegistry = true;
      _providerRuntimeShutdownHook = _agentProviderRuntimeRegistry.close;
      if (widget.enableNativeWindowFrame) {
        addDesktopWindowShutdownHook(_providerRuntimeShutdownHook!);
      }
    }
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
    if (_ownsAgentProviderRuntimeRegistry) {
      unawaited(_agentProviderRuntimeRegistry.close());
    }
    // runtime 进程由 registry 拥有；插件目录只需按激活反序释放插件句柄。
    final pluginCatalog = _pluginCatalog;
    if (pluginCatalog != null) {
      _pluginCatalog = null;
      unawaited(pluginCatalog.close());
    }
    if (_ownsAppearanceController) {
      _appearanceController.dispose();
    }
    if (_ownsGeneralSettingsController) {
      _generalSettingsController.dispose();
    }
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
    return ValueListenableBuilder<AppearanceSettings>(
      valueListenable: _appearanceController.listenable,
      builder: (context, settings, _) {
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
        final materialBrightness = resolveBrightnessForThemeMode(
          settings.themeMode,
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
              themeMode: settings.themeMode,
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
                themeMode: resolveShadcnThemeMode(settings.themeMode),
                home: _generalSettingsReady
                    ? IdeHome(
                        key: const ValueKey<String>('zeta.ide-home'),
                        directoryPicker:
                            widget.directoryPicker ?? getDirectoryPath,
                        enableNativeWindowFrame: widget.enableNativeWindowFrame,
                        showWindowControls: widget.showWindowControls,
                        sessionStore: _createSessionStore(),
                        agentProviderFactory: _agentProviderFactory,
                        agentProviderRuntimeRegistry:
                            _agentProviderRuntimeRegistry,
                        desktopNotificationService:
                            widget.desktopNotificationService,
                        desktopAttentionIndicator:
                            widget.desktopAttentionIndicator,
                        agentProviderConfigStore:
                            widget.agentProviderConfigStore ??
                            _createAgentProviderConfigStore(),
                        agentProviderAvailabilityLoader:
                            widget.agentProviderAvailabilityLoader,
                        homeProviderDetectionLoader:
                            widget.homeProviderDetectionLoader ??
                            (_usesCallbackPersistence
                                ? _loadNoInstalledHomeProviders
                                : null),
                        projectLocationOpener:
                            widget.projectLocationOpener ??
                            openPathInSystemFileManager,
                        appearanceController: _appearanceController,
                        generalSettingsController: _generalSettingsController,
                        usageStatisticsDependencies:
                            IdeShellUsageStatisticsDependencies(
                              partitionStore: _usageStatisticsPartitionStore,
                              agentUsagePanelRepository:
                                  widget.agentUsagePanelRepository,
                            ),
                        agentModelCatalogRepository:
                            _agentModelCatalogRepository,
                        turnContextStore: _turnContextStore,
                        agentUiTextCatalog: _agentUiTextCatalog,
                        metrics: _metrics,
                        desktopAttentionTextCatalog:
                            _desktopAttentionTextCatalog,
                        // 回调存储用于测试/嵌入宿主；未显式注入统计仓储时不读取本机 CLI 历史。
                        enableAgentUsageAutoRefresh:
                            !_usesCallbackPersistence ||
                            widget.agentUsagePanelRepository != null,
                      )
                    : ColoredBox(
                        key: const ValueKey<String>(
                          'zeta.localization-loading',
                        ),
                        color: materialIdeTheme.colors.frame,
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  bool get _tickersEnabled {
    final state = _appLifecycleState;
    final lifecycleAllowsTickers =
        state == null ||
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    return lifecycleAllowsTickers && !_nativeWindowSuspended;
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

  IdeSessionStore _createSessionStore() {
    if (widget.sessionLoader != null || widget.sessionSaver != null) {
      return CallbackIdeSessionStore(
        loadJson: widget.sessionLoader ?? () async => null,
        saveJson: widget.sessionSaver ?? (_) async {},
      );
    }
    final dataPaths = widget.dataPaths;
    if (_useFilePersistence && dataPaths != null) {
      return FileIdeSessionStore(file: dataPaths.ideSessionFile);
    }
    return const CallbackIdeSessionStore(
      loadJson: _loadEmptySession,
      saveJson: _ignoreSessionSave,
    );
  }

  AgentProviderConfigStore _createAgentProviderConfigStore() {
    if (widget.agentProviderConfigStore != null) {
      return widget.agentProviderConfigStore!;
    }
    if (widget.sessionLoader != null || widget.sessionSaver != null) {
      // widget test 传入会话回调时，默认不触碰真实 ~/.zeta。
      return MemoryAgentProviderConfigStore();
    }
    final dataPaths = widget.dataPaths;
    if (_useFilePersistence && dataPaths != null) {
      return FileAgentProviderConfigStore(
        file: dataPaths.providersFile,
        codec: _agentProviderSettingsCodec,
      );
    }
    return MemoryAgentProviderConfigStore();
  }

  bool get _useFilePersistence =>
      widget.dataPaths != null &&
      widget.sessionLoader == null &&
      widget.sessionSaver == null;

  bool get _usesCallbackPersistence =>
      widget.sessionLoader != null || widget.sessionSaver != null;
}

Future<String?> _loadEmptySession() async => null;

Future<void> _ignoreSessionSave(String _) async {}

Future<List<ManagedAgent>> _loadNoInstalledHomeProviders() async =>
    const <ManagedAgent>[];

File _claudeCodeSessionDecisionFile(ZetaDataPaths dataPaths, String sessionId) {
  final encodedSessionId = Uri.encodeComponent(sessionId);
  return File(
    '${dataPaths.stateDirectory.path}${Platform.pathSeparator}'
    'claude_code${Platform.pathSeparator}session_$encodedSessionId.json',
  );
}

File _claudeCodeHiddenThreadsFile(ZetaDataPaths dataPaths) {
  return File(
    '${dataPaths.stateDirectory.path}${Platform.pathSeparator}'
    'claude_code${Platform.pathSeparator}hidden_threads.json',
  );
}

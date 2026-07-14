import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta/src/app/app_constants.dart';
import 'package:zeta/src/core/storage/zeta_data_paths.dart';
import 'package:zeta/src/core/utils/system_file_manager.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/data/datasources/acp/cursor_session_index_store.dart';
import 'package:zeta/src/features/agent/data/default_agent_provider_factory.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/ide_session/data/ide_session_store.dart';
import 'package:zeta/src/features/settings/application/appearance_settings_controller.dart';
import 'package:zeta/src/features/settings/data/appearance_settings_store.dart';
import 'package:zeta/src/features/settings/data/system_font_catalog_service.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';
import 'package:zeta/src/features/usage_statistics/data/usage_statistics_index_store.dart';
import 'package:zeta/src/ui/core/app_theme.dart';
import 'package:zeta/src/ui/features/ide/views/ide_home.dart';

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
    this.sessionLoader,
    this.sessionSaver,
    this.agentProviderFactory,
    this.agentProviderConfigStore,
    this.agentProviderAvailabilityLoader,
    this.projectLocationOpener,
    this.appearanceController,
    this.dataPaths,
    this.usageStatisticsIndexStore,
  });

  final Future<String?> Function()? directoryPicker;
  final bool enableNativeWindowFrame;
  final Future<String?> Function()? sessionLoader;
  final Future<void> Function(String value)? sessionSaver;
  final AgentProviderFactory? agentProviderFactory;
  final AgentProviderConfigStore? agentProviderConfigStore;
  final AgentProviderAvailabilityLoader? agentProviderAvailabilityLoader;
  final ProjectLocationOpener? projectLocationOpener;

  /// 全局外观控制器。测试可注入内存版本以避免触碰真实用户文件；
  /// 生产环境由 [MainAppState.appearanceController] 自动创建并加载持久化偏好。
  final AppearanceSettingsController? appearanceController;

  /// 生产启动阶段解析并初始化的 Zeta 自有数据路径。
  ///
  /// 未传入时使用内存/回调存储，避免测试或嵌入式宿主意外写入真实 HOME。
  final ZetaDataPaths? dataPaths;

  /// 使用统计索引存储注入点；默认按 [dataPaths] 选择文件或内存实现。
  final UsageStatisticsIndexStore? usageStatisticsIndexStore;

  @override
  State<MainApp> createState() => MainAppState();
}

class MainAppState extends State<MainApp> {
  late final AppearanceSettingsController _appearanceController;
  late final AgentProviderFactory _defaultAgentProviderFactory;
  late final UsageStatisticsIndexStore _usageStatisticsIndexStore;
  bool _ownsAppearanceController = false;

  /// 全局外观控制器引用，供设置面板和主题构建共享。
  AppearanceSettingsController get appearanceController =>
      _appearanceController;

  @override
  void initState() {
    super.initState();
    final useFilePersistence = _useFilePersistence;
    final dataPaths = widget.dataPaths;
    final cursorSessionIndexStore = useFilePersistence
        ? FileCursorSessionIndexStore(file: dataPaths!.cursorSessionsFile)
        : MemoryCursorSessionIndexStore();
    _defaultAgentProviderFactory = DefaultAgentProviderFactory(
      cursorSessionIndexStore: cursorSessionIndexStore,
    );
    _usageStatisticsIndexStore =
        widget.usageStatisticsIndexStore ??
        (useFilePersistence
            ? FileUsageStatisticsIndexStore(
                file: dataPaths!.usageStatisticsIndexFile,
              )
            : MemoryUsageStatisticsIndexStore());
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
      );
      _ownsAppearanceController = true;
    }
    unawaited(_appearanceController.load());
  }

  @override
  void dispose() {
    if (_ownsAppearanceController) {
      _appearanceController.dispose();
    }
    super.dispose();
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
        );
        final darkIdeTheme = buildIdeThemeData(
          brightness: Brightness.dark,
          uiFontFamily: settings.uiFontFamily,
          codeFontFamily: settings.codeFontFamily,
        );
        final materialBrightness = resolveBrightnessForThemeMode(
          settings.themeMode,
        );
        final materialIdeTheme = materialBrightness == Brightness.dark
            ? darkIdeTheme
            : lightIdeTheme;
        return IdeThemeScope(
          themeMode: settings.themeMode,
          lightTheme: lightIdeTheme,
          darkTheme: darkIdeTheme,
          child: sf.ShadcnApp(
            debugShowCheckedModeBanner: false,
            title: appTitle,
            theme: buildShadcnTheme(lightIdeTheme),
            darkTheme: buildShadcnTheme(darkIdeTheme),
            materialTheme: buildMaterialTheme(materialIdeTheme),
            themeMode: resolveShadcnThemeMode(settings.themeMode),
            home: IdeHome(
              directoryPicker: widget.directoryPicker ?? getDirectoryPath,
              enableNativeWindowFrame: widget.enableNativeWindowFrame,
              sessionStore: _createSessionStore(),
              agentProviderFactory:
                  widget.agentProviderFactory ?? _defaultAgentProviderFactory,
              agentProviderConfigStore:
                  widget.agentProviderConfigStore ??
                  _createAgentProviderConfigStore(),
              agentProviderAvailabilityLoader:
                  widget.agentProviderAvailabilityLoader,
              projectLocationOpener:
                  widget.projectLocationOpener ?? openPathInSystemFileManager,
              appearanceController: _appearanceController,
              usageStatisticsIndexStore: _usageStatisticsIndexStore,
            ),
          ),
        );
      },
    );
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
      return FileAgentProviderConfigStore(file: dataPaths.providersFile);
    }
    return MemoryAgentProviderConfigStore();
  }

  bool get _useFilePersistence =>
      widget.dataPaths != null &&
      widget.sessionLoader == null &&
      widget.sessionSaver == null;
}

Future<String?> _loadEmptySession() async => null;

Future<void> _ignoreSessionSave(String _) async {}

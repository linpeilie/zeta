import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zeta/src/core/utils/system_file_manager.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/data/default_agent_provider_factory.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/ide_session/data/ide_session_store.dart';
import 'package:zeta/src/ui/core/app_theme.dart';
import 'package:zeta/src/ui/core/theme_mode_controller.dart';
import 'package:zeta/src/ui/features/ide/views/ide_home.dart';
import 'package:zeta/src/app/app_constants.dart';

/// 应用根组件。
///
/// 允许测试注入目录选择器、会话存储和 Agent provider 工厂；生产环境使用真实实现。
/// 主题模式由 [ThemeModeController] 管理，默认跟随系统，并通过 shared_preferences
/// 持久化；后续设置面板可直接持有该控制器切换浅色/深色/跟随系统。
class MainApp extends StatefulWidget {
  const MainApp({
    super.key,
    this.directoryPicker,
    this.enableNativeWindowFrame = true,
    this.sessionLoader,
    this.sessionSaver,
    this.agentProviderFactory,
    this.agentProviderConfigStore,
    this.projectLocationOpener,
    this.themeModeController,
  });

  final Future<String?> Function()? directoryPicker;
  final bool enableNativeWindowFrame;
  final Future<String?> Function()? sessionLoader;
  final Future<void> Function(String value)? sessionSaver;
  final AgentProviderFactory? agentProviderFactory;
  final AgentProviderConfigStore? agentProviderConfigStore;
  final ProjectLocationOpener? projectLocationOpener;

  /// 主题模式控制器。测试可注入内存版本以避免触碰 shared_preferences；
  /// 生产环境由 [MainAppState.controller] 自动创建并加载持久化偏好。
  final ThemeModeController? themeModeController;

  @override
  State<MainApp> createState() => MainAppState();
}

class MainAppState extends State<MainApp> {
  late final ThemeModeController _themeModeController;
  bool _ownsThemeModeController = false;

  /// 主题模式控制器引用，供后续设置面板调用切换浅色/深色/跟随系统。
  ThemeModeController get themeModeController => _themeModeController;

  static final ThemeData _lightTheme = buildIdeTheme(
    brightness: Brightness.light,
  );
  static final ThemeData _darkTheme = buildIdeTheme(
    brightness: Brightness.dark,
  );

  @override
  void initState() {
    super.initState();
    if (widget.themeModeController != null) {
      _themeModeController = widget.themeModeController!;
      _ownsThemeModeController = false;
    } else {
      // 测试通过 sessionLoader/sessionSaver 注入会话回调时，避免读写真实
      // shared_preferences；生产环境走默认持久化。
      final usePersistence =
          widget.sessionLoader == null && widget.sessionSaver == null;
      _themeModeController = ThemeModeController(
        preferences: usePersistence ? SharedPreferencesAsync() : null,
      );
      _ownsThemeModeController = true;
      unawaited(_themeModeController.load());
    }
  }

  @override
  void dispose() {
    if (_ownsThemeModeController) {
      _themeModeController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeModeController.listenable,
      builder: (context, mode, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: appTitle,
          theme: _lightTheme,
          darkTheme: _darkTheme,
          themeMode: mode,
          home: IdeHome(
            directoryPicker: widget.directoryPicker ?? getDirectoryPath,
            enableNativeWindowFrame: widget.enableNativeWindowFrame,
            sessionStore: _createSessionStore(),
            agentProviderFactory:
                widget.agentProviderFactory ??
                const DefaultAgentProviderFactory(),
            agentProviderConfigStore:
                widget.agentProviderConfigStore ??
                _createAgentProviderConfigStore(),
            projectLocationOpener:
                widget.projectLocationOpener ?? openPathInSystemFileManager,
            themeModeController: _themeModeController,
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
    return SharedPreferencesIdeSessionStore();
  }

  AgentProviderConfigStore _createAgentProviderConfigStore() {
    if (widget.agentProviderConfigStore != null) {
      return widget.agentProviderConfigStore!;
    }
    if (widget.sessionLoader != null || widget.sessionSaver != null) {
      // widget test 传入会话回调时，默认不触碰真实 shared_preferences。
      return MemoryAgentProviderConfigStore();
    }
    return SharedPreferencesAgentProviderConfigStore();
  }
}

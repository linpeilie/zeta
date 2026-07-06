import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/data/default_agent_provider_factory.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/ide_session/data/ide_session_store.dart';
import 'package:zeta/src/ui/core/app_theme.dart';
import 'package:zeta/src/ui/features/ide/views/ide_home.dart';
import 'package:zeta/src/app/app_constants.dart';

/// 应用根组件。
///
/// 允许测试注入目录选择器、会话存储和 Agent provider 工厂；生产环境使用真实实现。
class MainApp extends StatelessWidget {
  const MainApp({
    super.key,
    this.directoryPicker,
    this.enableNativeWindowFrame = true,
    this.sessionLoader,
    this.sessionSaver,
    this.agentProviderFactory,
    this.agentProviderConfigStore,
  });

  final Future<String?> Function()? directoryPicker;
  final bool enableNativeWindowFrame;
  final Future<String?> Function()? sessionLoader;
  final Future<void> Function(String value)? sessionSaver;
  final AgentProviderFactory? agentProviderFactory;
  final AgentProviderConfigStore? agentProviderConfigStore;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: appTitle,
      theme: buildCompactTheme(),
      home: IdeHome(
        directoryPicker: directoryPicker ?? getDirectoryPath,
        enableNativeWindowFrame: enableNativeWindowFrame,
        sessionStore: _createSessionStore(),
        agentProviderFactory:
            agentProviderFactory ?? const DefaultAgentProviderFactory(),
        agentProviderConfigStore:
            agentProviderConfigStore ?? _createAgentProviderConfigStore(),
      ),
    );
  }

  IdeSessionStore _createSessionStore() {
    if (sessionLoader != null || sessionSaver != null) {
      return CallbackIdeSessionStore(
        loadJson: sessionLoader ?? () async => null,
        saveJson: sessionSaver ?? (_) async {},
      );
    }
    return SharedPreferencesIdeSessionStore();
  }

  AgentProviderConfigStore _createAgentProviderConfigStore() {
    if (agentProviderConfigStore != null) {
      return agentProviderConfigStore!;
    }
    if (sessionLoader != null || sessionSaver != null) {
      // widget test 传入会话回调时，默认不触碰真实 shared_preferences。
      return MemoryAgentProviderConfigStore();
    }
    return SharedPreferencesAgentProviderConfigStore();
  }
}

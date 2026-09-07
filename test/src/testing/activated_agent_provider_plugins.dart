import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta/src/app/plugins/agent_provider_manifest.dart';
import 'agent_provider_implementations.dart';
import 'package:zeta_plugin_kernel/zeta_plugin_kernel.dart';

/// 把 Claude 凭据指到临时空目录，并关闭 OAuth 续期。
///
/// 生产 `listModels` 会先 `ensureFresh()`。若不隔离，本机过期登录会去抢用户
/// 目录下的 `.claude.lock`，残锁或 Claude Code 占用都会让测试在 12 秒后失败。
AgentProviderConfig isolatedClaudeCodeProviderConfig([
  AgentProviderConfig? base,
]) {
  final dir = Directory.systemTemp.createTempSync('zeta-claude-config-');
  addTearDown(() {
    try {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    } on FileSystemException {
      // 临时目录收尾失败不得掩盖用例结果。
    }
  });
  final config = base ?? defaultClaudeCodeAgentProviderConfig;
  return config.copyWith(
    extra: <String, Object?>{...config.extra, 'hasApiKey': true},
    environment: <String, String>{
      ...config.environment,
      'CLAUDE_CONFIG_DIR': dir.path,
    },
  );
}

/// 同步激活三个生产 Provider 插件，并把插件目录关闭登记到当前测试。
AgentProviderBundleFactory activateBuiltInAgentProviderBundleFactory({
  ClaudeCodeCliMetadataLoader? claudeCodeMetadataLoader,
}) {
  final registry = ZetaPluginRegistry(
    factories: zetaAgentProviderPluginFactories(
      claudeCodeMetadataLoader: claudeCodeMetadataLoader,
    ),
  );
  addTearDown(registry.close);
  final report = registry.activateAllSynchronously();
  if (report.isDegraded) {
    throw StateError('Built-in Agent provider plugins failed to activate');
  }
  return ResolvedAgentProviderPlugins(
    registry.contributions<AgentProviderPluginContribution>(),
  ).bundleFactory;
}

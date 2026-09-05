import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta/src/app/plugins/agent_provider_manifest.dart';
import 'agent_provider_implementations.dart';
import 'package:zeta_plugin_kernel/zeta_plugin_kernel.dart';

/// 编译期 manifest 的跨插件组装回归。
void main() {
  group('适配层可脱离宿主使用', () {
    test('三个内置 Provider 都能从中立配置造出 bundle', () {
      final factory = _activateBuiltInFactory();

      for (final config in <AgentProviderConfig>[
        defaultCodexAgentProviderConfig,
        defaultGrokAgentProviderConfig,
        defaultClaudeCodeAgentProviderConfig,
      ]) {
        final bundle = factory.createBundle(config);
        addTearDown(bundle.runtime.dispose);

        expect(bundle.runtime.config.id, config.id);
        // 能力协商是 bundle 的职责：端口为空时对应 capability 必须为 false（G4）。
        expect(
          bundle.threadCatalog == null,
          isNot(bundle.runtime.capabilities.canListThreads),
        );
      }
    });

    test('静态能力目录按开放 type 给出中立能力', () {
      final codex = zetaAgentProviderDefinitionCatalog.staticCapabilitiesFor(
        codexAgentProviderType,
      );
      final acp = zetaAgentProviderDefinitionCatalog.staticCapabilitiesFor(
        grokAgentProviderType,
      );

      expect(codex.canCreateSession, isTrue);
      expect(acp.canCreateSession, isTrue);
    });

    test('CLI 定位器只做路径形态判断，不启动进程', () {
      expect(looksLikeCodexCliPath('/usr/local/bin/codex'), isTrue);
      expect(looksLikeGrokCliPath('/opt/homebrew/bin/grok'), isTrue);
      expect(looksLikeClaudeCodeCliPath('/usr/local/bin/claude'), isTrue);
      expect(looksLikeCodexCliPath('/usr/local/bin/grok'), isFalse);
    });
  });
}

AgentProviderBundleFactory _activateBuiltInFactory() {
  final registry = ZetaPluginRegistry(
    factories: zetaAgentProviderPluginFactories(),
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

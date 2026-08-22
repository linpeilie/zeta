import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';

/// `zeta_agent_providers` 的包内契约测试入口。
///
/// 这里只放**不依赖宿主**的适配层契约；大量既有的协议 fixture 序列测试仍在根
/// 测试树（它们复用应用侧 fixture 与 harness），迁移是后续增量。
void main() {
  group('适配层可脱离宿主使用', () {
    test('三个内置 Provider 都能从中立配置造出 bundle', () {
      const factory = DefaultAgentProviderFactory();

      for (final config in <AgentProviderConfig>[
        AgentProviderConfig.defaultCodex,
        AgentProviderConfig.defaultGrok,
        AgentProviderConfig.defaultClaudeCode,
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

    test('静态能力表按 kind 给出中立能力', () {
      final codex = AgentProviderStaticCapabilities.forKind(
        AgentProviderKind.codexAppServer,
      );
      final acp = AgentProviderStaticCapabilities.forKind(
        AgentProviderKind.acp,
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

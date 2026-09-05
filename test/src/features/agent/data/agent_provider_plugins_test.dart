import 'package:zeta/src/app/plugins/agent_provider_manifest.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import '../../../testing/agent_provider_implementations.dart';

import '../../../testing/activated_agent_provider_plugins.dart';

void main() {
  test('Claude Code 插件贡献可初始化的原生 bundle', () async {
    final factory = activateBuiltInAgentProviderBundleFactory();

    final bundle = factory.createBundle(defaultClaudeCodeAgentProviderConfig);
    expect(bundle.runtime, isA<ClaudeCodeAgentProvider>());
    expect(bundle.runtime.config.kind, claudeCodeAgentProviderType);
    expect(bundle.runtime.capabilities.canRemoveThreadFromList, isTrue);
    expect(bundle.threadCatalog, isNotNull);
    expect(bundle.localThreadList, isNotNull);

    await bundle.runtime.initialize();
    await bundle.runtime.dispose();
  });

  test('Claude Code 插件把 CLI metadata loader 注入模型目录', () async {
    var metadataCalls = 0;
    final factory = activateBuiltInAgentProviderBundleFactory(
      claudeCodeMetadataLoader: () async {
        metadataCalls += 1;
        return const ClaudeCodeCliMetadataSnapshot(
          models: AgentModelList(
            models: <AgentModelInfo>[
              AgentModelInfo(
                id: 'cli-default',
                model: 'cli-default',
                displayName: 'CLI Default',
                isDefault: true,
              ),
            ],
          ),
          subscriptionType: 'Claude Pro',
        );
      },
    );
    final bundle = factory.createBundle(defaultClaudeCodeAgentProviderConfig);
    addTearDown(bundle.runtime.dispose);

    final models = await bundle.modelCatalog!.listModels();

    expect(models.models.single.id, 'cli-default');
    expect(metadataCalls, 1);
  });

  test('自定义配置 id 仍按开放 Provider type 路由', () async {
    final factory = activateBuiltInAgentProviderBundleFactory();
    final config = defaultClaudeCodeAgentProviderConfig.copyWith(
      id: 'claude-work',
      displayName: 'Claude Work',
    );

    final bundle = factory.createBundle(config);
    addTearDown(bundle.runtime.dispose);

    expect(bundle.runtime, isA<ClaudeCodeAgentProvider>());
    expect(bundle.runtime.config.id, 'claude-work');
    expect(bundle.runtime.config.displayName, 'Claude Work');
  });

  test('未注册的开放 Provider type fail-closed', () {
    final factory = activateBuiltInAgentProviderBundleFactory();
    const config = AgentProviderConfig(
      id: 'future-provider',
      displayName: 'Future Provider',
      kind: AgentProviderTypeId('future.protocol'),
      command: 'future',
    );

    expect(() => factory.createBundle(config), throwsUnsupportedError);
  });

  test('内置保留 id 不能冒充另一 Provider type', () {
    final factory = activateBuiltInAgentProviderBundleFactory();
    final config = defaultClaudeCodeAgentProviderConfig.copyWith(
      id: defaultAgentProviderId,
    );

    expect(() => factory.createBundle(config), throwsUnsupportedError);
  });
}

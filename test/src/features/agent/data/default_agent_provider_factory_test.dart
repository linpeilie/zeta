import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

void main() {
  test('creates Claude Code bundle that initializes without process', () async {
    const factory = DefaultAgentProviderFactory();

    final bundle = factory.createBundle(AgentProviderConfig.defaultClaudeCode);
    expect(bundle.runtime, isA<ClaudeCodeAgentProvider>());
    expect(bundle.runtime.config.kind, AgentProviderKind.claudeCode);
    expect(bundle.runtime.capabilities.canRemoveThreadFromList, isTrue);
    expect(bundle.threadCatalog, isNotNull);
    expect(bundle.localThreadList, isNotNull);

    await bundle.runtime.initialize();
    await bundle.runtime.dispose();
  });

  test('wires the Claude CLI metadata loader into the model catalog', () async {
    var metadataCalls = 0;
    final factory = DefaultAgentProviderFactory(
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
    final bundle = factory.createBundle(AgentProviderConfig.defaultClaudeCode);
    addTearDown(bundle.runtime.dispose);

    final models = await bundle.modelCatalog!.listModels();

    expect(models.models.single.id, 'cli-default');
    expect(metadataCalls, 1);
  });
}

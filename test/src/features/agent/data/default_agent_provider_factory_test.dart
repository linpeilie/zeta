import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_agent_provider.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_cli_metadata.dart';
import 'package:zeta/src/features/agent/data/default_agent_provider_factory.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  test('DefaultAgentProviderFactory never creates a Cursor runtime', () {
    const factory = DefaultAgentProviderFactory();

    expect(
      () => factory.createBundle(AgentProviderConfig.defaultCursor),
      throwsA(
        isA<UnsupportedError>().having(
          (error) => error.message,
          'message',
          contains('已退役'),
        ),
      ),
    );
  });

  test('rejects a Cursor runtime kind even under a legacy alias', () {
    const factory = DefaultAgentProviderFactory();
    final config = AgentProviderConfig.defaultCursor.copyWith(
      id: 'legacy-cursor-alias',
      displayName: 'Legacy Cursor Alias',
    );

    expect(() => factory.createBundle(config), throwsUnsupportedError);
  });

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

  test('createBundle never creates a Cursor runtime', () {
    const factory = DefaultAgentProviderFactory();

    expect(
      () => factory.createBundle(AgentProviderConfig.defaultCursor),
      throwsA(
        isA<UnsupportedError>().having(
          (error) => error.message,
          'message',
          contains('已退役'),
        ),
      ),
    );
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

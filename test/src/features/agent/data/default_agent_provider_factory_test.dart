import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_agent_provider.dart';
import 'package:zeta/src/features/agent/data/default_agent_provider_factory.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider_bundle.dart';

void main() {
  test('DefaultAgentProviderFactory never creates a Cursor runtime', () {
    const factory = DefaultAgentProviderFactory();

    expect(
      () => factory.create(AgentProviderConfig.defaultCursor),
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

    expect(() => factory.create(config), throwsUnsupportedError);
  });

  test(
    'creates Claude Code provider that initializes without process',
    () async {
      const factory = DefaultAgentProviderFactory();

      final provider = factory.create(AgentProviderConfig.defaultClaudeCode);
      expect(provider, isA<ClaudeCodeAgentProvider>());
      expect(provider.config.kind, AgentProviderKind.claudeCode);
      expect(provider.capabilities.canRemoveThreadFromList, isTrue);
      expect(provider.bundle.threadCatalog, isNotNull);
      expect(provider.bundle.localThreadList, isNotNull);

      await provider.initialize();
      await provider.dispose();
    },
  );
}

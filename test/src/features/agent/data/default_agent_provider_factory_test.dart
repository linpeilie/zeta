import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/default_agent_provider_factory.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  test('DefaultAgentProviderFactory never creates a Cursor runtime', () {
    const factory = DefaultAgentProviderFactory();

    expect(
      () => factory.create(AgentProviderConfig.defaultCursor),
      throwsA(
        isA<UnsupportedError>().having(
          (error) => error.message,
          'message',
          contains('已软下线'),
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
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/agent_management/data/codex_agent_management_repository.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';

void main() {
  group('CodexAgentManagementRepository', () {
    late Directory codexHome;
    late CodexAgentManagementRepository repository;

    setUp(() async {
      codexHome = await Directory.systemTemp.createTemp(
        'zeta-agent-management-test-',
      );
      repository = CodexAgentManagementRepository(
        providerFactory: const _ThrowingProviderFactory(),
        codexHomeProvider: () => codexHome.path,
      );
    });

    tearDown(() async {
      if (await codexHome.exists()) {
        await codexHome.delete(recursive: true);
      }
    });

    test('compares semantic versions conservatively', () {
      expect(isNewerVersion('0.131.0', '0.130.0'), isTrue);
      expect(isNewerVersion('1.0.0', '0.130.0'), isTrue);
      expect(isNewerVersion('0.130.0', '0.130.0'), isFalse);
      expect(isNewerVersion('0.129.9', '0.130.0'), isFalse);
      expect(isNewerVersion('latest', '0.130.0'), isFalse);
    });

    test('masks configuration and redacts log credentials', () {
      final masked = maskSensitiveConfiguration('''
model = "gpt"
api_key = "sk-secret-value-123456"
refreshToken = "refresh-secret"
''');
      expect(masked, contains('model = "gpt"'));
      expect(masked, isNot(contains('sk-secret-value-123456')));
      expect(masked, isNot(contains('refresh-secret')));

      final redacted = redactLogLine(
        'Authorization: Bearer abc.def.ghi token=secret-value '
        'sk-abcdefghijklmnop',
      );
      expect(redacted, isNot(contains('abc.def.ghi')));
      expect(redacted, isNot(contains('secret-value')));
      expect(redacted, isNot(contains('abcdefghijklmnop')));
    });

    test(
      'saves valid TOML through a backup and reloads the snapshot',
      () async {
        final config = File(repository.configPath);
        await config.writeAsString('model = "gpt-old"\n');
        final original = await repository.readConfiguration();

        final result = await repository.saveConfiguration(
          original: original,
          content: 'model = "gpt-new"\n',
        );

        expect(await config.readAsString(), 'model = "gpt-new"\n');
        expect(result.document.content, 'model = "gpt-new"\n');
        expect(result.backupPath, isNotNull);
        expect(
          await File(result.backupPath!).readAsString(),
          'model = "gpt-old"\n',
        );
      },
    );

    test('rejects invalid TOML without changing the original file', () async {
      final config = File(repository.configPath);
      await config.writeAsString('model = "gpt"\n');
      final original = await repository.readConfiguration();

      expect(
        () => repository.saveConfiguration(
          original: original,
          content: 'model = [\n',
        ),
        throwsA(isA<AgentConfigurationValidationException>()),
      );
      expect(await config.readAsString(), 'model = "gpt"\n');
    });

    test('detects an external modification before saving', () async {
      final config = File(repository.configPath);
      await config.writeAsString('model = "one"\n');
      final original = await repository.readConfiguration();
      await config.writeAsString('model = "external"\n');

      expect(
        () => repository.saveConfiguration(
          original: original,
          content: 'model = "local"\n',
        ),
        throwsA(isA<AgentConfigurationConflictException>()),
      );
      expect(await config.readAsString(), 'model = "external"\n');
    });
  });
}

class _ThrowingProviderFactory implements AgentProviderFactory {
  const _ThrowingProviderFactory();

  @override
  AgentProvider create(AgentProviderConfig config) {
    throw UnsupportedError('Provider creation is not used by these tests.');
  }
}

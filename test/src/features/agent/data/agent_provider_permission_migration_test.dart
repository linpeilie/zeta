import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_codec.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import '../../../testing/fixture_reader.dart';

void main() {
  group('AgentProviderPermissionMigrationRegistry', () {
    test('composition registry exposes only registered provider types', () {
      final registry = _migrationRegistry();

      expect(registry.registeredTypes, <AgentProviderTypeId>{
        codexAgentProviderType,
        grokAgentProviderType,
      });
      expect(
        () => registry.registeredTypes.add(claudeCodeAgentProviderType),
        throwsUnsupportedError,
      );
    });

    test('a new provider can register migration without domain changes', () {
      final codec = AgentProviderSettingsCodec(
        providerDefinitions: _definitionsWithMigrator(
          claudeCodeAgentProviderType,
          const _FixtureMigrator('claude-safe'),
        ),
      );

      final config = codec.decodeProvider(<String, Object?>{
        'id': 'claude',
        'displayName': 'Claude',
        'kind': 'claudeCode',
        'command': 'claude',
        'legacyPermission': 'provider-owned-value',
      });

      expect(config?.selectedPermissionOptionId, 'claude-safe');
    });
  });

  group('AgentProviderSettingsCodec V1/V2 compatibility', () {
    test('fixture table keeps V2 priority and provider-specific fallback', () {
      final codec = _codec();
      final fixture = readFixtureJsonMap(
        'agent_permission_runtime_architecture/permission_migration_cases.json',
      );
      final cases = fixture['cases']! as List<Object?>;

      for (final value in cases) {
        final row = _stringMap(value);
        final config = codec.decodeProvider(row['input']);

        expect(config, isNotNull, reason: row['id']!.toString());
        expect(
          config!.selectedPermissionOptionId,
          row['expectedOptionId'],
          reason: row['id']!.toString(),
        );

        // 迁移后的 V2 再解码结果不变，保证幂等。
        final roundTrip = codec.decodeProvider(config.toJson());
        expect(
          roundTrip?.selectedPermissionOptionId,
          row['expectedOptionId'],
          reason: '${row['id']}: idempotent V2 round-trip',
        );
      }
    });

    test('present V2 field short-circuits migrator even when empty', () {
      final spy = _SpyMigrator(':must-not-run');
      final codec = AgentProviderSettingsCodec(
        providerDefinitions: _definitionsWithMigrator(
          codexAgentProviderType,
          spy,
        ),
      );

      final config = codec.decodeProvider(<String, Object?>{
        'id': 'codex',
        'displayName': 'Codex',
        'kind': 'codexAppServer',
        'command': 'codex',
        'selectedPermissionOptionId': '   ',
        'selectedPermissionProfileId': 'stale-high-privilege-profile',
      });

      expect(config?.selectedPermissionOptionId, isNull);
      expect(spy.calls, 0);
    });

    test('V2 optionId stays opaque and is never provider-normalized', () {
      final config = _codec().decodeProvider(<String, Object?>{
        'id': 'grok',
        'displayName': 'Grok',
        'kind': 'acp',
        'command': 'grok',
        'selectedPermissionOptionId': 'future-mode',
        'selectedPermissionMode': 'default',
      });

      expect(config?.selectedPermissionOptionId, 'future-mode');
    });

    test('Codex legacy policies are strict and fail closed', () {
      final migrator = const CodexPermissionPreferenceMigrator();

      expect(
        migrator.migrateLegacyOptionId(<String, Object?>{
          'selectedApprovalPolicy': 'never',
          'selectedSandboxPolicy': 'dangerFullAccess',
        }),
        ':danger-full-access',
      );
      expect(
        migrator.migrateLegacyOptionId(<String, Object?>{
          'selectedApprovalPolicy': 'never',
          'selectedSandboxPolicy': 'workspaceWrite',
        }),
        isNull,
      );
      expect(
        migrator.migrateLegacyOptionId(<String, Object?>{
          'selectedApprovalPolicy': 'future-policy',
          'selectedSandboxPolicy': 'dangerFullAccess',
        }),
        isNull,
      );
      expect(
        migrator.migrateLegacyOptionId(<String, Object?>{
          'selectedPermissionProfileId': 'team-safe',
          'selectedApprovalPolicy': 'never',
          'selectedSandboxPolicy': 'dangerFullAccess',
        }),
        'team-safe',
      );
    });

    test('Grok legacy aliases normalize only inside its data migrator', () {
      final migrator = const GrokPermissionPreferenceMigrator();

      for (final testCase in <(Object?, String)>[
        ('default', 'ask'),
        ('', 'ask'),
        ('future-mode', 'ask'),
        ('auto', 'auto'),
        ('yolo', 'always-approve'),
      ]) {
        expect(
          migrator.migrateLegacyOptionId(<String, Object?>{
            'selectedPermissionMode': testCase.$1,
          }),
          testCase.$2,
        );
      }
      expect(migrator.migrateLegacyOptionId(const <String, Object?>{}), isNull);
    });

    test('V1 settings decode tolerantly and encode as V2 option-only', () {
      final codec = _codec();
      final settings = codec.decode(<String, Object?>{
        'version': 1,
        'activeProviderId': 'grok',
        'providers': <Object?>[
          <String, Object?>{
            'id': 'grok',
            'displayName': 'Grok',
            'kind': 'acp',
            'command': 'grok',
            'selectedPermissionMode': 'auto',
          },
        ],
      });

      expect(settings.activeProvider.selectedPermissionOptionId, 'auto');
      final encoded = codec.encodeJson(settings);
      expect(encoded, contains('"version":2'));
      expect(encoded, contains('"selectedPermissionOptionId":"auto"'));
      for (final legacyField in const <String>[
        'selectedPermissionProfileId',
        'selectedApprovalPolicy',
        'selectedSandboxPolicy',
        'selectedPermissionMode',
      ]) {
        expect(encoded, isNot(contains(legacyField)));
      }
    });

    test('damaged JSON and unsupported versions fall back safely', () {
      final codec = _codec();

      expect(codec.decodeJson('{broken').activeProvider.id, 'codex');
      expect(
        codec
            .decode(<String, Object?>{'version': 99, 'providers': <Object?>[]})
            .activeProvider
            .id,
        'codex',
      );
    });

    test('migration boundary is pure and has no Agent home IO', () {
      final source = File(
        'packages/zeta_agent_providers/lib/src/agent_provider_permission_migration.dart',
      ).readAsStringSync();

      expect(source, isNot(contains("import 'dart:io'")));
      expect(source, isNot(contains('Directory(')));
      expect(source, isNot(contains('File(')));
      expect(source, isNot(contains('.codex')));
      expect(source, isNot(contains('.grok')));
    });
  });
}

AgentProviderPermissionMigrationRegistry _migrationRegistry() {
  return AgentProviderPermissionMigrationRegistry(
    <AgentProviderTypeId, AgentProviderPermissionPreferenceMigrator>{
      codexAgentProviderType: const CodexPermissionPreferenceMigrator(),
      grokAgentProviderType: const GrokPermissionPreferenceMigrator(),
    },
  );
}

AgentProviderSettingsCodec _codec() {
  return AgentProviderSettingsCodec(
    providerDefinitions: builtInAgentProviderDefinitionCatalog,
  );
}

AgentProviderDefinitionCatalog _definitionsWithMigrator(
  AgentProviderTypeId providerType,
  AgentProviderPermissionPreferenceMigrator migrator,
) {
  return AgentProviderDefinitionCatalog(
    builtInAgentProviderDefinitions.map((definition) {
      if (definition.providerType != providerType) {
        return definition;
      }
      return AgentProviderDefinition(
        providerId: definition.providerId,
        providerType: definition.providerType,
        defaultConfig: definition.defaultConfig,
        staticCapabilities: definition.staticCapabilities,
        modelCatalogSourceLabel: definition.modelCatalogSourceLabel,
        modelCatalogFingerprintExtraKeys:
            definition.modelCatalogFingerprintExtraKeys,
        permissionPreferenceMigrator: migrator,
        isDefault: definition.isDefault,
      );
    }),
  );
}

Map<String, Object?> _stringMap(Object? value) {
  return (value! as Map<Object?, Object?>).map(
    (key, item) => MapEntry(key.toString(), item),
  );
}

final class _FixtureMigrator
    implements AgentProviderPermissionPreferenceMigrator {
  const _FixtureMigrator(this.optionId);

  final String optionId;

  @override
  String? migrateLegacyOptionId(Map<String, Object?> legacyConfig) => optionId;
}

final class _SpyMigrator implements AgentProviderPermissionPreferenceMigrator {
  _SpyMigrator(this.optionId);

  final String optionId;
  int calls = 0;

  @override
  String? migrateLegacyOptionId(Map<String, Object?> legacyConfig) {
    calls += 1;
    return optionId;
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_codec.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

void main() {
  group('FileAgentProviderConfigStore', () {
    late Directory tempDirectory;
    late File settingsFile;

    setUp(() {
      tempDirectory = Directory.systemTemp.createTempSync(
        'zeta_provider_store_',
      );
      settingsFile = File(
        '${tempDirectory.path}${Platform.pathSeparator}providers.json',
      );
    });

    tearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('loads the default Codex provider when storage is empty', () async {
      final store = _fileStore(settingsFile);

      final settings = await store.load();

      expect(settings.activeProvider.id, defaultAgentProviderId);
      expect(settings.activeProvider.command, 'codex');
      expect(settings.activeProvider.arguments, <String>['app-server']);
      expect(settings.providers.map((provider) => provider.id), <String>[
        defaultAgentProviderId,
        grokAgentProviderId,
      ]);
    });

    test('saves provider settings as versioned JSON', () async {
      final store = _fileStore(settingsFile);
      const settings = AgentProviderSettings(
        providers: <AgentProviderConfig>[
          AgentProviderConfig.defaultCodex,
          AgentProviderConfig(
            id: 'claude',
            displayName: 'Claude Code',
            kind: AgentProviderKind.claudeCode,
            command: 'claude',
          ),
        ],
        activeProviderId: 'claude',
      );

      await store.save(settings);
      final raw =
          jsonDecode(await settingsFile.readAsString()) as Map<String, Object?>;

      expect(raw['version'], AgentProviderSettings.currentVersion);
      expect(raw['version'], 2);
      expect(raw['activeProviderId'], 'claude');
      expect(await store.load(), isA<AgentProviderSettings>());
      expect((await store.load()).activeProvider.id, 'claude');
    });

    test('falls back to defaults when the JSON file is damaged', () async {
      await settingsFile.writeAsString('{not-json');
      final store = _fileStore(settingsFile);

      final settings = await store.load();

      expect(settings.activeProvider.id, defaultAgentProviderId);
    });

    test('falls back to defaults when the file is not valid UTF-8', () async {
      await settingsFile.writeAsBytes(<int>[0xff]);
      final store = _fileStore(settingsFile);

      final settings = await store.load();

      expect(settings.activeProvider.id, defaultAgentProviderId);
    });

    test('propagates file system errors while saving', () async {
      final blockedParent = File(
        '${tempDirectory.path}${Platform.pathSeparator}blocked',
      );
      await blockedParent.writeAsString('not a directory');
      final store = FileAgentProviderConfigStore(
        file: File(
          '${blockedParent.path}${Platform.pathSeparator}providers.json',
        ),
        codec: _codec(),
      );

      await expectLater(
        store.save(const AgentProviderSettings()),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('loads V1 permission fields and rewrites V2 only', () async {
      await settingsFile.writeAsString(
        jsonEncode(<String, Object?>{
          'version': 1,
          'activeProviderId': 'grok',
          'providers': <Object?>[
            <String, Object?>{
              'id': 'grok',
              'displayName': 'Grok',
              'kind': 'acp',
              'command': 'grok',
              'selectedPermissionMode': 'yolo',
            },
          ],
        }),
      );
      final store = _fileStore(settingsFile);

      final settings = await store.load();
      expect(
        settings.activeProvider.selectedPermissionOptionId,
        'always-approve',
      );

      await store.save(settings);
      final rewritten = await settingsFile.readAsString();
      expect(rewritten, contains('"selectedPermissionOptionId"'));
      expect(rewritten, isNot(contains('selectedPermissionMode')));
    });
  });

  group('AgentProviderSettings', () {
    test('normalizes legacy built-in provider display names', () {
      final settings = _codec().decode(<String, Object?>{
        'version': 1,
        'activeProviderId': defaultAgentProviderId,
        'providers': <Object?>[
          <String, Object?>{
            ...AgentProviderConfig.defaultCodex.toJson(),
            'displayName': 'Codex CLI',
          },
          <String, Object?>{
            ...AgentProviderConfig.defaultGrok.toJson(),
            'displayName': 'Grok CLI',
          },
        ],
      });

      expect(
        settings.providers.map((provider) => provider.displayName),
        <String>['Codex', 'Grok'],
      );
    });

    test('round-trips versioned model preferences tolerantly', () {
      final updatedAt = DateTime.utc(2026, 7, 15, 8);
      final config = AgentProviderConfig.defaultCodex.withModelConfiguration(
        selection: const AgentModelSelection(
          modelId: 'gpt-5.5',
          reasoningEffort: 'high',
        ),
        preferences: <String, AgentModelPreference>{
          'gpt-5.5': AgentModelPreference(
            modelId: 'gpt-5.5',
            reasoningEffort: 'high',
            fastEnabled: false,
            serviceTierId: null,
            updatedAt: updatedAt,
          ),
        },
      );

      final decoded = _codec().decodeProvider(config.toJson());

      expect(decoded, isNotNull);
      expect(decoded!.selectedServiceTier, isNull);
      expect(decoded.modelPreferences['gpt-5.5']?.reasoningEffort, 'high');
      expect(decoded.modelPreferences['gpt-5.5']?.fastEnabled, isFalse);
      expect(decoded.modelPreferences['gpt-5.5']?.updatedAt, updatedAt);
    });

    test('ignores damaged model preference entries', () {
      final raw = AgentProviderConfig.defaultCodex.toJson();
      raw['modelPreferences'] = <String, Object?>{
        'missing-id': <String, Object?>{'fastEnabled': true},
        'valid': <String, Object?>{
          'modelId': 'gpt-5.5',
          'reasoningEffort': 'medium',
          'fastEnabled': false,
          'updatedAt': 'not-a-date',
        },
      };

      final decoded = _codec().decodeProvider(raw);

      expect(decoded?.modelPreferences.keys, <String>['gpt-5.5']);
      expect(
        decoded?.modelPreferences['gpt-5.5']?.updatedAt,
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    });
  });
}

FileAgentProviderConfigStore _fileStore(File file) {
  return FileAgentProviderConfigStore(file: file, codec: _codec());
}

AgentProviderSettingsCodec _codec() {
  return AgentProviderSettingsCodec(
    migrationRegistry: AgentProviderPermissionMigrationRegistry(
      <AgentProviderKind, AgentProviderPermissionPreferenceMigrator>{
        AgentProviderKind.codexAppServer:
            const CodexPermissionPreferenceMigrator(),
        AgentProviderKind.acp: const GrokPermissionPreferenceMigrator(),
      },
    ),
  );
}

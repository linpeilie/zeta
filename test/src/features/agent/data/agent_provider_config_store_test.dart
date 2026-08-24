import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/app/storage/atomic_text_file.dart';
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

    test('loads every built-in provider when storage is empty', () async {
      final store = _fileStore(settingsFile);

      final settings = await store.load();

      expect(settings.activeProvider.id, defaultAgentProviderId);
      expect(settings.activeProvider.command, 'codex');
      expect(settings.activeProvider.arguments, <String>['app-server']);
      expect(settings.providers.map((provider) => provider.id), <String>[
        defaultAgentProviderId,
        grokAgentProviderId,
        defaultClaudeCodeProviderId,
      ]);
    });

    test('saves provider settings as versioned JSON', () async {
      final store = _fileStore(settingsFile);
      const settings = AgentProviderSettings(
        providers: <AgentProviderConfig>[
          defaultCodexAgentProviderConfig,
          AgentProviderConfig(
            id: 'claude',
            displayName: 'Claude Code',
            kind: claudeCodeAgentProviderType,
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
      expect(settings.providers.map((provider) => provider.id), <String>[
        defaultAgentProviderId,
        grokAgentProviderId,
        defaultClaudeCodeProviderId,
      ]);
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
        storage: AtomicTextFile(
          File('${blockedParent.path}${Platform.pathSeparator}providers.json'),
        ),
        codec: _codec(),
      );

      await expectLater(
        store.save(const AgentProviderSettings()),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('AgentProviderSettings', () {
    test('current version with invalid active id uses plugin default', () {
      final decoded = _codec().decode(<String, Object?>{
        'version': AgentProviderSettings.currentVersion,
        'activeProviderId': 'removed-provider',
        'providers': <Object?>[
          <String, Object?>{
            'id': 'custom-grok',
            'displayName': 'Custom Grok',
            'kind': grokAgentProviderType.value,
            'command': 'custom-grok',
          },
          defaultCodexAgentProviderConfig.toJson(),
        ],
      });

      expect(decoded.activeProviderId, defaultAgentProviderId);
      expect(decoded.activeProvider.id, defaultAgentProviderId);
      expect(decoded.providers.first.id, 'custom-grok');
    });

    test('unsupported version falls back to plugin defaults', () {
      final decoded = _codec().decode(<String, Object?>{
        'version': AgentProviderSettings.currentVersion - 1,
        'providers': <Object?>[defaultGrokAgentProviderConfig.toJson()],
      });

      expect(decoded.activeProvider.id, defaultAgentProviderId);
      expect(decoded.providers.map((provider) => provider.id), <String>[
        defaultAgentProviderId,
        grokAgentProviderId,
        defaultClaudeCodeProviderId,
      ]);
    });

    test('drops a built-in id that claims another plugin type', () {
      final decoded = _codec().decode(<String, Object?>{
        'version': 2,
        'activeProviderId': defaultAgentProviderId,
        'providers': <Object?>[
          <String, Object?>{
            'id': defaultAgentProviderId,
            'displayName': 'Wrong',
            'kind': claudeCodeAgentProviderType.value,
            'command': 'claude',
          },
        ],
      });

      expect(decoded.activeProvider, defaultCodexAgentProviderConfig);
      expect(decoded.providers, contains(defaultClaudeCodeAgentProviderConfig));
    });

    test('normalizes built-in provider display names', () {
      final settings = _codec().decode(<String, Object?>{
        'version': AgentProviderSettings.currentVersion,
        'activeProviderId': defaultAgentProviderId,
        'providers': <Object?>[
          <String, Object?>{
            ...defaultCodexAgentProviderConfig.toJson(),
            'displayName': 'Codex CLI',
          },
          <String, Object?>{
            ...defaultGrokAgentProviderConfig.toJson(),
            'displayName': 'Grok CLI',
          },
          <String, Object?>{
            ...defaultClaudeCodeAgentProviderConfig.toJson(),
            'displayName': 'Claude Code',
          },
        ],
      });

      expect(
        settings.providers.map((provider) => provider.displayName),
        <String>['Codex', 'Grok', 'Claude'],
      );
    });

    test('round-trips current model preferences', () {
      final updatedAt = DateTime.utc(2026, 7, 15, 8);
      final config = defaultCodexAgentProviderConfig.withModelConfiguration(
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
      final raw = defaultCodexAgentProviderConfig.toJson();
      raw['modelPreferences'] = <String, Object?>{
        'missing-id': <String, Object?>{'fastEnabled': true},
        'valid': <String, Object?>{
          'modelId': 'gpt-5.5',
          'reasoningEffort': 'medium',
          'fastEnabled': false,
          'updatedAt': 'not-a-date',
          'version': AgentModelPreference.currentVersion,
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
  return FileAgentProviderConfigStore(
    storage: AtomicTextFile(file),
    codec: _codec(),
  );
}

AgentProviderSettingsCodec _codec() {
  return AgentProviderSettingsCodec(
    providerDefinitions: builtInAgentProviderDefinitionCatalog,
  );
}

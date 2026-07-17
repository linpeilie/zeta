import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

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
      final store = FileAgentProviderConfigStore(file: settingsFile);

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
      final store = FileAgentProviderConfigStore(file: settingsFile);
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

      expect(raw['version'], 1);
      expect(raw['activeProviderId'], 'claude');
      expect(await store.load(), isA<AgentProviderSettings>());
      expect((await store.load()).activeProvider.id, 'claude');
    });

    test('falls back to defaults when the JSON file is damaged', () async {
      await settingsFile.writeAsString('{not-json');
      final store = FileAgentProviderConfigStore(file: settingsFile);

      final settings = await store.load();

      expect(settings.activeProvider.id, defaultAgentProviderId);
    });

    test('falls back to defaults when the file is not valid UTF-8', () async {
      await settingsFile.writeAsBytes(<int>[0xff]);
      final store = FileAgentProviderConfigStore(file: settingsFile);

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
      );

      await expectLater(
        store.save(const AgentProviderSettings()),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('AgentProviderSettings', () {
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

      final decoded = AgentProviderConfig.tryDecode(config.toJson());

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

      final decoded = AgentProviderConfig.tryDecode(raw);

      expect(decoded?.modelPreferences.keys, <String>['gpt-5.5']);
      expect(
        decoded?.modelPreferences['gpt-5.5']?.updatedAt,
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    });

    test('does not add Cursor to existing non-Cursor settings', () {
      final settings = AgentProviderSettings.tryDecode(<String, Object?>{
        'version': 1,
        'activeProviderId': grokAgentProviderId,
        'providers': <Object?>[
          AgentProviderConfig.defaultCodex.toJson(),
          AgentProviderConfig.defaultGrok.toJson(),
        ],
      });

      expect(settings.activeProviderId, grokAgentProviderId);
      expect(
        settings.providers.map((provider) => provider.id),
        isNot(contains(cursorAgentProviderId)),
      );
    });

    test(
      'decodes and round-trips legacy Cursor settings without migration',
      () {
        final legacyCursor = AgentProviderConfig.defaultCursor.copyWith(
          enabled: true,
          command: '/legacy/cursor-agent',
          extra: const <String, Object?>{'legacyMarker': 'keep-me'},
        );
        final original = <String, Object?>{
          'version': 1,
          'activeProviderId': cursorAgentProviderId,
          'providers': <Object?>[
            AgentProviderConfig.defaultCodex.toJson(),
            AgentProviderConfig.defaultGrok.toJson(),
            legacyCursor.toJson(),
          ],
        };

        final settings = AgentProviderSettings.tryDecode(<String, Object?>{
          ...original,
        });

        expect(settings.activeProviderId, cursorAgentProviderId);
        final cursor = settings.providers.singleWhere(
          (provider) => provider.id == cursorAgentProviderId,
        );
        expect(cursor.kind, AgentProviderKind.cursorAcp);
        expect(cursor.enabled, isTrue);
        expect(cursor.command, '/legacy/cursor-agent');
        expect(cursor.extra['legacyMarker'], 'keep-me');
        expect(settings.toJson(), original);
      },
    );

    test('preserves a missing legacy Cursor active id for safe fallback', () {
      final settings = AgentProviderSettings.tryDecode(<String, Object?>{
        'version': 1,
        'activeProviderId': cursorAgentProviderId,
        'providers': <Object?>[
          AgentProviderConfig.defaultCodex.toJson(),
          AgentProviderConfig.defaultGrok.toJson(),
        ],
      });

      expect(settings.activeProviderId, cursorAgentProviderId);
      expect(
        settings.providers.map((provider) => provider.id),
        isNot(contains(cursorAgentProviderId)),
      );
    });
  });
}

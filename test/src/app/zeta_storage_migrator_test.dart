import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/app/zeta_storage_migrator.dart';
import 'package:zeta/src/core/storage/zeta_data_paths.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/ide_session/data/ide_session_store.dart';
import 'package:zeta/src/features/settings/data/appearance_settings_store.dart';
import 'package:zeta/src/features/settings/domain/app_language.dart';
import 'package:zeta/src/features/usage_statistics/data/usage_statistics_partition_store.dart';

void main() {
  group('SharedPreferencesLegacyZetaPreferences', () {
    test('prefers the async backend value', () async {
      var legacyReads = 0;
      final preferences = SharedPreferencesLegacyZetaPreferences(
        asyncReadString: (_) async => 'async-value',
        legacyReadString: (_) async {
          legacyReads += 1;
          return 'legacy-value';
        },
      );

      expect(await preferences.getString('key'), 'async-value');
      expect(legacyReads, 0);
    });

    test('falls back to the legacy backend when async is empty', () async {
      final legacyKeys = <String>[];
      final preferences = SharedPreferencesLegacyZetaPreferences(
        asyncReadString: (_) async => null,
        legacyReadString: (key) async {
          legacyKeys.add(key);
          return 'legacy-value';
        },
      );

      expect(await preferences.getString('usage-key'), 'legacy-value');
      expect(legacyKeys, <String>['usage-key']);
    });
  });

  group('ZetaStorageMigrator', () {
    late Directory homeDirectory;
    late ZetaDataPaths paths;

    setUp(() {
      homeDirectory = Directory.systemTemp.createTempSync('zeta_migration_');
      paths = ZetaDataPaths.fromHomeDirectory(
        homeDirectory.path,
        isWindows: Platform.isWindows,
      );
    });

    tearDown(() {
      if (homeDirectory.existsSync()) {
        homeDirectory.deleteSync(recursive: true);
      }
    });

    test('migrates active Zeta preferences', () async {
      final values = <String, String>{
        agentProviderConfigStorageKey: '{"version":1,"providers":[]}',
        appearanceSettingsStorageKey: '{"version":1,"themeMode":"dark"}',
        sessionStorageKey: '{"version":2,"projectPaths":[]}',
        usageStatisticsIndexStorageKey: '{"version":2,"sessions":[]}',
      };
      final preferences = _FakeLegacyZetaPreferences(values);
      final migrator = ZetaStorageMigrator(
        paths: paths,
        preferences: preferences,
        clock: () => DateTime.utc(2026, 7, 14, 8, 30),
      );

      final result = await migrator.migrate();

      expect(result.alreadyCompleted, isFalse);
      expect(result.migratedKeys, unorderedEquals(values.keys));
      expect(
        await File(paths.providersFilePath).readAsString(),
        values[agentProviderConfigStorageKey],
      );
      expect(
        await File(paths.appearanceFilePath).readAsString(),
        values[appearanceSettingsStorageKey],
      );
      expect(
        await File(paths.ideSessionFilePath).readAsString(),
        values[sessionStorageKey],
      );
      // 迁移时归一到当前 v4 不透明分区，并保留 v2 的 Codex 空分区。
      final usageIndex =
          jsonDecode(
                await File(paths.usageStatisticsIndexFilePath).readAsString(),
              )
              as Map<String, Object?>;
      expect(usageIndex['version'], usageStatisticsPartitionIndexVersion);
      expect((usageIndex['providers'] as Map).keys, <String>['codex']);
      final marker =
          jsonDecode(await File(paths.migrationMarkerFilePath).readAsString())
              as Map<String, Object?>;
      expect(marker['version'], zetaStorageMigrationVersion);
      expect(marker['completedAt'], '2026-07-14T08:30:00.000Z');
      expect(Directory(paths.cacheDirectoryPath).existsSync(), isTrue);
    });

    test('converts the legacy theme value into appearance v1 JSON', () async {
      final migrator = ZetaStorageMigrator(
        paths: paths,
        preferences: _FakeLegacyZetaPreferences(<String, String>{
          legacyThemeModeStorageKey: 'dark',
        }),
      );

      final result = await migrator.migrate();

      final appearance =
          jsonDecode(await File(paths.appearanceFilePath).readAsString())
              as Map<String, Object?>;
      expect(result.migratedKeys, <String>[legacyThemeModeStorageKey]);
      expect(appearance['version'], 1);
      expect(appearance['themeMode'], 'dark');
    });

    test(
      'cleans CLI paths and raw errors from the migrated usage index',
      () async {
        const sourcePath = '/home/user/.codex/sessions/rollout-secret.jsonl';
        const errorMessage = 'raw error containing prompt text';
        const errorCode = 'provider-secret-error-code';
        final legacyIndex = jsonEncode(<String, Object?>{
          'version': 2,
          'sessions': <Object?>[
            <String, Object?>{
              'sourcePath': sourcePath,
              'fingerprint': '10:20',
              'threadId': 'thread-1',
              'projectPath': '/workspace/zeta',
              'sourceKind': 'codex_cli_rs',
              'createdAt': 1783987200000,
              'turns': <Object?>[
                <String, Object?>{
                  'id': 'turn-1',
                  'status': 'failed',
                  'errorMessage': errorMessage,
                  'errorCode': errorCode,
                  'samples': <Object?>[],
                },
              ],
            },
          ],
        });
        final migrator = ZetaStorageMigrator(
          paths: paths,
          preferences: _FakeLegacyZetaPreferences(<String, String>{
            usageStatisticsIndexStorageKey: legacyIndex,
          }),
        );

        await migrator.migrate();

        final migrated = await File(
          paths.usageStatisticsIndexFilePath,
        ).readAsString();
        expect(migrated, contains('sourceId'));
        expect(migrated, isNot(contains('sourcePath')));
        expect(migrated, isNot(contains(sourcePath)));
        expect(migrated, isNot(contains('errorMessage')));
        expect(migrated, isNot(contains(errorMessage)));
        expect(migrated, isNot(contains(errorCode)));
      },
    );

    test(
      'keeps existing target files and marker makes reruns read-free',
      () async {
        await Directory(paths.configDirectoryPath).create(recursive: true);
        await File(paths.providersFilePath).writeAsString('{"new":true}');
        final preferences = _FakeLegacyZetaPreferences(<String, String>{
          agentProviderConfigStorageKey: '{"old":true}',
        });
        final migrator = ZetaStorageMigrator(
          paths: paths,
          preferences: preferences,
        );

        final first = await migrator.migrate();
        final readsAfterFirstRun = preferences.readKeys.length;
        final second = await migrator.migrate();

        expect(
          await File(paths.providersFilePath).readAsString(),
          '{"new":true}',
        );
        expect(
          first.existingTargetKeys,
          contains(agentProviderConfigStorageKey),
        );
        expect(second.alreadyCompleted, isTrue);
        expect(preferences.readKeys, hasLength(readsAfterFirstRun));
      },
    );

    test(
      'does not mark a partial migration complete and retries safely',
      () async {
        await Directory(paths.configDirectoryPath).create(recursive: true);
        final appearanceBlocker = Directory(paths.appearanceFilePath)
          ..createSync();
        final preferences = _FakeLegacyZetaPreferences(<String, String>{
          agentProviderConfigStorageKey: '{"version":1,"providers":[]}',
          appearanceSettingsStorageKey: '{"version":1,"themeMode":"light"}',
        });
        final migrator = ZetaStorageMigrator(
          paths: paths,
          preferences: preferences,
        );

        await expectLater(
          migrator.migrate(),
          throwsA(isA<FileSystemException>()),
        );

        expect(File(paths.providersFilePath).existsSync(), isTrue);
        expect(File(paths.migrationMarkerFilePath).existsSync(), isFalse);

        appearanceBlocker.deleteSync();
        final retry = await migrator.migrate();

        expect(retry.alreadyCompleted, isFalse);
        expect(
          retry.existingTargetKeys,
          contains(agentProviderConfigStorageKey),
        );
        expect(File(paths.appearanceFilePath).existsSync(), isTrue);
        expect(File(paths.migrationMarkerFilePath).existsSync(), isTrue);
      },
    );

    test('retries after a transient legacy preference read failure', () async {
      final preferences = _FakeLegacyZetaPreferences(<String, String>{
        agentProviderConfigStorageKey: '{"version":1,"providers":[]}',
        appearanceSettingsStorageKey: '{"version":1,"themeMode":"dark"}',
        sessionStorageKey: '{"version":2,"projectPaths":[]}',
      }, throwOnKey: appearanceSettingsStorageKey);
      final migrator = ZetaStorageMigrator(
        paths: paths,
        preferences: preferences,
      );

      await expectLater(migrator.migrate(), throwsStateError);

      expect(File(paths.providersFilePath).existsSync(), isTrue);
      expect(File(paths.appearanceFilePath).existsSync(), isFalse);
      expect(File(paths.ideSessionFilePath).existsSync(), isFalse);
      expect(File(paths.migrationMarkerFilePath).existsSync(), isFalse);

      preferences.throwOnKey = null;
      final retry = await migrator.migrate();

      expect(retry.existingTargetKeys, contains(agentProviderConfigStorageKey));
      expect(File(paths.appearanceFilePath).existsSync(), isTrue);
      expect(File(paths.ideSessionFilePath).existsSync(), isTrue);
      expect(File(paths.migrationMarkerFilePath).existsSync(), isTrue);
    });

    test('replaces an invalid UTF-8 marker and reruns migration', () async {
      await Directory(paths.stateDirectoryPath).create(recursive: true);
      await File(paths.migrationMarkerFilePath).writeAsBytes(<int>[0xff]);
      final preferences = _FakeLegacyZetaPreferences(<String, String>{
        sessionStorageKey: '{"version":2,"projectPaths":[]}',
      });

      final result = await ZetaStorageMigrator(
        paths: paths,
        preferences: preferences,
      ).migrate();

      expect(result.alreadyCompleted, isFalse);
      expect(File(paths.ideSessionFilePath).existsSync(), isTrue);
      final marker =
          jsonDecode(await File(paths.migrationMarkerFilePath).readAsString())
              as Map<String, Object?>;
      expect(marker['version'], zetaStorageMigrationVersion);
    });

    test('upgrades v1 general.json and writes marker v2 last', () async {
      await Directory(paths.configDirectoryPath).create(recursive: true);
      await File(paths.generalSettingsFilePath).writeAsString(
        jsonEncode(<String, Object?>{
          'version': 1,
          'sendMessageShortcut': 'primaryModifierEnter',
        }),
      );
      final result = await ZetaStorageMigrator(
        paths: paths,
        preferences: _FakeLegacyZetaPreferences(const <String, String>{}),
      ).migrate();

      expect(result.alreadyCompleted, isFalse);
      final general =
          jsonDecode(await File(paths.generalSettingsFilePath).readAsString())
              as Map<String, Object?>;
      expect(general['version'], 3);
      expect(general['appLanguage'], 'zh-Hans');
      expect(general['sendMessageShortcut'], 'primaryModifierEnter');
      final marker =
          jsonDecode(await File(paths.migrationMarkerFilePath).readAsString())
              as Map<String, Object?>;
      expect(marker['version'], 2);
    });

    test(
      'creates missing general.json with the supplied seed language',
      () async {
        await ZetaStorageMigrator(
          paths: paths,
          missingGeneralLanguage: AppLanguage.english,
          preferences: _FakeLegacyZetaPreferences(const <String, String>{}),
        ).migrate();

        final general =
            jsonDecode(await File(paths.generalSettingsFilePath).readAsString())
                as Map<String, Object?>;
        expect(general['version'], 3);
        expect(general['appLanguage'], 'en');
      },
    );

    test(
      'leaves damaged general.json untouched and still writes marker',
      () async {
        await Directory(paths.configDirectoryPath).create(recursive: true);
        await File(paths.generalSettingsFilePath).writeAsString('{not-json');

        await ZetaStorageMigrator(
          paths: paths,
          preferences: _FakeLegacyZetaPreferences(const <String, String>{}),
        ).migrate();

        expect(
          await File(paths.generalSettingsFilePath).readAsString(),
          '{not-json',
        );
        expect(File(paths.migrationMarkerFilePath).existsSync(), isTrue);
      },
    );

    test('does not write marker when general.json cannot be created', () async {
      await Directory(paths.configDirectoryPath).create(recursive: true);
      final blocker = Directory(paths.generalSettingsFilePath)..createSync();

      await expectLater(
        ZetaStorageMigrator(
          paths: paths,
          preferences: _FakeLegacyZetaPreferences(const <String, String>{}),
        ).migrate(),
        throwsA(isA<FileSystemException>()),
      );

      expect(File(paths.migrationMarkerFilePath).existsSync(), isFalse);
      blocker.deleteSync();
    });
  });
}

class _FakeLegacyZetaPreferences implements LegacyZetaPreferences {
  _FakeLegacyZetaPreferences(this.values, {this.throwOnKey});

  final Map<String, String> values;
  final List<String> readKeys = <String>[];
  String? throwOnKey;

  @override
  Future<String?> getString(String key) async {
    readKeys.add(key);
    if (key == throwOnKey) {
      throw StateError('temporary preference failure');
    }
    return values[key];
  }
}

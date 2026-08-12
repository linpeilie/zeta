import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/app/zeta_storage_migrator.dart';
import 'package:zeta/src/core/storage/zeta_data_paths.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/ide_session/data/ide_session_store.dart';
import 'package:zeta/src/features/settings/data/appearance_settings_store.dart';
import 'package:zeta/src/features/usage_statistics/data/usage_statistics_partition_store.dart';

const _legacyCursorSessionIndexStorageKey = 'zeta.agent.cursor.sessions.v1';

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
      paths = ZetaDataPaths.fromHomeDirectory(homeDirectory.path);
    });

    tearDown(() {
      if (homeDirectory.existsSync()) {
        homeDirectory.deleteSync(recursive: true);
      }
    });

    test(
      'migrates active Zeta preferences but never reads Cursor index',
      () async {
        final values = <String, String>{
          agentProviderConfigStorageKey: '{"version":1,"providers":[]}',
          appearanceSettingsStorageKey: '{"version":1,"themeMode":"dark"}',
          sessionStorageKey: '{"version":2,"projectPaths":[]}',
          _legacyCursorSessionIndexStorageKey: '{"version":1,"sessions":[]}',
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
        expect(
          result.migratedKeys,
          unorderedEquals(
            values.keys.where(
              (key) => key != _legacyCursorSessionIndexStorageKey,
            ),
          ),
        );
        expect(
          await paths.providersFile.readAsString(),
          values[agentProviderConfigStorageKey],
        );
        expect(
          await paths.appearanceFile.readAsString(),
          values[appearanceSettingsStorageKey],
        );
        expect(
          await paths.ideSessionFile.readAsString(),
          values[sessionStorageKey],
        );
        expect(paths.cursorSessionsFile.existsSync(), isFalse);
        expect(
          preferences.readKeys,
          isNot(contains(_legacyCursorSessionIndexStorageKey)),
        );
        // 迁移时归一到当前 v4 不透明分区，并保留 v2 的 Codex 空分区。
        final usageIndex =
            jsonDecode(await paths.usageStatisticsIndexFile.readAsString())
                as Map<String, Object?>;
        expect(usageIndex['version'], usageStatisticsPartitionIndexVersion);
        expect((usageIndex['providers'] as Map).keys, <String>['codex']);
        final marker =
            jsonDecode(await paths.migrationMarkerFile.readAsString())
                as Map<String, Object?>;
        expect(marker['version'], zetaStorageMigrationVersion);
        expect(marker['completedAt'], '2026-07-14T08:30:00.000Z');
        expect(paths.cacheDirectory.existsSync(), isTrue);
      },
    );

    test('converts the legacy theme value into appearance v1 JSON', () async {
      final migrator = ZetaStorageMigrator(
        paths: paths,
        preferences: _FakeLegacyZetaPreferences(<String, String>{
          legacyThemeModeStorageKey: 'dark',
        }),
      );

      final result = await migrator.migrate();

      final appearance =
          jsonDecode(await paths.appearanceFile.readAsString())
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

        final migrated = await paths.usageStatisticsIndexFile.readAsString();
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
        await paths.configDirectory.create(recursive: true);
        await paths.providersFile.writeAsString('{"new":true}');
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

        expect(await paths.providersFile.readAsString(), '{"new":true}');
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
        await paths.configDirectory.create(recursive: true);
        final appearanceBlocker = Directory(paths.appearanceFile.path)
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

        expect(paths.providersFile.existsSync(), isTrue);
        expect(paths.migrationMarkerFile.existsSync(), isFalse);

        appearanceBlocker.deleteSync();
        final retry = await migrator.migrate();

        expect(retry.alreadyCompleted, isFalse);
        expect(
          retry.existingTargetKeys,
          contains(agentProviderConfigStorageKey),
        );
        expect(paths.appearanceFile.existsSync(), isTrue);
        expect(paths.migrationMarkerFile.existsSync(), isTrue);
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

      expect(paths.providersFile.existsSync(), isTrue);
      expect(paths.appearanceFile.existsSync(), isFalse);
      expect(paths.ideSessionFile.existsSync(), isFalse);
      expect(paths.migrationMarkerFile.existsSync(), isFalse);

      preferences.throwOnKey = null;
      final retry = await migrator.migrate();

      expect(retry.existingTargetKeys, contains(agentProviderConfigStorageKey));
      expect(paths.appearanceFile.existsSync(), isTrue);
      expect(paths.ideSessionFile.existsSync(), isTrue);
      expect(paths.migrationMarkerFile.existsSync(), isTrue);
    });

    test('replaces an invalid UTF-8 marker and reruns migration', () async {
      await paths.stateDirectory.create(recursive: true);
      await paths.migrationMarkerFile.writeAsBytes(<int>[0xff]);
      final preferences = _FakeLegacyZetaPreferences(<String, String>{
        sessionStorageKey: '{"version":2,"projectPaths":[]}',
      });

      final result = await ZetaStorageMigrator(
        paths: paths,
        preferences: preferences,
      ).migrate();

      expect(result.alreadyCompleted, isFalse);
      expect(paths.ideSessionFile.existsSync(), isTrue);
      final marker =
          jsonDecode(await paths.migrationMarkerFile.readAsString())
              as Map<String, Object?>;
      expect(marker['version'], zetaStorageMigrationVersion);
    });

    test('does not inspect or modify protected Cursor data', () async {
      final sentinels = <File>[];
      for (final directoryName in <String>['.codex', '.grok', '.cursor']) {
        final directory = Directory(_join(homeDirectory.path, directoryName))
          ..createSync();
        final sentinel = File(_join(directory.path, 'session-history.jsonl'))
          ..writeAsStringSync('agent-owned-$directoryName');
        sentinels.add(sentinel);
      }
      final projectCursorFile = File(
        _join(
          _join(_join(homeDirectory.path, 'workspace'), '.cursor'),
          'rules.json',
        ),
      )..createSync(recursive: true);
      projectCursorFile.writeAsStringSync('project-cursor-owned');
      sentinels.add(projectCursorFile);
      await paths.stateDirectory.create(recursive: true);
      await paths.cursorSessionsFile.writeAsString(
        '{"version":1,"sessions":[{"id":"keep-index"}]}',
      );
      sentinels.add(paths.cursorSessionsFile);
      await paths.configDirectory.create(recursive: true);
      await paths.providersFile.writeAsString(
        '{"version":1,"activeProviderId":"cursor",'
        '"providers":[{"id":"cursor","legacyMarker":"keep-config"}]}',
      );
      sentinels.add(paths.providersFile);
      final before = <String, String>{
        for (final sentinel in sentinels)
          sentinel.path: sentinel.readAsStringSync(),
      };
      final preferences = _FakeLegacyZetaPreferences(<String, String>{
        _legacyCursorSessionIndexStorageKey:
            '{"version":1,"sessions":[{"id":"overwrite-attempt"}]}',
        agentProviderConfigStorageKey:
            '{"version":1,"activeProviderId":"codex","providers":[]}',
      });

      await ZetaStorageMigrator(
        paths: paths,
        preferences: preferences,
      ).migrate();

      for (final sentinel in sentinels) {
        expect(sentinel.existsSync(), isTrue);
        expect(sentinel.readAsStringSync(), before[sentinel.path]);
      }
      expect(
        preferences.readKeys,
        isNot(contains(_legacyCursorSessionIndexStorageKey)),
      );
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

String _join(String parent, String child) =>
    '$parent${Platform.pathSeparator}$child';

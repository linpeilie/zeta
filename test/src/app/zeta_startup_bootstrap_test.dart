import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/app/zeta_startup_bootstrap.dart';
import 'package:zeta/src/app/zeta_storage_migrator.dart';
import 'package:zeta/src/core/storage/zeta_data_paths.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/settings/domain/app_language.dart';

void main() {
  group('ZetaStartupBootstrap', () {
    late Directory homeDirectory;
    late ZetaDataPaths paths;

    setUp(() {
      homeDirectory = Directory.systemTemp.createTempSync('zeta_bootstrap_');
      paths = ZetaDataPaths.fromHomeDirectory(homeDirectory.path);
    });

    tearDown(() {
      if (homeDirectory.existsSync()) {
        homeDirectory.deleteSync(recursive: true);
      }
    });

    test('fresh install seeds the first system language', () async {
      final result = await ZetaStartupBootstrap(
        paths: paths,
        firstSystemLanguage: AppLanguage.english,
        preferences: _EmptyPreferences(),
      ).run();

      expect(result.filePersistenceEnabled, isTrue);
      expect(result.cohort, ZetaStorageCohort.fresh);
      expect(result.fallbackLanguage, AppLanguage.english);
      final general =
          jsonDecode(await paths.generalSettingsFile.readAsString())
              as Map<String, Object?>;
      expect(general['appLanguage'], 'en');
      expect(
        jsonDecode(await paths.migrationMarkerFile.readAsString())['version'],
        zetaStorageMigrationVersion,
      );
    });

    test('v1 marker is existing and seeds Chinese', () async {
      await paths.stateDirectory.create(recursive: true);
      await paths.migrationMarkerFile.writeAsString(
        jsonEncode(<String, Object?>{'version': 1}),
      );

      final result = await ZetaStartupBootstrap(
        paths: paths,
        firstSystemLanguage: AppLanguage.english,
        preferences: _EmptyPreferences(),
      ).run();

      expect(result.cohort, ZetaStorageCohort.existing);
      expect(result.fallbackLanguage, AppLanguage.simplifiedChinese);
      final general =
          jsonDecode(await paths.generalSettingsFile.readAsString())
              as Map<String, Object?>;
      expect(general['appLanguage'], 'zh-Hans');
    });

    test('legacy preference without files is existing Chinese', () async {
      final result = await ZetaStartupBootstrap(
        paths: paths,
        firstSystemLanguage: AppLanguage.english,
        preferences: _MapPreferences(<String, String>{
          agentProviderConfigStorageKey: '{"version":1,"providers":[]}',
        }),
      ).run();

      expect(result.cohort, ZetaStorageCohort.existing);
      expect(result.fallbackLanguage, AppLanguage.simplifiedChinese);
    });

    test('keeps valid v3 language and upgrades marker', () async {
      await paths.configDirectory.create(recursive: true);
      await paths.generalSettingsFile.writeAsString(
        jsonEncode(<String, Object?>{
          'version': 3,
          'sendMessageShortcut': 'enter',
          'notifications': <String, Object?>{
            'enabled': true,
            'turnTerminalEnabled': true,
            'actionRequiredEnabled': true,
          },
          'appLanguage': 'en',
        }),
      );

      final result = await ZetaStartupBootstrap(
        paths: paths,
        firstSystemLanguage: AppLanguage.simplifiedChinese,
        preferences: _EmptyPreferences(),
      ).run();

      expect(result.cohort, ZetaStorageCohort.existing);
      final general =
          jsonDecode(await paths.generalSettingsFile.readAsString())
              as Map<String, Object?>;
      expect(general['appLanguage'], 'en');
      expect(result.filePersistenceEnabled, isTrue);
    });

    test('write failure disables file persistence and skips marker', () async {
      await paths.configDirectory.create(recursive: true);
      Directory(paths.generalSettingsFile.path).createSync();

      final result = await ZetaStartupBootstrap(
        paths: paths,
        firstSystemLanguage: AppLanguage.english,
        preferences: _EmptyPreferences(),
      ).run();

      expect(result.filePersistenceEnabled, isFalse);
      expect(paths.migrationMarkerFile.existsSync(), isFalse);
      expect(result.fallbackLanguage, AppLanguage.english);
    });

    test('rerunning after v2 marker is idempotent', () async {
      final bootstrap = ZetaStartupBootstrap(
        paths: paths,
        firstSystemLanguage: AppLanguage.english,
        preferences: _EmptyPreferences(),
      );
      final first = await bootstrap.run();
      final firstGeneral = await paths.generalSettingsFile.readAsString();
      final second = await bootstrap.run();

      expect(first.filePersistenceEnabled, isTrue);
      expect(second.filePersistenceEnabled, isTrue);
      expect(await paths.generalSettingsFile.readAsString(), firstGeneral);
    });
  });
}

class _EmptyPreferences implements LegacyZetaPreferences {
  @override
  Future<String?> getString(String key) async => null;
}

class _MapPreferences implements LegacyZetaPreferences {
  _MapPreferences(this.values);

  final Map<String, String> values;

  @override
  Future<String?> getString(String key) async => values[key];
}

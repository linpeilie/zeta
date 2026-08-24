import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
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
      SharedPreferences.setMockInitialValues(<String, Object>{});
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      homeDirectory = Directory.systemTemp.createTempSync('zeta_bootstrap_');
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

    test('fresh install seeds the first system language', () async {
      final result = await ZetaStartupBootstrap(
        paths: paths,
        firstSystemLanguage: AppLanguage.english,
      ).run();

      expect(result.filePersistenceEnabled, isTrue);
      expect(result.fallbackLanguage, AppLanguage.english);
      final general =
          jsonDecode(await File(paths.generalSettingsFilePath).readAsString())
              as Map<String, Object?>;
      expect(general['appLanguage'], 'en');
      expect(
        jsonDecode(
          await File(paths.migrationMarkerFilePath).readAsString(),
        )['version'],
        zetaStorageMigrationVersion,
      );
    });

    test(
      'marker file is existing and seeds Chinese without version parsing',
      () async {
        await Directory(paths.stateDirectoryPath).create(recursive: true);
        await File(
          paths.migrationMarkerFilePath,
        ).writeAsString(jsonEncode(<String, Object?>{'version': 0}));

        final result = await ZetaStartupBootstrap(
          paths: paths,
          firstSystemLanguage: AppLanguage.english,
        ).run();

        expect(result.fallbackLanguage, AppLanguage.simplifiedChinese);
        final general =
            jsonDecode(await File(paths.generalSettingsFilePath).readAsString())
                as Map<String, Object?>;
        expect(general['appLanguage'], 'zh-Hans');
      },
    );

    test('legacy preference without files is existing Chinese', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        agentProviderConfigStorageKey: '{"version":1,"providers":[]}',
      });

      final isExisting = await hasExistingZetaStorage(paths: paths);

      expect(isExisting, isTrue);
    });

    test('keeps valid v3 language and upgrades marker', () async {
      await Directory(paths.configDirectoryPath).create(recursive: true);
      await File(paths.generalSettingsFilePath).writeAsString(
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
      ).run();

      final general =
          jsonDecode(await File(paths.generalSettingsFilePath).readAsString())
              as Map<String, Object?>;
      expect(general['appLanguage'], 'en');
      expect(result.filePersistenceEnabled, isTrue);
    });

    test('write failure disables file persistence and skips marker', () async {
      await Directory(paths.configDirectoryPath).create(recursive: true);
      Directory(paths.generalSettingsFilePath).createSync();

      final result = await ZetaStartupBootstrap(
        paths: paths,
        firstSystemLanguage: AppLanguage.english,
      ).run();

      expect(result.filePersistenceEnabled, isFalse);
      expect(File(paths.migrationMarkerFilePath).existsSync(), isFalse);
      expect(result.fallbackLanguage, AppLanguage.english);
    });

    test('rerunning after v2 marker is idempotent', () async {
      final bootstrap = ZetaStartupBootstrap(
        paths: paths,
        firstSystemLanguage: AppLanguage.english,
      );
      final first = await bootstrap.run();
      final firstGeneral = await File(
        paths.generalSettingsFilePath,
      ).readAsString();
      final second = await bootstrap.run();

      expect(first.filePersistenceEnabled, isTrue);
      expect(second.filePersistenceEnabled, isTrue);
      expect(
        await File(paths.generalSettingsFilePath).readAsString(),
        firstGeneral,
      );
    });
  });
}

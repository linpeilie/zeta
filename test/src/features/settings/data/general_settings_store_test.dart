import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/settings/data/general_settings_store.dart';
import 'package:zeta/src/features/settings/domain/app_language.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';

void main() {
  group('FileGeneralSettingsStore', () {
    late Directory tempDirectory;
    late File settingsFile;

    setUp(() {
      tempDirectory = Directory.systemTemp.createTempSync(
        'zeta_general_store_',
      );
      settingsFile = File(
        '${tempDirectory.path}${Platform.pathSeparator}general.json',
      );
    });

    tearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('loads fallback language when storage is empty', () async {
      final store = FileGeneralSettingsStore(
        file: settingsFile,
        fallbackLanguage: AppLanguage.english,
      );

      expect(
        await store.load(),
        const GeneralSettings(appLanguage: AppLanguage.english),
      );
    });

    test('round trips v3 including language', () async {
      final store = FileGeneralSettingsStore(
        file: settingsFile,
        fallbackLanguage: AppLanguage.simplifiedChinese,
      );
      const settings = GeneralSettings(
        sendMessageShortcut: MessageSendShortcut.primaryModifierEnter,
        appLanguage: AppLanguage.english,
      );

      await store.save(settings);

      final saved =
          jsonDecode(await settingsFile.readAsString()) as Map<String, Object?>;
      expect(saved, <String, Object?>{
        'version': 3,
        'sendMessageShortcut': 'primaryModifierEnter',
        'notifications': <String, Object?>{
          'enabled': true,
          'turnTerminalEnabled': true,
          'actionRequiredEnabled': true,
        },
        'appLanguage': 'en',
      });
      expect(await store.load(), settings);
    });

    test('reads v2 as Chinese and keeps other fields', () async {
      await settingsFile.writeAsString(
        jsonEncode(<String, Object?>{
          'version': 2,
          'sendMessageShortcut': 'primaryModifierEnter',
          'notifications': <String, Object?>{
            'enabled': true,
            'turnTerminalEnabled': false,
            'actionRequiredEnabled': true,
          },
        }),
      );
      final store = FileGeneralSettingsStore(
        file: settingsFile,
        fallbackLanguage: AppLanguage.english,
      );

      expect(
        await store.load(),
        const GeneralSettings(
          sendMessageShortcut: MessageSendShortcut.primaryModifierEnter,
          notifications: AgentNotificationSettings(turnTerminalEnabled: false),
          appLanguage: AppLanguage.simplifiedChinese,
        ),
      );
    });

    test('falls back to explicit language for damaged json', () async {
      await settingsFile.writeAsString('{not-json');
      final store = FileGeneralSettingsStore(
        file: settingsFile,
        fallbackLanguage: AppLanguage.english,
      );

      expect(
        await store.load(),
        const GeneralSettings(appLanguage: AppLanguage.english),
      );
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/settings/data/general_settings_store.dart';
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

    test('loads defaults when storage is empty', () async {
      final store = FileGeneralSettingsStore(file: settingsFile);

      expect(await store.load(), const GeneralSettings());
    });

    test('round trips the primary modifier shortcut', () async {
      final store = FileGeneralSettingsStore(file: settingsFile);
      const settings = GeneralSettings(
        sendMessageShortcut: MessageSendShortcut.primaryModifierEnter,
      );

      await store.save(settings);

      final saved =
          jsonDecode(await settingsFile.readAsString()) as Map<String, Object?>;
      expect(saved, <String, Object?>{
        'version': 2,
        'sendMessageShortcut': 'primaryModifierEnter',
        'notifications': <String, Object?>{
          'enabled': true,
          'turnTerminalEnabled': true,
          'actionRequiredEnabled': true,
        },
      });
      expect(await store.load(), settings);
    });

    test('falls back to defaults for damaged json', () async {
      await settingsFile.writeAsString('{not-json');
      final store = FileGeneralSettingsStore(file: settingsFile);

      expect(await store.load(), const GeneralSettings());
    });
  });
}

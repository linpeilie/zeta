import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/settings/data/appearance_settings_store.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';

void main() {
  group('FileAppearanceSettingsStore', () {
    late Directory tempDirectory;
    late File settingsFile;

    setUp(() {
      tempDirectory = Directory.systemTemp.createTempSync(
        'zeta_appearance_store_',
      );
      settingsFile = File(
        '${tempDirectory.path}${Platform.pathSeparator}appearance.json',
      );
    });

    tearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('loads default appearance settings when storage is empty', () async {
      final store = FileAppearanceSettingsStore(file: settingsFile);

      expect(await store.load(), const AppearanceSettings());
    });

    test('saves versioned appearance settings json', () async {
      final store = FileAppearanceSettingsStore(file: settingsFile);

      await store.save(
        const AppearanceSettings(
          themeMode: ThemeMode.dark,
          uiFontChoice: AppearanceFontChoice.system('Maple UI'),
          codeFontChoice: AppearanceFontChoice.system('Cascadia Mono'),
          uiFontSize: 14,
          codeFontSize: 16,
        ),
      );

      final saved =
          jsonDecode(await settingsFile.readAsString()) as Map<String, Object?>;
      expect(saved['version'], 1);
      expect(saved['themeMode'], 'dark');
      expect(saved['uiFontChoice'], <String, Object?>{
        'kind': 'system',
        'fontFamily': 'Maple UI',
      });
      expect(saved['codeFontChoice'], <String, Object?>{
        'kind': 'system',
        'fontFamily': 'Cascadia Mono',
      });
      expect(saved['uiFontSize'], 14.0);
      expect(saved['codeFontSize'], 16.0);
      expect(
        await store.load(),
        const AppearanceSettings(
          themeMode: ThemeMode.dark,
          uiFontChoice: AppearanceFontChoice.system('Maple UI'),
          codeFontChoice: AppearanceFontChoice.system('Cascadia Mono'),
          uiFontSize: 14,
          codeFontSize: 16,
        ),
      );
    });

    test('uses default font sizes for older or damaged values', () async {
      await settingsFile.writeAsString(
        jsonEncode(<String, Object?>{
          'version': 1,
          'themeMode': 'dark',
          'uiFontSize': 99,
          'codeFontSize': 'large',
        }),
      );
      final store = FileAppearanceSettingsStore(file: settingsFile);

      expect(
        await store.load(),
        const AppearanceSettings(themeMode: ThemeMode.dark),
      );
    });

    test('falls back to defaults on invalid json', () async {
      await settingsFile.writeAsString('{not-json');
      final store = FileAppearanceSettingsStore(file: settingsFile);

      expect(await store.load(), const AppearanceSettings());
    });

    test('falls back to defaults on invalid UTF-8', () async {
      await settingsFile.writeAsBytes(<int>[0xff]);
      final store = FileAppearanceSettingsStore(file: settingsFile);

      expect(await store.load(), const AppearanceSettings());
    });

    test('propagates file system errors while saving', () async {
      final blockedParent = File(
        '${tempDirectory.path}${Platform.pathSeparator}blocked',
      );
      await blockedParent.writeAsString('not a directory');
      final store = FileAppearanceSettingsStore(
        file: File(
          '${blockedParent.path}${Platform.pathSeparator}appearance.json',
        ),
      );

      await expectLater(
        store.save(const AppearanceSettings()),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  test('callback store falls back to the legacy theme mode', () async {
    final store = CallbackAppearanceSettingsStore(
      loadJson: () async => null,
      saveJson: (_) async {},
      loadLegacyThemeMode: () async => 'dark',
    );

    expect(
      await store.load(),
      const AppearanceSettings(themeMode: ThemeMode.dark),
    );
  });
}

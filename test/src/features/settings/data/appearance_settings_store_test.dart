import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/settings/data/appearance_settings_store.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';

void main() {
  test('loads default appearance settings when storage is empty', () async {
    final store = SharedPreferencesAppearanceSettingsStore(
      readString: (_) async => null,
      writeString: (_, _) async {},
    );

    expect(await store.load(), const AppearanceSettings());
  });

  test('saves versioned appearance settings json', () async {
    final writes = <String, String>{};
    final store = SharedPreferencesAppearanceSettingsStore(
      readString: (_) async => null,
      writeString: (key, value) async {
        writes[key] = value;
      },
    );

    await store.save(
      const AppearanceSettings(
        themeMode: ThemeMode.dark,
        uiFontChoice: AppearanceFontChoice.system('Maple UI'),
        codeFontChoice: AppearanceFontChoice.system('Cascadia Mono'),
      ),
    );

    final saved =
        jsonDecode(writes[appearanceSettingsStorageKey]!)
            as Map<String, Object?>;
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
  });

  test('falls back to defaults on invalid json', () async {
    final store = SharedPreferencesAppearanceSettingsStore(
      readString: (_) async => '{not-json',
      writeString: (_, _) async {},
    );

    expect(await store.load(), const AppearanceSettings());
  });

  test('migrates legacy theme mode when new settings key is missing', () async {
    final values = <String, String>{legacyThemeModeStorageKey: 'dark'};
    final store = SharedPreferencesAppearanceSettingsStore(
      readString: (key) async => values[key],
      writeString: (_, _) async {},
    );

    expect(
      await store.load(),
      const AppearanceSettings(themeMode: ThemeMode.dark),
    );
  });
}

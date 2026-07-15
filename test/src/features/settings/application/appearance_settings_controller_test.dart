import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/settings/application/appearance_settings_controller.dart';
import 'package:zeta/src/features/settings/data/appearance_settings_store.dart';
import 'package:zeta/src/features/settings/data/system_font_catalog_service.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';

void main() {
  test('loads persisted appearance settings', () async {
    final controller = AppearanceSettingsController(
      store: MemoryAppearanceSettingsStore(
        const AppearanceSettings(
          themeMode: ThemeMode.dark,
          uiFontChoice: AppearanceFontChoice.system('Maple UI'),
          codeFontChoice: AppearanceFontChoice.system('Cascadia Mono'),
          uiFontSize: 14,
          codeFontSize: 16,
        ),
      ),
      fontCatalog: const _FakeSystemFontCatalogService(
        loadableFonts: <String>{'Maple UI', 'Cascadia Mono'},
      ),
    );
    addTearDown(controller.dispose);

    expect(
      await controller.load(),
      const AppearanceSettings(
        themeMode: ThemeMode.dark,
        uiFontChoice: AppearanceFontChoice.system('Maple UI'),
        codeFontChoice: AppearanceFontChoice.system('Cascadia Mono'),
        uiFontSize: 14,
        codeFontSize: 16,
      ),
    );
  });

  test('setThemeMode updates settings and notifies listeners', () async {
    final controller = AppearanceSettingsController(
      store: MemoryAppearanceSettingsStore(),
      fontCatalog: const _FakeSystemFontCatalogService(),
    );
    addTearDown(controller.dispose);

    var notifications = 0;
    controller.addListener(() {
      notifications += 1;
    });

    await controller.load();
    final updated = await controller.setThemeMode(ThemeMode.dark);

    expect(updated, isTrue);
    expect(controller.settings.themeMode, ThemeMode.dark);
    expect(notifications, greaterThanOrEqualTo(2));
  });

  test(
    'setUiFontChoice loads system font and persists the selection',
    () async {
      final store = MemoryAppearanceSettingsStore();
      final controller = AppearanceSettingsController(
        store: store,
        fontCatalog: const _FakeSystemFontCatalogService(
          loadableFonts: <String>{'Maple UI'},
        ),
      );
      addTearDown(controller.dispose);

      await controller.load();
      final updated = await controller.setUiFontChoice(
        const AppearanceFontChoice.system('Maple UI'),
      );

      expect(updated, isTrue);
      expect(
        controller.settings.uiFontChoice,
        const AppearanceFontChoice.system('Maple UI'),
      );
      expect(
        await store.load(),
        const AppearanceSettings(
          uiFontChoice: AppearanceFontChoice.system('Maple UI'),
        ),
      );
    },
  );

  test(
    'setCodeFontChoice keeps previous value when font loading fails',
    () async {
      final controller = AppearanceSettingsController(
        store: MemoryAppearanceSettingsStore(),
        fontCatalog: const _FakeSystemFontCatalogService(),
      );
      addTearDown(controller.dispose);

      await controller.load();
      final updated = await controller.setCodeFontChoice(
        const AppearanceFontChoice.system('Missing Mono'),
      );

      expect(updated, isFalse);
      expect(
        controller.settings.codeFontChoice,
        const AppearanceFontChoice.bundledJetBrainsMono(),
      );
    },
  );

  test('font size setters normalize and persist values', () async {
    final store = MemoryAppearanceSettingsStore();
    final controller = AppearanceSettingsController(
      store: store,
      fontCatalog: const _FakeSystemFontCatalogService(),
    );
    addTearDown(controller.dispose);

    expect(await controller.setUiFontSize(14.4), isTrue);
    expect(await controller.setCodeFontSize(99), isTrue);
    expect(await controller.setUiFontSize(double.nan), isFalse);

    expect(
      await store.load(),
      const AppearanceSettings(uiFontSize: 14, codeFontSize: maxCodeFontSize),
    );
  });

  test(
    'load normalizes persisted fonts that can no longer be loaded',
    () async {
      final store = MemoryAppearanceSettingsStore(
        const AppearanceSettings(
          uiFontChoice: AppearanceFontChoice.system('Missing UI'),
          codeFontChoice: AppearanceFontChoice.system('Missing Mono'),
        ),
      );
      final controller = AppearanceSettingsController(
        store: store,
        fontCatalog: const _FakeSystemFontCatalogService(),
      );
      addTearDown(controller.dispose);

      expect(await controller.load(), const AppearanceSettings());
      expect(await store.load(), const AppearanceSettings());
    },
  );
}

class _FakeSystemFontCatalogService implements SystemFontCatalogService {
  const _FakeSystemFontCatalogService({this.loadableFonts = const <String>{}});

  final Set<String> loadableFonts;

  @override
  Future<List<String>> codeFontFamilies() async => const <String>[];

  @override
  Future<bool> ensureFontLoaded(String fontFamily) async {
    return loadableFonts.contains(fontFamily);
  }

  @override
  Future<List<String>> uiFontFamilies() async => const <String>[];
}

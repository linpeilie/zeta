import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/settings/application/appearance_settings_controller.dart';
import 'package:zeta/src/features/settings/data/appearance_settings_store.dart';
import 'package:zeta/src/features/settings/data/system_font_catalog_service.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';
import 'package:zeta/src/features/settings/domain/system_font_family.dart';

const _mapleUi = SystemFontFamily(
  id: 'test:maple-ui',
  familyName: 'Maple UI',
  displayName: 'Maple UI',
  aliases: <String>['Maple UI'],
  isMonospace: false,
);
const _cascadiaMono = SystemFontFamily(
  id: 'test:cascadia-mono',
  familyName: 'Cascadia Mono',
  displayName: 'Cascadia Mono',
  aliases: <String>['Cascadia Mono'],
  isMonospace: true,
);
const _fangSong = SystemFontFamily(
  id: 'test:fangsong',
  familyName: 'FangSong',
  displayName: '仿宋',
  aliases: <String>['FangSong', '仿宋', 'simfang'],
  isMonospace: false,
);

void main() {
  test('uses initial settings before load completes', () {
    final controller = AppearanceSettingsController(
      store: MemoryAppearanceSettingsStore(
        const AppearanceSettings(themeMode: ThemeMode.dark),
      ),
      fontCatalog: const _FakeSystemFontCatalogService(),
      initialSettings: const AppearanceSettings(themeMode: ThemeMode.light),
    );
    addTearDown(controller.dispose);

    expect(controller.settings.themeMode, ThemeMode.light);
    expect(controller.listenable.value.themeMode, ThemeMode.light);
  });

  test('does not notify when load matches the preloaded settings', () async {
    const settings = AppearanceSettings(themeMode: ThemeMode.light);
    final controller = AppearanceSettingsController(
      store: MemoryAppearanceSettingsStore(settings),
      fontCatalog: const _FakeSystemFontCatalogService(),
      initialSettings: settings,
    );
    addTearDown(controller.dispose);

    var notifications = 0;
    controller.addListener(() {
      notifications += 1;
    });

    expect(await controller.load(), settings);
    expect(notifications, 0);
  });

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
        families: <SystemFontFamily>[_mapleUi, _cascadiaMono],
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
    expect(notifications, 1);
  });

  test(
    'setUiFontChoice resolves system font and persists the selection',
    () async {
      final store = MemoryAppearanceSettingsStore();
      final controller = AppearanceSettingsController(
        store: store,
        fontCatalog: const _FakeSystemFontCatalogService(
          families: <SystemFontFamily>[_mapleUi],
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
    'setCodeFontChoice keeps previous value when font resolution fails',
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

  test(
    'load migrates legacy file name and keeps localized display name',
    () async {
      final store = MemoryAppearanceSettingsStore(
        const AppearanceSettings(
          uiFontChoice: AppearanceFontChoice.system('simfang'),
        ),
      );
      final controller = AppearanceSettingsController(
        store: store,
        fontCatalog: const _FakeSystemFontCatalogService(
          families: <SystemFontFamily>[_fangSong],
        ),
      );
      addTearDown(controller.dispose);

      final settings = await controller.load();

      expect(
        settings.uiFontChoice,
        const AppearanceFontChoice.system('FangSong'),
      );
      expect(controller.displayNameFor(settings.uiFontChoice), '仿宋');
      expect(
        (await store.load()).uiFontChoice,
        const AppearanceFontChoice.system('FangSong'),
      );
    },
  );

  test(
    'load preserves stored font when native catalog is unavailable',
    () async {
      const stored = AppearanceSettings(
        uiFontChoice: AppearanceFontChoice.system('Maple UI'),
      );
      final store = MemoryAppearanceSettingsStore(stored);
      final controller = AppearanceSettingsController(
        store: store,
        fontCatalog: const _FakeSystemFontCatalogService(throwOnResolve: true),
      );
      addTearDown(controller.dispose);

      expect(await controller.load(), stored);
      expect(await store.load(), stored);
    },
  );
}

class _FakeSystemFontCatalogService implements SystemFontCatalogService {
  const _FakeSystemFontCatalogService({
    this.families = const <SystemFontFamily>[],
    this.throwOnResolve = false,
  });

  final List<SystemFontFamily> families;
  final bool throwOnResolve;

  @override
  Future<List<SystemFontFamily>> codeFontFamilies() async =>
      families.where((family) => family.isMonospace).toList(growable: false);

  @override
  Future<SystemFontFamily?> resolveFontFamily(String name) async {
    if (throwOnResolve) {
      throw StateError('Native font catalog unavailable');
    }
    final normalized = name.toLowerCase();
    for (final family in families) {
      if (family.aliases.any((alias) => alias.toLowerCase() == normalized)) {
        return family;
      }
    }
    return null;
  }

  @override
  Future<List<SystemFontFamily>> uiFontFamilies() async => families;
}

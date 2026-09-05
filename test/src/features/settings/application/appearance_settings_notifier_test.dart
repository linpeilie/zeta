import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/app/settings_slice/settings_slice_overrides.dart';
import 'package:zeta/src/features/settings/application/appearance_settings_notifier.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings_repository.dart';
import 'package:zeta/src/features/settings/domain/system_font_catalog_service.dart';
import 'package:zeta/src/features/settings/domain/system_font_family.dart';

import '../../../testing/memory_feature_stores.dart';

const _systemFont = SystemFontFamily(
  id: 'maple-ui',
  familyName: 'Maple UI',
  displayName: 'Maple UI',
  aliases: <String>[],
  isMonospace: false,
);

const _monoFont = SystemFontFamily(
  id: 'cascadia',
  familyName: 'Cascadia Mono',
  displayName: 'Cascadia Mono',
  aliases: <String>[],
  isMonospace: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppearanceSettingsNotifier · 主题', () {
    test('setThemeMode 乐观更新并持久化', () async {
      final dataStore = MemoryAppearanceSettingsStore();
      final container = _container(repository: dataStore);
      addTearDown(container.dispose);
      final notifier = container.read(appearanceSettingsProvider.notifier);

      await notifier.setThemeMode(ZetaThemeModePreference.dark);

      expect(
        container.read(appearanceSettingsValueProvider).themeMode,
        ZetaThemeModePreference.dark,
      );
      expect((await dataStore.load()).themeMode, ZetaThemeModePreference.dark);
    });

    test('persist 失败不回滚已应用主题', () async {
      final container = _container(repository: _FailingAppearanceStore());
      addTearDown(container.dispose);
      final notifier = container.read(appearanceSettingsProvider.notifier);

      await notifier.setThemeMode(ZetaThemeModePreference.dark);

      expect(
        container.read(appearanceSettingsValueProvider).themeMode,
        ZetaThemeModePreference.dark,
      );
    });

    test('相等选择早退', () async {
      final dataStore = MemoryAppearanceSettingsStore();
      final container = _container(repository: dataStore);
      addTearDown(container.dispose);
      final notifier = container.read(appearanceSettingsProvider.notifier);

      await notifier.setThemeMode(ZetaThemeModePreference.system);

      expect(await dataStore.load(), const AppearanceSettings());
    });
  });

  group('AppearanceSettingsNotifier · 字号', () {
    test('四舍五入并夹取后持久化，非有限值拒绝', () async {
      final dataStore = MemoryAppearanceSettingsStore();
      final container = _container(repository: dataStore);
      addTearDown(container.dispose);
      final notifier = container.read(appearanceSettingsProvider.notifier);

      await notifier.setUiFontSize(14.4);
      await notifier.setCodeFontSize(99);
      await notifier.setUiFontSize(double.nan);

      expect(
        await dataStore.load(),
        const AppearanceSettings(uiFontSize: 14, codeFontSize: maxCodeFontSize),
      );
    });
  });

  group('AppearanceSettingsNotifier · 载入归一化', () {
    test('存储的系统字体不可解析时回落默认并回写', () async {
      final dataStore = MemoryAppearanceSettingsStore(
        const AppearanceSettings(
          uiFontChoice: AppearanceFontChoice.system('Missing Font'),
        ),
      );
      final container = _container(
        repository: dataStore,
        fontCatalog: _FakeFontCatalog(families: const [_systemFont]),
      );
      addTearDown(container.dispose);
      container.read(appearanceSettingsProvider);
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(appearanceSettingsValueProvider).uiFontChoice.kind,
        AppearanceFontChoiceKind.systemDefault,
      );
      expect(
        (await dataStore.load()).uiFontChoice.kind,
        AppearanceFontChoiceKind.systemDefault,
      );
    });

    test('代码字体要求等宽：非等宽系统字体回落 bundled', () async {
      final dataStore = MemoryAppearanceSettingsStore(
        const AppearanceSettings(
          codeFontChoice: AppearanceFontChoice.system('Maple UI'),
        ),
      );
      final container = _container(
        repository: dataStore,
        fontCatalog: _FakeFontCatalog(families: const [_systemFont]),
      );
      addTearDown(container.dispose);
      container.read(appearanceSettingsProvider);
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(appearanceSettingsValueProvider).codeFontChoice.kind,
        AppearanceFontChoiceKind.bundledJetBrainsMono,
      );
    });

    test('原生字体目录暂时不可用时保留已存选择', () async {
      const persisted = AppearanceSettings(
        uiFontChoice: AppearanceFontChoice.system('Maple UI'),
      );
      final dataStore = MemoryAppearanceSettingsStore(persisted);
      final container = _container(
        repository: dataStore,
        fontCatalog: _FakeFontCatalog(throwOnResolve: true),
      );
      addTearDown(container.dispose);
      container.read(appearanceSettingsProvider);
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(appearanceSettingsValueProvider).uiFontChoice,
        persisted.uiFontChoice,
      );
      expect(await dataStore.load(), persisted);
    });
  });

  group('AppearanceSettingsNotifier · 字体解析', () {
    test('界面槽位拒绝 bundled；代码槽位拒绝 systemDefault', () async {
      final container = _container();
      addTearDown(container.dispose);
      final notifier = container.read(appearanceSettingsProvider.notifier);

      expect(
        await notifier.setUiFontChoice(
          const AppearanceFontChoice.bundledJetBrainsMono(),
        ),
        isFalse,
      );
      expect(
        container.read(appearanceSettingsValueProvider).uiFontChoice.kind,
        AppearanceFontChoiceKind.systemDefault,
      );

      expect(
        await notifier.setCodeFontChoice(
          const AppearanceFontChoice.systemDefault(),
        ),
        isFalse,
      );
      expect(
        container.read(appearanceSettingsValueProvider).codeFontChoice.kind,
        AppearanceFontChoiceKind.bundledJetBrainsMono,
      );
    });

    test('系统字体经目录解析成功后应用并持久化', () async {
      final dataStore = MemoryAppearanceSettingsStore();
      final container = _container(
        repository: dataStore,
        fontCatalog: _FakeFontCatalog(families: const [_systemFont, _monoFont]),
      );
      addTearDown(container.dispose);
      final notifier = container.read(appearanceSettingsProvider.notifier);

      expect(
        await notifier.setUiFontChoice(
          const AppearanceFontChoice.system('Maple UI'),
        ),
        isTrue,
      );
      expect(
        container.read(appearanceSettingsValueProvider).uiFontChoice,
        const AppearanceFontChoice.system('Maple UI'),
      );
      expect(
        (await dataStore.load()).uiFontChoice,
        const AppearanceFontChoice.system('Maple UI'),
      );
    });

    test('字体目录：界面槽位默认项在前，展示名进映射', () async {
      final container = _container(
        fontCatalog: _FakeFontCatalog(families: const [_systemFont]),
      );
      addTearDown(container.dispose);
      final notifier = container.read(appearanceSettingsProvider.notifier);

      final options = await notifier.ensureFontCatalog(forCodeFont: false);

      expect(options.length, 2);
      expect(options.first.choice.kind, AppearanceFontChoiceKind.systemDefault);
      expect(
        container
            .read(appearanceSettingsProvider)
            .catalog
            .displayNames['maple ui'],
        'Maple UI',
      );
    });
  });

  group('AppearanceSettingsNotifier · 加载叠加', () {
    test('写入等待首次 load，并把用户改动叠加到加载快照', () async {
      final dataStore = _DelayedAppearanceStore();
      final container = _container(repository: dataStore);
      addTearDown(container.dispose);
      final notifier = container.read(appearanceSettingsProvider.notifier);

      final theme = notifier.setThemeMode(ZetaThemeModePreference.dark);
      await Future<void>.delayed(Duration.zero);
      expect(dataStore.savedSnapshots, isEmpty);

      dataStore.completeLoad(
        const AppearanceSettings(
          themeMode: ZetaThemeModePreference.light,
          uiFontSize: 18,
        ),
      );
      await theme;
      final saved = await dataStore.firstSave.future;

      expect(
        saved,
        const AppearanceSettings(
          themeMode: ZetaThemeModePreference.dark,
          uiFontSize: 18,
        ),
      );
      expect(
        container.read(appearanceSettingsValueProvider).themeMode,
        ZetaThemeModePreference.dark,
      );
      expect(container.read(appearanceSettingsValueProvider).uiFontSize, 18);
    });
  });
}

ProviderContainer _container({
  AppearanceSettingsRepository? repository,
  SystemFontCatalogService? fontCatalog,
  AppearanceSettings? initial,
}) {
  return ProviderContainer(
    overrides: <Override>[
      ...settingsSliceOverrides(),
      appearanceSettingsRepositoryProvider.overrideWithValue(
        repository ?? MemoryAppearanceSettingsStore(),
      ),
      appearanceFontCatalogProvider.overrideWithValue(
        fontCatalog ?? _FakeFontCatalog(),
      ),
      if (initial != null)
        initialAppearanceSettingsProvider.overrideWithValue(initial),
    ],
  );
}

final class _FakeFontCatalog implements SystemFontCatalogService {
  _FakeFontCatalog({
    this.families = const <SystemFontFamily>[],
    this.throwOnResolve = false,
  });

  final List<SystemFontFamily> families;
  final bool throwOnResolve;

  @override
  Future<List<SystemFontFamily>> uiFontFamilies() async => families;

  @override
  Future<List<SystemFontFamily>> codeFontFamilies() async => families;

  @override
  Future<SystemFontFamily?> resolveFontFamily(String name) async {
    if (throwOnResolve) {
      throw StateError('font catalog unavailable');
    }
    final normalized = name.toLowerCase();
    for (final family in families) {
      if (family.familyName.toLowerCase() == normalized ||
          family.aliases.any((alias) => alias.toLowerCase() == normalized)) {
        return family;
      }
    }
    return null;
  }
}

final class _FailingAppearanceStore implements AppearanceSettingsRepository {
  @override
  Future<AppearanceSettings> load() async => const AppearanceSettings();

  @override
  Future<void> save(AppearanceSettings settings) async {
    throw Exception('persist blocked');
  }
}

final class _DelayedAppearanceStore implements AppearanceSettingsRepository {
  final Completer<AppearanceSettings> _loadCompleter =
      Completer<AppearanceSettings>();
  final Completer<AppearanceSettings> firstSave =
      Completer<AppearanceSettings>();
  final List<AppearanceSettings> savedSnapshots = <AppearanceSettings>[];

  void completeLoad(AppearanceSettings settings) {
    _loadCompleter.complete(settings);
  }

  @override
  Future<AppearanceSettings> load() => _loadCompleter.future;

  @override
  Future<void> save(AppearanceSettings settings) async {
    savedSnapshots.add(settings);
    if (!firstSave.isCompleted) {
      firstSave.complete(settings);
    }
  }
}

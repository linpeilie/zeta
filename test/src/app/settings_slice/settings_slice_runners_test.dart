import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:zeta/src/app/settings_slice/settings_slice_overrides.dart';
import 'package:zeta/src/app/storage/zeta_store_providers.dart';
import 'package:zeta/src/app/settings_slice/settings_slice_runners.dart';
import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_effect.dart';
import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_state.dart';
import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_store.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_effect.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_store.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_state.dart';
import 'package:zeta/src/features/settings/application/settings_slice/settings_slice_operation.dart';
import 'package:zeta/src/features/settings/data/appearance_settings_store.dart';
import 'package:zeta/src/features/settings/data/general_settings_store.dart';
import 'package:zeta/src/features/settings/data/system_font_catalog_service.dart';
import 'package:zeta/src/features/settings/domain/app_language.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';
import 'package:zeta/src/features/settings/domain/system_font_family.dart';
import 'package:zeta/src/features/settings/presentation/settings_slice/settings_slice_providers.dart';
import '../../testing/memory_feature_stores.dart';

/// 可编程字体目录：按 familyName 解析。
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
      if (family.familyName.toLowerCase() == normalized) {
        return family;
      }
    }
    return null;
  }
}

/// save 恒失败的仓库，验证 persist 失败回执。
final class _FailingAppearanceStore implements AppearanceSettingsStore {
  @override
  Future<AppearanceSettings> load() async => const AppearanceSettings();

  @override
  Future<void> save(AppearanceSettings settings) async {
    throw Exception('persist blocked');
  }
}

final class _FailingGeneralStore implements GeneralSettingsStore {
  @override
  Future<GeneralSettings> load() async => const GeneralSettings();

  @override
  Future<void> save(GeneralSettings settings) async {
    throw Exception('persist blocked');
  }
}

final class _RecordingGeneralStore implements GeneralSettingsStore {
  GeneralSettings _settings = const GeneralSettings();
  final List<GeneralSettings> savedSnapshots = <GeneralSettings>[];

  @override
  Future<GeneralSettings> load() async => _settings;

  @override
  Future<void> save(GeneralSettings settings) async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    _settings = settings;
    savedSnapshots.add(settings);
  }
}

final class _DelayedAppearanceStore implements AppearanceSettingsStore {
  final Completer<AppearanceSettings> _loadCompleter =
      Completer<AppearanceSettings>();
  final Completer<AppearanceSettings> firstSave =
      Completer<AppearanceSettings>();
  final List<AppearanceSettings> savedSnapshots = <AppearanceSettings>[];

  @override
  Future<AppearanceSettings> load() => _loadCompleter.future;

  void completeLoad(AppearanceSettings settings) {
    _loadCompleter.complete(settings);
  }

  @override
  Future<void> save(AppearanceSettings settings) async {
    savedSnapshots.add(settings);
    if (!firstSave.isCompleted) {
      firstSave.complete(settings);
    }
  }
}

final class _DelayedGeneralStore implements GeneralSettingsStore {
  final Completer<GeneralSettings> _loadCompleter =
      Completer<GeneralSettings>();
  final Completer<GeneralSettings> firstSave = Completer<GeneralSettings>();
  final List<GeneralSettings> savedSnapshots = <GeneralSettings>[];

  @override
  Future<GeneralSettings> load() => _loadCompleter.future;

  void completeLoad(GeneralSettings settings) {
    _loadCompleter.complete(settings);
  }

  @override
  Future<void> save(GeneralSettings settings) async {
    savedSnapshots.add(settings);
    if (!firstSave.isCompleted) {
      firstSave.complete(settings);
    }
  }
}

const _systemFont = SystemFontFamily(
  id: 'maple-ui',
  familyName: 'Maple UI',
  displayName: 'Maple UI',
  aliases: <String>[],
  isMonospace: false,
);

const _monoFont = SystemFontFamily(
  id: 'cascadia-mono',
  familyName: 'Cascadia Mono',
  displayName: 'Cascadia Mono',
  aliases: <String>[],
  isMonospace: true,
);

const _localizedFont = SystemFontFamily(
  id: 'fangsong',
  familyName: 'FangSong',
  displayName: '仿宋',
  aliases: <String>['simfang'],
  isMonospace: false,
);

/// 与组合层同款的工厂注入装配。
AppearanceSettingsSliceStore _appearanceStoreWith({
  required AppearanceSettingsStore dataStore,
  required SystemFontCatalogService fontCatalog,
}) {
  return AppearanceSettingsSliceStore(
    initialState: const AppearanceSettingsSliceState(),
    effectRunnerFactory: (sliceStore) => AppearanceSettingsSliceRunnerAdapter(
      store: dataStore,
      fontCatalog: fontCatalog,
      sliceStore: sliceStore,
    ),
  );
}

GeneralSettingsSliceStore _generalStoreWith(GeneralSettingsStore dataStore) {
  return GeneralSettingsSliceStore(
    initialState: const GeneralSettingsSliceState(),
    effectRunnerFactory: (sliceStore) => GeneralSettingsSliceRunnerAdapter(
      store: dataStore,
      sliceStore: sliceStore,
    ),
  );
}

GeneralSettingsSliceStore _unloadedGeneralStoreWith(
  GeneralSettingsStore dataStore,
) {
  return GeneralSettingsSliceStore(
    initialState: const GeneralSettingsSliceState(),
    effectRunnerFactory: (sliceStore) => GeneralSettingsSliceRunnerAdapter(
      store: dataStore,
      sliceStore: sliceStore,
    ),
    initiallyLoaded: false,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('settings 切片装配 · 唯一 owner', () {
    test('构造期外观快照同步可见，initialLoad 等持久化加载', () async {
      final container = ProviderContainer(
        overrides: <Override>[
          initialAppearanceSettingsProvider.overrideWithValue(
            const AppearanceSettings(themeMode: ZetaThemeModePreference.light),
          ),
          settingsFallbackLanguageProvider.overrideWithValue(
            AppLanguage.simplifiedChinese,
          ),
          appearanceSettingsStoreProvider.overrideWithValue(
            MemoryAppearanceSettingsStore(
              const AppearanceSettings(themeMode: ZetaThemeModePreference.dark),
            ),
          ),
          generalSettingsStoreProvider.overrideWithValue(
            MemoryGeneralSettingsStore(
              const GeneralSettings(appLanguage: AppLanguage.english),
            ),
          ),
          systemFontCatalogServiceProvider.overrideWithValue(
            _FakeFontCatalog(),
          ),
          ...settingsSliceOverrides(),
        ],
      );
      addTearDown(container.dispose);

      final appearanceStore = container.read(
        appearanceSettingsSliceStoreProvider,
      );
      final generalStore = container.read(generalSettingsSliceStoreProvider);

      expect(
        appearanceStore.state.value.themeMode,
        ZetaThemeModePreference.light,
        reason: '首帧必须使用启动阶段已读快照',
      );

      final general = await generalStore.initialLoad;

      expect(general.appLanguage, AppLanguage.english);
      expect(generalStore.state.settings, general);
      await Future<void>.delayed(Duration.zero);
      expect(
        appearanceStore.state.value.themeMode,
        ZetaThemeModePreference.dark,
      );
    });

    test('容器 dispose 关闭两个切片 store', () {
      final container = ProviderContainer(
        overrides: <Override>[
          appearanceSettingsStoreProvider.overrideWithValue(
            MemoryAppearanceSettingsStore(const AppearanceSettings()),
          ),
          generalSettingsStoreProvider.overrideWithValue(
            MemoryGeneralSettingsStore(const GeneralSettings()),
          ),
          systemFontCatalogServiceProvider.overrideWithValue(
            _FakeFontCatalog(),
          ),
          ...settingsSliceOverrides(),
        ],
      );
      final appearanceStore = container.read(
        appearanceSettingsSliceStoreProvider,
      );
      final generalStore = container.read(generalSettingsSliceStoreProvider);

      container.dispose();

      expect(appearanceStore.isClosed, isTrue);
      expect(generalStore.isClosed, isTrue);
    });
  });

  group('appearance runner · 载入归一化', () {
    test('存储的系统字体不可解析时回落默认并回写', () async {
      final dataStore = MemoryAppearanceSettingsStore(
        const AppearanceSettings(
          uiFontChoice: AppearanceFontChoice.system('Missing Font'),
        ),
      );
      final store = _appearanceStoreWith(
        dataStore: dataStore,
        fontCatalog: _FakeFontCatalog(families: const [_systemFont]),
      );

      store.load();
      await Future<void>.delayed(Duration.zero);

      expect(
        store.state.value.uiFontChoice.kind,
        AppearanceFontChoiceKind.systemDefault,
      );
      final persisted = await dataStore.load();
      expect(
        persisted.uiFontChoice.kind,
        AppearanceFontChoiceKind.systemDefault,
      );
    });

    test('代码字体要求等宽：非等宽系统字体回落 bundled', () async {
      final dataStore = MemoryAppearanceSettingsStore(
        const AppearanceSettings(
          codeFontChoice: AppearanceFontChoice.system('Maple UI'),
        ),
      );
      final store = _appearanceStoreWith(
        dataStore: dataStore,
        fontCatalog: _FakeFontCatalog(families: const [_systemFont]),
      );

      store.load();
      await Future<void>.delayed(Duration.zero);

      expect(
        store.state.value.codeFontChoice.kind,
        AppearanceFontChoiceKind.bundledJetBrainsMono,
      );
    });

    test('无法解析的系统字体回落默认，目录保留本地化展示名', () async {
      final dataStore = MemoryAppearanceSettingsStore(
        const AppearanceSettings(
          uiFontChoice: AppearanceFontChoice.system('simfang'),
        ),
      );
      final store = _appearanceStoreWith(
        dataStore: dataStore,
        fontCatalog: _FakeFontCatalog(families: const [_localizedFont]),
      );

      store.load();
      await Future<void>.delayed(Duration.zero);
      store.requestFontCatalog(forCodeFont: false);
      await Future<void>.delayed(Duration.zero);

      expect(
        store.state.value.uiFontChoice,
        const AppearanceFontChoice.systemDefault(),
      );
      expect(store.state.catalog.displayNames['fangsong'], '仿宋');
      expect(
        (await dataStore.load()).uiFontChoice,
        const AppearanceFontChoice.systemDefault(),
      );
    });

    test('原生字体目录暂时不可用时保留已存选择', () async {
      const persisted = AppearanceSettings(
        uiFontChoice: AppearanceFontChoice.system('Maple UI'),
      );
      final dataStore = MemoryAppearanceSettingsStore(persisted);
      final store = _appearanceStoreWith(
        dataStore: dataStore,
        fontCatalog: _FakeFontCatalog(throwOnResolve: true),
      );

      store.load();
      await Future<void>.delayed(Duration.zero);

      expect(store.state.value.uiFontChoice, persisted.uiFontChoice);
      expect(await dataStore.load(), persisted);
    });
  });

  group('appearance runner · 字体解析规则', () {
    test('界面槽位拒绝 bundled；代码槽位拒绝 systemDefault', () async {
      final store = _appearanceStoreWith(
        dataStore: MemoryAppearanceSettingsStore(),
        fontCatalog: _FakeFontCatalog(),
      );

      final bundled = store.selectUiFontChoice(
        const AppearanceFontChoice.bundledJetBrainsMono(),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        store.state.value.uiFontChoice.kind,
        AppearanceFontChoiceKind.systemDefault,
      );

      final systemDefault = store.selectCodeFontChoice(
        const AppearanceFontChoice.systemDefault(),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        store.state.value.codeFontChoice.kind,
        AppearanceFontChoiceKind.bundledJetBrainsMono,
      );
      expect(store.diagnostics.staleResultCount, 0);
      expect(bundled.scope, SettingsOperationScopes.appearanceFontChoice);
      expect(systemDefault.scope, SettingsOperationScopes.appearanceFontChoice);
    });

    test('字体目录投影：界面槽位默认项在前，展示名进映射', () async {
      final store = _appearanceStoreWith(
        dataStore: MemoryAppearanceSettingsStore(),
        fontCatalog: _FakeFontCatalog(families: const [_systemFont]),
      );

      store.requestFontCatalog(forCodeFont: false);
      await Future<void>.delayed(Duration.zero);

      expect(store.state.catalog.uiOptions?.length, 2);
      expect(
        store.state.catalog.uiOptions?.first.choice.kind,
        AppearanceFontChoiceKind.systemDefault,
      );
      expect(store.state.catalog.displayNames['maple ui'], 'Maple UI');
    });

    test('系统字体经目录解析成功后应用并持久化', () async {
      final dataStore = MemoryAppearanceSettingsStore();
      final store = _appearanceStoreWith(
        dataStore: dataStore,
        fontCatalog: _FakeFontCatalog(families: const [_systemFont, _monoFont]),
      );

      store.selectUiFontChoice(const AppearanceFontChoice.system('Maple UI'));
      await Future<void>.delayed(Duration.zero);

      expect(
        store.state.value.uiFontChoice,
        const AppearanceFontChoice.system('Maple UI'),
      );
      final persisted = await dataStore.load();
      expect(
        persisted.uiFontChoice,
        const AppearanceFontChoice.system('Maple UI'),
      );
    });
  });

  group('appearance runner · persist 回执', () {
    test('写入等待首次 load，并把用户改动叠加到加载快照', () async {
      final dataStore = _DelayedAppearanceStore();
      final store = _appearanceStoreWith(
        dataStore: dataStore,
        fontCatalog: _FakeFontCatalog(),
      );

      store.load();
      store.selectThemeMode(ZetaThemeModePreference.dark);
      await Future<void>.delayed(Duration.zero);
      expect(dataStore.savedSnapshots, isEmpty);

      dataStore.completeLoad(
        const AppearanceSettings(
          themeMode: ZetaThemeModePreference.light,
          uiFontSize: 18,
        ),
      );
      final saved = await dataStore.firstSave.future;
      await Future<void>.delayed(Duration.zero);

      expect(
        saved,
        const AppearanceSettings(
          themeMode: ZetaThemeModePreference.dark,
          uiFontSize: 18,
        ),
      );
      expect(store.state.value.themeMode, ZetaThemeModePreference.dark);
      expect(store.state.value.uiFontSize, 18);
    });

    test('失败回执不改已应用值（语义 A）', () async {
      final store = _appearanceStoreWith(
        dataStore: _FailingAppearanceStore(),
        fontCatalog: _FakeFontCatalog(),
      );

      store.selectThemeMode(ZetaThemeModePreference.dark);
      await Future<void>.delayed(Duration.zero);

      expect(store.state.value.themeMode, ZetaThemeModePreference.dark);
    });

    test('字号四舍五入、夹取后持久化，非有限值拒绝', () async {
      final dataStore = MemoryAppearanceSettingsStore();
      final store = _appearanceStoreWith(
        dataStore: dataStore,
        fontCatalog: _FakeFontCatalog(),
      );

      store.adjustUiFontSize(14.4);
      store.adjustCodeFontSize(99);
      store.adjustUiFontSize(double.nan);
      await Future<void>.delayed(Duration.zero);

      expect(
        await dataStore.load(),
        const AppearanceSettings(uiFontSize: 14, codeFontSize: maxCodeFontSize),
      );
    });
  });

  group('general runner', () {
    test('写入等待首次 load，并从加载完成的快照计算', () async {
      final dataStore = _DelayedGeneralStore();
      final store = _unloadedGeneralStoreWith(dataStore);

      store.load();
      store.setAppLanguage(AppLanguage.english);
      await Future<void>.delayed(Duration.zero);
      expect(dataStore.savedSnapshots, isEmpty);

      dataStore.completeLoad(
        const GeneralSettings(
          sendMessageShortcut: MessageSendShortcut.primaryModifierEnter,
          notifications: AgentNotificationSettings(enabled: false),
        ),
      );
      final saved = await dataStore.firstSave.future;
      await Future<void>.delayed(Duration.zero);

      expect(
        saved,
        const GeneralSettings(
          sendMessageShortcut: MessageSendShortcut.primaryModifierEnter,
          notifications: AgentNotificationSettings(enabled: false),
          appLanguage: AppLanguage.english,
        ),
      );
      expect(store.state.settings, saved);
    });

    test('persist 成功回执应用；失败回执保持旧值并登记分类', () async {
      final store = _generalStoreWith(
        MemoryGeneralSettingsStore(null, AppLanguage.simplifiedChinese),
      );
      final id = store.setAppLanguage(AppLanguage.english);
      await Future<void>.delayed(Duration.zero);
      expect(store.state.settings.appLanguage, AppLanguage.english);

      final failing = _generalStoreWith(_FailingGeneralStore());
      final failId = failing.setMessageSendShortcut(
        MessageSendShortcut.primaryModifierEnter,
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        failing.state.settings.sendMessageShortcut,
        MessageSendShortcut.enter,
      );
      expect(
        failing.state.lastPersistFailure,
        const GeneralSettingsSlicePersistFailure(
          kind: SettingsPersistFailureKind.persistence,
          operation: GeneralSettingsPersistOperation.shortcut,
        ),
      );
      expect(id.scope, SettingsOperationScopes.generalPersist);
      expect(failId.scope, SettingsOperationScopes.generalPersist);
    });

    test('语言、通知与快捷键按提交顺序串行，且不丢在途值链', () async {
      final dataStore = _RecordingGeneralStore();
      final store = _generalStoreWith(dataStore);

      store.setAppLanguage(AppLanguage.english);
      store.setNotificationsEnabled(false);
      store.setMessageSendShortcut(MessageSendShortcut.primaryModifierEnter);
      await Future<void>.delayed(const Duration(milliseconds: 40));

      const expected = GeneralSettings(
        sendMessageShortcut: MessageSendShortcut.primaryModifierEnter,
        notifications: AgentNotificationSettings(enabled: false),
        appLanguage: AppLanguage.english,
      );
      expect(dataStore.savedSnapshots, hasLength(3));
      expect(dataStore.savedSnapshots.last, expected);
      expect(store.state.settings, expected);
    });
  });

  group('唯一 owner 与镜像 provider', () {
    test('Riverpod 只镜像 slice store，两个投影都跟随', () {
      final appearanceSlice = AppearanceSettingsSliceStore(
        initialState: const AppearanceSettingsSliceState(),
        effectRunnerFactory: (_) => _NoopAppearanceRunner(),
      );
      final generalSlice = GeneralSettingsSliceStore(
        initialState: const GeneralSettingsSliceState(),
        effectRunnerFactory: (_) => _NoopGeneralRunner(),
      );

      final container = ProviderContainer(
        overrides: [
          appearanceSettingsSliceStoreProvider.overrideWithValue(
            appearanceSlice,
          ),
          generalSettingsSliceStoreProvider.overrideWithValue(generalSlice),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(appearanceSettingsSliceValueProvider).themeMode,
        ZetaThemeModePreference.system,
      );

      appearanceSlice.selectThemeMode(ZetaThemeModePreference.dark);
      final generalOperation = generalSlice.setMessageSendShortcut(
        MessageSendShortcut.primaryModifierEnter,
      );
      generalSlice.persisted(
        generalOperation,
        generalSlice.state.pendingValue!,
      );

      expect(
        container.read(appearanceSettingsSliceValueProvider).themeMode,
        ZetaThemeModePreference.dark,
      );
      expect(
        container.read(generalSettingsSliceValueProvider).sendMessageShortcut,
        MessageSendShortcut.primaryModifierEnter,
      );
    });
  });
}

final class _NoopAppearanceRunner
    implements AppearanceSettingsSliceEffectRunner {
  @override
  void run(AppearanceSettingsSliceEffect effect) {}
}

final class _NoopGeneralRunner implements GeneralSettingsSliceEffectRunner {
  @override
  void run(GeneralSettingsSliceEffect effect) {}
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:zeta/src/app/settings_slice/settings_slice_overrides.dart';
import 'package:zeta/src/app/storage/zeta_store_providers.dart';
import 'package:zeta/src/app/settings_slice/settings_slice_runners.dart';
import 'package:zeta/src/features/settings/application/appearance_settings_notifier.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_effect.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_store.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_state.dart';
import 'package:zeta/src/features/settings/application/settings_slice/settings_slice_operation.dart';
import 'package:zeta/src/features/settings/data/general_settings_store.dart';
import 'package:zeta/src/features/settings/domain/app_language.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';
import 'package:zeta/src/features/settings/domain/system_font_catalog_service.dart';
import 'package:zeta/src/features/settings/domain/system_font_family.dart';
import 'package:zeta/src/features/settings/presentation/settings_slice/settings_slice_providers.dart';
import '../../testing/memory_feature_stores.dart';

/// 可编程字体目录：按 familyName 解析。
final class _FakeFontCatalog implements SystemFontCatalogService {
  @override
  Future<List<SystemFontFamily>> uiFontFamilies() async =>
      const <SystemFontFamily>[];

  @override
  Future<List<SystemFontFamily>> codeFontFamilies() async =>
      const <SystemFontFamily>[];

  @override
  Future<SystemFontFamily?> resolveFontFamily(String name) async => null;
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
          appearanceSettingsRepositoryProvider.overrideWithValue(
            MemoryAppearanceSettingsStore(
              const AppearanceSettings(themeMode: ZetaThemeModePreference.dark),
            ),
          ),
          generalSettingsStoreProvider.overrideWithValue(
            MemoryGeneralSettingsStore(
              const GeneralSettings(appLanguage: AppLanguage.english),
            ),
          ),
          appearanceFontCatalogProvider.overrideWithValue(_FakeFontCatalog()),
          ...settingsSliceOverrides(),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(appearanceSettingsValueProvider).themeMode,
        ZetaThemeModePreference.light,
        reason: '首帧必须使用启动阶段已读快照',
      );
      final generalStore = container.read(generalSettingsSliceStoreProvider);

      final general = await generalStore.initialLoad;

      expect(general.appLanguage, AppLanguage.english);
      expect(generalStore.state.settings, general);
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(appearanceSettingsValueProvider).themeMode,
        ZetaThemeModePreference.dark,
      );
    });

    test('容器 dispose 关闭两个切片 store', () {
      final container = ProviderContainer(
        overrides: <Override>[
          appearanceSettingsRepositoryProvider.overrideWithValue(
            MemoryAppearanceSettingsStore(const AppearanceSettings()),
          ),
          generalSettingsStoreProvider.overrideWithValue(
            MemoryGeneralSettingsStore(const GeneralSettings()),
          ),
          appearanceFontCatalogProvider.overrideWithValue(_FakeFontCatalog()),
          ...settingsSliceOverrides(),
        ],
      );
      final generalStore = container.read(generalSettingsSliceStoreProvider);

      container.dispose();

      expect(generalStore.isClosed, isTrue);
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
    test('外观 Notifier 与 general 切片投影都跟随', () async {
      final generalSlice = GeneralSettingsSliceStore(
        initialState: const GeneralSettingsSliceState(),
        effectRunnerFactory: (_) => _NoopGeneralRunner(),
      );

      final container = ProviderContainer(
        overrides: [
          appearanceSettingsRepositoryProvider.overrideWithValue(
            MemoryAppearanceSettingsStore(),
          ),
          appearanceFontCatalogProvider.overrideWithValue(_FakeFontCatalog()),
          generalSettingsSliceStoreProvider.overrideWithValue(generalSlice),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(appearanceSettingsValueProvider).themeMode,
        ZetaThemeModePreference.system,
      );

      await container
          .read(appearanceSettingsProvider.notifier)
          .setThemeMode(ZetaThemeModePreference.dark);
      final generalOperation = generalSlice.setMessageSendShortcut(
        MessageSendShortcut.primaryModifierEnter,
      );
      generalSlice.persisted(
        generalOperation,
        generalSlice.state.pendingValue!,
      );

      expect(
        container.read(appearanceSettingsValueProvider).themeMode,
        ZetaThemeModePreference.dark,
      );
      expect(
        container.read(generalSettingsSliceValueProvider).sendMessageShortcut,
        MessageSendShortcut.primaryModifierEnter,
      );
    });
  });
}

final class _NoopGeneralRunner implements GeneralSettingsSliceEffectRunner {
  @override
  void run(GeneralSettingsSliceEffect effect) {}
}

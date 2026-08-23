import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zeta/src/app/settings_slice/settings_slice_runners.dart';
import 'package:zeta/src/features/settings/application/appearance_settings_controller.dart';
import 'package:zeta/src/features/settings/application/general_settings_controller.dart';
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
import 'package:zeta/src/features/settings/presentation/settings_slice/settings_slice_ingress.dart';
import 'package:zeta/src/features/settings/presentation/settings_slice/settings_slice_providers.dart';

/// 可编程字体目录：按 familyName 解析。
final class _FakeFontCatalog implements SystemFontCatalogService {
  _FakeFontCatalog({this.families = const <SystemFontFamily>[]});

  final List<SystemFontFamily> families;

  @override
  Future<List<SystemFontFamily>> uiFontFamilies() async => families;

  @override
  Future<List<SystemFontFamily>> codeFontFamilies() async => families;

  @override
  Future<SystemFontFamily?> resolveFontFamily(String name) async {
    for (final family in families) {
      if (family.familyName == name) {
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

/// 与组合层同款的延迟绑定装配。
AppearanceSettingsSliceStore _appearanceStoreWith({
  required AppearanceSettingsStore dataStore,
  required SystemFontCatalogService fontCatalog,
}) {
  final deferred = _DeferredAppearanceRunner();
  final store = AppearanceSettingsSliceStore(
    initialState: const AppearanceSettingsSliceState(),
    effectRunner: deferred,
  );
  deferred.self = store;
  deferred.delegate = AppearanceSettingsSliceRunnerAdapter(
    store: dataStore,
    fontCatalog: fontCatalog,
    sliceStore: store,
  );
  return store;
}

final class _DeferredAppearanceRunner
    implements AppearanceSettingsSliceEffectRunner {
  AppearanceSettingsSliceEffectRunner? delegate;
  AppearanceSettingsSliceStore? self;

  @override
  void run(AppearanceSettingsSliceEffect effect) => delegate?.run(effect);
}

GeneralSettingsSliceStore _generalStoreWith(GeneralSettingsStore dataStore) {
  final deferred = _DeferredGeneralRunner();
  final store = GeneralSettingsSliceStore(
    initialState: const GeneralSettingsSliceState(),
    effectRunner: deferred,
  );
  deferred.self = store;
  deferred.delegate = GeneralSettingsSliceRunnerAdapter(
    store: dataStore,
    sliceStore: store,
  );
  return store;
}

final class _DeferredGeneralRunner implements GeneralSettingsSliceEffectRunner {
  GeneralSettingsSliceEffectRunner? delegate;
  GeneralSettingsSliceStore? self;

  @override
  void run(GeneralSettingsSliceEffect effect) => delegate?.run(effect);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    test('失败回执不改已应用值（语义 A）', () async {
      final store = _appearanceStoreWith(
        dataStore: _FailingAppearanceStore(),
        fontCatalog: _FakeFontCatalog(),
      );

      store.selectThemeMode(ZetaThemeModePreference.dark);
      await Future<void>.delayed(Duration.zero);

      expect(store.state.value.themeMode, ZetaThemeModePreference.dark);
    });
  });

  group('general runner', () {
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
        SettingsPersistFailureKind.persistence,
      );
      expect(id.scope, SettingsOperationScopes.generalPersist);
      expect(failId.scope, SettingsOperationScopes.generalPersist);
    });
  });

  group('迁移期 ingress 与镜像 provider', () {
    test('旧 controller 的变化镜像进切片，镜像 provider 跟随', () async {
      final appearanceController = AppearanceSettingsController(
        store: MemoryAppearanceSettingsStore(),
        fontCatalog: const _NoopCatalog(),
      );
      final generalController = GeneralSettingsController(
        store: MemoryGeneralSettingsStore(null, AppLanguage.simplifiedChinese),
      );
      final appearanceSlice = AppearanceSettingsSliceStore(
        initialState: const AppearanceSettingsSliceState(),
        effectRunner: _NoopAppearanceRunner(),
      );
      final generalSlice = GeneralSettingsSliceStore(
        initialState: const GeneralSettingsSliceState(),
        effectRunner: _NoopGeneralRunner(),
      );
      final ingress = SettingsSliceIngress(
        appearanceController: appearanceController,
        generalController: generalController,
        appearanceSlice: appearanceSlice,
        generalSlice: generalSlice,
      );
      addTearDown(ingress.dispose);

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

      await appearanceController.setThemeMode(ZetaThemeModePreference.dark);

      expect(
        container.read(appearanceSettingsSliceValueProvider).themeMode,
        ZetaThemeModePreference.dark,
      );
    });
  });
}

final class _NoopCatalog implements SystemFontCatalogService {
  const _NoopCatalog();

  @override
  Future<List<SystemFontFamily>> uiFontFamilies() async => const [];

  @override
  Future<List<SystemFontFamily>> codeFontFamilies() async => const [];

  @override
  Future<SystemFontFamily?> resolveFontFamily(String name) async => null;
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

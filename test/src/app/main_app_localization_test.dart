import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta/src/app/composition/zeta_host_mode.dart';
import 'package:zeta/src/app/app.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/settings/data/appearance_settings_store.dart';
import 'package:zeta/src/features/settings/data/general_settings_store.dart';
import 'package:zeta/src/features/settings/data/system_font_catalog_service.dart';
import 'package:zeta/src/features/settings/domain/app_language.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';
import 'package:zeta/src/features/settings/domain/system_font_family.dart';
import 'package:zeta/src/features/settings/presentation/settings_slice/settings_slice_providers.dart';
import 'package:zeta/src/ui/features/ide/views/ide_home.dart';
import 'package:zeta/src/ui/localization/generated/app_localizations.dart';

import '../testing/ide_test_harness.dart';

void main() {
  testWidgets('waits with a textless background before IdeHome mounts', (
    tester,
  ) async {
    final store = _DeferredGeneralSettingsStore();

    await _pumpMainApp(
      tester,
      generalSettingsStore: store,
      waitForGeneralSettings: true,
    );
    await tester.pump();

    expect(find.byType(IdeHome), findsNothing);
    expect(find.byType(Text), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('zeta.localization-loading')),
      findsOneWidget,
    );

    store.complete();
    await tester.pump();
    await tester.pump();

    expect(find.byType(IdeHome), findsOneWidget);
    final context = tester.element(find.byType(IdeHome));
    expect(AppLocalizations.of(context).localeName, anyOf('zh', 'zh_Hans'));
    expect(Localizations.localeOf(context).languageCode, 'zh');
    expect(sf.ShadcnLocalizations.of(context).commandSearch, isNotEmpty);
    expect(WidgetsLocalizations.of(context), isNotNull);
  });

  testWidgets('slice-only composition survives deferred locale bootstrap', (
    tester,
  ) async {
    final store = _DeferredGeneralSettingsStore();

    await _pumpMainApp(
      tester,
      generalSettingsStore: store,
      waitForGeneralSettings: true,
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('zeta.localization-loading')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    store.complete();
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(IdeHome), findsOneWidget);
  });

  testWidgets('wait path freezes the persisted app language', (tester) async {
    final englishStore = _DeferredGeneralSettingsStore(
      const GeneralSettings(appLanguage: AppLanguage.english),
    );
    await _pumpMainApp(
      tester,
      key: const ValueKey<String>('main-app-en'),
      generalSettingsStore: englishStore,
      waitForGeneralSettings: true,
    );
    await tester.pump();
    expect(find.byType(IdeHome), findsNothing);

    englishStore.complete();
    await tester.pump();
    await tester.pump();
    expect(
      Localizations.localeOf(tester.element(find.byType(IdeHome))).languageCode,
      'en',
    );

    final chineseStore = _DeferredGeneralSettingsStore(
      const GeneralSettings(appLanguage: AppLanguage.simplifiedChinese),
    );
    await _pumpMainApp(
      tester,
      key: const ValueKey<String>('main-app-zh'),
      generalSettingsStore: chineseStore,
      waitForGeneralSettings: true,
    );
    await tester.pump();
    expect(find.byType(IdeHome), findsNothing);
    chineseStore.complete();
    await tester.pump();
    await tester.pump();
    expect(
      Localizations.localeOf(tester.element(find.byType(IdeHome))).languageCode,
      'zh',
    );
  });

  testWidgets('tests can pump English without changing production default', (
    tester,
  ) async {
    await _pumpMainApp(tester, displayLanguageOverride: AppLanguage.english);
    await tester.pump();

    final context = tester.element(find.byType(IdeHome));
    expect(AppLocalizations.of(context).localeName, 'en');
    expect(
      AppLocalizations.of(context).localizationContractGreeting('Ada'),
      'Hello Ada',
    );
  });

  testWidgets('language and appearance updates do not remount IdeHome', (
    tester,
  ) async {
    await _pumpMainApp(
      tester,
      generalSettingsStore: MemoryGeneralSettingsStore(),
      appearanceSettingsStore: MemoryAppearanceSettingsStore(),
      systemFontCatalogService: const _FakeSystemFontCatalogService(),
      initialAppearanceSettings: const AppearanceSettings(
        themeMode: ZetaThemeModePreference.dark,
      ),
    );
    await tester.pump();

    final first = tester.element(find.byType(IdeHome));
    final container = ProviderScope.containerOf(first, listen: false);
    container
        .read(generalSettingsSliceStoreProvider)
        .setAppLanguage(AppLanguage.english);
    container
        .read(appearanceSettingsSliceStoreProvider)
        .selectThemeMode(ZetaThemeModePreference.light);
    await tester.pump();

    expect(tester.element(find.byType(IdeHome)), same(first));
    expect(Localizations.localeOf(first).languageCode, 'zh');
  });

  testWidgets(
    'ignores platform locale changes after the display language freezes',
    (tester) async {
      final store = MemoryGeneralSettingsStore(
        const GeneralSettings(appLanguage: AppLanguage.simplifiedChinese),
      );

      await _pumpMainApp(
        tester,
        generalSettingsStore: store,
        waitForGeneralSettings: true,
      );
      await tester.pump();
      await tester.pump();

      expect(
        Localizations.localeOf(
          tester.element(find.byType(IdeHome)),
        ).languageCode,
        'zh',
      );

      tester.platformDispatcher.localesTestValue = <Locale>[
        const Locale('en', 'US'),
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      ];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await tester.pump();

      expect(
        Localizations.localeOf(
          tester.element(find.byType(IdeHome)),
        ).languageCode,
        'zh',
      );
    },
  );

  testWidgets(
    'rebuilding MainApp with the same store applies the saved language',
    (tester) async {
      final store = MemoryGeneralSettingsStore(
        const GeneralSettings(appLanguage: AppLanguage.simplifiedChinese),
      );

      await _pumpMainApp(
        tester,
        key: const ValueKey<String>('main-app-before-restart'),
        generalSettingsStore: store,
        waitForGeneralSettings: true,
      );
      await tester.pump();
      await tester.pump();
      expect(
        Localizations.localeOf(
          tester.element(find.byType(IdeHome)),
        ).languageCode,
        'zh',
      );

      final firstContext = tester.element(find.byType(IdeHome));
      ProviderScope.containerOf(firstContext, listen: false)
          .read(generalSettingsSliceStoreProvider)
          .setAppLanguage(AppLanguage.english);
      await tester.pump();
      expect(
        Localizations.localeOf(
          tester.element(find.byType(IdeHome)),
        ).languageCode,
        'zh',
      );

      await _pumpMainApp(
        tester,
        key: const ValueKey<String>('main-app-after-restart'),
        generalSettingsStore: store,
        waitForGeneralSettings: true,
      );
      await tester.pump();
      await tester.pump();
      expect(
        Localizations.localeOf(
          tester.element(find.byType(IdeHome)),
        ).languageCode,
        'en',
      );
    },
  );
}

Future<void> _pumpMainApp(
  WidgetTester tester, {
  Key? key,
  GeneralSettingsStore? generalSettingsStore,
  AppearanceSettingsStore? appearanceSettingsStore,
  SystemFontCatalogService? systemFontCatalogService,
  AppearanceSettings? initialAppearanceSettings,
  AppLanguage? displayLanguageOverride,
  bool waitForGeneralSettings = false,
}) async {
  tester.view
    ..physicalSize = const Size(1400, 900)
    ..devicePixelRatio = 1;
  addTearDown(() {
    tester.view
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MainApp(
      key: key,
      enableNativeWindowFrame: false,
      showWindowControls: false,
      hostMode: ZetaHostMode.ephemeral,
      agentProviderFactory: FakeAgentProviderBundleBuilder.fromFake(
        FakeAgentProvider(),
      ),
      agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      generalSettingsStore: generalSettingsStore,
      appearanceSettingsStore: appearanceSettingsStore,
      systemFontCatalogService: systemFontCatalogService,
      initialAppearanceSettings: initialAppearanceSettings,
      displayLanguageOverride: displayLanguageOverride,
      waitForGeneralSettings: waitForGeneralSettings,
    ),
  );
}

class _DeferredGeneralSettingsStore implements GeneralSettingsStore {
  _DeferredGeneralSettingsStore([this._value = const GeneralSettings()]);

  final GeneralSettings _value;
  final _completer = Completer<GeneralSettings>();

  void complete() {
    _completer.complete(_value);
  }

  @override
  Future<GeneralSettings> load() => _completer.future;

  @override
  Future<void> save(GeneralSettings settings) async {}
}

class _FakeSystemFontCatalogService implements SystemFontCatalogService {
  const _FakeSystemFontCatalogService();

  @override
  Future<List<SystemFontFamily>> uiFontFamilies() async =>
      const <SystemFontFamily>[];

  @override
  Future<List<SystemFontFamily>> codeFontFamilies() async =>
      const <SystemFontFamily>[];

  @override
  Future<SystemFontFamily?> resolveFontFamily(String name) async => null;
}

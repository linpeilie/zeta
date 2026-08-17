import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta/src/app/app.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/settings/application/appearance_settings_controller.dart';
import 'package:zeta/src/features/settings/application/general_settings_controller.dart';
import 'package:zeta/src/features/settings/data/appearance_settings_store.dart';
import 'package:zeta/src/features/settings/data/general_settings_store.dart';
import 'package:zeta/src/features/settings/data/system_font_catalog_service.dart';
import 'package:zeta/src/features/settings/domain/app_language.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';
import 'package:zeta/src/features/settings/domain/system_font_family.dart';
import 'package:zeta/src/ui/features/ide/views/ide_home.dart';
import 'package:zeta/src/ui/localization/generated/app_localizations.dart';

import '../testing/ide_test_harness.dart';

void main() {
  testWidgets('waits with a textless background before IdeHome mounts', (
    tester,
  ) async {
    final store = _DeferredGeneralSettingsStore();
    final controller = GeneralSettingsController(store: store);
    addTearDown(controller.dispose);

    await _pumpMainApp(
      tester,
      generalSettingsController: controller,
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

  testWidgets('wait path freezes the persisted app language', (tester) async {
    final englishStore = _DeferredGeneralSettingsStore(
      const GeneralSettings(appLanguage: AppLanguage.english),
    );
    final englishController = GeneralSettingsController(store: englishStore);
    addTearDown(englishController.dispose);
    await _pumpMainApp(
      tester,
      key: const ValueKey<String>('main-app-en'),
      generalSettingsController: englishController,
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
    final chineseController = GeneralSettingsController(store: chineseStore);
    addTearDown(chineseController.dispose);
    await _pumpMainApp(
      tester,
      key: const ValueKey<String>('main-app-zh'),
      generalSettingsController: chineseController,
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
    final general = GeneralSettingsController(
      store: MemoryGeneralSettingsStore(),
    );
    addTearDown(general.dispose);
    final appearance = AppearanceSettingsController(
      store: MemoryAppearanceSettingsStore(),
      fontCatalog: const _FakeSystemFontCatalogService(),
      initialSettings: const AppearanceSettings(themeMode: ThemeMode.dark),
    );
    addTearDown(appearance.dispose);

    await _pumpMainApp(
      tester,
      generalSettingsController: general,
      appearanceController: appearance,
    );
    await tester.pump();

    final first = tester.element(find.byType(IdeHome));
    await general.setAppLanguage(AppLanguage.english);
    await appearance.setThemeMode(ThemeMode.light);
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
      final controller = GeneralSettingsController(store: store);
      addTearDown(controller.dispose);

      await _pumpMainApp(
        tester,
        generalSettingsController: controller,
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
      final firstController = GeneralSettingsController(store: store);
      addTearDown(firstController.dispose);

      await _pumpMainApp(
        tester,
        key: const ValueKey<String>('main-app-before-restart'),
        generalSettingsController: firstController,
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

      await firstController.setAppLanguage(AppLanguage.english);
      await tester.pump();
      expect(
        Localizations.localeOf(
          tester.element(find.byType(IdeHome)),
        ).languageCode,
        'zh',
      );

      final secondController = GeneralSettingsController(store: store);
      addTearDown(secondController.dispose);
      await _pumpMainApp(
        tester,
        key: const ValueKey<String>('main-app-after-restart'),
        generalSettingsController: secondController,
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
  GeneralSettingsController? generalSettingsController,
  AppearanceSettingsController? appearanceController,
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
      sessionLoader: () async => null,
      sessionSaver: (_) async {},
      agentProviderFactory: FakeAgentProviderBundleBuilder.fromFake(
        FakeAgentProvider(),
      ),
      agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      generalSettingsController: generalSettingsController,
      appearanceController: appearanceController,
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

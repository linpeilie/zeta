import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/ide_session/data/ide_session_store.dart';
import 'package:zeta/src/features/settings/application/appearance_settings_controller.dart';
import 'package:zeta/src/features/settings/data/appearance_settings_store.dart';
import 'package:zeta/src/features/settings/data/system_font_catalog_service.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';
import 'package:zeta/src/ui/core/app_theme.dart';
import 'package:zeta/src/ui/core/ide_choice_card.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/features/ide/views/ide_home.dart';

import '../testing/ide_test_harness.dart';

void main() {
  testWidgets('title bar settings action opens settings page', (tester) async {
    await _pumpIdeWithSettings(tester);

    expect(
      find.byKey(const ValueKey('titlebar-settings-action')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('settings-page')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('titlebar-settings-action')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('settings-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-nav-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-detail-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-back-button')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-nav-appearance')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('settings-theme-tabs')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-ui-font-row')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-code-font-row')),
      findsOneWidget,
    );
    expect(find.text('外观'), findsNWidgets(2));
  });

  testWidgets('returning from settings preserves ide panel state', (
    tester,
  ) async {
    await _pumpIdeWithSettings(tester);

    await tester.tap(find.byKey(const ValueKey('left-projects-action')));
    await tester.pump();
    expect(find.byKey(const ValueKey('projects-panel-card')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('titlebar-settings-action')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-page')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings-back-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('settings-page')), findsNothing);
    expect(find.byKey(const ValueKey('projects-panel-card')), findsNothing);
    expect(find.byKey(const ValueKey('agent-pane-host')), findsOneWidget);
  });

  testWidgets('theme selection updates controller and selected option', (
    tester,
  ) async {
    final controller = AppearanceSettingsController(
      store: MemoryAppearanceSettingsStore(),
      fontCatalog: const _FakeSystemFontCatalogService(),
    );
    await _pumpIdeWithSettings(tester, controller: controller);

    // 回归断言：标题文字必须随主题切换重建为当前调色板的 textPrimary，
    // 防止 token 访问器不监听 ShadTheme 时残留旧主题颜色（深浅混杂）。
    Color? headingColor() =>
        tester.widget<Text>(find.text('主题模式')).style?.color;

    await tester.tap(find.byKey(const ValueKey('titlebar-settings-action')));
    await tester.pumpAndSettle();

    expect(controller.settings.themeMode, ThemeMode.system);
    expect(
      tester
          .widget<IdeChoiceCard>(
            find.byKey(const ValueKey('settings-theme-system')),
          )
          .selected,
      isTrue,
    );
    expect(find.text('使用系统当前的浅色或深色偏好。'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings-theme-dark')));
    await tester.pumpAndSettle();

    expect(controller.settings.themeMode, ThemeMode.dark);
    expect(
      tester
          .widget<IdeChoiceCard>(
            find.byKey(const ValueKey('settings-theme-dark')),
          )
          .selected,
      isTrue,
    );
    expect(find.text('使用深底、高对比度面板和明亮强调色。'), findsOneWidget);
    expect(headingColor(), IdeColors.dark.textPrimary);

    await tester.tap(find.byKey(const ValueKey('settings-theme-light')));
    await tester.pumpAndSettle();

    expect(controller.settings.themeMode, ThemeMode.light);
    expect(
      tester
          .widget<IdeChoiceCard>(
            find.byKey(const ValueKey('settings-theme-light')),
          )
          .selected,
      isTrue,
    );
    expect(find.text('使用浅底、低对比度边框和蔚蓝强调色。'), findsOneWidget);
    expect(headingColor(), IdeColors.light.textPrimary);
  });

  testWidgets('ui font picker shows system default and supports search', (
    tester,
  ) async {
    final controller = AppearanceSettingsController(
      store: MemoryAppearanceSettingsStore(),
      fontCatalog: const _FakeSystemFontCatalogService(
        uiFonts: <String>['Maple UI', 'Source Han Sans'],
        codeFonts: <String>['Cascadia Mono'],
        loadableFonts: <String>{'Maple UI', 'Source Han Sans', 'Cascadia Mono'},
      ),
    );
    await _pumpIdeWithSettings(tester, controller: controller);

    await tester.tap(find.byKey(const ValueKey('titlebar-settings-action')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('界面字体'));
    await tester.pumpAndSettle();

    final dialogFinder = find.byKey(
      const ValueKey('settings-font-picker-dialog'),
    );
    expect(dialogFinder, findsOneWidget);
    expect(
      find.descendant(of: dialogFinder, matching: find.text('系统默认')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialogFinder, matching: find.text('Maple UI')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialogFinder, matching: find.text('Source Han Sans')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('settings-font-search-field')),
      'source',
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: dialogFinder, matching: find.text('系统默认')),
      findsNothing,
    );
    expect(
      find.descendant(of: dialogFinder, matching: find.text('Maple UI')),
      findsNothing,
    );
    expect(
      find.descendant(of: dialogFinder, matching: find.text('Source Han Sans')),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(of: dialogFinder, matching: find.text('Source Han Sans')),
    );
    await tester.pumpAndSettle();

    expect(
      controller.settings.uiFontChoice,
      const AppearanceFontChoice.system('Source Han Sans'),
    );
    expect(find.text('Source Han Sans'), findsOneWidget);
  });

  testWidgets(
    'code font picker keeps bundled default and only lists code fonts',
    (tester) async {
      final controller = AppearanceSettingsController(
        store: MemoryAppearanceSettingsStore(),
        fontCatalog: const _FakeSystemFontCatalogService(
          uiFonts: <String>['Maple UI', 'Source Han Sans'],
          codeFonts: <String>['Cascadia Mono', 'Fira Code'],
          loadableFonts: <String>{
            'Maple UI',
            'Source Han Sans',
            'Cascadia Mono',
            'Fira Code',
          },
        ),
      );
      await _pumpIdeWithSettings(tester, controller: controller);

      await tester.tap(find.byKey(const ValueKey('titlebar-settings-action')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('代码字体'));
      await tester.pumpAndSettle();

      final dialogFinder = find.byKey(
        const ValueKey('settings-font-picker-dialog'),
      );
      expect(
        find.descendant(
          of: dialogFinder,
          matching: find.text('JetBrainsMono（内置默认）'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialogFinder, matching: find.text('Cascadia Mono')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialogFinder, matching: find.text('Fira Code')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialogFinder, matching: find.text('Maple UI')),
        findsNothing,
      );

      await tester.enterText(
        find.byKey(const ValueKey('settings-font-search-field')),
        'cascadia',
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: dialogFinder,
          matching: find.text('JetBrainsMono（内置默认）'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: dialogFinder, matching: find.text('Cascadia Mono')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialogFinder, matching: find.text('Fira Code')),
        findsNothing,
      );

      await tester.tap(
        find.descendant(of: dialogFinder, matching: find.text('Cascadia Mono')),
      );
      await tester.pumpAndSettle();

      expect(
        controller.settings.codeFontChoice,
        const AppearanceFontChoice.system('Cascadia Mono'),
      );
      expect(find.text('Cascadia Mono'), findsOneWidget);
    },
  );
}

Future<void> _pumpIdeWithSettings(
  WidgetTester tester, {
  AppearanceSettingsController? controller,
  Size size = const Size(1400, 900),
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(() {
    tester.view
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });

  final appearanceController =
      controller ??
      AppearanceSettingsController(
        store: MemoryAppearanceSettingsStore(),
        fontCatalog: const _FakeSystemFontCatalogService(),
      );
  addTearDown(appearanceController.dispose);
  await appearanceController.load();

  final session = MemorySessionStore();
  final provider = FakeAgentProvider();

  await tester.pumpWidget(
    ValueListenableBuilder<AppearanceSettings>(
      valueListenable: appearanceController.listenable,
      builder: (context, settings, _) {
        return ShadApp(
          theme: buildShadTheme(
            brightness: Brightness.light,
            uiFontFamily: settings.uiFontFamily,
            codeFontFamily: settings.codeFontFamily,
          ),
          darkTheme: buildShadTheme(
            brightness: Brightness.dark,
            uiFontFamily: settings.uiFontFamily,
            codeFontFamily: settings.codeFontFamily,
          ),
          themeMode: settings.themeMode,
          home: IdeCodeFontScope(
            codeFontFamily: settings.codeFontFamily,
            child: IdeHome(
              directoryPicker: () async => null,
              enableNativeWindowFrame: true,
              showWindowControls: false,
              sessionStore: CallbackIdeSessionStore(
                loadJson: session.load,
                saveJson: session.save,
              ),
              agentProviderFactory: FakeAgentProviderFactory(provider),
              agentProviderConfigStore: MemoryAgentProviderConfigStore(),
              projectLocationOpener: (_) async {},
              appearanceController: appearanceController,
            ),
          ),
        );
      },
    ),
  );
  await tester.pump();
}

class _FakeSystemFontCatalogService implements SystemFontCatalogService {
  const _FakeSystemFontCatalogService({
    this.uiFonts = const <String>[],
    this.codeFonts = const <String>[],
    this.loadableFonts = const <String>{},
  });

  final List<String> uiFonts;
  final List<String> codeFonts;
  final Set<String> loadableFonts;

  @override
  Future<List<String>> codeFontFamilies() async => codeFonts;

  @override
  Future<bool> ensureFontLoaded(String fontFamily) async {
    return loadableFonts.contains(fontFamily);
  }

  @override
  Future<List<String>> uiFontFamilies() async => uiFonts;
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta/src/features/settings/application/appearance_settings_controller.dart';
import 'package:zeta/src/features/settings/application/general_settings_controller.dart';
import 'package:zeta/src/features/settings/data/appearance_settings_store.dart';
import 'package:zeta/src/features/settings/data/general_settings_store.dart';
import 'package:zeta/src/features/settings/data/system_font_catalog_service.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';
import 'package:zeta/src/features/settings/domain/system_font_family.dart';
import 'package:zeta/src/features/settings/presentation/settings_page.dart';
import 'package:zeta/src/ui/core/app_theme.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_tabs.dart';
import 'package:zeta/src/ui/core/rows/ide_row_divider.dart';

void main() {
  testWidgets('general settings defaults to Enter and updates shortcut', (
    tester,
  ) async {
    final generalController = GeneralSettingsController(
      store: MemoryGeneralSettingsStore(),
    );
    await _pumpSettingsPage(
      tester,
      activeSection: SettingsSection.general,
      generalController: generalController,
      platform: TargetPlatform.windows,
    );

    expect(find.byKey(const ValueKey('settings-nav-general')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-general-group')),
      findsOneWidget,
    );
    expect(find.text('发送快捷键'), findsOneWidget);
    expect(find.text('Enter 发送'), findsOneWidget);
    expect(find.text('Ctrl + Enter 发送'), findsOneWidget);
    expect(
      tester
          .widget<IdeTabs<MessageSendShortcut>>(
            find.byKey(const ValueKey('settings-send-message-shortcut-tabs')),
          )
          .value,
      MessageSendShortcut.enter,
    );
    expect(find.text('按 Enter 发送消息，按 Shift + Enter 换行。'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('settings-send-message-shortcut-modifier')),
    );
    await tester.pumpAndSettle();

    expect(
      generalController.settings.sendMessageShortcut,
      MessageSendShortcut.primaryModifierEnter,
    );
    expect(find.text('按 Ctrl + Enter 发送消息，按 Enter 换行。'), findsOneWidget);
  });

  testWidgets('general settings uses Cmd label on macOS', (tester) async {
    await _pumpSettingsPage(
      tester,
      activeSection: SettingsSection.general,
      platform: TargetPlatform.macOS,
    );

    expect(find.text('Cmd + Enter 发送'), findsOneWidget);
    expect(find.text('Ctrl + Enter 发送'), findsNothing);
  });

  testWidgets('general settings row stacks in a narrow detail pane', (
    tester,
  ) async {
    await _pumpSettingsPage(
      tester,
      activeSection: SettingsSection.general,
      size: const Size(820, 720),
    );

    expect(
      find.byKey(const ValueKey('ide-settings-row-stacked')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings page renders navigation and appearance detail', (
    tester,
  ) async {
    await _pumpSettingsPage(tester);

    expect(find.byKey(const ValueKey('settings-nav-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-detail-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-back-button')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-nav-appearance')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('settings-theme-tabs')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-appearance-group')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('settings-appearance-group')))
          .width,
      lessThanOrEqualTo(960),
    );
    expect(find.byKey(const ValueKey('settings-ui-font-row')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-ui-font-size-row')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-code-font-row')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-code-font-size-row')),
      findsOneWidget,
    );
    expect(find.text('外观'), findsNWidgets(2));
    expect(find.byType(IdeRowDivider), findsNWidgets(4));
  });

  testWidgets('settings rows stack below the content breakpoint', (
    tester,
  ) async {
    await _pumpSettingsPage(tester, size: const Size(820, 720));

    expect(
      find.byKey(const ValueKey('ide-settings-row-stacked')),
      findsNWidgets(5),
    );
    expect(find.byKey(const ValueKey('ide-settings-row-inline')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings back button invokes onBackPressed', (tester) async {
    var backPressed = false;
    await _pumpSettingsPage(
      tester,
      onBackPressed: () {
        backPressed = true;
      },
    );

    await tester.tap(find.byKey(const ValueKey('settings-back-button')));
    await tester.pump();

    expect(backPressed, isTrue);
  });

  testWidgets('theme selection updates controller and selected option', (
    tester,
  ) async {
    final controller = AppearanceSettingsController(
      store: MemoryAppearanceSettingsStore(),
      fontCatalog: const _FakeSystemFontCatalogService(),
    );
    await _pumpSettingsPage(tester, controller: controller);

    // 回归断言：标题文字必须随主题切换重建为当前调色板的 textPrimary，
    // 防止 token 访问器在根主题切换后残留旧主题颜色（深浅混杂）。
    Color? headingColor() =>
        tester.widget<Text>(find.text('主题模式')).style?.color;

    expect(controller.settings.themeMode, ThemeMode.system);
    expect(
      tester
          .widget<IdeTabs<ThemeMode>>(
            find.byKey(const ValueKey('settings-theme-tabs')),
          )
          .value,
      ThemeMode.system,
    );
    expect(find.text('使用系统当前的浅色或深色偏好。'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings-theme-dark')));
    await tester.pumpAndSettle();

    expect(controller.settings.themeMode, ThemeMode.dark);
    expect(
      tester
          .widget<IdeTabs<ThemeMode>>(
            find.byKey(const ValueKey('settings-theme-tabs')),
          )
          .value,
      ThemeMode.dark,
    );
    expect(find.text('使用深底、高对比度面板和明亮强调色。'), findsOneWidget);
    expect(headingColor(), IdeColors.dark.textPrimary);

    await tester.tap(find.byKey(const ValueKey('settings-theme-light')));
    await tester.pumpAndSettle();

    expect(controller.settings.themeMode, ThemeMode.light);
    expect(
      tester
          .widget<IdeTabs<ThemeMode>>(
            find.byKey(const ValueKey('settings-theme-tabs')),
          )
          .value,
      ThemeMode.light,
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
        displayNames: <String, String>{'Source Han Sans': '思源黑体'},
        aliases: <String, List<String>>{
          'Source Han Sans': <String>['Source Han Sans', 'sourcehansans'],
        },
      ),
    );
    await _pumpSettingsPage(tester, controller: controller);

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
      find.descendant(of: dialogFinder, matching: find.text('思源黑体')),
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
      find.descendant(of: dialogFinder, matching: find.text('思源黑体')),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(of: dialogFinder, matching: find.text('思源黑体')),
    );
    await tester.pumpAndSettle();

    expect(
      controller.settings.uiFontChoice,
      const AppearanceFontChoice.system('Source Han Sans'),
    );
    expect(find.text('思源黑体'), findsOneWidget);
  });

  testWidgets('font size controls update settings and theme tokens', (
    tester,
  ) async {
    final controller = AppearanceSettingsController(
      store: MemoryAppearanceSettingsStore(),
      fontCatalog: const _FakeSystemFontCatalogService(),
    );
    await _pumpSettingsPage(tester, controller: controller);

    double? headingFontSize() =>
        tester.widget<Text>(find.text('主题模式')).style?.fontSize;

    expect(headingFontSize(), 12);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('settings-ui-font-size-value')),
          )
          .data,
      '12 px',
    );

    await tester.tap(
      find.byKey(const ValueKey('settings-ui-font-size-increase')),
    );
    await tester.pumpAndSettle();

    expect(controller.settings.uiFontSize, 13);
    expect(headingFontSize(), closeTo(13, 0.001));

    await tester.tap(
      find.byKey(const ValueKey('settings-code-font-size-increase')),
    );
    await tester.pumpAndSettle();

    expect(controller.settings.codeFontSize, 13);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('settings-code-font-size-value')),
          )
          .data,
      '13 px',
    );
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
      await _pumpSettingsPage(tester, controller: controller);

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

  testWidgets('font picker shows toast when selected font cannot load', (
    tester,
  ) async {
    final controller = AppearanceSettingsController(
      store: MemoryAppearanceSettingsStore(),
      fontCatalog: const _FakeSystemFontCatalogService(
        uiFonts: <String>['Broken UI'],
        // 列表可见，但选择时目录解析失败，触发错误 toast。
        loadableFonts: <String>{},
      ),
    );
    await _pumpSettingsPage(tester, controller: controller);

    await tester.tap(find.text('界面字体'));
    await tester.pumpAndSettle();

    final dialogFinder = find.byKey(
      const ValueKey('settings-font-picker-dialog'),
    );
    await tester.tap(
      find.descendant(of: dialogFinder, matching: find.text('Broken UI')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('无法加载所选界面字体。'), findsOneWidget);
    expect(
      controller.settings.uiFontChoice,
      isNot(const AppearanceFontChoice.system('Broken UI')),
    );

    // toast 有自动关闭 timer，显式推进时间避免 pending timer。
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 600));
  });
}

Future<void> _pumpSettingsPage(
  WidgetTester tester, {
  AppearanceSettingsController? controller,
  GeneralSettingsController? generalController,
  SettingsSection activeSection = SettingsSection.appearance,
  TargetPlatform? platform,
  VoidCallback? onBackPressed,
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
  final resolvedGeneralController =
      generalController ??
      GeneralSettingsController(store: MemoryGeneralSettingsStore());
  addTearDown(resolvedGeneralController.dispose);
  await resolvedGeneralController.load();

  await tester.pumpWidget(
    ValueListenableBuilder<AppearanceSettings>(
      valueListenable: appearanceController.listenable,
      builder: (context, settings, _) {
        final lightIdeTheme = buildIdeThemeData(
          brightness: Brightness.light,
          uiFontFamily: settings.uiFontFamily,
          codeFontFamily: settings.codeFontFamily,
          uiFontSize: settings.uiFontSize,
          codeFontSize: settings.codeFontSize,
        );
        final darkIdeTheme = buildIdeThemeData(
          brightness: Brightness.dark,
          uiFontFamily: settings.uiFontFamily,
          codeFontFamily: settings.codeFontFamily,
          uiFontSize: settings.uiFontSize,
          codeFontSize: settings.codeFontSize,
        );
        final materialBrightness = resolveBrightnessForThemeMode(
          settings.themeMode,
        );
        final materialIdeTheme = materialBrightness == Brightness.dark
            ? darkIdeTheme
            : lightIdeTheme;
        return IdeThemeScope(
          themeMode: settings.themeMode,
          lightTheme: lightIdeTheme,
          darkTheme: darkIdeTheme,
          child: sf.ShadcnApp(
            theme: buildShadcnTheme(lightIdeTheme),
            darkTheme: buildShadcnTheme(darkIdeTheme),
            materialTheme: buildMaterialTheme(
              materialIdeTheme,
            ).copyWith(platform: platform),
            themeMode: resolveShadcnThemeMode(settings.themeMode),
            home: sf.Scaffold(
              child: SettingsPage(
                activeSection: activeSection,
                appearanceController: appearanceController,
                generalSettingsController: resolvedGeneralController,
                onBackPressed: onBackPressed ?? () {},
                onSectionSelected: (_) {},
              ),
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
    this.displayNames = const <String, String>{},
    this.aliases = const <String, List<String>>{},
  });

  final List<String> uiFonts;
  final List<String> codeFonts;
  final Set<String> loadableFonts;
  final Map<String, String> displayNames;
  final Map<String, List<String>> aliases;

  @override
  Future<List<SystemFontFamily>> codeFontFamilies() async =>
      codeFonts.map((name) => _family(name, isMonospace: true)).toList();

  @override
  Future<SystemFontFamily?> resolveFontFamily(String name) async {
    final normalized = name.toLowerCase();
    for (final family in <SystemFontFamily>[
      ...await uiFontFamilies(),
      ...await codeFontFamilies(),
    ]) {
      if (!loadableFonts.contains(family.familyName)) {
        continue;
      }
      if (family.aliases.any((alias) => alias.toLowerCase() == normalized)) {
        return family;
      }
    }
    return null;
  }

  @override
  Future<List<SystemFontFamily>> uiFontFamilies() async => uiFonts
      .map((name) => _family(name, isMonospace: codeFonts.contains(name)))
      .toList();

  SystemFontFamily _family(String name, {required bool isMonospace}) {
    return SystemFontFamily(
      id: 'test:${name.toLowerCase()}',
      familyName: name,
      displayName: displayNames[name] ?? name,
      aliases: <String>{name, ...?aliases[name]}.toList(growable: false),
      isMonospace: isMonospace,
    );
  }
}

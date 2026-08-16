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
import 'package:zeta/src/ui/core/ide_switch.dart';
import 'package:zeta/src/ui/core/ide_tabs.dart';
import 'package:zeta/src/app/localization/zeta_localization.dart';
import 'package:zeta/src/ui/core/rows/ide_row_divider.dart';

void main() {
  testWidgets('settings chrome follows locale while values stay stable', (
    tester,
  ) async {
    await _pumpSettingsPage(
      tester,
      locale: ZetaLocalization.english,
      activeSection: SettingsSection.general,
    );
    expect(find.text('General'), findsOneWidget);
    expect(find.text('Enter to send'), findsOneWidget);
    expect(find.text('常规'), findsNothing);

    await _pumpSettingsPage(
      tester,
      locale: ZetaLocalization.simplifiedChinese,
      activeSection: SettingsSection.general,
    );
    expect(find.text('常规'), findsOneWidget);
    expect(find.text('Enter 发送'), findsOneWidget);
  });

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

    expect(
      find.byKey(const ValueKey('settings-agent-notifications-group')),
      findsOneWidget,
    );
    expect(find.text('系统通知'), findsOneWidget);
    expect(find.text('任务结束'), findsOneWidget);
    expect(find.text('需要确认'), findsOneWidget);
    expect(
      tester
          .widget<IdeSwitch>(
            find.byKey(
              const ValueKey('settings-action-required-notifications-switch'),
            ),
          )
          .value,
      isTrue,
    );

    await tester.tap(
      find.byKey(
        const ValueKey('settings-action-required-notifications-switch'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      generalController.settings.notifications.actionRequiredEnabled,
      isFalse,
    );
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
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('分组标题压过行标题一档，并靠留白把分组之间拉开', (tester) async {
    await _pumpSettingsPage(tester, activeSection: SettingsSection.general);

    final groupTitle = tester.widget<Text>(find.text('通知')).style!;
    final rowTitle = tester.widget<Text>(find.text('系统通知')).style!;
    final rowDescription = tester
        .widget<Text>(find.text('在任务转入后台或其他会话时发送系统提醒。'))
        .style!;

    // 眉标题：最小字号 + 最粗字重 + 次级色，不参与阅读只做索引。
    expect(groupTitle.fontSize, lessThan(rowTitle.fontSize!));
    expect(groupTitle.fontSize, lessThan(rowDescription.fontSize!));
    expect(groupTitle.fontWeight, FontWeight.w700);
    expect(groupTitle.color, isNot(rowTitle.color));
    expect(groupTitle.color, isNot(rowDescription.color));

    // 分组标题离上一组的距离必须大于它到自己首行的距离，
    // 否则去掉卡片后读者无法判断标题管辖哪几行。
    final previousGroupBottom = tester
        .getBottomLeft(find.byKey(const ValueKey('settings-general-group')))
        .dy;
    final titleRect = tester.getRect(find.text('通知'));
    final firstRowTitleTop = tester.getTopLeft(find.text('系统通知')).dy;
    expect(
      titleRect.top - previousGroupBottom,
      greaterThan(firstRowTitleTop - titleRect.bottom),
    );
  });

  testWidgets('settings page renders navigation and appearance detail', (
    tester,
  ) async {
    await _pumpSettingsPage(tester);

    expect(find.byKey(const ValueKey('settings-nav-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-detail-panel')), findsOneWidget);
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
    // 页面顶栏已移除，'外观' 只剩左侧导航项一处。
    expect(find.text('外观'), findsOneWidget);
    // 外观分成「主题」（1 行，组内无分割线）与「字体」（4 行 → 3 条分割线）。
    expect(
      find.byKey(const ValueKey('settings-appearance-font-group')),
      findsOneWidget,
    );
    expect(find.byType(IdeRowDivider), findsNWidgets(3));
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

  testWidgets('ui font select shows system default and supports search', (
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

    final selectFinder = find.byKey(const ValueKey('settings-ui-font-select'));
    expect(selectFinder, findsOneWidget);
    expect(
      tester.widget<sf.Select<AppearanceFontChoice>>(selectFinder).value,
      const AppearanceFontChoice.systemDefault(),
    );

    await tester.tap(selectFinder);
    await _pumpSelectOverlay(tester);

    final popupFinder = find.byKey(
      const ValueKey('settings-ui-font-select-popup'),
    );
    expect(popupFinder, findsOneWidget);
    expect(
      find.descendant(of: popupFinder, matching: find.text('Geist（内置默认）')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: popupFinder, matching: find.text('Maple UI')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: popupFinder, matching: find.text('思源黑体')),
      findsOneWidget,
    );

    final searchFinder = find.descendant(
      of: popupFinder,
      matching: find.byType(sf.TextField),
    );
    expect(searchFinder, findsOneWidget);
    await tester.enterText(searchFinder, 'source');
    await _pumpSelectOverlay(tester);

    expect(
      find.descendant(of: popupFinder, matching: find.text('系统默认')),
      findsNothing,
    );
    expect(
      find.descendant(of: popupFinder, matching: find.text('Maple UI')),
      findsNothing,
    );
    expect(
      find.descendant(of: popupFinder, matching: find.text('思源黑体')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(
        const ValueKey('settings-ui-font-option-system-Source Han Sans'),
      ),
    );
    await _pumpSelectOverlay(tester);

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
    'code font select keeps bundled default and only lists code fonts',
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

      final selectFinder = find.byKey(
        const ValueKey('settings-code-font-select'),
      );
      expect(selectFinder, findsOneWidget);
      expect(
        tester.widget<sf.Select<AppearanceFontChoice>>(selectFinder).value,
        const AppearanceFontChoice.bundledJetBrainsMono(),
      );

      await tester.tap(selectFinder);
      await _pumpSelectOverlay(tester);

      final popupFinder = find.byKey(
        const ValueKey('settings-code-font-select-popup'),
      );
      expect(
        find.descendant(
          of: popupFinder,
          matching: find.text('JetBrainsMono（内置默认）'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: popupFinder, matching: find.text('Cascadia Mono')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: popupFinder, matching: find.text('Fira Code')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: popupFinder, matching: find.text('Maple UI')),
        findsNothing,
      );

      final searchFinder = find.descendant(
        of: popupFinder,
        matching: find.byType(sf.TextField),
      );
      expect(searchFinder, findsOneWidget);
      await tester.enterText(searchFinder, 'cascadia');
      await _pumpSelectOverlay(tester);

      expect(
        find.descendant(
          of: popupFinder,
          matching: find.text('JetBrainsMono（内置默认）'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: popupFinder, matching: find.text('Cascadia Mono')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: popupFinder, matching: find.text('Fira Code')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(
          const ValueKey('settings-code-font-option-system-Cascadia Mono'),
        ),
      );
      await _pumpSelectOverlay(tester);

      expect(
        controller.settings.codeFontChoice,
        const AppearanceFontChoice.system('Cascadia Mono'),
      );
      expect(find.text('Cascadia Mono'), findsOneWidget);
    },
  );

  testWidgets('font select shows toast when selected font cannot load', (
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

    await tester.tap(find.byKey(const ValueKey('settings-ui-font-select')));
    await _pumpSelectOverlay(tester);

    await tester.tap(
      find.byKey(const ValueKey('settings-ui-font-option-system-Broken UI')),
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

/// Select 弹层可能带持续动画；用有界 pump，避免 pumpAndSettle 超时。
Future<void> _pumpSelectOverlay(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _pumpSettingsPage(
  WidgetTester tester, {
  AppearanceSettingsController? controller,
  GeneralSettingsController? generalController,
  SettingsSection activeSection = SettingsSection.appearance,
  TargetPlatform? platform,
  Size size = const Size(1400, 900),
  Locale locale = ZetaLocalization.simplifiedChinese,
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
            locale: locale,
            supportedLocales: ZetaLocalization.supportedLocales,
            localizationsDelegates: ZetaLocalization.delegates,
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

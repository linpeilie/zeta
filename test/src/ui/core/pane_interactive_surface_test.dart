import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta/src/ui/core/app_theme.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';

void main() {
  for (final themeMode in <ThemeMode>[ThemeMode.light, ThemeMode.dark]) {
    testWidgets('PaneInteractiveSurface 在 ${themeMode.name} 模式使用语义状态 Token', (
      tester,
    ) async {
      final previousHighlightStrategy = FocusManager.instance.highlightStrategy;
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(() {
        FocusManager.instance.highlightStrategy = previousHighlightStrategy;
      });
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);

      await _pumpSurface(tester, themeMode: themeMode, focusNode: focusNode);
      final colors = themeMode == ThemeMode.dark
          ? IdeColors.dark
          : IdeColors.light;
      expect(_decorationOf(tester).color, Colors.transparent);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(_surfaceFinder));
      await tester.pumpAndSettle();
      expect(_decorationOf(tester).color, colors.hoverSurface);

      final press = await tester.startGesture(tester.getCenter(_surfaceFinder));
      await tester.pumpAndSettle();
      expect(_decorationOf(tester).color, colors.pressedSurface);
      await press.up();
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();

      await _pumpSurface(
        tester,
        themeMode: themeMode,
        focusNode: focusNode,
        selected: true,
      );
      await tester.pumpAndSettle();
      expect(_decorationOf(tester).color, colors.selectedSurface);

      await mouse.moveTo(tester.getCenter(_surfaceFinder));
      await tester.pumpAndSettle();
      expect(_decorationOf(tester).color, colors.selectedHoverSurface);

      final selectedPress = await tester.startGesture(
        tester.getCenter(_surfaceFinder),
      );
      await tester.pumpAndSettle();
      expect(_decorationOf(tester).color, colors.pressedSurface);
      await selectedPress.up();
      await tester.pumpAndSettle();

      focusNode.requestFocus();
      await tester.pumpAndSettle();
      final border = _decorationOf(tester).border! as Border;
      expect(border.top.color, colors.focusRing);

      await _pumpSurface(
        tester,
        themeMode: themeMode,
        focusNode: focusNode,
        selected: true,
        enabled: false,
      );
      await tester.pumpAndSettle();
      expect(_decorationOf(tester).color, Colors.transparent);
    });
  }

  testWidgets('无点击回调的展示型表面不会进入 hover 状态', (tester) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await _pumpSurface(
      tester,
      themeMode: ThemeMode.dark,
      focusNode: focusNode,
      selected: true,
      interactive: false,
    );
    expect(_decorationOf(tester).color, IdeColors.dark.selectedSurface);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(_surfaceFinder));
    await tester.pumpAndSettle();

    expect(_decorationOf(tester).color, IdeColors.dark.selectedSurface);
  });
}

const _surfaceKey = ValueKey<String>('interactive-surface');
final _surfaceFinder = find.byKey(_surfaceKey);

BoxDecoration _decorationOf(WidgetTester tester) {
  final container = tester.widget<AnimatedContainer>(
    find.descendant(
      of: _surfaceFinder,
      matching: find.byType(AnimatedContainer),
    ),
  );
  return container.decoration! as BoxDecoration;
}

Future<void> _pumpSurface(
  WidgetTester tester, {
  required ThemeMode themeMode,
  required FocusNode focusNode,
  bool selected = false,
  bool enabled = true,
  bool interactive = true,
}) async {
  final lightTheme = buildIdeThemeData(
    brightness: Brightness.light,
    codeFontFamily: 'CodeFont',
  );
  final darkTheme = buildIdeThemeData(
    brightness: Brightness.dark,
    codeFontFamily: 'CodeFont',
  );
  final currentTheme = themeMode == ThemeMode.dark ? darkTheme : lightTheme;
  await tester.pumpWidget(
    IdeThemeScope(
      themeMode: themeMode,
      lightTheme: lightTheme,
      darkTheme: darkTheme,
      child: sf.ShadcnApp(
        theme: buildShadcnTheme(lightTheme),
        darkTheme: buildShadcnTheme(darkTheme),
        materialTheme: buildMaterialTheme(currentTheme),
        themeMode: resolveShadcnThemeMode(themeMode),
        home: sf.Scaffold(
          child: Center(
            child: PaneInteractiveSurface(
              key: _surfaceKey,
              focusNode: focusNode,
              onPressed: interactive ? () {} : null,
              selected: selected,
              enabled: enabled,
              width: 120,
              height: 36,
              child: const Text('Token surface'),
            ),
          ),
        ),
      ),
    ),
  );
}

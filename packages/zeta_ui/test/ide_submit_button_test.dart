import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta_ui/zeta_ui.dart';

void main() {
  testWidgets('filled 提交按钮使用 accent、图标盒与独立按钮 key', (tester) async {
    var pressed = false;
    late IdeColors colors;
    await _pumpSubmitButton(
      tester,
      Builder(
        builder: (context) {
          colors = IdeColors.of(context);
          return IdeSubmitButton(
            key: const ValueKey('state'),
            buttonKey: const ValueKey('button'),
            icon: Icons.arrow_upward_rounded,
            tooltip: '发送',
            filled: true,
            onPressed: () => pressed = true,
          );
        },
      ),
    );

    expect(find.byKey(const ValueKey('state')), findsOneWidget);
    expect(find.byKey(const ValueKey('button')), findsOneWidget);
    expect(find.byType(IdeIconBox), findsOneWidget);
    final ringSize = IdeMetrics.controlIconBoxFor(
      IdeTextStyles.of(
        tester.element(find.byType(IdeSubmitButton)),
      ).displayLarge,
    );
    expect(tester.getSize(find.byType(IdeSubmitButton)).shortestSide, ringSize);
    expect(_discDecoration(tester).color, colors.accent);
    expect(_ringDecoration(tester).border?.top.color, colors.accent);
    expect(
      _ringDecoration(tester).border?.top.width,
      IdeMetrics.submitButtonRingWidth,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('button'))).shortestSide,
      ringSize -
          2 *
              (IdeMetrics.submitButtonRingWidth +
                  IdeMetrics.submitButtonRingGap),
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.arrow_upward_rounded)).color,
      colors.onAccent,
    );

    await tester.tap(find.byKey(const ValueKey('button')));
    expect(pressed, isTrue);
  });

  testWidgets('surface 与禁用态按回调可用性映射中性色', (tester) async {
    late IdeColors colors;
    await _pumpSubmitButton(
      tester,
      Builder(
        builder: (context) {
          colors = IdeColors.of(context);
          return IdeSubmitButton(
            icon: Icons.stop_rounded,
            tooltip: '停止',
            onPressed: () {},
          );
        },
      ),
    );

    expect(
      _discDecoration(tester).color,
      colors.border.withValues(alpha: 0.36),
    );
    expect(
      _ringDecoration(tester).border?.top.color,
      colors.border.withValues(alpha: 0.36),
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.stop_rounded)).color,
      colors.textSecondary,
    );

    await _pumpSubmitButton(
      tester,
      Builder(
        builder: (context) => const IdeSubmitButton(
          icon: Icons.arrow_upward_rounded,
          tooltip: '发送',
          onPressed: null,
        ),
      ),
    );

    expect(_discDecoration(tester).color, colors.border.withValues(alpha: 0.2));
    expect(
      _ringDecoration(tester).border?.top.color,
      colors.border.withValues(alpha: 0.2),
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.arrow_upward_rounded)).color,
      colors.textSecondary.withValues(alpha: 0.72),
    );
  });

  testWidgets('tooltip 同时提供按钮无障碍名称', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpSubmitButton(
      tester,
      const IdeSubmitButton(
        icon: Icons.arrow_upward_rounded,
        tooltip: '发送消息',
        onPressed: null,
      ),
    );

    final buttonSemantics = find.bySemanticsLabel('发送消息');
    expect(buttonSemantics, findsOneWidget);
    expect(
      tester.getSemantics(buttonSemantics),
      matchesSemantics(
        label: '发送消息',
        isButton: true,
        hasEnabledState: true,
        isEnabled: false,
      ),
    );
    semantics.dispose();
  });
}

BoxDecoration _discDecoration(WidgetTester tester) {
  return _circleDecorations(
    tester,
  ).firstWhere((decoration) => decoration.color != null);
}

BoxDecoration _ringDecoration(WidgetTester tester) {
  return _circleDecorations(
    tester,
  ).firstWhere((decoration) => decoration.border != null);
}

Iterable<BoxDecoration> _circleDecorations(WidgetTester tester) {
  return tester
      .widgetList<DecoratedBox>(
        find.descendant(
          of: find.byType(IdeSubmitButton),
          matching: find.byType(DecoratedBox),
        ),
      )
      .map((widget) => widget.decoration)
      .whereType<BoxDecoration>()
      .where((decoration) => decoration.shape == BoxShape.circle);
}

Future<void> _pumpSubmitButton(WidgetTester tester, Widget child) async {
  final lightTheme = buildIdeThemeData(brightness: Brightness.light);
  final darkTheme = buildIdeThemeData(brightness: Brightness.dark);
  await tester.pumpWidget(
    IdeThemeScope(
      themeMode: ThemeMode.dark,
      lightTheme: lightTheme,
      darkTheme: darkTheme,
      child: sf.ShadcnApp(
        theme: buildShadcnTheme(lightTheme),
        darkTheme: buildShadcnTheme(darkTheme),
        themeMode: sf.ThemeMode.dark,
        home: sf.Scaffold(
          child: Align(alignment: Alignment.topLeft, child: child),
        ),
      ),
    ),
  );
}

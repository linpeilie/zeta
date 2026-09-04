import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta_ui/zeta_ui.dart';

void main() {
  testWidgets('compact 状态卡默认零外边距且不低于 30px', (tester) async {
    await _pumpStatusCard(
      tester,
      const IdeStatusCard(
        key: ValueKey('card'),
        tone: IdeStatusCardTone.info,
        density: IdeStatusCardDensity.compact,
        title: '配置将在下一回合生效',
      ),
    );

    final cardSize = tester.getSize(find.byKey(const ValueKey('card')));
    final panelSize = tester.getSize(
      find.descendant(
        of: find.byKey(const ValueKey('card')),
        matching: find.byType(PanelCard),
      ),
    );

    expect(cardSize.height, greaterThanOrEqualTo(30));
    expect(cardSize, panelSize);
  });

  testWidgets('compact 状态卡使用 bodySmall、tone 色与图标盒', (tester) async {
    late IdeColors colors;
    late IdeTextStyles textStyles;
    await _pumpStatusCard(
      tester,
      Builder(
        builder: (context) {
          colors = IdeColors.of(context);
          textStyles = IdeTextStyles.of(context);
          return const IdeStatusCard(
            tone: IdeStatusCardTone.warning,
            density: IdeStatusCardDensity.compact,
            title: '提示',
          );
        },
      ),
    );

    final title = tester.widget<Text>(find.text('提示'));
    expect(title.style?.fontSize, textStyles.bodySmall.fontSize);
    expect(title.style?.color, colors.warning);
    expect(find.byType(IdeIconBox), findsOneWidget);
  });

  testWidgets('compact 状态卡标题可显示两行', (tester) async {
    await _pumpStatusCard(
      tester,
      const SizedBox(
        width: 150,
        child: IdeStatusCard(
          tone: IdeStatusCardTone.info,
          density: IdeStatusCardDensity.compact,
          title: '这是一条需要占据两行显示的模型自动切换提示信息',
          titleMaxLines: 2,
        ),
      ),
    );

    final title = tester.widget<Text>(find.byType(Text));
    expect(title.maxLines, 2);
  });
}

Future<void> _pumpStatusCard(WidgetTester tester, Widget child) async {
  final lightTheme = buildIdeThemeData(
    brightness: Brightness.light,
    codeFontFamily: bundledCodeFontFamily,
  );
  final darkTheme = buildIdeThemeData(
    brightness: Brightness.dark,
    codeFontFamily: bundledCodeFontFamily,
  );
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

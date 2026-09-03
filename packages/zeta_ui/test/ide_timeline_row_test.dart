import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta_ui/zeta_ui.dart';

void main() {
  testWidgets('统一排列图标盒、前缀、单行标题与尾部 meta', (tester) async {
    await _pumpTimelineRow(
      tester,
      const SizedBox(
        width: 260,
        child: IdeTimelineRow(
          title: '一条足够长且需要在窄空间中截断的时间线标题',
          leading: Icon(Icons.terminal_rounded, key: ValueKey('leading')),
          prefix: Text('运行'),
          trailing: Text('1.2s'),
        ),
      ),
    );

    expect(find.byType(IdeIconBox), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(IdeIconBox),
        matching: find.byKey(const ValueKey('leading')),
      ),
      findsOneWidget,
    );
    final title = tester.widget<Text>(find.text('一条足够长且需要在窄空间中截断的时间线标题'));
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
    expect(find.text('运行'), findsOneWidget);
    expect(find.text('1.2s'), findsOneWidget);
  });

  testWidgets('交互行公开按钮语义并响应点击', (tester) async {
    var presses = 0;
    await _pumpTimelineRow(
      tester,
      IdeTimelineRow(
        title: '运行命令',
        semanticLabel: '打开运行命令',
        onTap: () => presses += 1,
      ),
    );

    final semantics = tester.getSemantics(find.byType(IdeTimelineRow));
    expect(semantics.label, '打开运行命令');
    expect(semantics.flagsCollection.isButton, isTrue);

    await tester.tap(find.byType(IdeTimelineRow));
    await tester.pump();
    expect(presses, 1);
  });

  testWidgets('放大文字时按内容自然增高', (tester) async {
    const row = IdeTimelineRow(title: '自然高度');
    await _pumpTimelineRow(tester, row);
    final normalHeight = tester.getSize(find.byType(IdeTimelineRow)).height;

    await _pumpTimelineRow(tester, row, textScaleFactor: 2);
    final scaledHeight = tester.getSize(find.byType(IdeTimelineRow)).height;

    expect(scaledHeight, greaterThan(normalHeight));
  });
}

Future<void> _pumpTimelineRow(
  WidgetTester tester,
  Widget child, {
  double textScaleFactor = 1,
}) async {
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
          child: MediaQuery(
            data: MediaQueryData(
              size: const Size(800, 600),
              textScaler: TextScaler.linear(textScaleFactor),
              disableAnimations: true,
            ),
            child: Align(alignment: Alignment.topLeft, child: child),
          ),
        ),
      ),
    ),
  );
}

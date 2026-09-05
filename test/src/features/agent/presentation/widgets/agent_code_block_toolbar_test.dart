import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta_ui/zeta_ui.dart';

import 'package:zeta/src/app/localization/zeta_localization.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_markdown_body.dart';

/// 会话正文里的代码块要带语言标签、行数与复制反馈。
void main() {
  const markdown = '```dart\nvoid main() {\n  print("hi");\n}\n```\n';

  Future<void> pump(WidgetTester tester, {String data = markdown}) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final theme = buildIdeThemeData(
      brightness: Brightness.dark,
      codeFontFamily: 'CodeFont',
    );
    await tester.pumpWidget(
      ProviderScope(
        child: IdeThemeScope(
          themeMode: ThemeMode.dark,
          lightTheme: theme,
          darkTheme: theme,
          child: sf.ShadcnApp(
            locale: ZetaLocalization.simplifiedChinese,
            supportedLocales: ZetaLocalization.supportedLocales,
            localizationsDelegates: ZetaLocalization.delegates,
            theme: buildShadcnTheme(theme),
            builder: (context, child) => IdeMaterialLayer(
              theme: buildMaterialTheme(theme),
              child: child,
            ),
            home: sf.Scaffold(
              child: SingleChildScrollView(
                child: SizedBox(
                  width: 720,
                  child: AgentRawMarkdownBody(data: data),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('展示语言标签与行数', (tester) async {
    await pump(tester);

    expect(find.text('dart'), findsOneWidget);
    expect(find.text('3 行'), findsOneWidget);
    expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
  });

  testWidgets('未标注语言时只显示行数', (tester) async {
    await pump(tester, data: '```\nplain text\n```\n');

    expect(find.text('1 行'), findsOneWidget);
    expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
  });

  testWidgets('点击复制写剪贴板并给出对勾反馈，随后复位', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add(
            (call.arguments as Map<Object?, Object?>)['text']! as String,
          );
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await pump(tester);
    await tester.tap(find.byIcon(Icons.copy_rounded));
    await tester.pump();

    expect(copied.single.trim(), 'void main() {\n  print("hi");\n}');
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byIcon(Icons.copy_rounded), findsNothing);

    // 反馈是有态的，1.5s 后复位；状态由工具栏自持，不受父级重建影响。
    await tester.pump(const Duration(seconds: 2));
    expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNothing);
  });
}

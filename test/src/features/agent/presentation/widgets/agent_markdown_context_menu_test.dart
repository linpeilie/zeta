import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta_markdown/zeta_markdown.dart';
import 'package:zeta_ui/zeta_ui.dart';

import 'package:zeta/src/app/localization/zeta_localization.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_markdown_body.dart';

/// 会话正文右键菜单：中文、收敛过项目、不再是被抑制的空菜单。
void main() {
  Future<void> pump(WidgetTester tester) async {
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
                  child: AgentRawMarkdownBody(data: '一段可以选中的会话正文。'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> secondaryTap(WidgetTester tester) async {
    // 点在首行文字上：正文用 useColumn，组件盒可能比内容高，取中心会落到空白处。
    final gesture = await tester.startGesture(
      tester.getTopLeft(find.byType(MarkdownWidget)) + const Offset(20, 8),
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('右键弹出中文菜单，且不含「全选」', (tester) async {
    await pump(tester);
    await secondaryTap(tester);

    expect(find.text('复制全文'), findsOneWidget);
    // 上游硬编码的英文不该再出现。
    expect(find.text('Copy all'), findsNothing);
    // 全选在会话流里会跨越整篇文档，收敛掉。
    expect(find.text('Select all'), findsNothing);
    expect(find.text('全选'), findsNothing);
  });

  testWidgets('正文声明 I-Beam 光标，且不再靠外层 MouseRegion 补丁', (tester) async {
    await pump(tester);

    final cursors = tester
        .widgetList<MouseRegion>(find.byType(MouseRegion))
        .map((region) => region.cursor)
        .toList();
    expect(cursors, contains(SystemMouseCursors.text));

    // 单段正文只应有一个文本光标区域——它由包内按文本块声明。
    // 外层补丁若复活，这里会变成两个（补丁那层把整棵树都包了）。
    expect(
      cursors.where((cursor) => cursor == SystemMouseCursors.text),
      hasLength(1),
    );
  });

  testWidgets('菜单不再是被抑制的空组件', (tester) async {
    await pump(tester);
    await secondaryTap(tester);

    expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
  });
}

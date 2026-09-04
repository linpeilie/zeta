import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_ui/zeta_ui.dart';

import 'package:zeta/src/features/agent/presentation/timeline_rendering/agent_timeline_extent_math.dart';
import 'package:zeta/src/app/localization/zeta_localization.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_markdown_body.dart';

/// Markdown 估算公式与真实渲染高度的契约守卫。
///
/// 虚拟化列表用 [estimateAgentMarkdownExtent] 的结果维持滚动锚点；包内布局一变
/// （代码块加工具栏、块间距调整、主题度量改动…）估算就会脱节，长会话滚动会跳。
/// 这条测试有两层：
///
/// 1. **真实高度基线**：改动包内布局时它会先红。红了不等于错——确认变化是有意的
///    之后，更新基线，并同步检查估算公式是否需要跟着改。
/// 2. **估算/真实比值带**：拦数量级失真。估算偏保守（宁可高估，虚拟化里高估只是
///    多留白，低估会让锚点向上跳），所以带子是不对称的。
///
/// 数值取自 flutter_test 的确定性字体，与生产字体无关；跨平台应当一致。
void main() {
  const width = 720.0;

  // 真实渲染高度基线（logical px）。改动包内布局后按实测更新。
  const fixtures = <String, ({String markdown, double realHeight})>{
    'prose': (
      markdown:
          '这是一段较长的 Agent 正文，用来验证估算与真实渲染的偏差。'
          '句子会折行多次，因此估算必须逐源行累加折行。\n\n'
          '第二段同样有一定长度，覆盖块间距的估算。\n\n'
          '- 列表项一\n- 列表项二\n- 列表项三\n',
      realHeight: 123.2,
    ),
    'code': (
      markdown:
          '说明文字：\n\n```dart\nvoid main() {\n  final a = 1;\n'
          '  print("hello");\n}\n```\n\n收尾说明。\n',
      realHeight: 145.6,
    ),
    'table': (
      markdown:
          '# 标题\n\n| 列一 | 列二 |\n| --- | --- |\n| 1 | 2 |\n| 3 | 4 |\n\n段落。\n',
      realHeight: 148.6,
    ),
  };

  for (final entry in fixtures.entries) {
    testWidgets('${entry.key}：真实高度守住基线，估算落在容差带内', (tester) async {
      final real = await _measureNaturalHeight(
        tester,
        markdown: entry.value.markdown,
        width: width,
      );
      final baseline = entry.value.realHeight;

      expect(
        real,
        closeTo(baseline, baseline * 0.06),
        reason:
            '${entry.key} 的真实渲染高度偏离基线（$baseline → $real）。'
            '若是有意改动包内布局，请更新基线并复核估算公式。',
      );

      final metrics = AgentTimelineExtentMetrics.from(
        crossAxisExtent: width,
        textScale: 1,
      );
      final estimate = estimateAgentMarkdownExtent(
        entry.value.markdown,
        width: metrics.width,
        lineHeight: metrics.lineHeight,
        scale: metrics.scale,
      );

      // 下界贴紧真实高度：低估会让锚点向上跳，是要拦的方向。
      // 上界留到 2.2 倍：高估只是多留白，且现状公式（逐源行折行 + 块间距）在
      // 测试字体下本就高估 30%~70%。
      expect(
        estimate / real,
        inInclusiveRange(0.95, 2.2),
        reason: '${entry.key} 的估算/真实比值越界（估算 $estimate，真实 $real）',
      );
    });
  }

  testWidgets('空正文不会被估成一屏', (tester) async {
    final metrics = AgentTimelineExtentMetrics.from(
      crossAxisExtent: width,
      textScale: 1,
    );
    expect(
      estimateAgentMarkdownExtent(
        '',
        width: metrics.width,
        lineHeight: metrics.lineHeight,
        scale: metrics.scale,
      ),
      lessThan(metrics.lineHeight * 2),
    );
  });
}

/// 在给定宽度下测量 markdown 子树的自然高度。
///
/// 必须放进可滚动容器：`MarkdownWidget` 在高度受限时会撑满约束，直接量会得到
/// 视口高度而不是内容高度。
Future<double> _measureNaturalHeight(
  WidgetTester tester, {
  required String markdown,
  required double width,
}) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final light = buildIdeThemeData(
    brightness: Brightness.light,
    codeFontFamily: 'CodeFont',
  );
  final dark = buildIdeThemeData(
    brightness: Brightness.dark,
    codeFontFamily: 'CodeFont',
  );
  final key = GlobalKey();

  await tester.pumpWidget(
    ProviderScope(
      child: IdeThemeScope(
        themeMode: ThemeMode.dark,
        lightTheme: light,
        darkTheme: dark,
        // 外壳与真实应用一致：代码块工具栏用 Ide* 控件（底层 shadcn Button），
        // 缺 shadcn 主题会断言失败；缺 l10n delegates 会渲染成错误组件，
        // 两种情况量到的都不是内容高度。
        child: sf.ShadcnApp(
          locale: ZetaLocalization.simplifiedChinese,
          supportedLocales: ZetaLocalization.supportedLocales,
          localizationsDelegates: ZetaLocalization.delegates,
          theme: buildShadcnTheme(dark),
          builder: (context, child) =>
              IdeMaterialLayer(theme: buildMaterialTheme(dark), child: child),
          home: sf.Scaffold(
            child: SingleChildScrollView(
              child: SizedBox(
                width: width,
                child: AgentRawMarkdownBody(key: key, data: markdown),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return tester.getSize(find.byKey(key)).height;
}

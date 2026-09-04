import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_markdown/zeta_markdown.dart';
import 'package:zeta_ui/zeta_ui.dart';

import 'package:zeta/src/features/agent/presentation/widgets/agent_pane_styles.dart';

/// 代码块配色必须全部来自 Graphite token，并且明暗主题各解析各的（G8）。
void main() {
  final light = buildIdeThemeData(
    brightness: Brightness.light,
    codeFontFamily: 'CodeFont',
  );
  final dark = buildIdeThemeData(
    brightness: Brightness.dark,
    codeFontFamily: 'CodeFont',
  );

  test('调色板逐槽位取自 token，不写死颜色', () {
    final palette = agentCodeHighlightPalette(dark.colors);

    expect(palette.keyword, dark.colors.accent);
    expect(palette.string, dark.colors.success);
    expect(palette.number, dark.colors.warning);
    expect(palette.comment, dark.colors.textTertiary);
    expect(palette.type, dark.colors.info);
    expect(palette.title, dark.colors.textPrimary);
    expect(palette.meta, dark.colors.textSecondary);
    expect(palette.punctuation, dark.colors.textSecondary);
    // link 不映射：继续跟随正文链接色。
    expect(palette.link, isNull);
  });

  test('明暗主题得到不同的调色板', () {
    expect(
      agentCodeHighlightPalette(light.colors),
      isNot(agentCodeHighlightPalette(dark.colors)),
    );
  });

  testWidgets('会话正文主题带上调色板，且同一主题下相等', (tester) async {
    late MarkdownThemeData first;
    late MarkdownThemeData second;
    await tester.pumpWidget(
      IdeThemeScope(
        themeMode: ThemeMode.dark,
        lightTheme: light,
        darkTheme: dark,
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              first = agentMarkdownTheme(context);
              second = agentMarkdownTheme(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(first.codeHighlightPalette, isNotNull);
    expect(first.codeHighlightPalette!.keyword, dark.colors.accent);
    // 值语义：两次现算的主题必须相等，否则 markdown view 每帧清空行缓存。
    expect(first, second);
  });
}

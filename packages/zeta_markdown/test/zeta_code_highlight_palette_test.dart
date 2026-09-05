import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_markdown/src/render/code_syntax_highlighter.dart';
import 'package:zeta_markdown/zeta_markdown.dart';

/// Zeta 侧新增的测试（见 `UPSTREAM.md`）：代码高亮调色板注入点。
void main() {
  const source = '''
// 注释
class Sample {
  final String name = 'zeta';
  final int count = 42;
}
''';

  Future<MarkdownThemeData> pumpTheme(WidgetTester tester) async {
    late MarkdownThemeData theme;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            theme = MarkdownThemeData.tight(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return theme;
  }

  Future<Set<Color?>> runColors(
    WidgetTester tester,
    MarkdownThemeData theme,
  ) async {
    final presentation = await tester.runAsync(
      () => const MarkdownCodeSyntaxHighlighter().buildPresentationAsync(
        source: source,
        baseStyle: theme.codeBlockStyle,
        theme: theme,
        language: 'dart',
      ),
    );
    expect(presentation, isNotNull);
    expect(presentation!.isHighlighted, isTrue);
    return presentation.runs.map((run) => run.style.color).toSet();
  }

  testWidgets('不注入时语义色仍从 linkStyle 推导', (tester) async {
    final theme = await pumpTheme(tester);
    expect(theme.codeHighlightPalette, isNull);

    final colors = await runColors(tester, theme);
    // 关键字色即 linkStyle 色，是上游的推导起点。
    expect(colors, contains(theme.linkStyle.color));
  });

  testWidgets('注入后关键字 / 字符串 / 注释走调色板色', (tester) async {
    const keyword = Color(0xFFAA0000);
    const string = Color(0xFF00AA00);
    const comment = Color(0xFF444444);

    final theme = await pumpTheme(tester);
    final baseline = await runColors(tester, theme);
    expect(baseline, isNot(contains(keyword)));
    expect(baseline, isNot(contains(string)));
    expect(baseline, isNot(contains(comment)));

    final themed = theme.copyWith(
      codeHighlightPalette: const MarkdownCodeHighlightPalette(
        keyword: keyword,
        string: string,
        comment: comment,
      ),
    );
    final colors = await runColors(tester, themed);

    expect(colors, contains(keyword));
    expect(colors, contains(string));
    expect(colors, contains(comment));
    // 未给的槽位继续走推导：与基线仍有交集（数字/类型/标题等没被覆盖）。
    // 注意 keyword 被覆盖后，linkStyle 那个原色本身就不再出现在任何 run 上——
    // 其余推导色都是它的 lerp 变体。
    expect(colors.intersection(baseline), isNotEmpty);
  });

  group('主题值语义', () {
    // 宿主通常在 build 里现算主题；MarkdownDocumentView 按 `theme !=` 决定要不要
    // 清空整份 block 行缓存，引用相等会让每帧都清（并连带炸布局断言）。
    testWidgets('相同槽位的两个调色板让主题相等', (tester) async {
      final theme = await pumpTheme(tester);
      final a = theme.copyWith(
        codeHighlightPalette: const MarkdownCodeHighlightPalette(
          keyword: Color(0xFFAA0000),
        ),
      );
      final b = theme.copyWith(
        codeHighlightPalette: const MarkdownCodeHighlightPalette(
          keyword: Color(0xFFAA0000),
        ),
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    testWidgets('槽位不同则主题不等', (tester) async {
      final theme = await pumpTheme(tester);
      final a = theme.copyWith(
        codeHighlightPalette: const MarkdownCodeHighlightPalette(
          keyword: Color(0xFFAA0000),
        ),
      );
      final b = theme.copyWith(
        codeHighlightPalette: const MarkdownCodeHighlightPalette(
          keyword: Color(0xFF00AA00),
        ),
      );

      expect(a, isNot(b));
    });
  });

  test('lerp 逐槽位插值，两侧为空返回空', () {
    const a = MarkdownCodeHighlightPalette(keyword: Color(0xFF000000));
    const b = MarkdownCodeHighlightPalette(keyword: Color(0xFFFFFFFF));

    expect(
      MarkdownCodeHighlightPalette.lerp(a, b, 0)!.keyword,
      const Color(0xFF000000),
    );
    expect(
      MarkdownCodeHighlightPalette.lerp(a, b, 1)!.keyword,
      const Color(0xFFFFFFFF),
    );
    expect(MarkdownCodeHighlightPalette.lerp(null, null, 0.5), isNull);
  });

  test('isEmpty 等价于不注入', () {
    expect(const MarkdownCodeHighlightPalette().isEmpty, isTrue);
    expect(
      const MarkdownCodeHighlightPalette(keyword: Color(0xFFAA0000)).isEmpty,
      isFalse,
    );
  });
}

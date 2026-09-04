import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_markdown/zeta_markdown.dart';

/// Zeta 侧新增的测试（见 `UPSTREAM.md`）：正文的缺省鼠标光标。
///
/// 桌面端正文 hover 应当是 I-Beam；上游给的是 `MouseCursor.defer`，落到桌面就是
/// 箭头，看起来像不可选中。
void main() {
  Set<MouseCursor> cursorsOf(WidgetTester tester) {
    return tester
        .widgetList<MouseRegion>(find.byType(MouseRegion))
        .map((region) => region.cursor)
        .toSet();
  }

  Future<void> pump(
    WidgetTester tester, {
    required bool selectable,
    String data = '一段普通正文。',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(data: data, selectable: selectable),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('可选中正文声明 I-Beam', (tester) async {
    await pump(tester, selectable: true);

    expect(cursorsOf(tester), contains(SystemMouseCursors.text));
  });

  testWidgets('不可选中时保持上游的 defer', (tester) async {
    await pump(tester, selectable: false);

    expect(cursorsOf(tester), isNot(contains(SystemMouseCursors.text)));
  });

  testWidgets('链接仍然是手型：run 自带光标在更内层，优先于块级缺省', (tester) async {
    await pump(
      tester,
      selectable: true,
      data: '正文 [链接](https://example.com) 收尾',
    );

    final richText = tester.widget<RichText>(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText && widget.text.toPlainText().contains('链接'),
      ),
    );
    final cursors = <MouseCursor?>[];
    richText.text.visitChildren((span) {
      if (span is TextSpan) {
        cursors.add(span.mouseCursor);
      }
      return true;
    });

    // 没挂 onTapLink 时链接沿用 defer（由下层决定）；挂上之后是 click。
    expect(cursors, isNotEmpty);
    expect(cursorsOf(tester), contains(SystemMouseCursors.text));
  });

  testWidgets('挂了 onTapLink 时链接 span 是手型', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '正文 [链接](https://example.com) 收尾',
            selectable: true,
            onTapLink: (destination, title, label) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final richText = tester.widget<RichText>(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText && widget.text.toPlainText().contains('链接'),
      ),
    );
    final cursors = <MouseCursor?>[];
    richText.text.visitChildren((span) {
      if (span is TextSpan) {
        cursors.add(span.mouseCursor);
      }
      return true;
    });

    expect(cursors, contains(SystemMouseCursors.click));
  });
}

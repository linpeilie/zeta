import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_markdown/zeta_markdown.dart';

/// Zeta 侧新增的测试（见 `UPSTREAM.md`）：右键菜单开关与文案注入。
void main() {
  Future<void> pump(
    WidgetTester tester, {
    bool enableContextMenu = true,
    MarkdownContextMenuLabels labels = const MarkdownContextMenuLabels(),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '一段可以选中的正文。',
            selectable: true,
            useColumn: true,
            padding: EdgeInsets.zero,
            enableContextMenu: enableContextMenu,
            contextMenuLabels: labels,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 右键点在正文上：包内是在 pointerDown 时按 secondary 键位判定的。
  Future<void> secondaryTap(WidgetTester tester) async {
    // 点在首行文字上：useColumn 时组件盒可能比内容高，取中心会落到空白处。
    final target =
        tester.getTopLeft(find.byType(MarkdownWidget)) + const Offset(20, 8);
    final gesture = await tester.startGesture(
      target,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('默认弹出菜单，自造项沿用上游英文', (tester) async {
    await pump(tester);
    await secondaryTap(tester);

    expect(find.text('Copy all'), findsOneWidget);
  });

  testWidgets('注入文案后自造项用注入值', (tester) async {
    await pump(
      tester,
      labels: const MarkdownContextMenuLabels(
        copyAll: '复制全文',
        clearSelection: '清除选区',
      ),
    );
    await secondaryTap(tester);

    expect(find.text('复制全文'), findsOneWidget);
    expect(find.text('Copy all'), findsNothing);
  });

  testWidgets('关掉开关后右键完全没有菜单', (tester) async {
    await pump(tester, enableContextMenu: false);
    await secondaryTap(tester);

    expect(find.text('Copy all'), findsNothing);
    expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
  });

  test('文案是值语义', () {
    expect(
      const MarkdownContextMenuLabels(copyAll: 'a'),
      const MarkdownContextMenuLabels(copyAll: 'a'),
    );
    expect(
      const MarkdownContextMenuLabels(copyAll: 'a'),
      isNot(const MarkdownContextMenuLabels(copyAll: 'b')),
    );
  });
}

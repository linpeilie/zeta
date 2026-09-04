import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_markdown/zeta_markdown.dart';

/// Zeta 侧新增的测试（见 `UPSTREAM.md`）：代码块工具栏注入点。
void main() {
  const source = '```dart\nvoid main() {\n  print("hi");\n}\n```\n';

  Future<void> pump(
    WidgetTester tester, {
    MarkdownCodeBlockToolbarBuilder? toolbarBuilder,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: source,
            codeBlockToolbarBuilder: toolbarBuilder,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('不注入时保持上游默认的复制按钮', (tester) async {
    await pump(tester);

    expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
  });

  testWidgets('注入后用自绘工具栏替换默认按钮，并拿到语言与行数', (tester) async {
    MarkdownCodeBlockToolbarData? seen;
    await pump(
      tester,
      toolbarBuilder: (context, data) {
        seen = data;
        return const Text('自绘工具栏');
      },
    );

    expect(find.byIcon(Icons.copy_rounded), findsNothing);
    expect(find.text('自绘工具栏'), findsOneWidget);
    expect(seen!.language, 'dart');
    expect(seen!.lineCount, 3);
    expect(seen!.theme, isNotNull);
  });

  testWidgets('builder 返回 null 表示不要工具栏', (tester) async {
    await pump(tester, toolbarBuilder: (context, data) => null);

    expect(find.byIcon(Icons.copy_rounded), findsNothing);
  });

  testWidgets('onCopy 复用默认的写剪贴板回调', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
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

    await pump(
      tester,
      toolbarBuilder: (context, data) => TextButton(
        onPressed: data.onCopy,
        child: const Text('复制'),
      ),
    );
    await tester.tap(find.text('复制'));
    await tester.pump();

    expect(copied.single.trim(), 'void main() {\n  print("hi");\n}');
  });

  testWidgets('未标注语言时 language 为 null', (tester) async {
    String? seen = 'sentinel';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '```\nplain\n```\n',
            codeBlockToolbarBuilder: (context, data) {
              seen = data.language;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(seen, isNull);
  });
}

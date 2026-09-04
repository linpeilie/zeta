import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:zeta_markdown/zeta_markdown.dart';

/// Zeta 侧新增的测试（见 `UPSTREAM.md`）：语法集注入点。
///
/// 注入点的第一要求是**默认行为零变化**，第二才是可裁剪。
void main() {
  group('默认集', () {
    test('standard 与上游两份列表逐条一致', () {
      expect(
        MarkdownSyntaxSet.standard.blockSyntaxes,
        buildMarkdownBlockSyntaxes(),
      );
      expect(
        MarkdownSyntaxSet.standard.inlineSyntaxes,
        buildMarkdownInlineSyntaxes(),
      );
    });

    test('不传语法集时表格照常解析成 table 块', () {
      final document = const MarkdownDocumentParser().parse(
        '| a | b |\n| --- | --- |\n| 1 | 2 |',
      );

      expect(
        document.blocks.map((block) => block.kind),
        contains(MarkdownBlockKind.table),
      );
    });
  });

  group('裁剪集', () {
    test('去掉 TableSyntax 后表格退化成段落', () {
      final withoutTable = MarkdownSyntaxSet(
        blockSyntaxes: MarkdownSyntaxSet.standard.blockSyntaxes
            .where((syntax) => syntax is! md.TableSyntax)
            .toList(growable: false),
        inlineSyntaxes: MarkdownSyntaxSet.standard.inlineSyntaxes,
      );

      final document = MarkdownDocumentParser(syntaxSet: withoutTable).parse(
        '| a | b |\n| --- | --- |\n| 1 | 2 |',
      );

      expect(
        document.blocks.map((block) => block.kind),
        isNot(contains(MarkdownBlockKind.table)),
      );
      expect(
        document.blocks.map((block) => block.kind),
        contains(MarkdownBlockKind.paragraph),
      );
    });

    test('裁剪同样作用于 details 内部的嵌套片段', () {
      const source = '<details>\n<summary>标题</summary>\n\n'
          '| a | b |\n| --- | --- |\n| 1 | 2 |\n\n</details>';

      final standardDocument = const MarkdownDocumentParser().parse(source);
      expect(_kindsOf(standardDocument), contains(MarkdownBlockKind.table));

      final withoutTable = MarkdownSyntaxSet(
        blockSyntaxes: MarkdownSyntaxSet.standard.blockSyntaxes
            .where((syntax) => syntax is! md.TableSyntax)
            .toList(growable: false),
        inlineSyntaxes: MarkdownSyntaxSet.standard.inlineSyntaxes,
      );
      final trimmedDocument =
          MarkdownDocumentParser(syntaxSet: withoutTable).parse(source);

      // 外层裁掉了表格，`<details>` 内部也必须跟着裁掉，否则同一份文档里
      // 两套语法并存。
      expect(
          _kindsOf(trimmedDocument), isNot(contains(MarkdownBlockKind.table)));
    });
  });

  group('controller 接线', () {
    test('MarkdownController 可直接注入语法集', () {
      final withoutTable = MarkdownSyntaxSet(
        blockSyntaxes: MarkdownSyntaxSet.standard.blockSyntaxes
            .where((syntax) => syntax is! md.TableSyntax)
            .toList(growable: false),
        inlineSyntaxes: MarkdownSyntaxSet.standard.inlineSyntaxes,
      );
      final controller = MarkdownController(
        data: '| a | b |\n| --- | --- |\n| 1 | 2 |',
        syntaxSet: withoutTable,
      );
      addTearDown(controller.dispose);

      expect(
        controller.document.blocks.map((block) => block.kind),
        isNot(contains(MarkdownBlockKind.table)),
      );
    });

    test('同时给 parser 与语法集会断言失败', () {
      expect(
        () => MarkdownController(
          parser: const MarkdownDocumentParser(),
          syntaxSet: MarkdownSyntaxSet.standard,
        ),
        throwsAssertionError,
      );
    });
  });
}

/// 递归收集块类型：details 会把内容包成嵌套块。
Iterable<MarkdownBlockKind> _kindsOf(MarkdownDocument document) sync* {
  Iterable<MarkdownBlockKind> walk(Iterable<BlockNode> blocks) sync* {
    for (final block in blocks) {
      yield block.kind;
      if (block is DetailsBlock) {
        yield* walk(block.children);
      }
    }
  }

  yield* walk(document.blocks);
}

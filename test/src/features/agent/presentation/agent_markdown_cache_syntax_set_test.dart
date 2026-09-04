import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_markdown/zeta_markdown.dart';

import 'package:zeta/src/features/agent/presentation/agent_markdown_cache.dart';

/// 语法集注入要一路通到会话正文的控制器上。
void main() {
  test('缓存默认用包内标准集：表格照常解析', () {
    final cache = AgentMarkdownCache();
    addTearDown(cache.dispose);

    final lease = cache.acquire(
      messageId: 'm1',
      data: '| a | b |\n| --- | --- |\n| 1 | 2 |',
      preferIncrementalUpdate: false,
    );
    addTearDown(lease.release);

    expect(
      lease.controller.document.blocks.map((block) => block.kind),
      contains(MarkdownBlockKind.table),
    );
  });

  test('注入裁剪集后，新建的控制器按裁剪集解析', () {
    // 极端裁剪（块级语法全空）：只为证明注入确实到达控制器，不代表推荐配置。
    // 具体裁剪哪几条语法是产品决定，见 WP-6 T5 记录。
    final cache = AgentMarkdownCache(
      syntaxSet: MarkdownSyntaxSet(
        // 从标准集过滤出空表，省得根包为了拿 md.BlockSyntax 这个类型
        // 去直接依赖 markdown 包（真要组合裁剪集时再加依赖）。
        blockSyntaxes: MarkdownSyntaxSet.standard.blockSyntaxes
            .where((_) => false)
            .toList(growable: false),
        inlineSyntaxes: MarkdownSyntaxSet.standard.inlineSyntaxes,
      ),
    );
    addTearDown(cache.dispose);

    final lease = cache.acquire(
      messageId: 'm1',
      data: '| a | b |\n| --- | --- |\n| 1 | 2 |',
      preferIncrementalUpdate: false,
    );
    addTearDown(lease.release);

    expect(
      lease.controller.document.blocks.map((block) => block.kind),
      isNot(contains(MarkdownBlockKind.table)),
    );
  });
}

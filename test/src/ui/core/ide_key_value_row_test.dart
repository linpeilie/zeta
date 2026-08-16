import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/ide_text_styles.dart';
import 'package:zeta/src/ui/core/rows/ide_key_value_row.dart';

import 'ide_component_test_harness.dart';

/// 测试宿主把 UI 与代码字体都固定成 JetBrainsMono 以保证度量确定，因此不能用
/// fontFamily 区分排版档位；改为比对语义 token 自身的字号/字重/字形特性。
final IdeTextStyles _styles = IdeTextStyles.resolve(
  colors: IdeColors.dark,
  uiFontFamily: 'JetBrainsMono',
  codeFontFamily: 'JetBrainsMono',
);

void main() {
  testWidgets('IdeKeyValueRow 的 Key 定宽、Value 同行紧随其后', (tester) async {
    await pumpIdeComponent(
      tester,
      child: const Align(
        alignment: Alignment.topLeft,
        child: IdeKeyValueRow(
          key: ValueKey('kv'),
          label: '启动命令',
          value: 'codex',
        ),
      ),
    );

    final labelBox = tester.getRect(find.text('启动命令'));
    final valueBox = tester.getRect(find.text('codex'));

    // 同一条水平线：Key 与 Value 的顶边对齐，视线不需要做纵向跳跃。
    expect((labelBox.top - valueBox.top).abs(), lessThan(1));
    // Value 从固定的竖轴起排：Key 列宽 + 间隙。
    expect(
      valueBox.left - labelBox.left,
      IdeMetrics.keyValueLabelWidth + IdeSpacing.space8,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('kv'))).height,
      greaterThanOrEqualTo(IdeMetrics.compactRowHeight),
    );
  });

  testWidgets('IdeKeyValueRow 在窄宽度下也不堆叠', (tester) async {
    await pumpIdeComponent(
      tester,
      // 远小于 IdeSettingsRow 的 stackedRowBreakpoint(640)：同行阅读是这个原语
      // 存在的理由，任何宽度都不能退化成上下两行。
      size: const Size(320, 240),
      child: const Align(
        alignment: Alignment.topLeft,
        child: IdeKeyValueRow(label: '可执行文件路径', value: '/usr/local/bin/codex'),
      ),
    );

    expect(
      (tester.getRect(find.text('可执行文件路径')).top -
              tester.getRect(find.text('/usr/local/bin/codex')).top)
          .abs(),
      lessThan(1),
    );
  });

  testWidgets('IdeKeyValueRow 的 Key 走次级色，四种 tone 命中对应排版 token', (tester) async {
    await pumpIdeComponent(
      tester,
      child: const Align(
        alignment: Alignment.topLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            IdeKeyValueRow(label: '厂商', value: 'OpenAI'),
            IdeKeyValueRow(
              label: '名称',
              value: 'Codex',
              tone: IdeKeyValueTone.identifier,
            ),
            IdeKeyValueRow(
              label: '路径',
              value: '/usr/local/bin/codex',
              tone: IdeKeyValueTone.code,
            ),
            IdeKeyValueRow(
              label: '耗时',
              value: '120 ms',
              tone: IdeKeyValueTone.numeric,
            ),
          ],
        ),
      ),
    );

    TextStyle styleOf(String text) =>
        tester.widget<Text>(find.text(text)).style!;

    // Key 明确弱于 Value：同字号但退到次级色，扫视时先落在值上。
    expect(styleOf('厂商').color, IdeColors.dark.textSecondary);
    expect(styleOf('厂商').fontSize, _styles.titleSmall.fontSize);

    expect(styleOf('OpenAI').fontSize, _styles.bodySmall.fontSize);
    expect(styleOf('OpenAI').fontWeight, _styles.bodySmall.fontWeight);

    expect(styleOf('Codex').fontSize, _styles.identifier.fontSize);
    expect(styleOf('Codex').fontWeight, _styles.identifier.fontWeight);

    expect(styleOf('/usr/local/bin/codex').color, _styles.codeSmall.color);
    expect(
      styleOf('/usr/local/bin/codex').fontSize,
      _styles.codeSmall.fontSize,
    );

    // 数值档必须带 tabularFigures，多行版本号才会按位对齐。
    expect(styleOf('120 ms').fontFeatures, _styles.numeric.fontFeatures);
    expect(styleOf('120 ms').fontFeatures, isNotEmpty);
  });

  testWidgets('IdeKeyValueRow 支持 valueColor 覆盖与 trailing 操作', (tester) async {
    var taps = 0;
    await pumpIdeComponent(
      tester,
      child: Align(
        alignment: Alignment.topLeft,
        child: IdeKeyValueRow(
          label: '最新版本',
          value: '0.144.5',
          tone: IdeKeyValueTone.numeric,
          valueColor: IdeColors.dark.warning,
          trailing: IconButton(
            key: const ValueKey('kv-trailing'),
            onPressed: () => taps += 1,
            icon: const Icon(Icons.copy_rounded, size: 14),
          ),
        ),
      ),
    );

    expect(
      tester.widget<Text>(find.text('0.144.5')).style?.color,
      IdeColors.dark.warning,
    );
    await tester.tap(find.byKey(const ValueKey('kv-trailing')));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('IdeKeyValueRow 的 selectable 值可被选中复制', (tester) async {
    await pumpIdeComponent(
      tester,
      child: const Align(
        alignment: Alignment.topLeft,
        child: IdeKeyValueRow(
          label: '可执行文件路径',
          value: '/usr/local/bin/codex',
          tone: IdeKeyValueTone.code,
          selectable: true,
        ),
      ),
    );

    expect(find.byType(SelectableText), findsOneWidget);
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      '/usr/local/bin/codex',
    );
  });
}

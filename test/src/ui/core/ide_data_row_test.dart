import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_text_styles.dart';
import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/rows/ide_data_row.dart';

import 'ide_component_test_harness.dart';

void main() {
  testWidgets('IdeDataRow 保持紧凑密度并响应整行点击', (tester) async {
    var taps = 0;
    await pumpIdeComponent(
      tester,
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 420,
          child: IdeDataRow(
            key: const ValueKey('data-row'),
            values: const ['Codex', '24', '98.5%'],
            flexes: const [3, 2, 2],
            onPressed: () => taps += 1,
          ),
        ),
      ),
    );

    expect(find.text('Codex'), findsOneWidget);
    expect(find.text('98.5%'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('data-row'))).height,
      greaterThanOrEqualTo(IdeMetrics.compactRowHeight),
    );

    await tester.tap(find.byKey(const ValueKey('data-row')));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('IdeDataRow 表头使用相同列宽并支持长文本省略', (tester) async {
    await pumpIdeComponent(
      tester,
      child: SizedBox(
        width: 240,
        child: IdeDataRow(
          values: const ['一个很长的统计字段名称', '调用次数'],
          flexes: const [1, 1],
          header: true,
        ),
      ),
    );

    final label = tester.widget<Text>(find.text('一个很长的统计字段名称'));
    expect(label.maxLines, 1);
    expect(label.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  testWidgets('数值列右对齐并使用等宽数字，标识符列使用等宽字体', (tester) async {
    await pumpIdeComponent(
      tester,
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 420,
          child: IdeDataRow(
            values: const ['gpt-5-codex', '1,204', '普通文本'],
            flexes: const [3, 2, 2],
            identifierColumns: const {0},
            numericColumns: const {1},
          ),
        ),
      ),
    );

    // 测试宿主把 UI 与代码字体都固定成同一个内置族，因此这里按
    // token 的结构特征断言，而不是按字体族名。
    final styles = IdeTextStyles.resolve(colors: IdeColors.dark);
    final identifier = tester.widget<Text>(find.text('gpt-5-codex'));
    final numeric = tester.widget<Text>(find.text('1,204'));
    final plain = tester.widget<Text>(find.text('普通文本'));

    // 标识符列：走 identifier token，保持左对齐。
    expect(identifier.style?.fontSize, styles.identifier.fontSize);
    expect(identifier.textAlign, TextAlign.left);

    // 数值列：tabularFigures + 右对齐。
    expect(
      numeric.style?.fontFeatures,
      contains(const FontFeature.tabularFigures()),
    );
    expect(numeric.style?.fontSize, styles.numeric.fontSize);
    expect(numeric.textAlign, TextAlign.right);

    // 未标注的列保持普通正文样式与左对齐。
    expect(plain.style?.fontSize, styles.bodySmall.fontSize);
    expect(plain.style?.fontFeatures, isNull);
    expect(plain.textAlign, TextAlign.left);
  });

  testWidgets('表头即使标注了数值列也保持工具栏标签样式', (tester) async {
    await pumpIdeComponent(
      tester,
      child: SizedBox(
        width: 420,
        child: IdeDataRow(
          values: const ['模型', 'Token'],
          flexes: const [3, 2],
          header: true,
          numericColumns: const {1},
        ),
      ),
    );

    // 表头跟随数值列右对齐以对齐列轴，但不切换成等宽数字样式。
    final styles = IdeTextStyles.resolve(colors: IdeColors.dark);
    final headerCell = tester.widget<Text>(find.text('Token'));
    expect(headerCell.textAlign, TextAlign.right);
    expect(headerCell.style?.fontSize, styles.toolbarLabel.fontSize);
    expect(headerCell.style?.fontFeatures, isNull);
  });
}

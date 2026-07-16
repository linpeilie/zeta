import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}

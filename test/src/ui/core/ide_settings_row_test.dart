import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/rows/ide_settings_row.dart';

import 'ide_component_test_harness.dart';

void main() {
  testWidgets('中宽屏设置项内联对齐', (tester) async {
    await pumpIdeComponent(
      tester,
      size: const Size(640, 300),
      child: const Align(
        alignment: Alignment.topCenter,
        child: IdeSettingsRow(
          key: ValueKey('settings-row'),
          label: 'Theme',
          description: 'Choose the application appearance.',
          control: SizedBox(
            key: ValueKey('settings-control'),
            width: 120,
            child: Text('System'),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('ide-settings-row-inline')), findsOne);
    expect(
      find.byKey(const ValueKey('ide-settings-row-stacked')),
      findsNothing,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('settings-row'))).height,
      greaterThanOrEqualTo(IdeMetrics.settingsRowMinHeight),
    );
  });

  testWidgets('窄屏设置项堆叠且控件位于说明下方', (tester) async {
    await pumpIdeComponent(
      tester,
      size: const Size(639, 300),
      child: const Align(
        alignment: Alignment.topCenter,
        child: IdeSettingsRow(
          label: 'Theme',
          description: 'Choose the application appearance.',
          control: SizedBox(
            key: ValueKey('settings-control'),
            width: 120,
            child: Text('System'),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('ide-settings-row-stacked')), findsOne);
    expect(find.byKey(const ValueKey('ide-settings-row-inline')), findsNothing);
    final labelBottom = tester
        .getBottomLeft(find.byKey(const ValueKey('ide-settings-row-label')))
        .dy;
    final controlTop = tester
        .getTopLeft(find.byKey(const ValueKey('settings-control')))
        .dy;
    expect(controlTop, greaterThan(labelBottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('主标题与描述拉开字重与明度对比', (tester) async {
    await pumpIdeComponent(
      tester,
      size: const Size(640, 300),
      child: const Align(
        alignment: Alignment.topCenter,
        child: IdeSettingsRow(
          label: 'Theme',
          description: 'Choose the application appearance.',
          control: SizedBox(width: 120, child: Text('System')),
        ),
      ),
    );

    final title = tester.widget<Text>(find.text('Theme')).style!;
    final description = tester
        .widget<Text>(find.text('Choose the application appearance.'))
        .style!;

    expect(title.fontWeight, FontWeight.w600);
    expect(title.color, IdeColors.dark.textPrimary);
    expect(description.fontWeight, FontWeight.w400);
    expect(description.color, IdeColors.dark.textTertiary);
  });

  testWidgets('平铺内边距去掉横向缩进，只保留上下留白', (tester) async {
    await pumpIdeComponent(
      tester,
      size: const Size(640, 300),
      child: const Align(
        alignment: Alignment.topCenter,
        child: IdeSettingsRow(
          key: ValueKey('settings-row'),
          label: 'Theme',
          description: 'Choose the application appearance.',
          padding: IdeSpacing.settingsRowPaddingFlat,
          control: SizedBox(width: 120, child: Text('System')),
        ),
      ),
    );

    final rowLeft = tester
        .getTopLeft(find.byKey(const ValueKey('settings-row')))
        .dx;
    final labelLeft = tester
        .getTopLeft(find.byKey(const ValueKey('ide-settings-row-label')))
        .dx;
    expect(labelLeft, rowLeft);
  });
}

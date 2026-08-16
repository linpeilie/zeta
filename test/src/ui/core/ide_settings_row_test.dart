import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/rows/ide_row_divider.dart';
import 'package:zeta/src/ui/core/rows/ide_settings_row.dart';

import 'ide_component_test_harness.dart';

/// 分隔线的缩进画在 [IdeRowDivider] 自己的盒子内部（与 Flutter `Divider` 一致），
/// 所以要量真正上色的那条线，而不是外层 Widget 的边界。
Finder _dividerLine() => find.descendant(
  of: find.byType(IdeRowDivider),
  matching: find.byType(ColoredBox),
);

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

  testWidgets('主标题与描述拉开字号、字重与明度三档对比', (tester) async {
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
    // 描述比主标题小一号，行高也更紧，退成「需要时才读」的第二层。
    expect(description.fontSize, lessThan(title.fontSize!));
    expect(description.height, 1.25);
    expect(description.height, lessThan(title.height!));
  });

  testWidgets('分割线起点缩进到主标题左边缘，不贴行的外沿', (tester) async {
    await pumpIdeComponent(
      tester,
      size: const Size(640, 300),
      child: const Align(
        alignment: Alignment.topCenter,
        child: IdeSettingsRow(
          key: ValueKey('settings-row'),
          label: 'Theme',
          description: 'Choose the application appearance.',
          control: SizedBox(width: 120, child: Text('System')),
        ),
      ),
    );

    final rowRect = tester.getRect(find.byKey(const ValueKey('settings-row')));
    final labelLeft = tester
        .getTopLeft(find.byKey(const ValueKey('ide-settings-row-label')))
        .dx;
    final dividerRect = tester.getRect(_dividerLine());

    expect(dividerRect.left, labelLeft);
    expect(dividerRect.left, greaterThan(rowRect.left));
    // 右端贯通到行的外沿，保持连续几行读起来是一叠。
    expect(dividerRect.right, rowRect.right);
  });

  testWidgets('平铺行内边距为零时分割线与主标题一起顶到外沿', (tester) async {
    await pumpIdeComponent(
      tester,
      size: const Size(640, 300),
      child: const Align(
        alignment: Alignment.topCenter,
        child: IdeSettingsRow(
          key: ValueKey('settings-row'),
          label: 'Theme',
          padding: IdeSpacing.settingsRowPaddingFlat,
          control: SizedBox(width: 120, child: Text('System')),
        ),
      ),
    );

    final rowLeft = tester
        .getRect(find.byKey(const ValueKey('settings-row')))
        .left;
    final labelLeft = tester
        .getTopLeft(find.byKey(const ValueKey('ide-settings-row-label')))
        .dx;

    expect(tester.getRect(_dividerLine()).left, labelLeft);
    expect(labelLeft, rowLeft);
  });

  testWidgets('showDivider 为 false 时不画线', (tester) async {
    await pumpIdeComponent(
      tester,
      size: const Size(640, 300),
      child: const Align(
        alignment: Alignment.topCenter,
        child: IdeSettingsRow(
          label: 'Theme',
          showDivider: false,
          control: SizedBox(width: 120, child: Text('System')),
        ),
      ),
    );

    expect(find.byType(IdeRowDivider), findsNothing);
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

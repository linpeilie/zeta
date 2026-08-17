import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta/src/ui/core/ide_button.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/ide_text_styles.dart';

import 'ide_component_test_harness.dart';

void main() {
  testWidgets('IdeButton 使用 bodySmall 字号并响应点击', (tester) async {
    var presses = 0;

    await pumpIdeComponent(
      tester,
      child: Align(
        alignment: Alignment.center,
        child: IdeButton(
          key: const ValueKey('sample-button'),
          label: '刷新',
          leadingIcon: Icons.refresh_rounded,
          onPressed: () => presses += 1,
        ),
      ),
    );

    final label = tester.widget<Text>(find.text('刷新'));
    final expectedSize = IdeTextStyles.of(
      tester.element(find.text('刷新')),
    ).bodySmall.fontSize;
    expect(label.style?.fontSize, expectedSize);
    expect(find.byType(sf.Button), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sample-button')));
    await tester.pump();
    expect(presses, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('IdeButton.toolbar 使用常规控件高度', (tester) async {
    await pumpIdeComponent(
      tester,
      child: const Align(
        alignment: Alignment.center,
        child: IdeButton.toolbar(
          key: ValueKey('toolbar-button'),
          label: '筛选',
          leadingIcon: Icons.calendar_month_rounded,
          trailingIcon: Icons.keyboard_arrow_down_rounded,
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('toolbar-button'))).height,
      closeTo(
        IdeMetrics.controlNaturalHeightFor(
          IdeTextStyles.of(
            tester.element(find.byKey(const ValueKey('toolbar-button'))),
          ).bodySmall,
          size: IdeControlSize.regular,
        ),
        0.01,
      ),
    );
    expect(find.byIcon(Icons.calendar_month_rounded), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('IdeButton 禁用时不触发 onPressed', (tester) async {
    var presses = 0;

    await pumpIdeComponent(
      tester,
      child: Align(
        alignment: Alignment.center,
        child: IdeButton(
          key: const ValueKey('disabled-button'),
          label: '不可点',
          enabled: false,
          onPressed: () => presses += 1,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('disabled-button')));
    await tester.pump();
    expect(presses, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('primary 按钮文字与前置图标都使用 onAccent', (tester) async {
    await pumpIdeComponent(
      tester,
      child: const Align(
        alignment: Alignment.center,
        child: IdeButton(
          key: ValueKey('primary-button'),
          label: '允许',
          variant: IdeButtonVariant.primary,
          leadingIcon: Icons.check_rounded,
          onPressed: _noop,
        ),
      ),
    );

    final colors = IdeColors.of(tester.element(find.text('允许')));
    expect(tester.widget<Text>(find.text('允许')).style?.color, colors.onAccent);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.check_rounded)).color,
      colors.onAccent,
    );
  });
}

void _noop() {}

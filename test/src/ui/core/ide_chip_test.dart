import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta/src/ui/core/ide_chip.dart';

import 'ide_component_test_harness.dart';

void main() {
  testWidgets('IdeChip 基于 sf.Chip 渲染标签与 leading 图标', (tester) async {
    await pumpIdeComponent(
      tester,
      child: const Align(
        alignment: Alignment.center,
        child: IdeChip(
          key: ValueKey('sample-chip'),
          label: 'Models',
          leadingIcon: Icons.memory_rounded,
        ),
      ),
    );

    expect(find.byType(sf.Chip), findsOneWidget);
    expect(find.text('Models'), findsOneWidget);
    expect(find.byIcon(Icons.memory_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('IdeChip 在启用时响应点击，禁用时忽略', (tester) async {
    var enabledPresses = 0;
    var disabledPresses = 0;

    await pumpIdeComponent(
      tester,
      child: Align(
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IdeChip(
              key: const ValueKey('enabled-chip'),
              label: 'Enabled',
              onPressed: () => enabledPresses += 1,
            ),
            const SizedBox(height: 8),
            IdeChip(
              key: const ValueKey('disabled-chip'),
              label: 'Disabled',
              enabled: false,
              onPressed: () => disabledPresses += 1,
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('enabled-chip')));
    await tester.tap(find.byKey(const ValueKey('disabled-chip')));
    await tester.pump();

    expect(enabledPresses, 1);
    expect(disabledPresses, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('IdeChip 删除按钮触发 onDeleted 且不依赖整颗 chip 点击', (tester) async {
    var presses = 0;
    var deletes = 0;

    await pumpIdeComponent(
      tester,
      child: Align(
        alignment: Alignment.center,
        child: IdeChip(
          key: const ValueKey('deletable-chip'),
          label: 'Tag',
          onPressed: () => presses += 1,
          onDeleted: () => deletes += 1,
        ),
      ),
    );

    expect(find.byType(sf.ChipButton), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();

    expect(deletes, 1);
    expect(presses, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('IdeChip 选中态使用 primary 样式', (tester) async {
    await pumpIdeComponent(
      tester,
      child: const Align(
        alignment: Alignment.center,
        child: IdeChip(
          key: ValueKey('selected-chip'),
          label: 'Selected',
          selected: true,
          onPressed: _noop,
        ),
      ),
    );

    final chip = tester.widget<sf.Chip>(find.byType(sf.Chip));
    expect(chip.style, isA<sf.ButtonStyle>());
    final style = chip.style! as sf.ButtonStyle;
    expect(identical(style.variance, sf.ButtonVariance.primary), isTrue);
    expect(tester.takeException(), isNull);
  });
}

void _noop() {}

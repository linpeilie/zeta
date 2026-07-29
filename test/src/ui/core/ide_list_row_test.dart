import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_effects.dart';
import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/rows/ide_list_row.dart';

import 'ide_component_test_harness.dart';

void main() {
  testWidgets('IdeListRow 呈现紧凑内容、选中态并响应点击', (tester) async {
    var taps = 0;
    await pumpIdeComponent(
      tester,
      child: Align(
        alignment: Alignment.topCenter,
        child: IdeListRow(
          key: const ValueKey('list-row'),
          title: 'Thread title',
          subtitle: 'Updated now',
          leading: const Icon(Icons.chat_bubble_outline),
          trailing: const Text('3'),
          selected: true,
          onPressed: () => taps += 1,
        ),
      ),
    );

    expect(find.text('Thread title'), findsOneWidget);
    expect(find.text('Updated now'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('list-row'))).height,
      greaterThanOrEqualTo(IdeMetrics.listRowHeight),
    );
    final decoration = _surfaceDecoration(tester);
    expect(decoration.color, IdeColors.dark.selectedSurface);
    expect(decoration.borderRadius, IdeRadius.allSmall);

    await tester.tap(find.byKey(const ValueKey('list-row')));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('IdeListRow hover 背景使用设计系统小圆角', (tester) async {
    await pumpIdeComponent(
      tester,
      child: Align(
        alignment: Alignment.topCenter,
        child: IdeListRow(
          key: const ValueKey('list-row'),
          title: 'Hover row',
          onPressed: () {},
        ),
      ),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('list-row'))),
    );
    await tester.pumpAndSettle();

    final decoration = _surfaceDecoration(tester);
    expect(decoration.color, IdeColors.dark.hoverSurface);
    expect(decoration.borderRadius, IdeRadius.allSmall);
  });

  testWidgets('禁用的 IdeListRow 保留按钮语义但不会触发回调', (tester) async {
    var taps = 0;
    await pumpIdeComponent(
      tester,
      child: Align(
        alignment: Alignment.topCenter,
        child: IdeListRow(
          key: const ValueKey('list-row'),
          title: 'Unavailable thread',
          enabled: false,
          onPressed: () => taps += 1,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('list-row')));
    await tester.pump();
    expect(taps, 0);
    expect(_surfaceDecoration(tester).color, Colors.transparent);
    expect(
      tester.widget<Text>(find.text('Unavailable thread')).style?.color,
      IdeColors.dark.textTertiary,
    );
  });
}

BoxDecoration _surfaceDecoration(WidgetTester tester) {
  final animatedContainer = tester.widget<AnimatedContainer>(
    find.descendant(
      of: find.byKey(const ValueKey('list-row')),
      matching: find.byType(AnimatedContainer),
    ),
  );
  return animatedContainer.decoration! as BoxDecoration;
}

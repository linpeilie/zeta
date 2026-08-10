import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_effects.dart';
import 'package:zeta/src/ui/core/surfaces/ide_surface.dart';

import 'ide_component_test_harness.dart';

void main() {
  testWidgets('IdeSurface 为四级表面应用统一装饰', (tester) async {
    await pumpIdeComponent(
      tester,
      child: const Column(
        children: [
          Expanded(
            child: IdeSurface.canvas(
              key: ValueKey('canvas-surface'),
              child: Text('Canvas'),
            ),
          ),
          Expanded(
            child: IdeSurface.pane(
              key: ValueKey('pane-surface'),
              child: Text('Pane'),
            ),
          ),
          Expanded(
            child: IdeSurface.row(
              key: ValueKey('row-surface'),
              child: Text('Row'),
            ),
          ),
          Expanded(
            child: IdeSurface.popover(
              key: ValueKey('popover-surface'),
              child: Text('Popover'),
            ),
          ),
        ],
      ),
    );

    expect(
      _decorationOf(tester, 'canvas-surface').color,
      IdeColors.dark.editor,
    );
    expect(_foregroundDecorationOf(tester, 'canvas-surface'), isNull);
    expect(_decorationOf(tester, 'pane-surface').color, IdeColors.dark.surface);
    expect(_foregroundDecorationOf(tester, 'pane-surface')?.border, isNotNull);
    // 面板与浮层同属圆角嵌套链路的最外层。
    expect(
      _foregroundDecorationOf(tester, 'pane-surface')?.borderRadius,
      IdeRadius.allLarge,
    );
    expect(_decorationOf(tester, 'row-surface').color, Colors.transparent);
    expect(_foregroundDecorationOf(tester, 'row-surface'), isNull);
    expect(
      _decorationOf(tester, 'popover-surface').borderRadius,
      IdeRadius.allLarge,
    );
    expect(
      _foregroundDecorationOf(tester, 'popover-surface')?.border,
      isNotNull,
    );
    expect(_decorationOf(tester, 'popover-surface').boxShadow, isNotEmpty);
  });
}

BoxDecoration _decorationOf(WidgetTester tester, String key) {
  return _containerOf(tester, key).decoration! as BoxDecoration;
}

BoxDecoration? _foregroundDecorationOf(WidgetTester tester, String key) {
  final decoration = _containerOf(tester, key).foregroundDecoration;
  return decoration as BoxDecoration?;
}

Container _containerOf(WidgetTester tester, String key) {
  return tester.widget<Container>(
    find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byType(Container),
    ),
  );
}

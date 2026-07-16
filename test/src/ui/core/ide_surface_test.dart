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
    expect(_decorationOf(tester, 'canvas-surface').border, isNull);
    expect(_decorationOf(tester, 'pane-surface').color, IdeColors.dark.surface);
    expect(_decorationOf(tester, 'pane-surface').border, isNotNull);
    expect(
      _decorationOf(tester, 'pane-surface').borderRadius,
      IdeRadius.allMedium,
    );
    expect(_decorationOf(tester, 'row-surface').color, Colors.transparent);
    expect(_decorationOf(tester, 'row-surface').border, isNull);
    expect(
      _decorationOf(tester, 'popover-surface').borderRadius,
      IdeRadius.allLarge,
    );
    expect(_decorationOf(tester, 'popover-surface').boxShadow, isNotEmpty);
  });
}

BoxDecoration _decorationOf(WidgetTester tester, String key) {
  final container = tester.widget<Container>(
    find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byType(Container),
    ),
  );
  return container.decoration! as BoxDecoration;
}

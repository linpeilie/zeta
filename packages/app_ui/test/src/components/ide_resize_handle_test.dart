import 'dart:ui';

import 'package:app_ui/app_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/helpers.dart';

void main() {
  group('IdeResizeHandle', () {
    testWidgets('horizontal handle supports pointer and arrow keys', (
      tester,
    ) async {
      final deltas = <Offset>[];
      await tester.pumpShadcnApp(
        SizedBox(
          height: 100,
          child: IdeResizeHandle(
            axis: IdeResizeHandleAxis.horizontal,
            semanticLabel: 'Resize pane',
            keyboardStep: 10,
            onDragUpdate: (details) => deltas.add(details.delta),
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byType(IdeResizeHandle)));
      await tester.pump();
      await mouse.moveTo(const Offset(790, 590));
      await mouse.removePointer();
      await tester.drag(find.byType(IdeResizeHandle), const Offset(20, 0));
      await tester.pump();
      expect(deltas, isNotEmpty);
      expect(deltas.first, const Offset(10, 0));
    });

    testWidgets('vertical handle supports callbacks and arrow keys', (
      tester,
    ) async {
      final deltas = <Offset>[];
      var starts = 0;
      var ends = 0;
      await tester.pumpShadcnApp(
        SizedBox(
          width: 100,
          child: IdeResizeHandle(
            axis: IdeResizeHandleAxis.vertical,
            thickness: 10,
            onDragStart: (_) => starts += 1,
            onDragUpdate: (details) => deltas.add(details.delta),
            onDragEnd: (_) => ends += 1,
            onDragCancel: () {},
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.drag(find.byType(IdeResizeHandle), const Offset(0, 20));
      await tester.pump();
      expect(deltas, isNotEmpty);
      expect(starts, 1);
      expect(ends, 1);
    });
  });
}

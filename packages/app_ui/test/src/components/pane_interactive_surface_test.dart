import 'dart:ui';

import 'package:app_ui/app_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/helpers.dart';

void main() {
  group('PaneInteractiveSurface', () {
    testWidgets('supports pointer, focus, keyboard, and state callbacks', (
      tester,
    ) async {
      var activations = 0;
      final hover = <bool>[];
      final focus = <bool>[];
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpShadcnApp(
        PaneInteractiveSurface(
          semanticLabel: 'Open',
          focusNode: node,
          autofocus: true,
          selected: true,
          width: 120,
          height: 48,
          padding: const EdgeInsets.all(4),
          onHoverChanged: hover.add,
          onFocusChanged: focus.add,
          onPressed: () => activations += 1,
          child: const Text('Open'),
        ),
      );
      await tester.pump();
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      await gesture.moveTo(tester.getCenter(find.text('Open')));
      await tester.pump();
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await gesture.moveTo(const Offset(790, 590));
      await gesture.removePointer();

      expect(activations, 2);
      expect(hover, containsAllInOrder(<bool>[true, false]));
      expect(focus, contains(true));
    });

    testWidgets('renders content-sized disabled surface', (tester) async {
      await tester.pumpShadcnApp(
        const PaneInteractiveSurface(
          enabled: false,
          selected: true,
          expandToConstraints: false,
          alignment: Alignment.topLeft,
          backgroundColor: Colors.black,
          hoverBackgroundColor: Colors.red,
          pressedBackgroundColor: Colors.green,
          selectedBackgroundColor: Colors.blue,
          selectedHoverBackgroundColor: Colors.yellow,
          borderColor: Colors.white,
          focusBorderColor: Colors.purple,
          selectedBorderColor: Colors.orange,
          borderRadius: BorderRadius.all(Radius.circular(2)),
          child: Text('Disabled'),
        ),
      );

      await tester.tap(find.text('Disabled'));
      expect(find.text('Disabled'), findsOneWidget);
    });

    testWidgets('shows the non-selected hover surface', (tester) async {
      await tester.pumpShadcnApp(
        PaneInteractiveSurface(
          onPressed: () {},
          child: const Text('Hover'),
        ),
      );
      tester
          .widget<FocusableActionDetector>(find.byType(FocusableActionDetector))
          .onShowHoverHighlight
          ?.call(true);
      await tester.pump();

      expect(find.text('Hover'), findsOneWidget);
    });
  });
}

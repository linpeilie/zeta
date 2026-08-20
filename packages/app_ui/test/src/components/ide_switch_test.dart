import 'package:app_ui/app_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/helpers.dart';

void main() {
  group('IdeSwitch', () {
    testWidgets('toggles by pointer and keyboard', (tester) async {
      final values = <bool>[];
      await tester.pumpShadcnApp(
        IdeSwitch(
          value: false,
          semanticLabel: 'Notifications',
          onChanged: values.add,
        ),
      );

      await tester.tap(find.byType(IdeSwitch));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(values, <bool>[true, true]);
    });

    testWidgets('renders on and disabled states', (tester) async {
      await tester.pumpShadcnApp(
        const IdeSwitch(value: true, enabled: false, onChanged: null),
        brightness: Brightness.dark,
      );

      await tester.tap(find.byType(IdeSwitch));
      await tester.pump();
      expect(tester.getSize(find.byType(IdeSwitch)).shortestSide, 24);

      await tester.pumpShadcnApp(
        IdeSwitch(value: true, onChanged: (_) {}),
      );
      expect(find.byType(IdeSwitch), findsOneWidget);

      await tester.pumpShadcnApp(
        const IdeSwitch(value: false, enabled: false, onChanged: null),
      );
      expect(find.byType(IdeSwitch), findsOneWidget);
    });
  });
}

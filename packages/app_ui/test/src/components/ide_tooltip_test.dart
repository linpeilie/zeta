import 'package:app_ui/app_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/helpers.dart';

void main() {
  group('IdeTooltip', () {
    testWidgets('wraps enabled non-empty copy in Tooltip', (tester) async {
      await tester.pumpShadcnApp(
        const IdeTooltip(
          message: 'Refresh',
          waitDuration: Duration.zero,
          child: Text('Child'),
        ),
      );

      expect(find.byType(Tooltip), findsOneWidget);
      expect(find.text('Child'), findsOneWidget);
    });

    testWidgets('returns its child when disabled or blank', (tester) async {
      await tester.pumpShadcnApp(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IdeTooltip(message: 'Hidden', enabled: false, child: Text('A')),
            IdeTooltip(message: ' ', child: Text('B')),
          ],
        ),
      );

      expect(find.byType(Tooltip), findsNothing);
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
    });
  });
}

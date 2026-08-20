import 'package:app_ui/app_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/helpers.dart';

void main() {
  group('IdeStatusCard', () {
    for (final tone in IdeStatusCardTone.values) {
      testWidgets('renders $tone', (tester) async {
        await tester.pumpShadcnApp(
          IdeStatusCard(
            tone: tone,
            title: 'Status',
            body: const Text('Body'),
            footer: const Text('Footer'),
          ),
        );

        expect(find.text('Status'), findsOneWidget);
        expect(find.text('Body'), findsOneWidget);
        expect(find.text('Footer'), findsOneWidget);
      });
    }

    testWidgets('supports custom content and insets', (tester) async {
      await tester.pumpShadcnApp(
        const IdeStatusCard(
          tone: IdeStatusCardTone.info,
          title: 'Custom',
          leading: Icon(Icons.star),
          margin: EdgeInsets.zero,
          padding: EdgeInsets.zero,
        ),
      );

      expect(find.byIcon(Icons.star), findsOneWidget);
    });
  });
}

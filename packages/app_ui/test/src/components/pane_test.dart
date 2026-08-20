import 'package:app_ui/app_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/helpers.dart';

void main() {
  group('Pane', () {
    testWidgets('renders title, subtitle, trailing, and body', (tester) async {
      await tester.pumpShadcnApp(
        const SizedBox(
          width: 300,
          height: 200,
          child: Pane(
            title: 'Files',
            subtitle: '3 items',
            trailing: Icon(Icons.add),
            child: Text('Body'),
          ),
        ),
      );

      expect(find.text('Files'), findsOneWidget);
      expect(find.text('3 items'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.text('Body'), findsOneWidget);
    });

    testWidgets('supports a custom or absent header', (tester) async {
      await tester.pumpShadcnApp(
        const Row(
          children: <Widget>[
            Expanded(
              child: Pane(titleContent: Text('Custom'), child: Text('One')),
            ),
            Expanded(child: Pane(child: Text('Two'))),
          ],
        ),
      );

      expect(find.text('Custom'), findsOneWidget);
      expect(find.text('Two'), findsOneWidget);
    });
  });

  testWidgets('EmptyState renders caller copy', (tester) async {
    await tester.pumpShadcnApp(const EmptyState(text: 'No items'));
    expect(find.text('No items'), findsOneWidget);
  });

  testWidgets('StateLabel renders caller copy and color', (tester) async {
    await tester.pumpShadcnApp(
      const StateLabel(text: 'Ready', color: Colors.green),
    );
    expect(find.text('Ready'), findsOneWidget);
    expect(
      tester.getSize(find.byType(StateLabel)).height,
      greaterThanOrEqualTo(24),
    );
  });
}

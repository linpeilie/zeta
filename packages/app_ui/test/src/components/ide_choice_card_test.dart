import 'package:app_ui/app_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/helpers.dart';

void main() {
  group('IdeChoiceCard', () {
    testWidgets('renders and activates selected and unselected choices', (
      tester,
    ) async {
      var presses = 0;
      await tester.pumpShadcnApp(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IdeChoiceCard(
              label: 'A',
              icon: Icons.looks_one,
              selected: true,
              semanticLabel: 'Choice A',
              onPressed: () => presses += 1,
            ),
            IdeChoiceCard(
              label: 'B',
              icon: Icons.looks_two,
              onPressed: () => presses += 1,
            ),
          ],
        ),
      );

      await tester.tap(find.text('A'));
      await tester.tap(find.text('B'));
      expect(presses, 2);
    });

    testWidgets('disabled choice ignores activation', (tester) async {
      await tester.pumpShadcnApp(
        const IdeChoiceCard(
          label: 'Disabled',
          icon: Icons.block,
          enabled: false,
          selected: true,
        ),
      );
      expect(find.text('Disabled'), findsOneWidget);
    });
  });

  group('IdeChoiceCardGroup', () {
    testWidgets('wraps options and reports selected values', (tester) async {
      final values = <int>[];
      await tester.pumpShadcnApp(
        IdeChoiceCardGroup<int>(
          value: 1,
          cardWidth: 100,
          onChanged: values.add,
          options: const <IdeChoiceCardOption<int>>[
            IdeChoiceCardOption<int>(
              value: 1,
              label: 'One',
              icon: Icons.looks_one,
              semanticLabel: 'First',
              key: ValueKey<String>('one'),
            ),
            IdeChoiceCardOption<int>(
              value: 2,
              label: 'Two',
              icon: Icons.looks_two,
            ),
          ],
        ),
      );

      await tester.tap(find.text('Two'));
      expect(values, <int>[2]);
    });
  });
}

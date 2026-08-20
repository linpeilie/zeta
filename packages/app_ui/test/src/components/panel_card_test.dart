import 'package:app_ui/app_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/helpers.dart';

void main() {
  group('PanelCard', () {
    testWidgets('renders the default smooth panel tier', (tester) async {
      await tester.pumpShadcnApp(
        const PanelCard(child: Text('Panel')),
      );

      expect(find.text('Panel'), findsOneWidget);
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(PanelCard),
          matching: find.byType(Container),
        ),
      );
      expect(container.decoration, isA<ShapeDecoration>());
      expect(container.foregroundDecoration, isA<ShapeDecoration>());
    });

    testWidgets('renders a custom round card without a border', (tester) async {
      await tester.pumpShadcnApp(
        const PanelCard(
          color: Colors.red,
          showBorder: false,
          borderRadius: BorderRadius.all(Radius.circular(3)),
          boxShadow: <BoxShadow>[BoxShadow(blurRadius: 1)],
          clipBehavior: Clip.none,
          child: Text('Card'),
        ),
      );

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(PanelCard),
          matching: find.byType(Container),
        ),
      );
      expect(container.decoration, isA<BoxDecoration>());
      expect(container.foregroundDecoration, isNull);
    });

    testWidgets('renders a bordered custom-radius card', (tester) async {
      await tester.pumpShadcnApp(
        const PanelCard(
          borderRadius: BorderRadius.all(Radius.circular(3)),
          borderColor: Colors.red,
          child: Text('Bordered'),
        ),
      );

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(PanelCard),
          matching: find.byType(Container),
        ),
      );
      expect(container.foregroundDecoration, isA<BoxDecoration>());
    });
  });
}

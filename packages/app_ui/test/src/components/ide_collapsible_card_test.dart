import 'package:app_ui/app_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/helpers.dart';

void main() {
  group('IdeCollapsibleCard', () {
    testWidgets('renders expanded content and toggles', (tester) async {
      var toggles = 0;
      await tester.pumpShadcnApp(
        IdeCollapsibleCard(
          expanded: true,
          title: 'Details',
          semanticLabel: 'Toggle details',
          leading: const Icon(Icons.info),
          summaryWidget: const Text('Summary'),
          body: const Text('Body'),
          backgroundColor: Colors.black,
          borderColor: Colors.white,
          boxShadow: const <BoxShadow>[BoxShadow(blurRadius: 1)],
          padding: const EdgeInsets.all(2),
          margin: const EdgeInsets.all(2),
          wrapBodyWithRepaintBoundary: false,
          onToggle: () => toggles += 1,
        ),
      );

      expect(find.text('Summary'), findsOneWidget);
      expect(find.text('Body'), findsOneWidget);
      await tester.tap(find.text('Details'));
      expect(toggles, 1);
    });

    testWidgets('supports custom title and collapsed disabled body', (
      tester,
    ) async {
      await tester.pumpShadcnApp(
        const IdeCollapsibleCard(
          expanded: false,
          canExpand: false,
          titleWidget: Text('Custom'),
          body: Text('Hidden'),
          onToggle: _noop,
        ),
      );

      expect(find.text('Custom'), findsOneWidget);
      expect(find.text('Hidden'), findsNothing);
    });

    testWidgets('wraps an expanded body in a repaint boundary', (tester) async {
      await tester.pumpShadcnApp(
        const IdeCollapsibleCard(
          expanded: true,
          title: 'Wrapped',
          body: Text('Wrapped body'),
          onToggle: _noop,
        ),
      );

      expect(find.byType(RepaintBoundary), findsWidgets);
    });
  });
}

void _noop() {}

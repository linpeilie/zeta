import 'package:app_ui/app_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/helpers.dart';

void main() {
  testWidgets('IdeActivityRail renders leading and trailing actions', (
    tester,
  ) async {
    var presses = 0;
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpShadcnApp(
      SizedBox(
        height: 200,
        child: IdeActivityRail(
          leadingActions: <IdeRailAction>[
            IdeRailAction(
              key: const Key('active-action'),
              icon: Icons.search,
              tooltip: 'Search tooltip',
              semanticLabel: 'Search',
              active: true,
              focusNode: focusNode,
              onPressed: () => presses += 1,
            ),
          ],
          trailingActions: <IdeRailAction>[
            IdeRailAction(
              icon: Icons.history,
              tooltip: 'History tooltip',
              semanticLabel: 'History',
              active: false,
              onPressed: () => presses += 10,
            ),
            IdeRailAction(
              key: const Key('disabled-action'),
              icon: Icons.settings,
              tooltip: 'Settings tooltip',
              semanticLabel: 'Settings',
              active: false,
              enabled: false,
              onPressed: () => presses += 100,
            ),
          ],
        ),
      ),
    );

    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.byIcon(Icons.settings), findsOneWidget);
    await tester.tap(find.byKey(const Key('active-action')));
    await tester.tap(find.byKey(const Key('disabled-action')));
    expect(presses, 1);
  });

  testWidgets('IdeActivityRail supports an empty trailing section', (
    tester,
  ) async {
    await tester.pumpShadcnApp(
      const IdeActivityRail(leadingActions: <IdeRailAction>[]),
    );

    expect(find.byType(IdeActivityRail), findsOneWidget);
  });
}

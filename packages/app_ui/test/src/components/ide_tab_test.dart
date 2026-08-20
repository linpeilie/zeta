import 'package:app_ui/app_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/helpers.dart';

void main() {
  testWidgets('IdeTab renders selected icons and activates', (tester) async {
    var presses = 0;
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await tester.pumpShadcnApp(
      IdeTab(
        label: 'Branch',
        leadingIcon: Icons.account_tree,
        selected: true,
        controlSize: AppControlSize.regular,
        semanticLabel: 'Current branch',
        focusNode: focusNode,
        onPressed: () => presses += 1,
      ),
    );

    expect(find.byIcon(Icons.account_tree), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
    await tester.tap(find.text('Branch'));
    expect(presses, 1);
  });

  testWidgets('IdeTab supports disabled and read-only labels', (tester) async {
    var presses = 0;
    await tester.pumpShadcnApp(
      IdeTab(
        label: 'Disabled',
        enabled: false,
        trailingIcon: null,
        onPressed: () => presses += 1,
      ),
    );
    await tester.tap(find.text('Disabled'));
    expect(presses, 0);

    await tester.pumpShadcnApp(const IdeTab(label: 'Read only'));
    expect(find.text('Read only'), findsOneWidget);
  });
}

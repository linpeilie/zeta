import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter_preflight/main.dart';

void main() {
  testWidgets('preflight prototypes open and interact', (tester) async {
    await tester.pumpWidget(const PrototypeApp());
    await tester.pumpAndSettle();

    expect(find.text('Graphite projection active'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('open-dialog-button')));
    await tester.pumpAndSettle();
    expect(find.text('Prototype alert'), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(find.text('Prototype alert'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('open-popover-button')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Rename thread'), findsOneWidget);
    expect(find.text('Archive thread'), findsOneWidget);
    await tester.tap(find.text('Rename thread'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Model'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('prototype-textarea')),
      'Validate TextArea migration.',
    );
    await tester.pump();
    expect(find.text('Validate TextArea migration.'), findsOneWidget);
  });
}

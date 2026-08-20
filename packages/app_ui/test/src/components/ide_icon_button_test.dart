import 'package:app_ui/app_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import '../../helpers/helpers.dart';

void main() {
  group('IdeIconButton', () {
    for (final variant in IdeButtonVariant.values) {
      testWidgets('renders and activates $variant', (tester) async {
        var presses = 0;
        await tester.pumpShadcnApp(
          IdeIconButton(
            icon: Icons.close,
            semanticLabel: 'Close',
            variant: variant,
            controlSize: AppControlSize.regular,
            onPressed: () => presses += 1,
          ),
        );

        expect(find.byType(sf.Button), findsOneWidget);
        expect(find.byIcon(Icons.close), findsOneWidget);
        expect(
          tester.getSize(find.byType(IdeIconButton)).shortestSide,
          greaterThanOrEqualTo(24),
        );
        await tester.tap(find.byType(IdeIconButton));
        await tester.pump();
        expect(presses, 1);
      });
    }

    testWidgets('does not activate when disabled', (tester) async {
      var presses = 0;
      await tester.pumpShadcnApp(
        IdeIconButton(
          icon: Icons.close,
          semanticLabel: 'Close',
          enabled: false,
          onPressed: () => presses += 1,
        ),
      );

      await tester.tap(find.byType(IdeIconButton));
      await tester.pump();
      expect(presses, 0);
    });
  });
}

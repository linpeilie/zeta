import 'package:app_ui/app_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import '../../helpers/helpers.dart';

void main() {
  group('IdeButton', () {
    for (final variant in IdeButtonVariant.values) {
      testWidgets('renders and activates $variant', (tester) async {
        var presses = 0;
        await tester.pumpShadcnApp(
          IdeButton(
            label: 'Run',
            semanticLabel: 'Run action',
            variant: variant,
            leadingIcon: Icons.play_arrow,
            trailingIcon: Icons.chevron_right,
            onPressed: () => presses += 1,
          ),
        );

        expect(find.byType(sf.Button), findsOneWidget);
        expect(find.text('Run'), findsOneWidget);
        expect(find.byIcon(Icons.play_arrow), findsOneWidget);
        expect(find.byIcon(Icons.chevron_right), findsOneWidget);
        expect(
          tester.getSize(find.byType(IdeButton)).height,
          greaterThanOrEqualTo(24),
        );
        await tester.tap(find.byType(IdeButton));
        await tester.pump();
        expect(presses, 1);
      });
    }

    testWidgets('supports toolbar, explicit sizing, and custom leading', (
      tester,
    ) async {
      await tester.pumpShadcnApp(
        const IdeButton.toolbar(
          label: 'Filter',
          width: 120,
          maxLines: 2,
          leading: Text('L'),
        ),
      );
      expect(tester.getSize(find.byType(IdeButton)).width, 120);
      expect(find.text('L'), findsOneWidget);

      await tester.pumpShadcnApp(
        const IdeButton(label: 'Sized', height: 1, width: 100),
      );
      expect(tester.getSize(find.byType(IdeButton)).height, 24);
    });

    testWidgets('does not activate when disabled', (tester) async {
      var presses = 0;
      await tester.pumpShadcnApp(
        IdeButton(
          label: 'Disabled',
          enabled: false,
          onPressed: () => presses += 1,
        ),
      );

      await tester.tap(find.byType(IdeButton));
      await tester.pump();
      expect(presses, 0);
    });
  });
}

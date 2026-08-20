import 'package:app_ui/app_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import '../../helpers/helpers.dart';

void main() {
  group('IdeChip', () {
    for (final variant in IdeChipVariant.values) {
      testWidgets('renders and activates $variant', (tester) async {
        var presses = 0;
        await tester.pumpShadcnApp(
          IdeChip(
            label: 'Tag',
            semanticLabel: 'Tag filter',
            variant: variant,
            leadingIcon: Icons.label,
            trailingIcon: Icons.chevron_right,
            onPressed: () => presses += 1,
          ),
        );

        expect(find.byType(sf.Chip), findsOneWidget);
        await tester.tap(find.text('Tag'));
        await tester.pump();
        expect(presses, 1);
      });
    }

    testWidgets('selected chip exposes a delete action', (tester) async {
      var deletes = 0;
      await tester.pumpShadcnApp(
        IdeChip(
          label: 'Selected',
          selected: true,
          onDeleted: () => deletes += 1,
        ),
      );

      await tester.tap(find.byType(sf.ChipButton));
      await tester.pump();
      expect(deletes, 1);
    });

    testWidgets('disabled chip ignores actions', (tester) async {
      var deletes = 0;
      await tester.pumpShadcnApp(
        IdeChip(
          label: 'Disabled',
          enabled: false,
          onDeleted: () => deletes += 1,
        ),
      );

      await tester.tap(find.byType(sf.ChipButton));
      await tester.pump();
      expect(deletes, 0);
    });
  });
}

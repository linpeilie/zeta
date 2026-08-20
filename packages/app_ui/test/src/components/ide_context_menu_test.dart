import 'dart:async';

import 'package:app_ui/app_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/helpers.dart';

void main() {
  testWidgets('IdeContextMenu renders and activates caller actions', (
    tester,
  ) async {
    var presses = 0;
    final copied = IdeContextMenuAction(
      key: const Key('enabled-action'),
      label: 'Open',
      leadingIcon: Icons.folder_open,
      semanticLabel: 'Open item',
      onPressed: () => presses += 1,
    ).withDividerAbove(value: true);

    await tester.pumpShadcnApp(
      IdeContextMenu(
        minWidth: 180,
        closeOnActivate: false,
        actions: <IdeContextMenuAction>[
          IdeContextMenuAction(
            label: 'Delete',
            destructive: true,
            onPressed: () => presses += 10,
          ),
          copied,
          IdeContextMenuAction(
            key: const Key('disabled-action'),
            label: 'Disabled',
            enabled: false,
            onPressed: () => presses += 100,
          ),
        ],
      ),
    );

    expect(find.byIcon(Icons.folder_open), findsOneWidget);
    expect(find.byType(Divider), findsOneWidget);
    await tester.tap(find.text('Open'));
    await tester.tap(find.text('Disabled'));
    expect(presses, 1);
  });

  testWidgets('IdeContextMenu closes a containing overlay on activation', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpShadcnApp(
      Builder(
        builder: (context) => IdeButton(
          label: 'Show menu',
          onPressed: () => unawaited(
            showIdeDialog<void>(
              context: context,
              builder: (_) => IdeContextMenu(
                actions: <IdeContextMenuAction>[
                  IdeContextMenuAction(
                    label: 'Activate',
                    onPressed: () => presses += 1,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show menu'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Activate'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(presses, 1);
  });
}

import 'dart:async';

import 'package:app_ui/app_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import '../../helpers/helpers.dart';

void main() {
  testWidgets('IdeDialog renders caller content and every action variant', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpShadcnApp(
      IdeDialog(
        leading: const Icon(Icons.info),
        trailing: const Icon(Icons.close),
        title: const Text('Dialog title'),
        content: const Text('Dialog content'),
        surfaceBlur: 0,
        surfaceOpacity: 1,
        barrierColor: Colors.black12,
        padding: EdgeInsets.zero,
        actions: <IdeDialogAction>[
          IdeDialogAction.cancel(
            label: 'Cancel',
            onPressed: () => presses += 1,
          ),
          IdeDialogAction.confirm(
            label: 'Confirm',
            onPressed: () => presses += 10,
          ),
          IdeDialogAction.destructive(
            label: 'Delete',
            onPressed: () => presses += 100,
          ),
          const IdeDialogAction(label: 'Disabled', onPressed: null),
        ],
      ),
    );

    expect(find.text('Dialog title'), findsOneWidget);
    expect(find.text('Dialog content'), findsOneWidget);
    expect(find.byType(sf.PrimaryButton), findsOneWidget);
    expect(find.byType(sf.DestructiveButton), findsOneWidget);
    expect(find.byType(sf.OutlineButton), findsNWidgets(2));
    await tester.tap(find.text('Cancel'));
    await tester.tap(find.text('Confirm'));
    await tester.tap(find.text('Delete'));
    expect(presses, 111);
  });

  testWidgets('IdeDialog supports no actions and showIdeDialog overlay', (
    tester,
  ) async {
    await tester.pumpShadcnApp(
      Builder(
        builder: (context) => IdeButton(
          label: 'Show',
          onPressed: () {
            unawaited(
              showIdeDialog<void>(
                context: context,
                useRootNavigator: false,
                barrierDismissible: false,
                barrierColor: Colors.black26,
                barrierLabel: 'Dialog barrier',
                useSafeArea: false,
                routeSettings: const RouteSettings(name: '/dialog'),
                anchorPoint: Offset.zero,
                traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
                alignment: Alignment.center,
                builder: (_) => const IdeDialog(content: Text('Overlay body')),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    expect(find.text('Overlay body'), findsOneWidget);
  });
}

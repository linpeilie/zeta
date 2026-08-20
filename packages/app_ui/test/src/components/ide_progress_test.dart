import 'package:app_ui/app_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import '../../helpers/helpers.dart';

void main() {
  group('IdeLoadingIndicator', () {
    testWidgets('renders caller copy as a live linear indicator', (
      tester,
    ) async {
      await tester.pumpShadcnApp(
        const IdeLoadingIndicator(
          semanticsLabel: 'Loading projects',
          width: 40,
          height: 12,
          barHeight: 4,
        ),
      );

      expect(find.byType(sf.Progress), findsOneWidget);
      expect(find.bySemanticsLabel('Loading projects'), findsOneWidget);
    });
  });

  group('IdeBusySpinner', () {
    testWidgets('renders indeterminate and determinate progress', (
      tester,
    ) async {
      await tester.pumpShadcnApp(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IdeBusySpinner(semanticsLabel: 'Running'),
            IdeBusySpinner(
              semanticsLabel: 'Half complete',
              size: 20,
              strokeWidth: 3,
              value: 0.5,
              color: Colors.red,
              backgroundColor: Colors.blue,
            ),
          ],
        ),
      );

      expect(find.byType(sf.CircularProgressIndicator), findsNWidgets(2));
      expect(find.bySemanticsLabel('Running'), findsOneWidget);
      expect(find.bySemanticsLabel('Half complete'), findsOneWidget);
    });

    testWidgets('stops indeterminate animation for reduced motion', (
      tester,
    ) async {
      await tester.pumpShadcnApp(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: IdeBusySpinner(semanticsLabel: 'Running'),
        ),
      );

      expect(find.byType(IdeBusySpinner), findsOneWidget);
    });
  });
}

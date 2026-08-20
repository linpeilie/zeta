import 'package:app_ui/app_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/helpers.dart';

void main() {
  group('skeleton components', () {
    testWidgets('bone pulses and supports a live-region label', (tester) async {
      await tester.pumpShadcnApp(
        const SizedBox(
          width: 100,
          child: IdeSkeletonBone(semanticsLabel: 'Loading'),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(IdeSkeletonBone),
          matching: find.byType(FadeTransition),
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    });

    testWidgets('bone becomes static for reduced motion', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: IdeSkeletonBone(
              width: 50,
              height: 20,
              borderRadius: BorderRadius.all(Radius.circular(2)),
            ),
          ),
        ),
      );

      expect(find.byType(Opacity), findsOneWidget);
    });

    testWidgets('line and block delegate their dimensions', (tester) async {
      await tester.pumpShadcnApp(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IdeSkeletonLine(width: 40, height: 10),
            IdeSkeletonBlock(width: 60, height: 30),
          ],
        ),
      );

      expect(find.byType(IdeSkeletonBone), findsNWidgets(2));
      expect(find.byType(IdeSkeletonLine), findsOneWidget);
      expect(find.byType(IdeSkeletonBlock), findsOneWidget);
    });
  });
}

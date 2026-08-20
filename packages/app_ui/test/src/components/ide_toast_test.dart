import 'package:app_ui/app_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import '../../helpers/helpers.dart';

void main() {
  testWidgets('showIdeToast ignores blank copy', (tester) async {
    await tester.pumpShadcnApp(
      Builder(
        builder: (context) {
          expect(
            showIdeToast(
              context,
              message: '   ',
              closeSemanticLabel: 'Close notification',
            ),
            isNull,
          );
          return const SizedBox.shrink();
        },
      ),
    );
  });

  for (final tone in IdeToastTone.values) {
    testWidgets('showIdeToast renders and closes $tone feedback', (
      tester,
    ) async {
      sf.ToastOverlay? overlay;
      await tester.pumpShadcnApp(
        Builder(
          builder: (context) => IdeButton(
            label: 'Show toast',
            onPressed: () => overlay = showIdeToast(
              context,
              message: ' Feedback ',
              closeSemanticLabel: 'Close notification',
              tone: tone,
              location: sf.ToastLocation.topCenter,
              showDuration: const Duration(milliseconds: 10),
              dismissible: false,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show toast'));
      await tester.pump();
      expect(find.text('Feedback'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == 'Close notification',
        ),
        findsOneWidget,
      );
      expect(overlay?.isShowing, isTrue);
      overlay?.close();
      expect(overlay?.isShowing, isFalse);
      await tester.pump(const Duration(seconds: 1));
    });
  }
}

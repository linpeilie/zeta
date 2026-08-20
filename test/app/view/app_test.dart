import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/app/app.dart';
import 'package:zeta/counter/counter.dart';
import 'package:zeta/l10n/l10n.dart';

void main() {
  group('App', () {
    testWidgets('renders CounterPage', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.pumpWidget(
        App(
          dependencies: AppDependencies(
            locale: const Locale('en'),
            failureMessages: FailureMessages(l10n),
            desktopNotificationCopyResolver: DesktopNotificationCopyResolver(
              l10n,
            ),
          ),
        ),
      );
      expect(find.byType(CounterPage), findsOneWidget);
    });
  });
}

// Ignore for testing purposes
// ignore_for_file: prefer_const_constructors

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/app/app.dart';
import 'package:zeta/counter/counter.dart';

void main() {
  group('App', () {
    testWidgets('renders CounterPage', (tester) async {
      await tester.pumpWidget(App());
      expect(find.byType(CounterPage), findsOneWidget);
    });
  });
}

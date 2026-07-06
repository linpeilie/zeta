import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/main.dart';

import '../testing/ide_test_harness.dart';

void main() {
  testWidgets('starts with the compact IDE panes', (tester) async {
    final session = MemorySessionStore();

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        sessionLoader: session.load,
        sessionSaver: session.save,
      ),
    );

    expect(find.text('Zeta IDE'), findsNothing);
    expect(find.byKey(const ValueKey('projects-panel-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-pane-host')), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-panel-card')), findsNothing);
    expect(find.byKey(const ValueKey('files-panel-card')), findsOneWidget);
    expect(find.text('Projects'), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-header-title')), findsOneWidget);
    expect(headerTitleText(tester), 'New thread');
    expect(find.text('Agent'), findsNothing);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('No folder opened'), findsOneWidget);
    expect(find.text('No file context'), findsNothing);
  });
}

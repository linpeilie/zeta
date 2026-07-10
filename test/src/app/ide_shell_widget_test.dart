import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/main.dart';

import '../testing/ide_test_harness.dart';

void main() {
  testWidgets('starts with the compact IDE panes', (tester) async {
    await _pumpIde(tester);

    expect(find.text('Zeta IDE'), findsNothing);
    expect(find.byKey(const ValueKey('projects-panel-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-pane-host')), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-panel-card')), findsNothing);
    expect(find.byKey(const ValueKey('files-panel-card')), findsNothing);
    expect(find.byKey(const ValueKey('context-panel-card')), findsNothing);
    expect(find.byKey(const ValueKey('tools-panel-card')), findsNothing);
    expect(find.byKey(const ValueKey('left-projects-action')), findsOneWidget);
    expect(find.byKey(const ValueKey('left-context-action')), findsOneWidget);
    expect(find.byKey(const ValueKey('right-files-action')), findsOneWidget);
    expect(find.byKey(const ValueKey('right-tools-action')), findsOneWidget);
    expect(find.text('Projects'), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-header-title')), findsOneWidget);
    expect(headerTitleText(tester), 'New thread');
    expect(find.text('Agent'), findsNothing);
    expect(find.text('Files'), findsNothing);
    expect(find.text('No folder opened'), findsOneWidget);
    expect(find.text('No file context'), findsNothing);
    expect(find.text('No tools running'), findsNothing);
  });

  testWidgets('activity icons toggle side panel columns', (tester) async {
    await _pumpIde(tester);

    await tester.tap(find.byKey(const ValueKey('left-projects-action')));
    await tester.pump();

    expect(find.byKey(const ValueKey('projects-panel-card')), findsNothing);
    expect(find.byKey(const ValueKey('context-panel-card')), findsNothing);
    expect(find.byKey(const ValueKey('left-activity-panel')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('left-context-action')));
    await tester.pump();

    expect(find.byKey(const ValueKey('context-panel-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('left-activity-panel')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('left-width-resize-handle')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('left-projects-action')));
    await tester.pump();

    expect(find.byKey(const ValueKey('projects-panel-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('left-activity-panel')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('left-width-resize-handle')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('right-files-action')));
    await tester.pump();

    expect(find.byKey(const ValueKey('files-panel-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('right-activity-panel')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('right-width-resize-handle')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('right-tools-action')));
    await tester.pump();

    expect(find.byKey(const ValueKey('tools-panel-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('right-activity-panel')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('right-tools-action')));
    await tester.pump();

    expect(find.byKey(const ValueKey('files-panel-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('tools-panel-card')), findsNothing);
    expect(find.byKey(const ValueKey('right-activity-panel')), findsOneWidget);
  });

  testWidgets('horizontal resize handles clamp side widths', (tester) async {
    await _pumpIde(tester);

    expect(_widthOf(tester, 'left-activity-panel'), 260);

    await tester.tap(find.byKey(const ValueKey('right-files-action')));
    await tester.pump();

    expect(_widthOf(tester, 'right-activity-panel'), 260);

    await tester.drag(
      find.byKey(const ValueKey('left-width-resize-handle')),
      const Offset(500, 0),
    );
    await tester.pump();
    expect(_widthOf(tester, 'left-activity-panel'), 400);

    await tester.drag(
      find.byKey(const ValueKey('left-width-resize-handle')),
      const Offset(-500, 0),
    );
    await tester.pump();
    expect(_widthOf(tester, 'left-activity-panel'), 200);

    await tester.drag(
      find.byKey(const ValueKey('right-width-resize-handle')),
      const Offset(-500, 0),
    );
    await tester.pump();
    expect(_widthOf(tester, 'right-activity-panel'), 400);

    await tester.drag(
      find.byKey(const ValueKey('right-width-resize-handle')),
      const Offset(500, 0),
    );
    await tester.pump();
    expect(_widthOf(tester, 'right-activity-panel'), 200);
  });

  testWidgets('vertical resize handles clamp panel ratio', (tester) async {
    await _pumpIde(tester);
    await tester.tap(find.byKey(const ValueKey('left-context-action')));
    await tester.pump();

    final columnHeight = _heightOf(tester, 'left-activity-panel');
    final minimumPanelHeight = (columnHeight - 8) * 0.1;

    await tester.drag(
      find.byKey(const ValueKey('left-height-resize-handle')),
      const Offset(0, -2000),
    );
    await tester.pump();

    expect(
      _heightOf(tester, 'projects-panel-card'),
      moreOrLessEquals(minimumPanelHeight, epsilon: 1),
    );

    await tester.tap(find.byKey(const ValueKey('left-context-action')));
    await tester.pump();

    expect(
      _heightOf(tester, 'projects-panel-card'),
      moreOrLessEquals(columnHeight, epsilon: 1),
    );
  });

  testWidgets('right panels use overlay below 800px width', (tester) async {
    await _pumpIde(tester, size: const Size(832, 900));

    expect(find.byKey(const ValueKey('right-activity-panel')), findsNothing);
    expect(
      find.byKey(const ValueKey('right-width-resize-handle')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('right-activity-overlay')), findsNothing);
    expect(find.byKey(const ValueKey('files-panel-card')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('right-files-action')));
    await tester.pump();

    expect(find.byKey(const ValueKey('right-activity-panel')), findsNothing);
    expect(
      find.byKey(const ValueKey('right-activity-overlay')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('files-panel-card')), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('right-overlay-scrim')));
    await tester.pump();

    expect(find.byKey(const ValueKey('right-activity-overlay')), findsNothing);
    expect(find.byKey(const ValueKey('right-activity-panel')), findsNothing);
    expect(find.byKey(const ValueKey('files-panel-card')), findsNothing);
  });

  testWidgets('left panels use an overlay when the window is narrow', (
    tester,
  ) async {
    await _pumpIde(tester, size: const Size(640, 900));

    expect(find.byKey(const ValueKey('left-activity-panel')), findsNothing);
    expect(find.byKey(const ValueKey('left-activity-overlay')), findsNothing);
    expect(find.byKey(const ValueKey('projects-panel-card')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('left-projects-action')));
    await tester.pump();

    expect(find.byKey(const ValueKey('left-activity-overlay')), findsOneWidget);
    expect(find.byKey(const ValueKey('projects-panel-card')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('left-overlay-scrim')));
    await tester.pump();

    expect(find.byKey(const ValueKey('left-activity-overlay')), findsNothing);
    expect(find.byKey(const ValueKey('agent-pane-host')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpIde(
  WidgetTester tester, {
  Size size = const Size(1400, 900),
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(() {
    tester.view
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });

  final session = MemorySessionStore();

  await tester.pumpWidget(
    MainApp(
      enableNativeWindowFrame: false,
      sessionLoader: session.load,
      sessionSaver: session.save,
    ),
  );
}

double _widthOf(WidgetTester tester, String key) {
  return tester.getSize(find.byKey(ValueKey<String>(key))).width;
}

double _heightOf(WidgetTester tester, String key) {
  return tester.getSize(find.byKey(ValueKey<String>(key))).height;
}

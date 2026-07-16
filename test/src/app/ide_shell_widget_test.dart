import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/main.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/agent/presentation/agent_pane.dart';
import 'package:zeta/src/ui/core/ide_metrics.dart';

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
    expect(
      find.byKey(const ValueKey('workbench-navigation-inline')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('left-context-action')));
    await tester.pump();

    expect(find.byKey(const ValueKey('context-panel-card')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('workbench-navigation-inline')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('left-width-resize-handle')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('left-projects-action')));
    await tester.pump();

    expect(find.byKey(const ValueKey('projects-panel-card')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('workbench-navigation-inline')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('left-width-resize-handle')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('right-files-action')));
    await tester.pump();

    expect(find.byKey(const ValueKey('files-panel-card')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('workbench-inspector-inline')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('right-width-resize-handle')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('right-tools-action')));
    await tester.pump();

    expect(find.byKey(const ValueKey('tools-panel-card')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('workbench-inspector-inline')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('right-tools-action')));
    await tester.pump();

    expect(find.byKey(const ValueKey('files-panel-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('tools-panel-card')), findsNothing);
    expect(
      find.byKey(const ValueKey('workbench-inspector-inline')),
      findsOneWidget,
    );
  });

  testWidgets('horizontal resize handles clamp side widths', (tester) async {
    await _pumpIde(tester);

    expect(
      _widthOf(tester, 'workbench-navigation-inline'),
      IdeMetrics.sidePaneDefaultWidth,
    );

    await tester.tap(find.byKey(const ValueKey('right-files-action')));
    await tester.pump();

    expect(
      _widthOf(tester, 'workbench-inspector-inline'),
      IdeMetrics.sidePaneDefaultWidth,
    );

    await tester.drag(
      find.byKey(const ValueKey('left-width-resize-handle')),
      const Offset(500, 0),
    );
    await tester.pump();
    expect(
      _widthOf(tester, 'workbench-navigation-inline'),
      IdeMetrics.sidePaneMaxWidth,
    );

    await tester.drag(
      find.byKey(const ValueKey('left-width-resize-handle')),
      const Offset(-500, 0),
    );
    await tester.pump();
    expect(
      _widthOf(tester, 'workbench-navigation-inline'),
      IdeMetrics.sidePaneMinWidth,
    );

    await tester.drag(
      find.byKey(const ValueKey('right-width-resize-handle')),
      const Offset(-500, 0),
    );
    await tester.pump();
    expect(
      _widthOf(tester, 'workbench-inspector-inline'),
      IdeMetrics.sidePaneMaxWidth,
    );

    await tester.drag(
      find.byKey(const ValueKey('right-width-resize-handle')),
      const Offset(500, 0),
    );
    await tester.pump();
    expect(
      _widthOf(tester, 'workbench-inspector-inline'),
      IdeMetrics.sidePaneMinWidth,
    );
  });

  testWidgets('vertical resize handles clamp panel ratio', (tester) async {
    await _pumpIde(tester);
    final expandedPanelHeight = _heightOf(tester, 'projects-panel-card');
    await tester.tap(find.byKey(const ValueKey('left-context-action')));
    await tester.pump();

    final minimumPanelHeight = (expandedPanelHeight - 8) * 0.1;

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
      moreOrLessEquals(expandedPanelHeight, epsilon: 1),
    );
  });

  testWidgets('right panels use overlay in medium and compact modes', (
    tester,
  ) async {
    await _pumpIde(tester, size: const Size(832, 900));

    expect(
      find.byKey(const ValueKey('workbench-inspector-inline')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('right-width-resize-handle')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('workbench-inspector-overlay')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('files-panel-card')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('right-files-action')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('workbench-inspector-inline')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('workbench-inspector-overlay')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('files-panel-card')), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);

    await tester.tapAt(const Offset(200, 450));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('workbench-inspector-overlay')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('workbench-inspector-inline')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('files-panel-card')), findsNothing);
  });

  testWidgets('left panels use an overlay when the window is narrow', (
    tester,
  ) async {
    await _pumpIde(tester, size: const Size(640, 900));

    expect(
      find.byKey(const ValueKey('workbench-navigation-inline')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('workbench-navigation-overlay')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('projects-panel-card')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('left-projects-action')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('workbench-navigation-overlay')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('projects-panel-card')), findsOneWidget);

    await tester.tapAt(const Offset(500, 450));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('workbench-navigation-overlay')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('agent-pane-host')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Agent to Settings and back retains the workbench and Agent state',
    (tester) async {
      final retained = await _prepareRetainedAgentState(tester);

      await tester.tap(find.byKey(const ValueKey('titlebar-settings-action')));
      await tester.pump();

      expect(find.byKey(const ValueKey('settings-nav-panel')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('settings-detail-panel')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('workbench-navigation-inline')),
          matching: find.byKey(const ValueKey('settings-nav-panel')),
        ),
        findsOneWidget,
      );
      expect(find.byType(AgentPane, skipOffstage: false), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('settings-nav-agents')));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('agent-management-page')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('workbench-canvas')),
          matching: find.byKey(const ValueKey('agent-management-page')),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('settings-back-button')));
      await tester.pump();

      _expectRetainedAgentState(tester, retained);
    },
  );

  testWidgets('Agent to Usage and back retains the workbench and Agent state', (
    tester,
  ) async {
    final retained = await _prepareRetainedAgentState(tester);

    await tester.tap(
      find.byKey(const ValueKey('titlebar-usage-statistics-action')),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('usage-statistics-page')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('workbench-canvas')),
        matching: find.byKey(const ValueKey('usage-statistics-page')),
      ),
      findsOneWidget,
    );
    expect(find.byType(AgentPane, skipOffstage: false), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('usage-statistics-back-button')),
    );
    await tester.pump();

    _expectRetainedAgentState(tester, retained);
  });
}

Future<void> _pumpIde(
  WidgetTester tester, {
  Size size = const Size(1400, 900),
  bool enableNativeWindowFrame = false,
  Future<String?> Function()? directoryPicker,
  AgentProviderFactory? agentProviderFactory,
  AgentProviderConfigStore? agentProviderConfigStore,
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
      enableNativeWindowFrame: enableNativeWindowFrame,
      showWindowControls: false,
      directoryPicker: directoryPicker,
      sessionLoader: session.load,
      sessionSaver: session.save,
      agentProviderFactory: agentProviderFactory,
      agentProviderConfigStore: agentProviderConfigStore,
    ),
  );
}

Future<_RetainedAgentState> _prepareRetainedAgentState(
  WidgetTester tester,
) async {
  final directory = Directory.systemTemp.createTempSync('zeta_workbench_test_');
  addTearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });
  File(
    '${directory.path}${Platform.pathSeparator}sample.txt',
  ).writeAsStringSync('workbench retention');

  final provider = FakeAgentProvider(
    threadHistories: <String, AgentThreadHistorySnapshot>{
      'retained-thread': AgentThreadHistorySnapshot(
        threadId: 'retained-thread',
        turns: <AgentHistoryTurn>[
          for (var turnIndex = 0; turnIndex < 8; turnIndex += 1)
            AgentHistoryTurn(
              id: 'retained-turn-$turnIndex',
              entries: <AgentHistoryEntry>[
                for (var messageIndex = 0; messageIndex < 4; messageIndex += 1)
                  AgentHistoryMessageEntry(
                    id: 'retained-message-$turnIndex-$messageIndex',
                    role: AgentMessageRole.agent,
                    text: List<String>.generate(
                      10,
                      (line) =>
                          'Retained conversation $turnIndex.$messageIndex '
                          'line $line keeps the timeline scrollable.',
                    ).join('\n\n'),
                  ),
              ],
            ),
        ],
      ),
    },
    threadPages: <AgentThreadPage>[
      AgentThreadPage(
        threads: <AgentThreadSummary>[
          agentThread(
            id: 'retained-thread',
            projectPath: directory.path,
            title: 'Retained thread',
          ),
        ],
        nextCursor: null,
      ),
    ],
  );
  await _pumpIde(
    tester,
    enableNativeWindowFrame: true,
    directoryPicker: () async => directory.path,
    agentProviderFactory: FakeAgentProviderFactory(provider),
    agentProviderConfigStore: MemoryAgentProviderConfigStore(),
  );

  await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
  await tester.runAsync(waitForIo);
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(
      ValueKey<String>('project-thread-${directory.path}-retained-thread'),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const ValueKey('right-files-action')));
  await tester.pump();
  await tester.drag(
    find.byKey(const ValueKey('left-width-resize-handle')),
    const Offset(48, 0),
  );
  await tester.pump();

  final messageList = find.byKey(const ValueKey('agent-message-list'));
  final scrollController = tester
      .widget<SingleChildScrollView>(messageList)
      .controller!;
  expect(scrollController.position.maxScrollExtent, greaterThan(0));
  scrollController.jumpTo(scrollController.position.maxScrollExtent / 2);
  await tester.pump();

  const draft = 'Draft retained across workbench pages';
  final input = _agentMessageInput();
  await tester.enterText(input, draft);
  await tester.pump();

  return _RetainedAgentState(
    windowFrameElement: tester.element(
      find.byKey(const ValueKey('ide-window-frame')),
    ),
    workbenchElement: tester.element(
      find.byKey(const ValueKey('ide-workbench')),
    ),
    agentPaneElement: tester.element(find.byType(AgentPane)),
    inputController: tester.widget<EditableText>(input).controller,
    scrollController: scrollController,
    scrollOffset: scrollController.offset,
    navigationWidth: _widthOf(tester, 'workbench-navigation-inline'),
    inspectorWidth: _widthOf(tester, 'workbench-inspector-inline'),
    draft: draft,
  );
}

void _expectRetainedAgentState(
  WidgetTester tester,
  _RetainedAgentState retained,
) {
  expect(
    tester.element(find.byKey(const ValueKey('ide-window-frame'))),
    same(retained.windowFrameElement),
  );
  expect(
    tester.element(find.byKey(const ValueKey('ide-workbench'))),
    same(retained.workbenchElement),
  );
  expect(
    tester.element(find.byType(AgentPane)),
    same(retained.agentPaneElement),
  );
  expect(
    tester.widget<EditableText>(_agentMessageInput()).controller,
    same(retained.inputController),
  );
  expect(retained.inputController.text, retained.draft);
  final currentScrollController = tester
      .widget<SingleChildScrollView>(
        find.byKey(const ValueKey('agent-message-list')),
      )
      .controller!;
  expect(currentScrollController, same(retained.scrollController));
  expect(currentScrollController.offset, closeTo(retained.scrollOffset, 0.1));
  expect(
    _widthOf(tester, 'workbench-navigation-inline'),
    retained.navigationWidth,
  );
  expect(
    _widthOf(tester, 'workbench-inspector-inline'),
    retained.inspectorWidth,
  );
  expect(find.byKey(const ValueKey('projects-panel-card')), findsOneWidget);
  expect(find.byKey(const ValueKey('files-panel-card')), findsOneWidget);
  expect(headerTitleText(tester), 'Retained thread');
  expect(tester.takeException(), isNull);
}

Finder _agentMessageInput() {
  return find.descendant(
    of: find.byKey(const ValueKey('agent-message-input')),
    matching: find.byType(EditableText),
  );
}

class _RetainedAgentState {
  const _RetainedAgentState({
    required this.windowFrameElement,
    required this.workbenchElement,
    required this.agentPaneElement,
    required this.inputController,
    required this.scrollController,
    required this.scrollOffset,
    required this.navigationWidth,
    required this.inspectorWidth,
    required this.draft,
  });

  final Element windowFrameElement;
  final Element workbenchElement;
  final Element agentPaneElement;
  final TextEditingController inputController;
  final ScrollController scrollController;
  final double scrollOffset;
  final double navigationWidth;
  final double inspectorWidth;
  final String draft;
}

double _widthOf(WidgetTester tester, String key) {
  return tester.getSize(find.byKey(ValueKey<String>(key))).width;
}

double _heightOf(WidgetTester tester, String key) {
  return tester.getSize(find.byKey(ValueKey<String>(key))).height;
}

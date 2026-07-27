import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/main.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/agent/presentation/agent_pane.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';
import 'package:zeta/src/features/ide_session/domain/ide_session_state.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_panel_models.dart';
import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';
import 'package:zeta/src/ui/core/surfaces/ide_surface.dart';

import '../testing/ide_test_harness.dart';

void main() {
  testWidgets('starts with the compact IDE panes', (tester) async {
    await _pumpIde(tester);
    await tester.pump();

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
    expect(find.byKey(const ValueKey('global-home-page')), findsOneWidget);
    expect(find.text('欢迎使用 Zeta'), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-header-title')), findsNothing);
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
    expect(find.text('Agent 统计'), findsOneWidget);
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

  testWidgets('side panel cards own borders without workbench pane wrappers', (
    tester,
  ) async {
    await _pumpIde(tester);
    await tester.tap(find.byKey(const ValueKey('left-context-action')));
    await tester.tap(find.byKey(const ValueKey('right-files-action')));
    await tester.tap(find.byKey(const ValueKey('right-tools-action')));
    await tester.pump();

    for (final panelKey in <String>[
      'projects-panel-card',
      'context-panel-card',
      'files-panel-card',
      'tools-panel-card',
    ]) {
      final panel = find.byKey(ValueKey<String>(panelKey));
      expect(tester.widget<PanelCard>(panel).showBorder, isTrue);
      expect(
        find.ancestor(of: panel, matching: find.byType(IdeSurface)),
        findsNothing,
      );
    }
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

  testWidgets('vertical resize handles preserve accumulated drag distance', (
    tester,
  ) async {
    await _pumpIde(tester);
    await tester.tap(find.byKey(const ValueKey('left-context-action')));
    await tester.tap(find.byKey(const ValueKey('right-files-action')));
    await tester.tap(find.byKey(const ValueKey('right-tools-action')));
    await tester.pump();

    Future<void> expectBurstDrag({
      required String handleKey,
      required String topPanelKey,
    }) async {
      final handle = find.byKey(ValueKey(handleKey));
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      final heightAfterDragStart = _heightOf(tester, topPanelKey);

      for (var index = 0; index < 4; index += 1) {
        await gesture.moveBy(const Offset(0, 12));
      }
      await gesture.up();
      await tester.pump();

      expect(
        _heightOf(tester, topPanelKey),
        moreOrLessEquals(heightAfterDragStart + 48, epsilon: 1),
      );
    }

    await expectBurstDrag(
      handleKey: 'left-height-resize-handle',
      topPanelKey: 'projects-panel-card',
    );
    await expectBurstDrag(
      handleKey: 'right-height-resize-handle',
      topPanelKey: 'files-panel-card',
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
      expect(retained.agentPaneElement.mounted, isTrue);
      expect(
        find.byKey(const ValueKey('settings-general-group')),
        findsOneWidget,
      );
      expect(
        (retained.agentPaneElement.widget as AgentPane).messageSendShortcut,
        MessageSendShortcut.enter,
      );

      await tester.tap(
        find.byKey(const ValueKey('settings-send-message-shortcut-modifier')),
      );
      await tester.pump();
      await tester.pump();

      expect(
        (retained.agentPaneElement.widget as AgentPane).messageSendShortcut,
        MessageSendShortcut.primaryModifierEnter,
      );
      expect(retained.inputController.text, retained.draft);

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
    expect(retained.agentPaneElement.mounted, isTrue);

    await tester.tap(
      find.byKey(const ValueKey('usage-statistics-back-button')),
    );
    await tester.pump();

    _expectRetainedAgentState(tester, retained);
  });

  testWidgets('Wide ↔ Medium workbench breakpoints retain AgentPane state', (
    tester,
  ) async {
    final retained = await _prepareRetainedAgentState(tester);

    expect(find.byKey(const ValueKey('workbench-base')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('workbench-inspector-inline')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workbench-navigation-inline')),
      findsOneWidget,
    );
    final baseElement = tester.element(
      find.byKey(const ValueKey('workbench-base')),
    );
    final canvasSlotElement = tester.element(
      find.byKey(const ValueKey('workbench-canvas-slot')),
    );

    // Wide → Medium：选用仍能容纳 nav + canvas 最小宽的宽度，避免降级到 compact。
    // Inspector 退出 inline，Canvas State 必须保持。
    tester.view.physicalSize = const Size(1100, 900);
    await tester.pump();

    expect(find.byKey(const ValueKey('workbench-base')), findsOneWidget);
    expect(
      tester.element(find.byKey(const ValueKey('workbench-base'))),
      same(baseElement),
    );
    expect(
      tester.element(find.byKey(const ValueKey('workbench-canvas-slot'))),
      same(canvasSlotElement),
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
    final mediumScrollController = tester
        .widget<SingleChildScrollView>(
          find.byKey(const ValueKey('agent-message-list')),
        )
        .controller!;
    expect(mediumScrollController, same(retained.scrollController));
    expect(mediumScrollController.offset, closeTo(retained.scrollOffset, 0.1));
    expect(
      find.byKey(const ValueKey('workbench-navigation-inline')),
      findsOneWidget,
    );
    // Wide 下通过 inline 打开的 Inspector 不会在断点切换时自动升为 Overlay；
    // 可见性意图仍保留，回到 Wide 后应恢复 inline。
    expect(
      find.byKey(const ValueKey('workbench-inspector-inline')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('workbench-inspector-overlay')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);

    // Medium → Wide：恢复 inline Inspector，草稿/滚动/State 仍不变。
    tester.view.physicalSize = const Size(1400, 900);
    await tester.pump();

    expect(
      tester.element(find.byKey(const ValueKey('workbench-base'))),
      same(baseElement),
    );
    expect(
      find.byKey(const ValueKey('workbench-inspector-inline')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workbench-inspector-overlay')),
      findsNothing,
    );
    _expectRetainedAgentState(tester, retained);
  });

  testWidgets(
    'inactive agent panes stay keep-alive without joining resize layout',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'zeta_inactive_layout_',
      );
      addTearDown(() {
        if (directory.existsSync()) {
          directory.deleteSync(recursive: true);
        }
      });
      File(
        '${directory.path}${Platform.pathSeparator}sample.txt',
      ).writeAsStringSync('inactive layout');

      final provider = FakeAgentProvider(
        threadHistories: <String, AgentThreadHistorySnapshot>{
          'thread-a': AgentThreadHistorySnapshot(
            threadId: 'thread-a',
            turns: <AgentHistoryTurn>[
              AgentHistoryTurn(
                id: 'turn-a-1',
                entries: const <AgentHistoryEntry>[
                  AgentHistoryMessageEntry(
                    id: 'thread-a-history',
                    role: AgentMessageRole.agent,
                    text: 'Thread A history for inactive layout',
                  ),
                ],
              ),
            ],
          ),
          'thread-b': AgentThreadHistorySnapshot(
            threadId: 'thread-b',
            turns: <AgentHistoryTurn>[
              AgentHistoryTurn(
                id: 'turn-b-1',
                entries: const <AgentHistoryEntry>[
                  AgentHistoryMessageEntry(
                    id: 'thread-b-history',
                    role: AgentMessageRole.agent,
                    text: 'Thread B history for inactive layout',
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
                id: 'thread-a',
                projectPath: directory.path,
                title: 'Thread A',
              ),
              agentThread(
                id: 'thread-b',
                projectPath: directory.path,
                title: 'Thread B',
                lastActiveAt: DateTime.fromMillisecondsSinceEpoch(3),
              ),
            ],
            nextCursor: null,
          ),
        ],
      );

      await _pumpIde(
        tester,
        directoryPicker: () async => directory.path,
        agentProviderFactory: FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      );

      await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
      await tester.runAsync(waitForIo);

      final threadARow = find.byKey(
        ValueKey<String>('project-thread-${directory.path}-thread-a'),
      );
      final threadBRow = find.byKey(
        ValueKey<String>('project-thread-${directory.path}-thread-b'),
      );
      await pumpUntilCondition(
        tester,
        () =>
            threadARow.evaluate().isNotEmpty &&
            threadBRow.evaluate().isNotEmpty,
        failureMessage: 'Thread rows did not become ready',
      );

      await tester.tap(threadARow);
      await pumpUntilCondition(
        tester,
        () => headerTitleText(tester) == 'Thread A',
        failureMessage: 'Thread A did not open',
      );
      await tester.enterText(_agentMessageInput(), 'inactive-layout-draft-a');
      await tester.pump();
      final paneAElement = tester.element(find.byType(AgentPane));
      final draftController = tester
          .widget<EditableText>(_agentMessageInput())
          .controller;

      await tester.tap(threadBRow);
      await pumpUntilCondition(
        tester,
        () => headerTitleText(tester) == 'Thread B',
        failureMessage: 'Thread B did not open',
      );

      // keep-alive 离屏页默认 skipOffstage；需显式包含。
      final allAgentPanes = find.byType(AgentPane, skipOffstage: false);
      expect(allAgentPanes.evaluate().length, greaterThanOrEqualTo(2));
      expect(paneAElement.mounted, isTrue);
      expect(draftController.text, 'inactive-layout-draft-a');

      // 横向 resize 不应丢弃 keep-alive 会话的 State。
      for (var width = 1400; width >= 1100; width -= 20) {
        tester.view.physicalSize = Size(width.toDouble(), 900);
        await tester.pump();
      }

      expect(paneAElement.mounted, isTrue);
      expect(
        find.byType(AgentPane, skipOffstage: false).evaluate().length,
        greaterThanOrEqualTo(2),
      );
      expect(draftController.text, 'inactive-layout-draft-a');

      await tester.tap(threadARow);
      await pumpUntilCondition(
        tester,
        () =>
            headerTitleText(tester) == 'Thread A' &&
            tester.widget<EditableText>(_agentMessageInput()).controller.text ==
                'inactive-layout-draft-a',
        failureMessage: 'Thread A draft was not retained after resize',
      );
      expect(
        find
            .byType(AgentPane, skipOffstage: false)
            .evaluate()
            .any((element) => identical(element, paneAElement)),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('switching threads keeps each pane draft isolated', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('zeta_thread_tabs_');
    addTearDown(() {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });
    File(
      '${directory.path}${Platform.pathSeparator}sample.txt',
    ).writeAsStringSync('thread pane retention');

    final provider = FakeAgentProvider(
      threadHistories: <String, AgentThreadHistorySnapshot>{
        'thread-a': AgentThreadHistorySnapshot(
          threadId: 'thread-a',
          turns: <AgentHistoryTurn>[
            AgentHistoryTurn(
              id: 'turn-a-1',
              entries: const <AgentHistoryEntry>[
                AgentHistoryMessageEntry(
                  id: 'thread-a-history',
                  role: AgentMessageRole.agent,
                  text: 'Thread A history',
                ),
              ],
            ),
          ],
        ),
        'thread-b': AgentThreadHistorySnapshot(
          threadId: 'thread-b',
          turns: <AgentHistoryTurn>[
            AgentHistoryTurn(
              id: 'turn-b-1',
              entries: const <AgentHistoryEntry>[
                AgentHistoryMessageEntry(
                  id: 'thread-b-history',
                  role: AgentMessageRole.agent,
                  text: 'Thread B history',
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
              id: 'thread-a',
              projectPath: directory.path,
              title: 'Thread A',
            ),
            agentThread(
              id: 'thread-b',
              projectPath: directory.path,
              title: 'Thread B',
              lastActiveAt: DateTime.fromMillisecondsSinceEpoch(3),
            ),
          ],
          nextCursor: null,
        ),
      ],
    );

    await _pumpIde(
      tester,
      directoryPicker: () async => directory.path,
      agentProviderFactory: FakeAgentProviderFactory(provider),
      agentProviderConfigStore: MemoryAgentProviderConfigStore(),
    );

    await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
    await tester.runAsync(waitForIo);

    final threadARow = find.byKey(
      ValueKey<String>('project-thread-${directory.path}-thread-a'),
    );
    final threadBRow = find.byKey(
      ValueKey<String>('project-thread-${directory.path}-thread-b'),
    );
    await pumpUntilCondition(
      tester,
      () =>
          threadARow.evaluate().isNotEmpty && threadBRow.evaluate().isNotEmpty,
      failureMessage: 'Thread rows did not become ready',
    );

    await tester.tap(threadARow);
    await pumpUntilCondition(
      tester,
      () =>
          headerTitleText(tester) == 'Thread A' &&
          find.text('Thread A history').evaluate().isNotEmpty,
      failureMessage: 'Thread A pane did not become ready',
    );
    await tester.enterText(_agentMessageInput(), 'draft for thread a');
    await tester.pump();

    await tester.tap(threadBRow);
    await pumpUntilCondition(
      tester,
      () =>
          headerTitleText(tester) == 'Thread B' &&
          find.text('Thread B history').evaluate().isNotEmpty,
      failureMessage: 'Thread B pane did not become ready',
    );
    expect(
      tester.widget<EditableText>(_agentMessageInput()).controller.text,
      isEmpty,
    );
    await tester.enterText(_agentMessageInput(), 'draft for thread b');
    await tester.pump();

    await tester.tap(threadARow);
    await pumpUntilCondition(
      tester,
      () =>
          headerTitleText(tester) == 'Thread A' &&
          tester.widget<EditableText>(_agentMessageInput()).controller.text ==
              'draft for thread a',
      failureMessage: 'Thread A draft was not retained',
    );

    await tester.tap(threadBRow);
    await pumpUntilCondition(
      tester,
      () =>
          headerTitleText(tester) == 'Thread B' &&
          tester.widget<EditableText>(_agentMessageInput()).controller.text ==
              'draft for thread b',
      failureMessage: 'Thread B draft was not retained',
    );
  });

  testWidgets('selected project without a thread shows the project home', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'zeta_project_home_test_',
    );
    addTearDown(() {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });
    final threads = <AgentThreadSummary>[
      for (var index = 0; index < 6; index += 1)
        agentThread(
          id: 'home-thread-$index',
          projectPath: directory.path,
          title: 'Home thread $index',
          lastActiveAt: DateTime.utc(
            2026,
            7,
            21,
          ).subtract(Duration(hours: index)),
        ),
    ];
    final provider = FakeAgentProvider(
      threadPages: <AgentThreadPage>[
        AgentThreadPage(threads: threads, nextCursor: null),
      ],
    );
    await _pumpIde(
      tester,
      directoryPicker: () async => directory.path,
      agentProviderFactory: FakeAgentProviderFactory(provider),
      agentProviderConfigStore: MemoryAgentProviderConfigStore(),
    );

    await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
    await tester.runAsync(waitForIo);
    await pumpUntilCondition(
      tester,
      () =>
          find
              .byKey(const ValueKey<String>('project-home-header'))
              .hitTestable()
              .evaluate()
              .isNotEmpty &&
          find
              .byKey(
                const ValueKey<String>('project-home-thread-home-thread-0'),
              )
              .evaluate()
              .isNotEmpty,
      failureMessage: 'Project home did not become ready',
    );

    expect(find.text(directory.path), findsOneWidget);
    expect(
      find
          .byKey(const ValueKey<String>('project-home-new-thread-button'))
          .hitTestable(),
      findsOneWidget,
    );
    expect(_agentMessageInput().hitTestable(), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('project-home-thread-home-thread-4')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('project-home-thread-home-thread-5')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('project-home-thread-home-thread-0')),
    );
    await pumpUntilCondition(
      tester,
      () =>
          headerTitleText(tester) == 'Home thread 0' &&
          _agentMessageInput().hitTestable().evaluate().isNotEmpty,
      failureMessage: 'Recent thread did not open its Agent pane',
    );

    await tester.tap(
      find.byKey(ValueKey<String>('project-tile-${directory.path}')),
    );
    await tester.pump();
    expect(headerTitleText(tester), 'Home thread 0');
    expect(_agentMessageInput().hitTestable(), findsOneWidget);
  });

  testWidgets('opens a recent project from the global home', (tester) async {
    final directory = Directory.systemTemp.createTempSync(
      'zeta_global_home_project_',
    );
    addTearDown(() {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });
    final thread = agentThread(
      id: 'recent-project-thread',
      projectPath: directory.path,
      title: 'Recent project thread',
      lastActiveAt: DateTime.utc(2026, 7, 21, 12),
    );
    final session = IdeSessionState(
      projectPaths: <String>[directory.path],
      projectLastOpenedAtByPath: <String, DateTime>{
        directory.path: DateTime.utc(2026, 7, 21, 13),
      },
      projectThreadExpansionByProject: <String, bool>{directory.path: false},
      cachedThreadsByProject: <String, List<AgentThreadSummary>>{
        directory.path: <AgentThreadSummary>[thread],
      },
    );
    final provider = FakeAgentProvider(
      threadPages: <AgentThreadPage>[
        AgentThreadPage(
          threads: <AgentThreadSummary>[thread],
          nextCursor: null,
        ),
      ],
    );

    await _pumpIde(
      tester,
      initialSessionJson: session.encode(),
      agentProviderFactory: FakeAgentProviderFactory(provider),
      agentProviderConfigStore: MemoryAgentProviderConfigStore(
        const AgentProviderSettings(
          providers: <AgentProviderConfig>[AgentProviderConfig.defaultCodex],
        ),
      ),
      homeProviderDetectionLoader: () async => <ManagedAgent>[
        _installedAgent(AgentDefinition.codex),
        ManagedAgent.forDefinition(
          definition: AgentDefinition.grok,
          enabled: true,
        ).copyWith(installationState: AgentInstallationState.notInstalled),
      ],
    );
    await pumpUntilCondition(
      tester,
      () => find
          .byKey(ValueKey<String>('global-home-project-${directory.path}'))
          .evaluate()
          .isNotEmpty,
      failureMessage: 'Global home recent project did not become ready',
    );

    expect(find.text('Codex'), findsOneWidget);
    expect(find.text('Grok'), findsNothing);
    await tester.tap(
      find.byKey(ValueKey<String>('global-home-project-${directory.path}')),
    );
    await tester.runAsync(waitForIo);
    await pumpUntilCondition(
      tester,
      () => find
          .byKey(const ValueKey<String>('project-home-header'))
          .evaluate()
          .isNotEmpty,
      failureMessage: 'Recent project did not open its project home',
    );

    expect(find.text(directory.path), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-header-title')), findsNothing);
  });

  testWidgets('opens a recent thread from the global home', (tester) async {
    final directory = Directory.systemTemp.createTempSync(
      'zeta_global_home_thread_',
    );
    addTearDown(() {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });
    final thread = agentThread(
      id: 'recent-home-thread',
      projectPath: directory.path,
      title: 'Recent home thread',
      lastActiveAt: DateTime.utc(2026, 7, 21, 14),
    );
    final session = IdeSessionState(
      projectPaths: <String>[directory.path],
      projectThreadExpansionByProject: <String, bool>{directory.path: false},
      cachedThreadsByProject: <String, List<AgentThreadSummary>>{
        directory.path: <AgentThreadSummary>[thread],
      },
    );
    final provider = FakeAgentProvider(
      threadPages: <AgentThreadPage>[
        AgentThreadPage(
          threads: <AgentThreadSummary>[thread],
          nextCursor: null,
        ),
      ],
      threadHistories: <String, AgentThreadHistorySnapshot>{
        thread.id: AgentThreadHistorySnapshot(
          threadId: thread.id,
          turns: <AgentHistoryTurn>[
            AgentHistoryTurn(
              id: 'recent-home-turn',
              status: AgentHistoryTurnStatus.completed,
              entries: const <AgentHistoryEntry>[],
            ),
          ],
        ),
      },
    );

    await _pumpIde(
      tester,
      initialSessionJson: session.encode(),
      agentProviderFactory: FakeAgentProviderFactory(provider),
      agentProviderConfigStore: MemoryAgentProviderConfigStore(
        const AgentProviderSettings(
          providers: <AgentProviderConfig>[AgentProviderConfig.defaultCodex],
        ),
      ),
    );
    final recentThread = find.byKey(
      const ValueKey<String>('global-home-thread-codex-recent-home-thread'),
    );
    await pumpUntilCondition(
      tester,
      () => recentThread.evaluate().isNotEmpty,
      failureMessage: 'Global home recent thread did not become ready',
    );

    await tester.tap(recentThread);
    await tester.runAsync(waitForIo);
    await pumpUntilCondition(
      tester,
      () =>
          find
              .byKey(const ValueKey('agent-header-title'))
              .evaluate()
              .isNotEmpty &&
          headerTitleText(tester) == 'Recent home thread',
      failureMessage: 'Recent thread did not open its Agent canvas',
    );

    expect(_agentMessageInput().hitTestable(), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('global-home-page')),
      findsNothing,
    );
  });
}

Future<void> _pumpIde(
  WidgetTester tester, {
  Size size = const Size(1400, 900),
  bool enableNativeWindowFrame = false,
  Future<String?> Function()? directoryPicker,
  AgentProviderFactory? agentProviderFactory,
  AgentProviderConfigStore? agentProviderConfigStore,
  AgentUsagePanelRepository? agentUsagePanelRepository,
  String? initialSessionJson,
  Future<List<ManagedAgent>> Function()? homeProviderDetectionLoader,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(() {
    tester.view
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });

  final session = MemorySessionStore(initialSessionJson);

  await tester.pumpWidget(
    MainApp(
      enableNativeWindowFrame: enableNativeWindowFrame,
      showWindowControls: false,
      directoryPicker: directoryPicker,
      sessionLoader: session.load,
      sessionSaver: session.save,
      agentProviderFactory: agentProviderFactory,
      agentProviderConfigStore: agentProviderConfigStore,
      homeProviderDetectionLoader: homeProviderDetectionLoader,
      agentUsagePanelRepository:
          agentUsagePanelRepository ?? const _EmptyAgentUsageRepository(),
    ),
  );
}

ManagedAgent _installedAgent(AgentDefinition definition) {
  return ManagedAgent.forDefinition(
    definition: definition,
    enabled: true,
  ).copyWith(
    installationState: AgentInstallationState.installed,
    runtimeState: AgentRuntimeState.idle,
    currentVersion: '1.0.0',
  );
}

class _EmptyAgentUsageRepository implements AgentUsagePanelRepository {
  const _EmptyAgentUsageRepository();

  @override
  Stream<AgentUsagePanelLoadEvent> load({bool forceRefresh = false}) async* {
    yield AgentUsagePanelProvidersDiscovered(
      providers: const <AgentUsagePanelProvider>[],
    );
    yield AgentUsagePanelLoadCompleted(DateTime(2026, 7, 21));
  }
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

  final provider = _ModeCapableFakeAgentProvider(
    threadHistories: <String, AgentThreadHistorySnapshot>{
      'retained-thread': AgentThreadHistorySnapshot(
        threadId: 'retained-thread',
        turns: <AgentHistoryTurn>[
          AgentHistoryTurn(
            id: 'retained-turn',
            status: AgentHistoryTurnStatus.completed,
            entries: <AgentHistoryEntry>[
              AgentHistoryMessageEntry(
                id: 'retained-message',
                role: AgentMessageRole.agent,
                text: List<String>.generate(
                  24,
                  (line) =>
                      'Retained conversation line $line keeps the timeline '
                      'scrollable across workbench pages.',
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
  await tester.tap(find.byKey(const ValueKey('right-files-action')));
  await tester.pump();
  final retainedThreadRow = find.byKey(
    ValueKey<String>('project-thread-${directory.path}-retained-thread'),
  );
  await pumpUntilCondition(
    tester,
    () =>
        retainedThreadRow.evaluate().isNotEmpty &&
        find.byKey(fileNodeKey('sample.txt')).evaluate().isNotEmpty,
    failureMessage: 'Project and retained thread did not become ready',
  );
  await tester.tap(retainedThreadRow);

  final messageList = find.byKey(const ValueKey('agent-message-list'));
  await pumpUntilCondition(tester, () {
    if (headerTitleText(tester) != 'Retained thread' ||
        messageList.evaluate().isEmpty) {
      return false;
    }
    final controller = tester
        .widget<SingleChildScrollView>(messageList)
        .controller;
    return controller?.hasClients == true &&
        controller!.position.maxScrollExtent > 0;
  }, failureMessage: 'Retained thread history did not become ready');

  await tester.drag(
    find.byKey(const ValueKey('left-width-resize-handle')),
    const Offset(48, 0),
  );
  await tester.pump();

  final scrollController = tester
      .widget<SingleChildScrollView>(messageList)
      .controller!;
  scrollController.jumpTo(scrollController.position.maxScrollExtent / 2);
  await tester.pump();

  final modeSelector = find.byKey(const ValueKey('agent-mode-selector'));
  await pumpUntilCondition(
    tester,
    () => modeSelector.evaluate().isNotEmpty,
    failureMessage: 'Conversation mode selector did not become ready',
  );
  await tester.tap(modeSelector);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.byKey(const ValueKey('agent-mode-option-plan')));
  await pumpUntilCondition(
    tester,
    () => find
        .byKey(const ValueKey('agent-mode-selector-popover'))
        .evaluate()
        .isEmpty,
    failureMessage: 'Conversation mode selector did not close',
  );

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
    selectedMode: AgentConversationModeId.plan,
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
  expect(
    (retained.agentPaneElement.widget as AgentPane)
        .viewModel
        .selectedConversationMode,
    retained.selectedMode,
  );
  expect(
    find.descendant(
      of: find.byKey(const ValueKey('agent-mode-selector')),
      matching: find.textContaining('Plan'),
    ),
    findsOneWidget,
  );
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
    required this.selectedMode,
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
  final AgentConversationModeId selectedMode;
}

class _ModeCapableFakeAgentProvider extends FakeAgentProvider
    implements AgentConversationModeCatalogProvider {
  _ModeCapableFakeAgentProvider({
    required super.threadHistories,
    required super.threadPages,
  }) : super(
         declaredCapabilities: AgentProviderCapabilities.codexAppServer
             .copyWith(supportsModeSelection: true),
       );

  @override
  Future<AgentConversationModeCatalog> listConversationModes() async {
    return AgentConversationModeCatalog(
      presets: const <AgentConversationModePreset>[
        AgentConversationModePreset(
          id: AgentConversationModeId.defaultMode,
          displayName: 'Default',
        ),
        AgentConversationModePreset(
          id: AgentConversationModeId.plan,
          displayName: 'Plan',
          suggestedReasoningEffort: 'medium',
        ),
      ],
    );
  }
}

double _widthOf(WidgetTester tester, String key) {
  return tester.getSize(find.byKey(ValueKey<String>(key))).width;
}

double _heightOf(WidgetTester tester, String key) {
  return tester.getSize(find.byKey(ValueKey<String>(key))).height;
}

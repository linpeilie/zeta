import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/main.dart';
import 'package:zeta/src/app/app.dart' show MainAppState;
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/agent/presentation/agent_pane.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_view_model.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';
import 'package:zeta/src/features/ide_session/domain/ide_session_state.dart';
import 'package:zeta/src/features/ide_session/domain/ide_workbench_layout_state.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_panel_models.dart';
import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';
import 'package:zeta/src/ui/core/surfaces/ide_surface.dart';
import 'package:zeta/src/ui/features/ide/views/ide_home.dart';

import '../testing/agent_event_storm_fixture.dart';
import '../testing/ide_test_harness.dart';
import '../testing/widget_build_counter.dart';

void main() {
  tearDown(() {
    IdeHome.debugShowTrailingRail = false;
  });

  testWidgets('starts with the compact IDE panes', (tester) async {
    await _pumpIde(tester);
    await tester.pump();

    expect(find.text('Zeta'), findsNothing);
    expect(find.byKey(const ValueKey('projects-panel-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-pane-host')), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-panel-card')), findsNothing);
    expect(find.byKey(const ValueKey('files-panel-card')), findsNothing);
    expect(find.byKey(const ValueKey('context-panel-card')), findsNothing);
    expect(find.byKey(const ValueKey('tools-panel-card')), findsNothing);
    expect(find.byKey(const ValueKey('left-projects-action')), findsOneWidget);
    expect(find.byKey(const ValueKey('left-context-action')), findsOneWidget);
    expect(find.byKey(const ValueKey('right-files-action')), findsNothing);
    expect(find.byKey(const ValueKey('right-tools-action')), findsNothing);
    expect(find.byKey(const ValueKey('workbench-trailing-rail')), findsNothing);
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

  testWidgets('窗口从最小化恢复可重启全局 ticker', (tester) async {
    await _pumpIde(tester);
    final appState = tester.state<MainAppState>(find.byType(MainApp));
    final homeContext = tester.element(
      find.byKey(const ValueKey('global-home-page')),
    );

    appState.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(TickerMode.valuesOf(homeContext).enabled, isTrue);

    appState.onWindowMinimize();
    await tester.pump();
    expect(TickerMode.valuesOf(homeContext).enabled, isFalse);

    appState.onWindowRestore();
    await tester.pump();
    expect(TickerMode.valuesOf(homeContext).enabled, isTrue);

    // Windows 会把“最小化前为最大化”的恢复报告为 maximize。
    appState.onWindowMinimize();
    appState.onWindowMaximize();
    await tester.pump();
    expect(TickerMode.valuesOf(homeContext).enabled, isTrue);

    appState.onWindowMinimize();
    appState.onWindowFocus();
    await tester.pump();
    expect(TickerMode.valuesOf(homeContext).enabled, isTrue);

    appState.onWindowMinimize();
    appState.onWindowEvent('show');
    await tester.pump();
    expect(TickerMode.valuesOf(homeContext).enabled, isTrue);

    appState.didChangeAppLifecycleState(AppLifecycleState.hidden);
    await tester.pump();
    expect(TickerMode.valuesOf(homeContext).enabled, isFalse);
  });

  testWidgets(
    'startup refreshes hidden Agent statistics through event message',
    (tester) async {
      final repository = _TrackedAgentUsageRepository();

      await _pumpIde(
        tester,
        agentUsagePanelRepository: repository,
        flushInitialUsageRefresh: false,
      );

      expect(find.byKey(const ValueKey('context-panel-card')), findsNothing);
      expect(repository.forceRefreshValues, isEmpty);

      await _flushInitialUsageRefresh(tester);

      expect(repository.forceRefreshValues, <bool>[true]);
      expect(find.byKey(const ValueKey('context-panel-card')), findsNothing);
    },
  );

  testWidgets(
    'turn terminal selects and persists usage Provider before one silent refresh',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'zeta_usage_terminal_',
      );
      addTearDown(() {
        if (directory.existsSync()) {
          directory.deleteSync(recursive: true);
        }
      });
      final provider = FakeAgentProvider(
        completeTurns: false,
        threadPages: <AgentThreadPage>[
          AgentThreadPage(
            threads: <AgentThreadSummary>[
              agentThread(
                id: 'usage-terminal-thread',
                projectPath: directory.path,
                title: 'Usage terminal thread',
              ),
            ],
            nextCursor: null,
          ),
        ],
      );
      final repository = _TrackedDirectoryAgentUsageRepository();
      final session = MemorySessionStore(
        const IdeSessionState(
          workbenchLayout: IdeWorkbenchLayoutState(
            selectedAgentUsageProviderId: 'grok',
          ),
        ).encode(),
      );

      await _pumpIde(
        tester,
        directoryPicker: () async => directory.path,
        agentProviderFactory: FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
        agentUsagePanelRepository: repository,
        sessionStore: session,
      );
      expect(repository.forceRefreshValues, <bool>[true]);
      repository.forceRefreshValues.clear();

      await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
      await tester.runAsync(waitForIo);
      final threadRow = find.byKey(
        ValueKey<String>(
          'project-thread-${directory.path}-usage-terminal-thread',
        ),
      );
      await pumpUntilCondition(
        tester,
        () => threadRow.evaluate().isNotEmpty,
        failureMessage: 'Usage terminal thread did not become ready',
      );
      await tester.tap(threadRow);
      await pumpUntilCondition(
        tester,
        () => _agentMessageInput().hitTestable().evaluate().isNotEmpty,
        failureMessage: 'Usage terminal Agent canvas did not become ready',
      );
      final viewModel = tester
          .widget<AgentPane>(find.byType(AgentPane))
          .viewModel;
      final activeProviderBefore = viewModel.activeProviderId;

      await viewModel.sendMessage('finish and refresh usage');
      await pumpUntilCondition(
        tester,
        () => viewModel.isTurnRunning,
        failureMessage: 'Usage terminal turn did not start',
      );
      provider.emit(
        const AgentTurnCompletedEvent(
          sessionId: 'usage-terminal-thread',
          turnId: 'turn-1',
        ),
      );
      await pumpUntilCondition(
        tester,
        () => !viewModel.isTurnRunning,
        failureMessage: 'Usage terminal turn did not settle',
      );
      await tester.pump(const Duration(milliseconds: 1));
      await tester.idle();
      await tester.pump();

      expect(repository.forceRefreshValues, <bool>[true]);
      expect(viewModel.activeProviderId, activeProviderBefore);

      await tester.pump(const Duration(seconds: 1));
      await tester.idle();
      expect(
        IdeSessionState.tryDecode(
          session.value,
        )?.workbenchLayout.selectedAgentUsageProviderId,
        defaultAgentProviderId,
      );
    },
  );

  testWidgets('activity icons toggle side panel columns', (tester) async {
    _enableTrailingRailForTest();
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

  testWidgets(
    'switching existing left regions retains the active Agent pane state',
    (tester) async {
      final retained = await _prepareRetainedAgentState(tester);

      await tester.tap(find.byKey(const ValueKey('left-context-action')));
      await tester.pump();

      expect(find.byKey(const ValueKey('projects-panel-card')), findsOneWidget);
      expect(find.byKey(const ValueKey('context-panel-card')), findsOneWidget);
      _expectRetainedAgentContentState(tester, retained);

      await tester.tap(find.byKey(const ValueKey('left-projects-action')));
      await tester.pump();

      expect(find.byKey(const ValueKey('projects-panel-card')), findsNothing);
      expect(find.byKey(const ValueKey('context-panel-card')), findsOneWidget);
      _expectRetainedAgentContentState(tester, retained);

      await tester.tap(find.byKey(const ValueKey('left-context-action')));
      await tester.pump();

      expect(find.byKey(const ValueKey('projects-panel-card')), findsNothing);
      expect(find.byKey(const ValueKey('context-panel-card')), findsNothing);
      expect(
        find.byKey(const ValueKey('workbench-navigation-inline')),
        findsNothing,
      );
      _expectRetainedAgentContentState(tester, retained);

      await tester.tap(find.byKey(const ValueKey('left-projects-action')));
      await tester.pump();

      _expectRetainedAgentState(tester, retained);
    },
  );

  testWidgets('side panel cards own borders without workbench pane wrappers', (
    tester,
  ) async {
    _enableTrailingRailForTest();
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
    _enableTrailingRailForTest();
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
    _enableTrailingRailForTest();
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
    _enableTrailingRailForTest();
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

  testWidgets('records the current Agent event storm rebuild baseline', (
    tester,
  ) async {
    final fixture = AgentEventStormFixture();
    final directory = Directory.systemTemp.createTempSync(
      'zeta_agent_storm_baseline_',
    );
    addTearDown(() {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });
    final provider = FakeAgentProvider(
      completeTurns: false,
      // warmup 发送不能往 timeline 注入正文，否则污染 storm 字符基线。
      responseText: '',
      threadPages: <AgentThreadPage>[
        AgentThreadPage(
          threads: <AgentThreadSummary>[
            agentThread(
              id: fixture.sessionId,
              projectPath: directory.path,
              title: 'Storm baseline thread',
            ),
          ],
          nextCursor: null,
        ),
      ],
      threadHistories: <String, AgentThreadHistorySnapshot>{
        fixture.sessionId: AgentThreadHistorySnapshot(
          threadId: fixture.sessionId,
          turns: const <AgentHistoryTurn>[],
        ),
      },
    );
    await _pumpIde(
      tester,
      directoryPicker: () async => directory.path,
      agentProviderFactory: FakeAgentProviderFactory(provider),
      agentProviderConfigStore: MemoryAgentProviderConfigStore(),
    );

    await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
    await tester.runAsync(waitForIo);
    final threadRow = find.byKey(
      ValueKey<String>('project-thread-${directory.path}-${fixture.sessionId}'),
    );
    await pumpUntilCondition(
      tester,
      () => threadRow.evaluate().isNotEmpty,
      failureMessage: 'Storm baseline thread did not become ready',
    );
    await tester.tap(threadRow);
    await pumpUntilCondition(
      tester,
      () =>
          find.byType(AgentPane).evaluate().isNotEmpty &&
          find
              .byKey(const ValueKey('agent-message-list'))
              .evaluate()
              .isNotEmpty,
      failureMessage: 'Storm baseline AgentPane did not become ready',
    );

    final viewModel = tester
        .widget<AgentPane>(find.byType(AgentPane))
        .viewModel;
    // Binding 架构：打开历史 thread 不挂 live Pipeline；先发一条消息附着 runtime。
    await _attachLiveEventPipelineForStorm(
      tester,
      provider: provider,
      viewModel: viewModel,
      sessionId: fixture.sessionId,
    );
    final beforeBuffer = viewModel.eventCoalescingBufferDiagnostics;
    final beforeScheduler = viewModel.eventDispatcherDiagnostics;
    final beforeUi = viewModel.uiStateDiagnostics;
    final beforeUiScheduler = viewModel.uiUpdateSchedulerDiagnostics;
    expect(beforeBuffer, isNotNull);
    expect(beforeScheduler, isNotNull);

    var shellSnapshotNotifyCount = 0;
    void handleShellSnapshotChanged() {
      shellSnapshotNotifyCount += 1;
    }

    viewModel.threadSnapshotListenable.addListener(handleShellSnapshotChanged);
    addTearDown(
      () => viewModel.threadSnapshotListenable.removeListener(
        handleShellSnapshotChanged,
      ),
    );

    final buildCounter = TestWidgetBuildCounter()..start();
    addTearDown(buildCounter.dispose);
    for (final event in fixture.events) {
      provider.emit(event);
    }

    var drained = false;
    for (var pumpCount = 0; pumpCount < 50; pumpCount += 1) {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      final buffer = viewModel.eventCoalescingBufferDiagnostics;
      final scheduler = viewModel.eventDispatcherDiagnostics;
      if (buffer != null &&
          buffer.receivedEvents - beforeBuffer!.receivedEvents ==
              fixture.expectedInputEventCount &&
          scheduler?.currentQueueDepth == 0 &&
          !viewModel.isTurnRunning) {
        drained = true;
        break;
      }
    }
    expect(drained, isTrue, reason: 'Agent event storm did not drain');
    await tester.pump(const Duration(milliseconds: 32));
    await tester.pump();

    final afterBuffer = viewModel.eventCoalescingBufferDiagnostics!;
    final afterScheduler = viewModel.eventDispatcherDiagnostics!;
    final afterUi = viewModel.uiStateDiagnostics;
    final afterUiScheduler = viewModel.uiUpdateSchedulerDiagnostics;
    final buildCounts = buildCounter.snapshot();
    buildCounter.dispose();

    final messageCharacters = viewModel.timelineEntries
        .whereType<AgentMessageTimelineEntry>()
        .where((entry) => entry.message.role == AgentMessageRole.agent)
        .fold<int>(0, (sum, entry) => sum + entry.message.text.length);
    final reasoningCharacters = viewModel.timelineEntries
        .whereType<AgentToolTimelineEntry>()
        .where((entry) => entry.toolCall.kind == AgentToolKind.think)
        .fold<int>(
          0,
          (sum, entry) => sum + (entry.toolCall.content?.length ?? 0),
        );

    expect(messageCharacters, fixture.expectedMessageCharacters);
    expect(reasoningCharacters, fixture.expectedReasoningCharacters);
    expect(viewModel.permissionRequests, isEmpty);
    expect(viewModel.isTurnRunning, isFalse);
    expect(
      viewModel.visibleHistoryTurns.map((turn) => turn.id),
      contains(fixture.turnId),
    );
    expect(
      viewModel.timelineEntries.whereType<AgentMessageTimelineEntry>().map(
        (entry) => entry.message.text,
      ),
      contains(AgentEventStormFixture.errorMessage),
    );
    expect(shellSnapshotNotifyCount, 2);
    expect(afterUiScheduler.hasPendingRequest, isFalse);
    expect(afterUiScheduler.hasScheduledFrame, isFalse);
    expect(
      afterUiScheduler.publishCount - beforeUiScheduler.publishCount,
      afterUi.publishCount - beforeUi.publishCount,
    );
    expect(
      afterUiScheduler.publishedEffects - beforeUiScheduler.publishedEffects,
      greaterThan(0),
    );

    debugPrint(
      'agent-event-widget-baseline '
      'fixture=${fixture.expectedInputEventCount} '
      'buffer={received:${afterBuffer.receivedEvents - beforeBuffer!.receivedEvents},'
      'coalesced:${afterBuffer.coalescedEvents - beforeBuffer.coalescedEvents},'
      'barrier:${afterBuffer.barrierEvents - beforeBuffer.barrierEvents},'
      'direct:${afterBuffer.directPassThroughEvents - beforeBuffer.directPassThroughEvents},'
      'backpressure:${afterBuffer.backpressureFlushes - beforeBuffer.backpressureFlushes},'
      'maxPending:${afterBuffer.maxPendingKeys}} '
      'scheduler={delivered:${afterScheduler.deliveredEvents - beforeScheduler!.deliveredEvents},'
      'batches:${afterScheduler.batchCount - beforeScheduler.batchCount},'
      'yields:${afterScheduler.yieldCount - beforeScheduler.yieldCount},'
      'maxQueue:${afterScheduler.maxQueueDepth}} '
      'uiState={published:${afterUi.publishCount - beforeUi.publishCount}} '
      'uiFrame={scheduledFrames:${afterUiScheduler.scheduledFrames - beforeUiScheduler.scheduledFrames},'
      'framePublish:${afterUiScheduler.framePublishes - beforeUiScheduler.framePublishes},'
      'immediatePublish:${afterUiScheduler.immediatePublishes - beforeUiScheduler.immediatePublishes},'
      'invalidated:${afterUiScheduler.invalidatedFrameCallbacks - beforeUiScheduler.invalidatedFrameCallbacks},'
      'effects:${afterUiScheduler.publishedEffects - beforeUiScheduler.publishedEffects}} '
      'shellSnapshotNotify=$shellSnapshotNotifyCount '
      'builds=$buildCounts',
    );
  });

  testWidgets(
    'pure message deltas rebuild live timeline without notifying the Shell',
    (tester) async {
      final fixture = AgentEventStormFixture();
      final prepared = await _prepareEventStormAgentPane(
        tester,
        fixture: fixture,
        directoryPrefix: 'zeta_message_delta_phase1_',
      );
      final provider = prepared.provider;
      final viewModel = prepared.viewModel;

      final beforeStart = viewModel.eventCoalescingBufferDiagnostics!;
      provider.emit(fixture.events.whereType<AgentTurnStartedEvent>().single);
      await _drainAgentEventSubset(
        tester,
        viewModel: viewModel,
        beforeReceivedEvents: beforeStart.receivedEvents,
        expectedInputEventCount: 1,
      );
      expect(viewModel.isTurnRunning, isTrue);
      await tester.pump(const Duration(milliseconds: 32));
      await tester.pump();

      final messageEvents = fixture.events
          .whereType<AgentMessageDeltaEvent>()
          .toList(growable: false);
      expect(
        messageEvents,
        hasLength(AgentEventStormFixture.messageDeltaCount),
      );
      final beforeWarmup = viewModel.eventCoalescingBufferDiagnostics!;
      provider.emit(messageEvents.first);
      await _drainAgentEventSubset(
        tester,
        viewModel: viewModel,
        beforeReceivedEvents: beforeWarmup.receivedEvents,
        expectedInputEventCount: 1,
      );
      await tester.pump(const Duration(milliseconds: 32));
      await tester.pump();

      var shellSnapshotNotifyCount = 0;
      var headerStateNotifyCount = 0;
      var composerStateNotifyCount = 0;
      void handleShellSnapshotChanged() {
        shellSnapshotNotifyCount += 1;
      }

      void handleHeaderStateChanged() {
        headerStateNotifyCount += 1;
      }

      void handleComposerStateChanged() {
        composerStateNotifyCount += 1;
      }

      viewModel.threadSnapshotListenable.addListener(
        handleShellSnapshotChanged,
      );
      viewModel.headerStateListenable.addListener(handleHeaderStateChanged);
      viewModel.composerStateListenable.addListener(handleComposerStateChanged);
      addTearDown(() {
        viewModel.threadSnapshotListenable.removeListener(
          handleShellSnapshotChanged,
        );
        viewModel.headerStateListenable.removeListener(
          handleHeaderStateChanged,
        );
        viewModel.composerStateListenable.removeListener(
          handleComposerStateChanged,
        );
      });

      final beforeBuffer = viewModel.eventCoalescingBufferDiagnostics!;
      final buildCounter = TestWidgetBuildCounter()..start();
      final localTimelineBuildCounter = _LocalTimelineBuildCounter()..start();
      addTearDown(buildCounter.dispose);
      addTearDown(localTimelineBuildCounter.dispose);
      for (final event in messageEvents.skip(1)) {
        provider.emit(event);
      }

      await _drainAgentEventSubset(
        tester,
        viewModel: viewModel,
        beforeReceivedEvents: beforeBuffer.receivedEvents,
        expectedInputEventCount: AgentEventStormFixture.messageDeltaCount - 1,
      );
      await tester.pump(const Duration(milliseconds: 32));
      await tester.pump();

      final buildCounts = buildCounter.snapshot();
      final localTimelineBuildCount = localTimelineBuildCounter.count;
      localTimelineBuildCounter.dispose();
      buildCounter.dispose();
      final messageCharacters = viewModel.timelineEntries
          .whereType<AgentMessageTimelineEntry>()
          .where((entry) => entry.message.role == AgentMessageRole.agent)
          .fold<int>(0, (sum, entry) => sum + entry.message.text.length);

      expect(messageCharacters, fixture.expectedMessageCharacters);
      expect(shellSnapshotNotifyCount, 0);
      expect(headerStateNotifyCount, 0);
      expect(composerStateNotifyCount, 0);
      expect(buildCounts[AgentBuildTarget.ideHome], 0);
      expect(buildCounts[AgentBuildTarget.agentPane], 0);
      expect(buildCounts[AgentBuildTarget.header], 0);
      expect(buildCounts[AgentBuildTarget.composer], 0);
      expect(buildCounts[AgentBuildTarget.liveTimeline], 0);
      expect(localTimelineBuildCount, greaterThan(0));

      debugPrint(
        'agent-event-phase1-message '
        'shellSnapshotNotify=$shellSnapshotNotifyCount '
        'headerStateNotify=$headerStateNotifyCount '
        'composerStateNotify=$composerStateNotifyCount '
        'localTimelineBuild=$localTimelineBuildCount '
        'builds=$buildCounts',
      );
    },
  );

  testWidgets(
    'reasoning and tool progress rebuild live timeline without notifying Shell',
    (tester) async {
      final fixture = AgentEventStormFixture();
      final prepared = await _prepareEventStormAgentPane(
        tester,
        fixture: fixture,
        directoryPrefix: 'zeta_reasoning_tool_phase1_',
      );
      final provider = prepared.provider;
      final viewModel = prepared.viewModel;

      final beforeStart = viewModel.eventCoalescingBufferDiagnostics!;
      provider.emit(fixture.events.whereType<AgentTurnStartedEvent>().single);
      await _drainAgentEventSubset(
        tester,
        viewModel: viewModel,
        beforeReceivedEvents: beforeStart.receivedEvents,
        expectedInputEventCount: 1,
      );
      expect(viewModel.isTurnRunning, isTrue);
      await tester.pump(const Duration(milliseconds: 32));
      await tester.pump();

      var shellSnapshotNotifyCount = 0;
      void handleShellSnapshotChanged() {
        shellSnapshotNotifyCount += 1;
      }

      viewModel.threadSnapshotListenable.addListener(
        handleShellSnapshotChanged,
      );
      addTearDown(
        () => viewModel.threadSnapshotListenable.removeListener(
          handleShellSnapshotChanged,
        ),
      );

      final streamEvents = fixture.events
          .where((event) {
            return event is AgentReasoningDeltaEvent ||
                event is AgentToolCallEvent &&
                    event.toolCall.status == AgentToolStatus.inProgress;
          })
          .toList(growable: false);
      expect(
        streamEvents,
        hasLength(
          AgentEventStormFixture.reasoningDeltaCount +
              AgentEventStormFixture.toolProgressCount,
        ),
      );

      final beforeBuffer = viewModel.eventCoalescingBufferDiagnostics!;
      final buildCounter = TestWidgetBuildCounter()..start();
      final localTimelineBuildCounter = _LocalTimelineBuildCounter()..start();
      addTearDown(buildCounter.dispose);
      addTearDown(localTimelineBuildCounter.dispose);
      for (final event in streamEvents) {
        provider.emit(event);
      }

      await _drainAgentEventSubset(
        tester,
        viewModel: viewModel,
        beforeReceivedEvents: beforeBuffer.receivedEvents,
        expectedInputEventCount: streamEvents.length,
      );
      await tester.pump(const Duration(milliseconds: 32));
      await tester.pump();

      final buildCounts = buildCounter.snapshot();
      final localTimelineBuildCount = localTimelineBuildCounter.count;
      localTimelineBuildCounter.dispose();
      buildCounter.dispose();
      final reasoningCharacters = viewModel.timelineEntries
          .whereType<AgentToolTimelineEntry>()
          .where((entry) => entry.toolCall.kind == AgentToolKind.think)
          .fold<int>(
            0,
            (sum, entry) => sum + (entry.toolCall.content?.length ?? 0),
          );
      final progressTools = viewModel.timelineEntries
          .whereType<AgentToolTimelineEntry>()
          .where((entry) => entry.toolCall.kind == AgentToolKind.execute)
          .map((entry) => entry.toolCall)
          .toList(growable: false);

      expect(reasoningCharacters, fixture.expectedReasoningCharacters);
      expect(progressTools, hasLength(AgentEventStormFixture.toolCount));
      expect(
        progressTools,
        everyElement(
          isA<AgentToolCall>()
              .having(
                (tool) => tool.status,
                'status',
                AgentToolStatus.inProgress,
              )
              .having((tool) => tool.content, 'content', 'progress'),
        ),
      );
      expect(shellSnapshotNotifyCount, 0);
      expect(buildCounts[AgentBuildTarget.ideHome], 0);
      expect(buildCounts[AgentBuildTarget.agentPane], 0);
      expect(buildCounts[AgentBuildTarget.liveTimeline], 0);
      expect(localTimelineBuildCount, greaterThan(0));

      debugPrint(
        'agent-event-phase1-reasoning-tool '
        'shellSnapshotNotify=$shellSnapshotNotifyCount '
        'localTimelineBuild=$localTimelineBuildCount '
        'builds=$buildCounts',
      );
    },
  );

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
        find.byKey(const ValueKey('workbench-leading-rail')),
        findsNothing,
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

      // 设置页不依赖 Activity Rail；窄窗口也必须保留可见的设置分区导航。
      tester.view.physicalSize = const Size(700, 900);
      await tester.pump();

      expect(
        find.byKey(const ValueKey('workbench-leading-rail')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('workbench-navigation-inline')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('settings-nav-panel')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('settings-navigation-action')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(1400, 900);
      await tester.pump();

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
    expect(find.byKey(const ValueKey('workbench-leading-rail')), findsNothing);
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

    // 外窗 1197 / 1196 / 1195px 精确跨越 WindowFrame 内层 wide 断点。
    for (final width in <double>[1197, 1196, 1195, 1196, 1197]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pump();
      expect(
        tester.element(find.byType(AgentPane)),
        same(retained.agentPaneElement),
      );
      expect(retained.inputController.text, retained.draft);
      expect(retained.agentPaneElement.mounted, isTrue);
    }

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
        .widget<ScrollView>(find.byKey(const ValueKey('agent-message-list')))
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
  Future<List<AgentProviderConfig>> Function()? agentProviderAvailabilityLoader,
  AgentUsagePanelRepository? agentUsagePanelRepository,
  String? initialSessionJson,
  MemorySessionStore? sessionStore,
  Future<List<ManagedAgent>> Function()? homeProviderDetectionLoader,
  bool flushInitialUsageRefresh = true,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(() {
    tester.view
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });

  final session = sessionStore ?? MemorySessionStore(initialSessionJson);

  await tester.pumpWidget(
    MainApp(
      enableNativeWindowFrame: enableNativeWindowFrame,
      showWindowControls: false,
      directoryPicker: directoryPicker,
      sessionLoader: session.load,
      sessionSaver: session.save,
      agentProviderFactory: agentProviderFactory,
      agentProviderConfigStore: agentProviderConfigStore,
      agentProviderAvailabilityLoader: agentProviderAvailabilityLoader,
      homeProviderDetectionLoader: homeProviderDetectionLoader,
      agentUsagePanelRepository:
          agentUsagePanelRepository ?? const _EmptyAgentUsageRepository(),
    ),
  );
  if (flushInitialUsageRefresh) {
    await _flushInitialUsageRefresh(tester);
  }
}

Future<void> _flushInitialUsageRefresh(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 1));
  await tester.idle();
  await tester.pump();
}

Future<({FakeAgentProvider provider, AgentConversationViewModel viewModel})>
_prepareEventStormAgentPane(
  WidgetTester tester, {
  required AgentEventStormFixture fixture,
  required String directoryPrefix,
}) async {
  final directory = Directory.systemTemp.createTempSync(directoryPrefix);
  addTearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });
  final provider = FakeAgentProvider(
    completeTurns: false,
    // warmup 发送不能往 timeline 注入正文，否则污染 storm 字符基线。
    responseText: '',
    threadPages: <AgentThreadPage>[
      AgentThreadPage(
        threads: <AgentThreadSummary>[
          agentThread(
            id: fixture.sessionId,
            projectPath: directory.path,
            title: 'Storm phase 1 thread',
          ),
        ],
        nextCursor: null,
      ),
    ],
    threadHistories: <String, AgentThreadHistorySnapshot>{
      fixture.sessionId: AgentThreadHistorySnapshot(
        threadId: fixture.sessionId,
        turns: const <AgentHistoryTurn>[],
      ),
    },
  );
  await _pumpIde(
    tester,
    directoryPicker: () async => directory.path,
    agentProviderFactory: FakeAgentProviderFactory(provider),
    agentProviderConfigStore: MemoryAgentProviderConfigStore(),
  );

  await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
  await tester.runAsync(waitForIo);
  final threadRow = find.byKey(
    ValueKey<String>('project-thread-${directory.path}-${fixture.sessionId}'),
  );
  await pumpUntilCondition(
    tester,
    () => threadRow.evaluate().isNotEmpty,
    failureMessage: 'Storm phase 1 thread did not become ready',
  );
  await tester.tap(threadRow);
  await pumpUntilCondition(
    tester,
    () =>
        find.byType(AgentPane).evaluate().isNotEmpty &&
        find.byKey(const ValueKey('agent-message-list')).evaluate().isNotEmpty,
    failureMessage: 'Storm phase 1 AgentPane did not become ready',
  );

  final viewModel = tester.widget<AgentPane>(find.byType(AgentPane)).viewModel;
  await _attachLiveEventPipelineForStorm(
    tester,
    provider: provider,
    viewModel: viewModel,
    sessionId: fixture.sessionId,
  );

  return (provider: provider, viewModel: viewModel);
}

/// 打开历史 thread 后不会建立 live 订阅；storm 测试通过一次发送附着 session
/// runtime，再收尾 warmup turn，避免干扰后续 fixture 事件。
Future<void> _attachLiveEventPipelineForStorm(
  WidgetTester tester, {
  required FakeAgentProvider provider,
  required AgentConversationViewModel viewModel,
  required String sessionId,
}) async {
  final sentBefore = provider.sentMessages.length;
  await tester.enterText(
    find.byKey(const ValueKey('agent-message-input')),
    '__storm_attach__',
  );
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('agent-send-button')));
  await pumpUntilCondition(
    tester,
    () =>
        viewModel.eventCoalescingBufferDiagnostics != null &&
        provider.sentMessages.length > sentBefore,
    failureMessage: 'Live event pipeline did not attach after send',
  );
  final turnId = 'turn-${provider.sentMessages.length}';
  provider.emit(AgentTurnCompletedEvent(sessionId: sessionId, turnId: turnId));
  await pumpUntilCondition(
    tester,
    () => !viewModel.isTurnRunning,
    failureMessage: 'Warmup turn did not settle after explicit completion',
  );
}

Future<void> _drainAgentEventSubset(
  WidgetTester tester, {
  required AgentConversationViewModel viewModel,
  required int beforeReceivedEvents,
  required int expectedInputEventCount,
}) async {
  for (var pumpCount = 0; pumpCount < 50; pumpCount += 1) {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final buffer = viewModel.eventCoalescingBufferDiagnostics;
    final scheduler = viewModel.eventDispatcherDiagnostics;
    if (buffer != null &&
        buffer.receivedEvents - beforeReceivedEvents ==
            expectedInputEventCount &&
        buffer.currentPendingKeys == 0 &&
        scheduler?.currentQueueDepth == 0) {
      return;
    }
  }
  fail(
    'Agent event subset did not drain '
    '(expected $expectedInputEventCount inputs)',
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

class _TrackedAgentUsageRepository implements AgentUsagePanelRepository {
  final List<bool> forceRefreshValues = <bool>[];

  @override
  Stream<AgentUsagePanelLoadEvent> load({bool forceRefresh = false}) async* {
    forceRefreshValues.add(forceRefresh);
    yield AgentUsagePanelProvidersDiscovered(
      providers: const <AgentUsagePanelProvider>[],
    );
    yield AgentUsagePanelLoadCompleted(DateTime(2026, 7, 21));
  }
}

class _TrackedDirectoryAgentUsageRepository
    implements AgentUsagePanelRepository {
  final List<bool> forceRefreshValues = <bool>[];

  @override
  Stream<AgentUsagePanelLoadEvent> load({bool forceRefresh = false}) async* {
    forceRefreshValues.add(forceRefresh);
    yield AgentUsagePanelProvidersDiscovered(
      providers: const <AgentUsagePanelProvider>[
        AgentUsagePanelProvider(providerId: 'codex', providerName: 'Codex'),
        AgentUsagePanelProvider(providerId: 'grok', providerName: 'Grok'),
      ],
    );
    yield AgentUsagePanelLoadCompleted(DateTime(2026, 7, 21));
  }
}

void _enableTrailingRailForTest() {
  IdeHome.debugShowTrailingRail = true;
}

Future<_RetainedAgentState> _prepareRetainedAgentState(
  WidgetTester tester,
) async {
  _enableTrailingRailForTest();
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
    final controller = tester.widget<ScrollView>(messageList).controller;
    return controller?.hasClients == true &&
        controller!.position.maxScrollExtent > 0;
  }, failureMessage: 'Retained thread history did not become ready');

  await tester.drag(
    find.byKey(const ValueKey('left-width-resize-handle')),
    const Offset(48, 0),
  );
  await tester.pump();

  final scrollController = tester.widget<ScrollView>(messageList).controller!;
  scrollController.jumpTo(scrollController.position.maxScrollExtent / 2);
  await tester.pump();

  final moreActionsButton = find.byKey(
    const ValueKey('agent-more-actions-button'),
  );
  await pumpUntilCondition(
    tester,
    () => moreActionsButton.evaluate().isNotEmpty,
    failureMessage: 'Composer more-actions button did not become ready',
  );
  await tester.tap(moreActionsButton);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.byKey(const ValueKey('agent-more-actions-plan')));
  await pumpUntilCondition(
    tester,
    () => find
        .byKey(const ValueKey('agent-composer-plan-badge'))
        .evaluate()
        .isNotEmpty,
    failureMessage: 'Plan badge did not appear after selecting Plan',
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
  _expectRetainedAgentContentState(tester, retained);
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
}

void _expectRetainedAgentContentState(
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
      .widget<ScrollView>(find.byKey(const ValueKey('agent-message-list')))
      .controller!;
  expect(currentScrollController, same(retained.scrollController));
  expect(currentScrollController.offset, closeTo(retained.scrollOffset, 0.1));
  expect(headerTitleText(tester), 'Retained thread');
  expect(
    (retained.agentPaneElement.widget as AgentPane)
        .viewModel
        .selectedConversationMode,
    retained.selectedMode,
  );
  expect(
    find.byKey(const ValueKey('agent-composer-plan-badge')),
    findsOneWidget,
  );
  expect(
    find.descendant(
      of: find.byKey(const ValueKey('agent-composer-plan-badge')),
      matching: find.text('Plan'),
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

/// 统计 `_AgentConversationTimeline` 内部 listenable builder 的局部重建。
///
/// 阶段 0 的通用计数器统计 Widget runtimeType；流式更新不会重建 timeline 外壳，
/// 因此这里通过 Element 祖先关系补充观察内部内容刷新，且不向生产 UI 注入 API。
final class _LocalTimelineBuildCounter {
  late final RebuildDirtyWidgetCallback _callback = _handleRebuild;
  RebuildDirtyWidgetCallback? _previousCallback;
  bool _started = false;
  int count = 0;

  void start() {
    if (_started) {
      return;
    }
    _started = true;
    _previousCallback = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = _callback;
  }

  void dispose() {
    if (!_started) {
      return;
    }
    if (identical(debugOnRebuildDirtyWidget, _callback)) {
      debugOnRebuildDirtyWidget = _previousCallback;
    }
    _previousCallback = null;
    _started = false;
  }

  void _handleRebuild(Element element, bool builtOnce) {
    _previousCallback?.call(element, builtOnce);
    if (element.widget.runtimeType.toString() != 'ListenableBuilder') {
      return;
    }
    var belongsToTimeline = false;
    element.visitAncestorElements((ancestor) {
      if (ancestor.widget.runtimeType.toString() ==
          AgentBuildTarget.liveTimeline) {
        belongsToTimeline = true;
        return false;
      }
      return true;
    });
    if (belongsToTimeline) {
      count += 1;
    }
  }
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

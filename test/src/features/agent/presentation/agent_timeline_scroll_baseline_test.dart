import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/main.dart';
import 'package:zeta/src/features/agent/application/agent_ui_update_request.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/presentation/agent_pane.dart';
import 'package:zeta/src/features/ide_session/domain/ide_session_state.dart';

import '../../../../support/scroll_metrics_trace.dart';
import '../../../testing/ide_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tempDirectories = <Directory>[];

  tearDown(() {
    for (final directory in tempDirectories) {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    }
    tempDirectories.clear();
  });

  testWidgets(
    'baseline characterization: mixed heights re-estimate max extent and thumb proxy',
    (tester) async {
      _configureTestView(tester, const Size(400, 600));
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final builtIds = <int>{};
      const scrollKey = ValueKey<String>('baseline-mixed-scroll');
      final trace = ScrollMetricsTrace('A');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              key: scrollKey,
              controller: controller,
              slivers: <Widget>[
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      builtIds.add(index);
                      return SizedBox(
                        key: ValueKey<String>('baseline-item-$index'),
                        height: _mixedExtent(index),
                        child: Text('item-$index'),
                      );
                    },
                    childCount: 2000,
                    addAutomaticKeepAlives: false,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      final scrollView = find.byKey(scrollKey);
      final initial = trace.capture(
        tester,
        label: 'initial',
        scrollView: scrollView,
        itemKeyPrefix: 'baseline-item-',
      );
      expect(builtIds.length, lessThan(100), reason: '首帧必须保持虚拟化：$initial');
      expect(initial.builtChildCount, lessThan(100), reason: '$initial');

      controller.jumpTo(1800);
      await tester.pump();
      final beforeExtreme = trace.capture(
        tester,
        label: 'before-extreme',
        scrollView: scrollView,
        itemKeyPrefix: 'baseline-item-',
      );

      controller.jumpTo(2600);
      await tester.pump();
      final afterExtreme = trace.capture(
        tester,
        label: 'after-extreme',
        scrollView: scrollView,
        itemKeyPrefix: 'baseline-item-',
      );

      final maxExtentCorrection =
          afterExtreme.maxScrollExtent - beforeExtreme.maxScrollExtent;
      expect(
        maxExtentCorrection.abs(),
        greaterThan(80),
        reason:
            '首次布局 2000px item 后应出现远大于普通短项的 extent 修正：'
            '$beforeExtreme -> $afterExtreme',
      );
      expect(
        afterExtreme.normalizedOffset,
        lessThan(beforeExtreme.normalizedOffset),
        reason:
            'pixels 增加时 normalized offset 反向变化，表征 thumb 停滞/跳变：'
            '$beforeExtreme -> $afterExtreme',
      );

      ScrollMetricsSample finalSample = afterExtreme;
      for (var attempt = 0; attempt < 12; attempt += 1) {
        controller.jumpTo(controller.position.maxScrollExtent);
        await tester.pump();
        finalSample = trace.capture(
          tester,
          label: 'end-$attempt',
          scrollView: scrollView,
          itemKeyPrefix: 'baseline-item-',
        );
        if (finalSample.extentAfter <= 0.5 &&
            finalSample.pixels <= finalSample.maxScrollExtent + 0.5) {
          break;
        }
      }
      expect(
        finalSample.extentAfter,
        lessThanOrEqualTo(0.5),
        reason: '重复跟随当前 max extent 后应最终到达列表末尾：$finalSample',
      );
      expect(
        finalSample.builtChildCount,
        lessThan(100),
        reason: '$finalSample',
      );
      expect(
        finalSample.visibleChildCount,
        lessThan(30),
        reason: '$finalSample',
      );
    },
  );

  testWidgets(
    'baseline characterization: Agent streaming follows bottom but respects manual scroll',
    (tester) async {
      _configureTestView(tester, const Size(1400, 700));
      final directory = Directory.systemTemp.createTempSync(
        'zeta_scroll_baseline_',
      );
      tempDirectories.add(directory);
      final provider = FakeAgentProvider(
        completeTurns: false,
        includeConversationTestThread: true,
        threadHistories: <String, AgentThreadHistorySnapshot>{
          conversationTestThreadId: AgentThreadHistorySnapshot(
            threadId: conversationTestThreadId,
            turns: <AgentHistoryTurn>[
              AgentHistoryTurn(
                id: 'history-stream-baseline',
                entries: <AgentHistoryEntry>[
                  for (var index = 0; index < 24; index += 1)
                    AgentHistoryMessageEntry(
                      id: 'stream-history-$index',
                      role: AgentMessageRole.agent,
                      text: 'Fixed history line $index',
                    ),
                ],
              ),
            ],
          ),
        },
        responseText: List<String>.generate(
          180,
          (index) => 'Streaming baseline line $index',
        ).join('\n'),
      );
      final session = _activeProjectSession(directory);

      await tester.pumpWidget(
        MainApp(
          enableNativeWindowFrame: false,
          sessionLoader: session.load,
          sessionSaver: session.save,
          agentProviderFactory: FakeAgentProviderFactory(provider),
          agentProviderConfigStore: MemoryAgentProviderConfigStore(),
        ),
      );
      await _openConversation(tester);
      await tester.enterText(
        find.byKey(const ValueKey<String>('agent-message-input')),
        'Start baseline stream',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('agent-send-button')));
      await _pumpLiveUi(tester);

      final scrollView = find.byKey(
        const ValueKey<String>('agent-message-list'),
      );
      final controller = tester.widget<ScrollView>(scrollView).controller!;
      final pane = tester.widget<AgentPane>(find.byType(AgentPane));
      var autoScrollNotifications = 0;
      final effectSubscription = pane.viewModel.uiEffects.listen((effect) {
        if (effect is AgentRequestAutoScroll) {
          autoScrollNotifications += 1;
        }
      });
      addTearDown(effectSubscription.cancel);
      final trace = ScrollMetricsTrace('B');

      await _pumpUntilScrollMetricsStable(tester, controller);
      controller.jumpTo(controller.position.maxScrollExtent);
      await _pumpUntilScrollMetricsStable(tester, controller);
      final bottomBefore = trace.capture(
        tester,
        label: 'bottom-before',
        scrollView: scrollView,
        itemKeyPrefix: 'timeline-viewport-',
      );

      for (var index = 0; index < 3; index += 1) {
        final repeatedContent = List<String>.filled(20, 'content').join(' ');
        provider.emit(
          AgentMessageDeltaEvent(
            messageId: 'message-1',
            delta: '\nBottom growth $index $repeatedContent',
            role: AgentMessageRole.agent,
            phase: AgentMessagePhase.response,
            sessionId: 'thread-1',
            turnId: 'turn-1',
          ),
        );
        await _pumpLiveUi(tester);
        await _pumpUntilScrollMetricsStable(tester, controller);
        trace.capture(
          tester,
          label: 'bottom-growth-$index',
          scrollView: scrollView,
          itemKeyPrefix: 'timeline-viewport-',
        );
      }
      final bottomAfter = trace.samples.last;
      expect(
        bottomAfter.endDistance,
        lessThanOrEqualTo(48),
        reason: '当前 48px 阈值内应继续跟随：$bottomBefore -> $bottomAfter',
      );

      controller.jumpTo(0);
      await _pumpUntilScrollMetricsStable(tester, controller);
      final freeBefore = trace.capture(
        tester,
        label: 'free-before',
        scrollView: scrollView,
        itemKeyPrefix: 'timeline-viewport-',
      );
      final freeGrowth = List<String>.filled(40, 'content').join(' ');
      provider.emit(
        AgentMessageDeltaEvent(
          messageId: 'message-1',
          delta: '\nFree mode growth $freeGrowth',
          role: AgentMessageRole.agent,
          phase: AgentMessagePhase.response,
          sessionId: 'thread-1',
          turnId: 'turn-1',
        ),
      );
      await _pumpLiveUi(tester);
      await _pumpUntilScrollMetricsStable(tester, controller);
      final freeAfter = trace.capture(
        tester,
        label: 'free-after',
        scrollView: scrollView,
        itemKeyPrefix: 'timeline-viewport-',
      );

      expect(
        freeAfter.pixels,
        closeTo(freeBefore.pixels, 1),
        reason: '手动离开底部后不应被抢回：$freeBefore -> $freeAfter',
      );
      expect(
        autoScrollNotifications,
        4,
        reason: '四次受控 delta 应合并为四次等价 auto-scroll 事件',
      );
    },
  );

  testWidgets('turn 完成迁入 history 后保持自由阅读锚点', (tester) async {
    _configureTestView(tester, const Size(1400, 700));
    final directory = Directory.systemTemp.createTempSync(
      'zeta_turn_completion_anchor_',
    );
    tempDirectories.add(directory);
    final provider = FakeAgentProvider(
      completeTurns: false,
      includeConversationTestThread: true,
      responseText: List<String>.generate(
        160,
        (index) => 'Stable completion anchor line $index',
      ).join('\n'),
    );
    final session = _activeProjectSession(directory);

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );
    await _openConversation(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('agent-message-input')),
      'Keep my reading position',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('agent-send-button')));
    await _pumpLiveUi(tester);

    final scrollView = find.byKey(const ValueKey<String>('agent-message-list'));
    final controller = tester.widget<ScrollView>(scrollView).controller!;
    await _pumpUntilScrollMetricsStable(tester, controller);
    controller.jumpTo(controller.position.maxScrollExtent);
    await _pumpUntilScrollMetricsStable(tester, controller);

    await tester.drag(scrollView, const Offset(0, 320));
    await _pumpUntilScrollMetricsStable(tester, controller);
    final messageKey = const ValueKey<String>(
      'timeline-viewport-turn-block-turn-1-message-message-1',
    );
    expect(find.byKey(messageKey), findsOneWidget);
    final pixelsBefore = controller.position.pixels;
    final messageTopBefore = itemViewportTop(
      tester,
      scrollView: scrollView,
      itemKey: messageKey,
    );
    expect(
      controller.position.maxScrollExtent - pixelsBefore,
      greaterThan(48),
      reason: '测试必须先进入离底部足够远的自由阅读状态。',
    );

    provider.emit(
      const AgentTurnCompletedEvent(sessionId: 'thread-1', turnId: 'turn-1'),
    );
    await _pumpLiveUi(tester);
    await _pumpUntilScrollMetricsStable(tester, controller);

    expect(find.byKey(messageKey), findsOneWidget);
    expect(
      controller.position.pixels,
      closeTo(pixelsBefore, 1),
      reason: 'live → history 不能因 item 身份变化把自由阅读位置拉回 turn 开头。',
    );
    expect(
      itemViewportTop(tester, scrollView: scrollView, itemKey: messageKey),
      closeTo(messageTopBefore, 1),
      reason: '完成迁移后当前消息应保持原视口坐标。',
    );
    expect(
      find.byKey(
        const ValueKey<String>('timeline-viewport-live-activity-turn-1'),
      ),
      findsNothing,
    );
  });

  testWidgets(
    'baseline characterization: command before and file edit after anchor move differently',
    (tester) async {
      _configureTestView(tester, const Size(1000, 450));
      final directory = Directory.systemTemp.createTempSync(
        'zeta_expand_baseline_',
      );
      tempDirectories.add(directory);
      const turnId = 'turn-baseline';
      const commandToolId = 'command-baseline';
      const editToolId = 'edit-baseline';
      const anchorEntryId = 'history-anchor';
      final provider = FakeAgentProvider(
        threadHistories: <String, AgentThreadHistorySnapshot>{
          'thread-baseline': AgentThreadHistorySnapshot(
            threadId: 'thread-baseline',
            turns: <AgentHistoryTurn>[
              AgentHistoryTurn(
                id: turnId,
                entries: <AgentHistoryEntry>[
                  for (var index = 0; index < 12; index += 1)
                    AgentHistoryMessageEntry(
                      id: 'history-before-$index',
                      role: AgentMessageRole.agent,
                      text: 'Before anchor message $index',
                    ),
                  AgentHistoryToolEntry(
                    toolCall: AgentToolCall(
                      id: commandToolId,
                      title: 'Baseline command',
                      kind: AgentToolKind.execute,
                      status: AgentToolStatus.completed,
                      content: 'flutter test',
                    ),
                  ),
                  const AgentHistoryEventEntry(
                    id: 'search-baseline',
                    kind: AgentHistoryEventKind.search,
                    title: 'Baseline search',
                    description: 'deterministic query',
                  ),
                  const AgentHistoryMessageEntry(
                    id: anchorEntryId,
                    role: AgentMessageRole.agent,
                    text: 'Stable visual anchor',
                  ),
                  AgentHistoryToolEntry(
                    toolCall: AgentToolCall(
                      id: editToolId,
                      title: 'Baseline edit',
                      kind: AgentToolKind.edit,
                      status: AgentToolStatus.completed,
                      locations: <String>['lib/example.dart'],
                      rawOutput: patchApplyChanges(<String, String?>{
                        'lib/example.dart':
                            '@@ -1 +1,18 @@\n-old\n'
                            '${List<String>.generate(18, (i) => '+new-$i').join('\n')}\n',
                      }),
                    ),
                  ),
                  for (var index = 0; index < 20; index += 1)
                    AgentHistoryMessageEntry(
                      id: 'history-after-$index',
                      role: AgentMessageRole.agent,
                      text: 'After anchor message $index',
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
                id: 'thread-baseline',
                projectPath: directory.path,
                title: 'Expansion baseline',
              ),
            ],
            nextCursor: null,
          ),
        ],
      );
      final session = MemorySessionStore();

      await tester.pumpWidget(
        MainApp(
          enableNativeWindowFrame: false,
          directoryPicker: () async => directory.path,
          sessionLoader: session.load,
          sessionSaver: session.save,
          agentProviderFactory: FakeAgentProviderFactory(provider),
          agentProviderConfigStore: MemoryAgentProviderConfigStore(),
        ),
      );
      await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
      await tester.runAsync(waitForIo);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          ValueKey<String>('project-thread-${directory.path}-thread-baseline'),
        ),
      );
      await tester.pumpAndSettle();

      final scrollView = find.byKey(
        const ValueKey<String>('agent-message-list'),
      );
      final anchorKey = const ValueKey<String>(
        'timeline-viewport-turn-block-turn-baseline-message-history-anchor',
      );
      final controller = tester.widget<ScrollView>(scrollView).controller!;
      for (var attempt = 0; attempt < 20; attempt += 1) {
        if (find.byKey(anchorKey).evaluate().isNotEmpty) {
          break;
        }
        controller.jumpTo(
          (controller.offset + 300).clamp(
            controller.position.minScrollExtent,
            controller.position.maxScrollExtent,
          ),
        );
        await tester.pump();
      }
      expect(find.byKey(anchorKey), findsOneWidget);
      final anchorTopBeforeAlign = itemViewportTop(
        tester,
        scrollView: scrollView,
        itemKey: anchorKey,
      );
      controller.jumpTo(controller.offset + anchorTopBeforeAlign);
      await _pumpUntilScrollMetricsStable(tester, controller);

      final trace = ScrollMetricsTrace('C');
      final beforeCommand = trace.capture(
        tester,
        label: 'command-collapsed',
        scrollView: scrollView,
        itemKeyPrefix: 'timeline-viewport-',
        trackedItemKey: anchorKey,
      );
      final anchorTopBeforeCommand = itemViewportTop(
        tester,
        scrollView: scrollView,
        itemKey: anchorKey,
      );
      final viewModel = tester
          .widget<AgentPane>(find.byType(AgentPane))
          .viewModel;
      viewModel.toggleCommandGroup(
        commandGroupId(turnId, 'tool-$commandToolId'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final commandMid = trace.capture(
        tester,
        label: 'command-mid-animation',
        scrollView: scrollView,
        itemKeyPrefix: 'timeline-viewport-',
        trackedItemKey: anchorKey,
      );
      await tester.pumpAndSettle();
      final commandExpanded = trace.capture(
        tester,
        label: 'command-expanded',
        scrollView: scrollView,
        itemKeyPrefix: 'timeline-viewport-',
        trackedItemKey: anchorKey,
      );
      final anchorTopAfterCommand = itemViewportTop(
        tester,
        scrollView: scrollView,
        itemKey: anchorKey,
      );
      // 阶段 4 接入 IdeAnchoredDynamicSliverList 后，锚点前增高应被
      // scrollOffsetCorrection 消化；阶段 0 基线曾观测到约 50px 漂移。
      expect(
        (anchorTopAfterCommand - anchorTopBeforeCommand).abs(),
        lessThanOrEqualTo(1),
        reason:
            '锚点前 command group 增高后 anchor 视口坐标应保持：'
            'before=$anchorTopBeforeCommand after=$anchorTopAfterCommand '
            '$beforeCommand -> $commandMid -> $commandExpanded',
      );

      viewModel.toggleCommandGroup(
        commandGroupId(turnId, 'tool-$commandToolId'),
      );
      await tester.pumpAndSettle();
      trace.capture(
        tester,
        label: 'command-collapsed-again',
        scrollView: scrollView,
        itemKeyPrefix: 'timeline-viewport-',
        trackedItemKey: anchorKey,
      );

      final fileGroupHeader = find.byKey(
        ValueKey<String>(
          'agent-file-edit-group-header-${fileEditGroupId(turnId, editToolId)}',
        ),
      );
      expect(fileGroupHeader, findsOneWidget);
      final anchorTopBeforeFile = itemViewportTop(
        tester,
        scrollView: scrollView,
        itemKey: anchorKey,
      );
      final beforeFile = trace.capture(
        tester,
        label: 'file-collapsed',
        scrollView: scrollView,
        itemKeyPrefix: 'timeline-viewport-',
        trackedItemKey: anchorKey,
      );
      await tester.tap(fileGroupHeader);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final fileMid = trace.capture(
        tester,
        label: 'file-mid-animation',
        scrollView: scrollView,
        itemKeyPrefix: 'timeline-viewport-',
        trackedItemKey: anchorKey,
      );
      await tester.pumpAndSettle();
      final fileExpanded = trace.capture(
        tester,
        label: 'file-expanded',
        scrollView: scrollView,
        itemKeyPrefix: 'timeline-viewport-',
        trackedItemKey: anchorKey,
      );
      final anchorTopAfterFile = itemViewportTop(
        tester,
        scrollView: scrollView,
        itemKey: anchorKey,
      );
      expect(
        anchorTopAfterFile,
        closeTo(anchorTopBeforeFile, 1),
        reason:
            '锚点后的 file edit group 高度变化不应移动当前锚点：'
            '$beforeFile -> $fileMid -> $fileExpanded',
      );
      await tester.tap(fileGroupHeader);
      await tester.pumpAndSettle();
      trace.capture(
        tester,
        label: 'file-collapsed-again',
        scrollView: scrollView,
        itemKeyPrefix: 'timeline-viewport-',
        trackedItemKey: anchorKey,
      );
    },
  );

  testWidgets(
    'baseline characterization: width 1400 to 700 to 1400 changes wrapping extent',
    (tester) async {
      _configureTestView(tester, const Size(1400, 600));
      final controller = ScrollController();
      addTearDown(controller.dispose);
      const scrollKey = ValueKey<String>('baseline-width-scroll');
      final trace = ScrollMetricsTrace('D');
      final text = List<String>.filled(
        12,
        'Deterministic markdown-like text wraps when the viewport narrows.',
      ).join(' ');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              key: scrollKey,
              controller: controller,
              slivers: <Widget>[
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => Padding(
                      key: ValueKey<String>('width-item-$index'),
                      padding: const EdgeInsets.all(8),
                      child: Text('$index $text'),
                    ),
                    childCount: 300,
                    addAutomaticKeepAlives: false,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      controller.jumpTo(2400);
      await tester.pump();
      final scrollView = find.byKey(scrollKey);
      final wide = trace.capture(
        tester,
        label: 'wide-1400',
        scrollView: scrollView,
        itemKeyPrefix: 'width-item-',
      );

      tester.view.physicalSize = const Size(700, 600);
      await tester.pumpAndSettle();
      final narrow = trace.capture(
        tester,
        label: 'narrow-700',
        scrollView: scrollView,
        itemKeyPrefix: 'width-item-',
      );

      tester.view.physicalSize = const Size(1400, 600);
      await tester.pumpAndSettle();
      final restored = trace.capture(
        tester,
        label: 'restored-1400',
        scrollView: scrollView,
        itemKeyPrefix: 'width-item-',
      );

      expect(
        (narrow.maxScrollExtent - wide.maxScrollExtent).abs(),
        greaterThan(100),
        reason: '宽度减半应导致全局 extent 明显重估：$wide -> $narrow',
      );
      expect(
        narrow.firstVisibleItemId != wide.firstVisibleItemId ||
            ((narrow.firstVisibleItemTop ?? 0) -
                        (wide.firstVisibleItemTop ?? 0))
                    .abs() >
                1,
        isTrue,
        reason: '当前实现应可观察到 anchor ID 或 top 漂移：$wide -> $narrow',
      );
      expect(
        (restored.maxScrollExtent - wide.maxScrollExtent).abs(),
        lessThan((narrow.maxScrollExtent - wide.maxScrollExtent).abs()),
        reason: '恢复原宽度后 extent 应比窄宽度更接近原值：$restored',
      );
    },
  );
}

void _configureTestView(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

double _mixedExtent(int index) {
  if (index < 60) {
    return index.isEven ? 24 : 80;
  }
  return switch ((index - 60) % 6) {
    0 => 2000,
    1 => 32,
    2 => 600,
    3 => 48,
    4 => 24,
    _ => 80,
  };
}

MemorySessionStore _activeProjectSession(Directory directory) {
  return MemorySessionStore(
    IdeSessionState(
      projectPaths: <String>[directory.path],
      activeProjectPath: directory.path,
      projectThreadExpansionByProject: <String, bool>{directory.path: false},
      projectHomeActive: true,
    ).encode(),
  );
}

Future<void> _openConversation(WidgetTester tester) async {
  final thread = find.byKey(
    const ValueKey<String>('project-home-thread-$conversationTestThreadId'),
  );
  await pumpUntilCondition(
    tester,
    () => thread.hitTestable().evaluate().isNotEmpty,
    failureMessage: 'Baseline conversation thread did not become ready',
  );
  await tester.tap(thread);
  await pumpUntilCondition(
    tester,
    () => find
        .byKey(const ValueKey<String>('agent-message-input'))
        .hitTestable()
        .evaluate()
        .isNotEmpty,
    failureMessage: 'Baseline Agent composer did not become ready',
  );
}

Future<void> _pumpLiveUi(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 20));
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _pumpUntilScrollMetricsStable(
  WidgetTester tester,
  ScrollController controller,
) async {
  double? previousMax;
  var stableFrames = 0;
  for (var attempt = 0; attempt < 12; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 100));
    final position = controller.position;
    final maxIsStable =
        previousMax != null &&
        (position.maxScrollExtent - previousMax).abs() <= 0.5;
    final pixelsInRange =
        position.pixels >= position.minScrollExtent - 0.5 &&
        position.pixels <= position.maxScrollExtent + 0.5;
    stableFrames = maxIsStable && pixelsInRange ? stableFrames + 1 : 0;
    if (stableFrames >= 2) {
      return;
    }
    previousMax = position.maxScrollExtent;
  }
}

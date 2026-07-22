// ignore_for_file: deprecated_member_use

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/main.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/ide_session/domain/ide_session_state.dart';
import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';

import '../../../testing/ide_test_harness.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final tempDirectories = <Directory>[];

  setUp(() {
    binding.window.devicePixelRatioTestValue = 1;
    binding.window.physicalSizeTestValue = const Size(1000, 600);
  });

  tearDown(() {
    binding.window.clearPhysicalSizeTestValue();
    binding.window.clearDevicePixelRatioTestValue();
    for (final directory in tempDirectories) {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    }
    tempDirectories.clear();
  });

  testWidgets('shows project threads and switches selected thread', (
    tester,
  ) async {
    final session = MemorySessionStore();
    final directory = Directory.systemTemp.createTempSync('zeta_test_');
    tempDirectories.add(directory);
    File(
      '${directory.path}${Platform.pathSeparator}sample.txt',
    ).writeAsStringSync('hello from zeta');
    final now = DateTime.now();
    final firstProviderPage = AgentThreadPage(
      threads: <AgentThreadSummary>[
        agentThread(
          id: 'thread-a',
          projectPath: directory.path,
          title: 'Initial thread',
          preview: 'Hidden preview text',
          lastActiveAt: now.subtract(const Duration(minutes: 5)),
        ),
        agentThread(
          id: 'thread-c',
          projectPath: directory.path,
          title: 'Dormant thread',
          lastActiveAt: now.subtract(const Duration(days: 3)),
        ),
        agentThread(
          id: 'thread-d',
          projectPath: directory.path,
          title: 'Recent thread D',
          lastActiveAt: now.subtract(const Duration(minutes: 10)),
        ),
        agentThread(
          id: 'thread-e',
          projectPath: directory.path,
          title: 'Recent thread E',
          lastActiveAt: now.subtract(const Duration(minutes: 30)),
        ),
        agentThread(
          id: 'thread-f',
          projectPath: directory.path,
          title: 'Recent thread F',
          lastActiveAt: now.subtract(const Duration(hours: 1)),
        ),
        agentThread(
          id: 'thread-g',
          projectPath: directory.path,
          title: 'Recent thread G',
          lastActiveAt: now.subtract(const Duration(minutes: 90)),
        ),
      ],
      nextCursor: 'next',
    );
    final secondProviderPage = AgentThreadPage(
      threads: <AgentThreadSummary>[
        agentThread(
          id: 'thread-b',
          projectPath: directory.path,
          title: 'Older thread',
          lastActiveAt: now.subtract(const Duration(hours: 2)),
        ),
      ],
      nextCursor: null,
    );

    final provider = FakeAgentProvider(
      threadHistories: <String, AgentThreadHistorySnapshot>{
        'thread-a': AgentThreadHistorySnapshot(
          threadId: 'thread-a',
          turns: <AgentHistoryTurn>[
            AgentHistoryTurn(
              id: 'turn-a-1',
              entries: <AgentHistoryEntry>[
                const AgentHistoryMessageEntry(
                  id: 'history-user-1',
                  role: AgentMessageRole.user,
                  text: 'Previously asked question',
                ),
                const AgentHistoryMessageEntry(
                  id: 'history-agent-1',
                  role: AgentMessageRole.agent,
                  text: 'Historical answer',
                ),
                AgentHistoryToolEntry(
                  toolCall: AgentToolCall(
                    id: 'history-tool-1',
                    title: 'History command',
                    kind: AgentToolKind.execute,
                    status: AgentToolStatus.completed,
                    content: 'done',
                  ),
                ),
                const AgentHistoryEventEntry(
                  id: 'history-event-1',
                  kind: AgentHistoryEventKind.permission,
                  title: 'Requested user input',
                  description: 'Need confirmation',
                  content: 'Option A, Option B',
                ),
              ],
              tokenUsage: const AgentTokenUsage(
                inputTokens: 41910,
                cachedInputTokens: 19712,
                outputTokens: 2332,
                totalTokens: 43462,
                modelContextWindow: 200000,
              ),
            ),
          ],
        ),
      },
      threadPages: <AgentThreadPage>[
        firstProviderPage,
        secondProviderPage,
        firstProviderPage,
        secondProviderPage,
      ],
    );

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        directoryPicker: () async => directory.path,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: FakeAgentProviderFactory(provider),
        agentProviderConfigStore: singleFakeProviderConfigStore(),
      ),
    );

    await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
    await tester.runAsync(waitForIo);
    await tester.pumpAndSettle();

    expect(provider.listQueries, hasLength(2));
    expect(provider.listQueries.first.limit, 10);
    expect(provider.listQueries.last.cursor, 'next');
    expect(
      find.descendant(
        of: find.byKey(
          ValueKey<String>('project-thread-${directory.path}-thread-a'),
        ),
        matching: find.text('Initial thread'),
      ),
      findsOneWidget,
    );
    expect(find.text('Hidden preview text'), findsOneWidget);
    expect(find.text('5m'), findsOneWidget);
    expect(find.text('3d'), findsNothing);
    final projectTile = find.byKey(
      ValueKey<String>('project-tile-${directory.path}'),
    );
    final projectTilePadding = find.byKey(
      ValueKey<String>('project-tile-padding-${directory.path}'),
    );
    final threadTile = find.byKey(
      ValueKey<String>('project-thread-${directory.path}-thread-a'),
    );
    expect(
      tester.widget<Padding>(projectTilePadding).padding,
      IdeSpacing.horizontal6,
    );
    expect(
      tester.widget<PaneInteractiveSurface>(projectTile).padding,
      IdeSpacing.horizontal8,
    );
    expect(
      tester.widget<PaneInteractiveSurface>(threadTile).padding,
      IdeSpacing.horizontal8,
    );
    expect(
      find.descendant(
        of: threadTile,
        matching: find.byKey(
          const ValueKey<String>('agent-provider-icon-svg-codex'),
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: threadTile, matching: find.text('Codex')),
      findsNothing,
    );
    expect(tester.getSize(projectTile).height, IdeMetrics.iconButtonHitSize);
    expect(tester.getSize(threadTile).height, IdeMetrics.iconButtonHitSize);
    expect(
      find.byKey(ValueKey<String>('project-tile-new-thread-${directory.path}')),
      findsNothing,
    );
    expect(
      find.byKey(ValueKey<String>('project-tile-more-${directory.path}')),
      findsNothing,
    );

    final mouse = await hoverProjectTile(tester, directory.path);
    addTearDown(mouse.removePointer);
    expect(
      find.byKey(
        ValueKey<String>('project-tile-expand-icon-${directory.path}'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey<String>('project-tile-more-${directory.path}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey<String>('project-tile-new-thread-${directory.path}')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(ValueKey<String>('project-tile-${directory.path}')),
    );
    await tester.pump();
    expect(
      find.byKey(ValueKey<String>('project-thread-${directory.path}-thread-a')),
      findsNothing,
    );
    expect(find.text('Initial thread'), findsOneWidget);

    await tester.tap(
      find.byKey(ValueKey<String>('project-tile-${directory.path}')),
    );
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(
          ValueKey<String>('project-thread-${directory.path}-thread-a'),
        ),
        matching: find.text('Initial thread'),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('project-thread-load-more-button')),
    );
    await tester.pumpAndSettle();
    expect(provider.listQueries.last.limit, 10);
    expect(provider.listQueries.last.cursor, 'next');
    expect(find.text('Older thread'), findsOneWidget);
    expect(find.text('2h'), findsOneWidget);
    expect(find.text('3d'), findsOneWidget);

    await tester.tap(
      find.byKey(ValueKey<String>('project-thread-${directory.path}-thread-a')),
    );
    await tester.pumpAndSettle();

    expect(provider.readHistories, contains('thread-a'));
    expect(
      provider.readHistorySessionPaths,
      contains('${directory.path}/thread-a.jsonl'),
    );
    expect(provider.resumedSessions, isEmpty);
    expect(find.text('Previously asked question'), findsOneWidget);
    expect(find.text('Historical answer'), findsOneWidget);
    expect(find.text('1 次执行'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey<String>('agent-command-group-item-tool-history-tool-1'),
      ),
      findsNothing,
    );
    expect(headerTitleText(tester), 'Initial thread');
    expect(find.byKey(const ValueKey('agent-header-token')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('agent-header-token')),
        matching: find.text('43.5k tokens'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('agent-tool-body-history-tool-1')),
      findsNothing,
    );
    expect(find.text('Requested user input'), findsOneWidget);
    expect(find.text('Selected thread: Initial thread'), findsNothing);
    expect(find.text('Opening thread...'), findsNothing);

    await tester.tap(
      find.byKey(
        ValueKey<String>(
          'agent-command-group-header-${commandGroupId('turn-a-1', 'tool-history-tool-1')}',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey<String>('agent-command-group-item-tool-history-tool-1'),
      ),
      findsOneWidget,
    );
    expect(find.text('done'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('agent-tool-body-history-tool-1')),
      findsNothing,
    );
  });

  testWidgets(
    'shows a running icon instead of relative time for active threads',
    (tester) async {
      final session = MemorySessionStore();
      final directory = Directory.systemTemp.createTempSync('zeta_test_');
      tempDirectories.add(directory);
      File(
        '${directory.path}${Platform.pathSeparator}sample.txt',
      ).writeAsStringSync('hello from zeta');
      final now = DateTime.now();

      final provider = FakeAgentProvider(
        threadPages: <AgentThreadPage>[
          AgentThreadPage(
            threads: <AgentThreadSummary>[
              agentThread(
                id: 'thread-a',
                projectPath: directory.path,
                title: 'Running thread',
                lastActiveAt: now.subtract(const Duration(minutes: 5)),
              ),
            ],
            nextCursor: null,
          ),
        ],
      );

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

      expect(find.text('5m'), findsOneWidget);
      expect(
        find.byKey(
          ValueKey<String>(
            'project-thread-running-icon-${directory.path}-thread-a',
          ),
        ),
        findsNothing,
      );

      provider.emit(
        const AgentTurnStartedEvent(
          AgentTurn(id: 'turn-1', sessionId: 'thread-a'),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('5m'), findsNothing);
      final listRunning = find.byKey(
        ValueKey<String>(
          'project-thread-running-icon-${directory.path}-thread-a',
        ),
      );
      expect(listRunning, findsOneWidget);
      expect(
        find.descendant(
          of: listRunning,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );

      provider.emit(
        const AgentTurnCompletedEvent(sessionId: 'thread-a', turnId: 'turn-1'),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(
          ValueKey<String>(
            'project-thread-running-icon-${directory.path}-thread-a',
          ),
        ),
        findsNothing,
      );
      // 后台完成：执行中 icon 替换为绿色完成提示，而非立刻回到相对时间。
      final listCompleted = find.byKey(
        ValueKey<String>(
          'project-thread-completed-icon-${directory.path}-thread-a',
        ),
      );
      expect(listCompleted, findsOneWidget);
      expect(find.text('5m'), findsNothing);

      await tester.tap(listCompleted);
      await tester.pump();
      await tester.pump();

      expect(listCompleted, findsNothing);
      // turn 开始时会 promote recency，结束后相对时间回到「刚刚」。
      expect(find.text('now'), findsOneWidget);
    },
  );

  testWidgets('shows project actions only while hovered', (tester) async {
    final session = MemorySessionStore();
    final directory = Directory.systemTemp.createTempSync('zeta_test_');
    tempDirectories.add(directory);
    File(
      '${directory.path}${Platform.pathSeparator}sample.txt',
    ).writeAsStringSync('hello from zeta');

    final provider = FakeAgentProvider(
      threadPages: <AgentThreadPage>[
        AgentThreadPage(
          threads: <AgentThreadSummary>[
            agentThread(
              id: 'thread-a',
              projectPath: directory.path,
              title: 'Hover thread',
            ),
          ],
          nextCursor: null,
        ),
      ],
    );

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

    final tileFinder = find.byKey(
      ValueKey<String>('project-tile-${directory.path}'),
    );
    final initialHeight = tester.getSize(tileFinder).height;

    expect(
      find.byKey(ValueKey<String>('project-tile-actions-${directory.path}')),
      findsNothing,
    );

    final mouse = await hoverProjectTile(tester, directory.path);
    addTearDown(mouse.removePointer);
    final hoveredHeight = tester.getSize(tileFinder).height;
    expect(
      find.byKey(ValueKey<String>('project-tile-actions-${directory.path}')),
      findsOneWidget,
    );
    expect(hoveredHeight, initialHeight);

    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();

    expect(
      find.byKey(ValueKey<String>('project-tile-actions-${directory.path}')),
      findsNothing,
    );
  });

  testWidgets('does not duplicate keys when thread actions toggle quickly', (
    tester,
  ) async {
    final session = MemorySessionStore();
    final directory = Directory.systemTemp.createTempSync('zeta_test_');
    tempDirectories.add(directory);
    File(
      '${directory.path}${Platform.pathSeparator}sample.txt',
    ).writeAsStringSync('hello from zeta');

    final provider = FakeAgentProvider(
      threadPages: <AgentThreadPage>[
        AgentThreadPage(
          threads: <AgentThreadSummary>[
            agentThread(
              id: 'thread-a',
              projectPath: directory.path,
              title: 'Hover thread',
            ),
          ],
          nextCursor: null,
        ),
      ],
    );

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

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await tester.pump();

    final threadFinder = find.byKey(
      ValueKey<String>('project-thread-${directory.path}-thread-a'),
    );

    await mouse.moveTo(tester.getCenter(threadFinder));
    await tester.pump(const Duration(milliseconds: 40));
    expect(tester.takeException(), isNull);

    await mouse.moveTo(Offset.zero);
    await tester.pump(const Duration(milliseconds: 40));
    expect(tester.takeException(), isNull);

    await mouse.moveTo(tester.getCenter(threadFinder));
    await tester.pump(const Duration(milliseconds: 40));
    expect(tester.takeException(), isNull);
  });

  testWidgets('starts a blank new thread from the project action', (
    tester,
  ) async {
    final session = MemorySessionStore();
    final directory = Directory.systemTemp.createTempSync('zeta_test_');
    tempDirectories.add(directory);
    File(
      '${directory.path}${Platform.pathSeparator}sample.txt',
    ).writeAsStringSync('hello from zeta');

    final provider = FakeAgentProvider(
      threadHistories: <String, AgentThreadHistorySnapshot>{
        'thread-a': AgentThreadHistorySnapshot(
          threadId: 'thread-a',
          turns: <AgentHistoryTurn>[
            AgentHistoryTurn(
              id: 'turn-a-1',
              entries: const <AgentHistoryEntry>[
                AgentHistoryMessageEntry(
                  id: 'history-user-1',
                  role: AgentMessageRole.user,
                  text: 'Previously asked question',
                ),
                AgentHistoryMessageEntry(
                  id: 'history-agent-1',
                  role: AgentMessageRole.agent,
                  text: 'Historical answer',
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
              title: 'Initial thread',
            ),
          ],
          nextCursor: null,
        ),
      ],
    );

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        directoryPicker: () async => directory.path,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
        agentProviderAvailabilityLoader: () async =>
            const <AgentProviderConfig>[
              AgentProviderConfig.defaultCodex,
              AgentProviderConfig.defaultGrok,
              AgentProviderConfig.defaultCursor,
            ],
      ),
    );

    await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
    await tester.runAsync(waitForIo);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(ValueKey<String>('project-thread-${directory.path}-thread-a')),
    );
    await tester.pumpAndSettle();

    expect(headerTitleText(tester), 'Initial thread');
    expect(find.text('Previously asked question'), findsOneWidget);

    final mouse = await hoverProjectTile(tester, directory.path);
    addTearDown(mouse.removePointer);
    await tester.tap(
      find.byKey(ValueKey<String>('project-tile-new-thread-${directory.path}')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const ValueKey<String>('new-thread-provider-popover')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('new-thread-provider-dialog')),
      findsNothing,
    );
    final newThreadButton = find.byKey(
      ValueKey<String>('project-tile-new-thread-${directory.path}'),
    );
    final providerPopover = find.byKey(
      const ValueKey<String>('new-thread-provider-popover'),
    );
    expect(
      tester.getRect(providerPopover).top,
      greaterThanOrEqualTo(tester.getRect(newThreadButton).bottom - 1),
    );
    expect(find.text('Codex'), findsOneWidget);
    expect(find.text('Grok'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('new-thread-provider-option-codex'),
        ),
        matching: find.byKey(
          const ValueKey<String>('agent-provider-icon-svg-codex'),
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('new-thread-provider-option-grok'),
        ),
        matching: find.byKey(
          const ValueKey<String>('agent-provider-icon-svg-grok'),
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('Cursor Agent'), findsNothing);
    expect(
      find.byKey(const ValueKey('new-thread-provider-option-cursor')),
      findsNothing,
    );
    expect(headerTitleText(tester), 'Initial thread');

    final codexOption = find.byKey(
      const ValueKey<String>('new-thread-provider-option-codex'),
    );
    await tester.tap(codexOption);
    await tester.pump();
    expect(
      find.descendant(
        of: codexOption,
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('创建 Thread'));
    await tester.pumpAndSettle();

    expect(headerTitleText(tester), 'New thread');
    expect(find.text('Previously asked question'), findsNothing);
    expect(find.text('Historical answer'), findsNothing);

    // 每次创建都重新选择，不沿用上一次的 Codex 选项。
    await tester.tap(
      find.byKey(ValueKey<String>('project-tile-new-thread-${directory.path}')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final reopenedCodexOption = find.byKey(
      const ValueKey<String>('new-thread-provider-option-codex'),
    );
    expect(
      find.descendant(
        of: reopenedCodexOption,
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsNothing,
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    final input = find.byKey(const ValueKey<String>('agent-message-input'));
    await tester.enterText(input, 'Create with selected provider');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('agent-send-button')));
    await tester.pumpAndSettle();
    expect(provider.sentMessages, contains('Create with selected provider'));
    await pumpSessionSave(tester);

    final savedState = IdeSessionState.tryDecode(session.value);
    final savedThreads = savedState!.cachedThreadsByProject[directory.path]!;
    expect(savedThreads.map((thread) => thread.id), contains('thread-1'));
    final createdThread = savedThreads
        .where((thread) => thread.id == 'thread-1')
        .single;
    expect(createdThread.providerId, defaultAgentProviderId);
  });

  testWidgets('opens the project location from the more menu', (tester) async {
    final session = MemorySessionStore();
    final directory = Directory.systemTemp.createTempSync('zeta_test_');
    tempDirectories.add(directory);
    File(
      '${directory.path}${Platform.pathSeparator}sample.txt',
    ).writeAsStringSync('hello from zeta');
    final openedPaths = <String>[];

    final provider = FakeAgentProvider(
      threadPages: <AgentThreadPage>[
        AgentThreadPage(
          threads: <AgentThreadSummary>[
            agentThread(
              id: 'thread-a',
              projectPath: directory.path,
              title: 'Menu thread',
            ),
          ],
          nextCursor: null,
        ),
      ],
    );

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        directoryPicker: () async => directory.path,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
        projectLocationOpener: (path) async {
          openedPaths.add(path);
        },
      ),
    );

    await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
    await tester.runAsync(waitForIo);
    await tester.pumpAndSettle();

    final mouse = await hoverProjectTile(tester, directory.path);
    addTearDown(mouse.removePointer);
    await tester.tap(
      find.byKey(ValueKey<String>('project-tile-more-menu-${directory.path}')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(
      find.byKey(
        ValueKey<String>('project-tile-open-location-${directory.path}'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(openedPaths, <String>[directory.path]);
  });

  testWidgets('refreshes the project thread list from the more menu', (
    tester,
  ) async {
    final session = MemorySessionStore();
    final directory = Directory.systemTemp.createTempSync('zeta_test_');
    tempDirectories.add(directory);
    File(
      '${directory.path}${Platform.pathSeparator}sample.txt',
    ).writeAsStringSync('hello from zeta');

    final provider = FakeAgentProvider(
      threadPages: <AgentThreadPage>[
        AgentThreadPage(
          threads: <AgentThreadSummary>[
            agentThread(
              id: 'thread-a',
              projectPath: directory.path,
              title: 'Initial thread',
            ),
          ],
          nextCursor: null,
        ),
        AgentThreadPage(
          threads: <AgentThreadSummary>[
            agentThread(
              id: 'thread-b',
              projectPath: directory.path,
              title: 'Refreshed thread',
            ),
          ],
          nextCursor: null,
        ),
      ],
    );

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        directoryPicker: () async => directory.path,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: FakeAgentProviderFactory(provider),
        agentProviderConfigStore: singleFakeProviderConfigStore(),
      ),
    );

    await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
    await tester.runAsync(waitForIo);
    await tester.pumpAndSettle();

    expect(provider.listQueries, hasLength(1));
    expect(
      find.descendant(
        of: find.byKey(
          ValueKey<String>('project-thread-${directory.path}-thread-a'),
        ),
        matching: find.text('Initial thread'),
      ),
      findsOneWidget,
    );

    final mouse = await hoverProjectTile(tester, directory.path);
    addTearDown(mouse.removePointer);
    await tester.tap(
      find.byKey(ValueKey<String>('project-tile-more-menu-${directory.path}')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(
      find.byKey(
        ValueKey<String>('project-tile-refresh-threads-${directory.path}'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(provider.listQueries, hasLength(2));
    expect(provider.listQueries.last.projectPath, directory.path);
    expect(provider.listQueries.last.limit, 10);
    expect(provider.listQueries.last.cursor, isNull);
    expect(find.text('Initial thread'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(
          ValueKey<String>('project-thread-${directory.path}-thread-b'),
        ),
        matching: find.text('Refreshed thread'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'removes the active project from the list and clears the workspace when no next project exists',
    (tester) async {
      final session = MemorySessionStore();
      final directory = Directory.systemTemp.createTempSync('zeta_test_');
      tempDirectories.add(directory);
      File(
        '${directory.path}${Platform.pathSeparator}sample.txt',
      ).writeAsStringSync('hello from zeta');

      final provider = FakeAgentProvider(
        threadHistories: <String, AgentThreadHistorySnapshot>{
          'thread-a': AgentThreadHistorySnapshot(
            threadId: 'thread-a',
            turns: <AgentHistoryTurn>[
              AgentHistoryTurn(
                id: 'turn-a-1',
                entries: const <AgentHistoryEntry>[
                  AgentHistoryMessageEntry(
                    id: 'history-user-1',
                    role: AgentMessageRole.user,
                    text: 'Previously asked question',
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
                title: 'Active thread',
              ),
            ],
            nextCursor: null,
          ),
        ],
      );

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
          ValueKey<String>('project-thread-${directory.path}-thread-a'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Previously asked question'), findsOneWidget);

      final mouse = await hoverProjectTile(tester, directory.path);
      addTearDown(mouse.removePointer);
      await tester.tap(
        find.byKey(
          ValueKey<String>('project-tile-more-menu-${directory.path}'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(
        find.byKey(ValueKey<String>('project-tile-remove-${directory.path}')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byKey(ValueKey<String>('project-tile-${directory.path}')),
        findsNothing,
      );
      expect(find.text('No folder opened'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('global-home-page')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('agent-header-title')),
        findsNothing,
      );
      expect(find.text('Previously asked question'), findsNothing);
    },
  );

  testWidgets('renames a project thread from the more menu', (tester) async {
    final session = MemorySessionStore();
    final directory = Directory.systemTemp.createTempSync('zeta_test_');
    tempDirectories.add(directory);
    File(
      '${directory.path}${Platform.pathSeparator}sample.txt',
    ).writeAsStringSync('hello from zeta');

    final provider = FakeAgentProvider(
      threadPages: <AgentThreadPage>[
        AgentThreadPage(
          threads: <AgentThreadSummary>[
            agentThread(
              id: 'thread-a',
              projectPath: directory.path,
              title: 'Menu thread',
            ),
          ],
          nextCursor: null,
        ),
      ],
    );

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

    final mouse = await hoverThreadTile(tester, directory.path, 'thread-a');
    addTearDown(mouse.removePointer);
    await tester.tap(
      find.byKey(
        ValueKey<String>('project-thread-more-menu-${directory.path}-thread-a'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(
        ValueKey<String>('project-thread-rename-${directory.path}-thread-a'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        ValueKey<String>('project-thread-archive-${directory.path}-thread-a'),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(
        ValueKey<String>('project-thread-rename-${directory.path}-thread-a'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final dialogFinder = find.byKey(
      ValueKey<String>(
        'project-thread-rename-dialog-${directory.path}-thread-a',
      ),
    );
    expect(dialogFinder, findsOneWidget);

    await tester.enterText(
      find.descendant(of: dialogFinder, matching: find.byType(EditableText)),
      'Renamed thread',
    );
    await tester.tap(find.text('确认'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(provider.renamedThreads, hasLength(1));
    expect(provider.renamedThreads.single.threadId, 'thread-a');
    expect(provider.renamedThreads.single.name, 'Renamed thread');
    expect(
      find.descendant(
        of: find.byKey(
          ValueKey<String>('project-thread-${directory.path}-thread-a'),
        ),
        matching: find.text('Renamed thread'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('keeps restored Cursor history unavailable and read-only', (
    tester,
  ) async {
    // Arrange
    final directory = Directory.systemTemp.createTempSync('zeta_test_');
    tempDirectories.add(directory);
    final cursorConfig = AgentProviderConfig.defaultCursor.copyWith(
      enabled: true,
    );
    final cursorThread = agentThread(
      id: 'cursor-thread',
      projectPath: directory.path,
      title: 'Cursor thread',
    ).copyWith(providerId: cursorAgentProviderId);
    final session = MemorySessionStore(
      IdeSessionState(
        projectPaths: <String>[directory.path],
        activeProjectPath: directory.path,
        activeAgentProviderId: cursorAgentProviderId,
        agentThreadIdsByProject: <String, String>{
          directory.path: cursorThread.id,
        },
        projectThreadExpansionByProject: <String, bool>{directory.path: true},
        cachedThreadsByProject: <String, List<AgentThreadSummary>>{
          directory.path: <AgentThreadSummary>[cursorThread],
        },
        selectedThreadIdsByProject: <String, String>{
          directory.path: cursorThread.id,
        },
      ).encode(),
    );
    final provider = FakeAgentProvider();
    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        directoryPicker: () async => directory.path,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(
          AgentProviderSettings(
            providers: <AgentProviderConfig>[
              AgentProviderConfig.defaultCodex,
              cursorConfig,
            ],
            activeProviderId: cursorAgentProviderId,
          ),
        ),
      ),
    );
    await tester.runAsync(waitForIo);
    await tester.pumpAndSettle();

    // Assert：历史摘要仍可见，但入口不得读取 Cursor 历史或暴露写操作。
    expect(
      find.descendant(
        of: find.byKey(
          ValueKey<String>('project-thread-${directory.path}-cursor-thread'),
        ),
        matching: find.byKey(
          const ValueKey<String>('agent-provider-icon-fallback-cursor'),
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('Cursor'), findsNothing);
    expect(find.textContaining('Cursor Agent unavailable'), findsWidgets);
    expect(provider.readHistories, isEmpty);
    expect(provider.resumedSessions, isEmpty);
    final mouse = await hoverThreadTile(
      tester,
      directory.path,
      'cursor-thread',
    );
    addTearDown(mouse.removePointer);
    expect(
      find.byKey(
        ValueKey<String>(
          'project-thread-more-menu-${directory.path}-cursor-thread',
        ),
      ),
      findsNothing,
    );
    expect(provider.removedLocalThreads, isEmpty);
  });

  testWidgets('hides thread action menu when Grok lacks lifecycle support', (
    tester,
  ) async {
    final session = MemorySessionStore();
    final directory = Directory.systemTemp.createTempSync('zeta_test_');
    tempDirectories.add(directory);
    final provider = FakeAgentProvider(
      threadPages: <AgentThreadPage>[
        AgentThreadPage(
          threads: <AgentThreadSummary>[
            agentThread(
              id: 'grok-thread',
              projectPath: directory.path,
              title: 'Grok thread',
            ).copyWith(providerId: grokAgentProviderId),
          ],
          nextCursor: null,
        ),
      ],
    );

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

    final mouse = await hoverThreadTile(tester, directory.path, 'grok-thread');
    addTearDown(mouse.removePointer);

    expect(
      find.byKey(
        ValueKey<String>(
          'project-thread-more-menu-${directory.path}-grok-thread',
        ),
      ),
      findsNothing,
    );
  });
}

MemoryAgentProviderConfigStore singleFakeProviderConfigStore() {
  return MemoryAgentProviderConfigStore(
    const AgentProviderSettings(
      providers: <AgentProviderConfig>[AgentProviderConfig.defaultCodex],
      activeProviderId: defaultAgentProviderId,
    ),
  );
}

Future<TestGesture> hoverProjectTile(
  WidgetTester tester,
  String projectPath,
) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  await tester.pump();
  await gesture.moveTo(
    tester.getCenter(find.byKey(ValueKey<String>('project-tile-$projectPath'))),
  );
  await tester.pumpAndSettle();
  return gesture;
}

Future<TestGesture> hoverThreadTile(
  WidgetTester tester,
  String projectPath,
  String threadId,
) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  await tester.pump();
  await gesture.moveTo(
    tester.getCenter(
      find.byKey(ValueKey<String>('project-thread-$projectPath-$threadId')),
    ),
  );
  await tester.pumpAndSettle();
  return gesture;
}

String openProjectLocationLabel() {
  if (Platform.isMacOS) {
    return '在 Finder 中打开';
  }
  if (Platform.isWindows) {
    return '在资源管理器中打开';
  }
  return '在文件管理器中打开';
}

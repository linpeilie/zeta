import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/main.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

import '../../../testing/ide_test_harness.dart';

void main() {
  final tempDirectories = <Directory>[];

  tearDown(() {
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
                outputTokens: 1552,
                reasoningOutputTokens: 780,
                totalTokens: 43462,
              ),
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
              preview: 'Hidden preview text',
              lastActiveAt: now.subtract(const Duration(minutes: 5)),
            ),
            agentThread(
              id: 'thread-c',
              projectPath: directory.path,
              title: 'Dormant thread',
              lastActiveAt: now.subtract(const Duration(days: 3)),
            ),
          ],
          nextCursor: 'next',
        ),
        AgentThreadPage(
          threads: <AgentThreadSummary>[
            agentThread(
              id: 'thread-b',
              projectPath: directory.path,
              title: 'Older thread',
              lastActiveAt: now.subtract(const Duration(hours: 2)),
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

    expect(provider.listQueries.single.limit, 5);
    expect(find.text('Initial thread'), findsOneWidget);
    expect(find.text('Hidden preview text'), findsNothing);
    expect(find.text('5m'), findsOneWidget);
    expect(find.text('3d'), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);

    await tester.tap(
      find.byKey(ValueKey<String>('project-tile-${directory.path}')),
    );
    await tester.pump();
    expect(find.text('Initial thread'), findsNothing);
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);

    await tester.tap(
      find.byKey(ValueKey<String>('project-tile-${directory.path}')),
    );
    await tester.pump();
    expect(find.text('Initial thread'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('project-thread-load-more-button')),
    );
    await tester.pumpAndSettle();
    expect(provider.listQueries.last.limit, 10);
    expect(provider.listQueries.last.cursor, 'next');
    expect(find.text('Older thread'), findsOneWidget);
    expect(find.text('2h'), findsOneWidget);

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
    expect(find.text('History command'), findsNothing);
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

    expect(find.text('History command'), findsOneWidget);
    expect(find.text('done'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('agent-tool-body-history-tool-1')),
      findsNothing,
    );
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/data/agent/agent_provider_config_store.dart';
import 'package:zeta/main.dart';
import 'package:zeta/src/data/file_system/path_utils.dart';
import 'package:zeta/src/domain/agent/agent_models.dart';
import 'package:zeta/src/domain/agent/agent_provider.dart';
import 'package:zeta/src/ui/core/app_theme.dart';

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

  testWidgets('starts with the compact IDE panes', (tester) async {
    final session = _MemorySessionStore();

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
    expect(_headerTitleText(tester), 'New thread');
    expect(find.text('Agent'), findsNothing);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('No folder opened'), findsOneWidget);
    expect(find.text('No file context'), findsNothing);
  });

  testWidgets('opens a folder and selects a file from the tree', (
    tester,
  ) async {
    final session = _MemorySessionStore();
    final directory = Directory.systemTemp.createTempSync('zeta_test_');
    tempDirectories.add(directory);

    final file = File('${directory.path}${Platform.pathSeparator}sample.txt');
    file.writeAsStringSync('hello from zeta');

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        directoryPicker: () async => directory.path,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: _FakeAgentProviderFactory(_FakeAgentProvider()),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
    await tester.runAsync(_waitForIo);
    await tester.pump();

    expect(find.byKey(_fileNodeKey(fileName(directory.path))), findsNothing);
    expect(find.text('sample.txt'), findsOneWidget);

    await tester.tap(find.byKey(_fileNodeKey('sample.txt')));
    await tester.runAsync(_waitForIo);
    await tester.pump();

    expect(find.text('sample.txt'), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-context-chip')), findsNothing);
    expect(find.byIcon(Icons.save_outlined), findsNothing);
  });

  testWidgets('opens this repository and shows top-level files', (
    tester,
  ) async {
    final session = _MemorySessionStore();
    final repositoryDirectory = Directory.current;

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        directoryPicker: () async => repositoryDirectory.path,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: _FakeAgentProviderFactory(_FakeAgentProvider()),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
    await tester.runAsync(_waitForIo);
    await tester.pump();

    expect(
      find.byKey(_fileNodeKey(fileName(repositoryDirectory.path))),
      findsNothing,
    );
    expect(find.text('lib'), findsOneWidget);
    expect(find.text('pubspec.yaml'), findsOneWidget);
  });

  testWidgets('loads nested file tree folders after expansion', (tester) async {
    final session = _MemorySessionStore();
    final directory = Directory.systemTemp.createTempSync('zeta_test_');
    tempDirectories.add(directory);

    final folder = Directory('${directory.path}${Platform.pathSeparator}lib')
      ..createSync();
    File(
      '${folder.path}${Platform.pathSeparator}main.dart',
    ).writeAsStringSync('void main() {}');

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        directoryPicker: () async => directory.path,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: _FakeAgentProviderFactory(_FakeAgentProvider()),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
    await tester.runAsync(_waitForIo);
    await tester.pump();

    expect(find.byKey(_fileNodeKey(fileName(directory.path))), findsNothing);
    expect(find.text('lib'), findsOneWidget);
    expect(find.text('main.dart'), findsNothing);

    await tester.tap(find.byKey(_fileNodeKey('lib')));
    await tester.pumpAndSettle();

    expect(find.text('main.dart'), findsOneWidget);
  });

  testWidgets('shows project threads and switches selected thread', (
    tester,
  ) async {
    final session = _MemorySessionStore();
    final directory = Directory.systemTemp.createTempSync('zeta_test_');
    tempDirectories.add(directory);
    File(
      '${directory.path}${Platform.pathSeparator}sample.txt',
    ).writeAsStringSync('hello from zeta');
    final now = DateTime.now();

    final provider = _FakeAgentProvider(
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
            _agentThread(
              id: 'thread-a',
              projectPath: directory.path,
              title: 'Initial thread',
              preview: 'Hidden preview text',
              lastActiveAt: now.subtract(const Duration(minutes: 5)),
            ),
            _agentThread(
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
            _agentThread(
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
        agentProviderFactory: _FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
    await tester.runAsync(_waitForIo);
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
    expect(_headerTitleText(tester), 'Initial thread');
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
          'agent-command-group-header-${_commandGroupId('turn-a-1', 'tool-history-tool-1')}',
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

  testWidgets('loads older turns without jumping the viewport', (tester) async {
    final session = _MemorySessionStore();
    final directory = Directory.systemTemp.createTempSync('zeta_test_');
    tempDirectories.add(directory);
    File(
      '${directory.path}${Platform.pathSeparator}sample.txt',
    ).writeAsStringSync('hello from zeta');

    final provider = _FakeAgentProvider(
      threadHistories: <String, AgentThreadHistorySnapshot>{
        'thread-a': AgentThreadHistorySnapshot(
          threadId: 'thread-a',
          turns: <AgentHistoryTurn>[
            for (var turnIndex = 1; turnIndex <= 5; turnIndex += 1)
              AgentHistoryTurn(
                id: 'turn-$turnIndex',
                entries: <AgentHistoryEntry>[
                  for (
                    var messageIndex = 0;
                    messageIndex < 8;
                    messageIndex += 1
                  )
                    AgentHistoryMessageEntry(
                      id: 'turn-$turnIndex-message-$messageIndex',
                      role: AgentMessageRole.agent,
                      text: 'Turn $turnIndex message $messageIndex',
                    ),
                ],
              ),
          ],
        ),
      },
      threadPages: <AgentThreadPage>[
        AgentThreadPage(
          threads: <AgentThreadSummary>[
            _agentThread(
              id: 'thread-a',
              projectPath: directory.path,
              title: 'Paged thread',
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
        agentProviderFactory: _FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
    await tester.runAsync(_waitForIo);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(ValueKey<String>('project-thread-${directory.path}-thread-a')),
    );
    await tester.pumpAndSettle();

    final listFinder = find.byKey(const ValueKey('agent-message-list'));
    final controller = tester
        .widget<SingleChildScrollView>(listFinder)
        .controller!;
    controller.jumpTo(0);
    await tester.pumpAndSettle();

    final anchorFinder = find.text('Turn 3 message 0');
    expect(anchorFinder, findsOneWidget);
    final oldAnchorY = tester.getTopLeft(anchorFinder).dy;

    await tester.tap(
      find.byKey(const ValueKey('agent-load-older-turns-button')),
    );
    await tester.pump();
    await tester.pump();

    expect(controller.offset, greaterThan(0));
    expect(tester.getTopLeft(anchorFinder).dy, closeTo(oldAnchorY, 2));
  });

  testWidgets('does not resume an existing thread until the first send', (
    tester,
  ) async {
    final session = _MemorySessionStore();
    final directory = Directory.systemTemp.createTempSync('zeta_test_');
    tempDirectories.add(directory);
    File(
      '${directory.path}${Platform.pathSeparator}sample.txt',
    ).writeAsStringSync('hello from zeta');

    final provider = _FakeAgentProvider(
      threadHistories: <String, AgentThreadHistorySnapshot>{
        'thread-a': AgentThreadHistorySnapshot(
          threadId: 'thread-a',
          turns: const <AgentHistoryTurn>[
            AgentHistoryTurn(
              id: 'turn-a-1',
              entries: <AgentHistoryEntry>[
                AgentHistoryMessageEntry(
                  id: 'history-user-1',
                  role: AgentMessageRole.user,
                  text: 'Pending resume history',
                ),
              ],
            ),
          ],
        ),
      },
      threadPages: <AgentThreadPage>[
        AgentThreadPage(
          threads: <AgentThreadSummary>[
            _agentThread(
              id: 'thread-a',
              projectPath: directory.path,
              title: 'Pending thread',
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
        agentProviderFactory: _FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
    await tester.runAsync(_waitForIo);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(ValueKey<String>('project-thread-${directory.path}-thread-a')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pending resume history'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent-thread-open-status')),
      findsNothing,
    );
    expect(provider.resumedSessions, isEmpty);

    final input = find.byKey(const ValueKey('agent-message-input'));
    await tester.tap(input);
    await tester.enterText(input, 'draft before first send');
    await tester.pump();

    expect(find.byKey(const ValueKey('agent-send-button')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('agent-send-button')));
    await tester.pumpAndSettle();

    expect(provider.resumedSessions, <String>['thread-a']);
    expect(provider.sentMessages, <String>['draft before first send']);
  });

  testWidgets('switches away from a running thread without blocking', (
    tester,
  ) async {
    final session = _MemorySessionStore();
    final directory = Directory.systemTemp.createTempSync('zeta_test_');
    tempDirectories.add(directory);
    File(
      '${directory.path}${Platform.pathSeparator}sample.txt',
    ).writeAsStringSync('hello from zeta');

    final provider = _FakeAgentProvider(
      threadHistories: <String, AgentThreadHistorySnapshot>{
        'thread-a': AgentThreadHistorySnapshot(
          threadId: 'thread-a',
          turns: const <AgentHistoryTurn>[
            AgentHistoryTurn(
              id: 'turn-a-1',
              status: AgentHistoryTurnStatus.running,
              entries: <AgentHistoryEntry>[
                AgentHistoryMessageEntry(
                  id: 'history-a',
                  role: AgentMessageRole.user,
                  text: 'History A',
                ),
              ],
            ),
          ],
        ),
        'thread-b': AgentThreadHistorySnapshot(
          threadId: 'thread-b',
          turns: const <AgentHistoryTurn>[
            AgentHistoryTurn(
              id: 'turn-b-1',
              entries: <AgentHistoryEntry>[
                AgentHistoryMessageEntry(
                  id: 'history-b',
                  role: AgentMessageRole.user,
                  text: 'History B',
                ),
              ],
            ),
          ],
        ),
      },
      threadPages: <AgentThreadPage>[
        AgentThreadPage(
          threads: <AgentThreadSummary>[
            _agentThread(
              id: 'thread-a',
              projectPath: directory.path,
              title: 'Thread A',
            ),
            _agentThread(
              id: 'thread-b',
              projectPath: directory.path,
              title: 'Thread B',
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
        agentProviderFactory: _FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
    await tester.runAsync(_waitForIo);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(ValueKey<String>('project-thread-${directory.path}-thread-a')),
    );
    await tester.pumpAndSettle();
    expect(find.text('History A'), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-cancel-button')), findsOneWidget);

    await tester.tap(
      find.byKey(ValueKey<String>('project-thread-${directory.path}-thread-b')),
    );
    await tester.pumpAndSettle();

    expect(find.text('History B'), findsOneWidget);
    expect(find.text('History A'), findsNothing);
    expect(
      find.textContaining('Finish or cancel the turn before switching.'),
      findsNothing,
    );
    expect(
      provider.readHistories,
      containsAll(<String>['thread-a', 'thread-b']),
    );
  });

  testWidgets(
    'shows Cancel for a running thread until text is entered, then steers on Send',
    (tester) async {
      final session = _MemorySessionStore();
      final directory = Directory.systemTemp.createTempSync('zeta_test_');
      tempDirectories.add(directory);
      File(
        '${directory.path}${Platform.pathSeparator}sample.txt',
      ).writeAsStringSync('hello from zeta');

      final provider = _FakeAgentProvider(
        threadHistories: <String, AgentThreadHistorySnapshot>{
          'thread-a': AgentThreadHistorySnapshot(
            threadId: 'thread-a',
            turns: const <AgentHistoryTurn>[
              AgentHistoryTurn(
                id: 'turn-a-1',
                status: AgentHistoryTurnStatus.running,
                entries: <AgentHistoryEntry>[
                  AgentHistoryMessageEntry(
                    id: 'history-a',
                    role: AgentMessageRole.user,
                    text: 'History A',
                  ),
                ],
              ),
            ],
          ),
        },
        threadPages: <AgentThreadPage>[
          AgentThreadPage(
            threads: <AgentThreadSummary>[
              _agentThread(
                id: 'thread-a',
                projectPath: directory.path,
                title: 'Thread A',
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
          agentProviderFactory: _FakeAgentProviderFactory(provider),
          agentProviderConfigStore: MemoryAgentProviderConfigStore(),
        ),
      );

      await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
      await tester.runAsync(_waitForIo);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(
          ValueKey<String>('project-thread-${directory.path}-thread-a'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('agent-cancel-button')), findsOneWidget);
      expect(find.byKey(const ValueKey('agent-send-button')), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey('agent-message-input')),
        'follow up',
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('agent-send-button')), findsOneWidget);
      expect(find.byKey(const ValueKey('agent-cancel-button')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('agent-send-button')));
      await tester.pumpAndSettle();

      expect(provider.resumedSessions, <String>['thread-a']);
      expect(provider.sentMessages, isEmpty);
      expect(provider.steeredMessages, <String>['follow up']);
    },
  );

  testWidgets(
    'keeps history visible and requires reselect after resume failure on first send',
    (tester) async {
      final session = _MemorySessionStore();
      final directory = Directory.systemTemp.createTempSync('zeta_test_');
      tempDirectories.add(directory);
      File(
        '${directory.path}${Platform.pathSeparator}sample.txt',
      ).writeAsStringSync('hello from zeta');
      var resumeAttempts = 0;

      final provider = _FakeAgentProvider(
        onResumeSession: (sessionId) {
          resumeAttempts += 1;
          if (resumeAttempts == 1) {
            return Future<AgentSession>.error(StateError('resume failed'));
          }
          return Future<AgentSession>.value(
            AgentSession(
              id: sessionId,
              providerId: defaultAgentProviderId,
              title: 'Recovered thread',
            ),
          );
        },
        threadHistories: <String, AgentThreadHistorySnapshot>{
          'thread-a': AgentThreadHistorySnapshot(
            threadId: 'thread-a',
            turns: const <AgentHistoryTurn>[
              AgentHistoryTurn(
                id: 'turn-a-1',
                entries: <AgentHistoryEntry>[
                  AgentHistoryMessageEntry(
                    id: 'history-user-1',
                    role: AgentMessageRole.user,
                    text: 'History survives failure',
                  ),
                ],
              ),
            ],
          ),
        },
        threadPages: <AgentThreadPage>[
          AgentThreadPage(
            threads: <AgentThreadSummary>[
              _agentThread(
                id: 'thread-a',
                projectPath: directory.path,
                title: 'Retryable thread',
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
          agentProviderFactory: _FakeAgentProviderFactory(provider),
          agentProviderConfigStore: MemoryAgentProviderConfigStore(),
        ),
      );

      await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
      await tester.runAsync(_waitForIo);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(
          ValueKey<String>('project-thread-${directory.path}-thread-a'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('History survives failure'), findsOneWidget);
      expect(
        find.text('Thread open failed. Click this thread again to retry.'),
        findsNothing,
      );

      await tester.enterText(
        find.byKey(const ValueKey('agent-message-input')),
        'first try',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('agent-send-button')));
      await tester.pumpAndSettle();

      expect(find.text('History survives failure'), findsOneWidget);
      expect(
        find.text('Thread open failed. Click this thread again to retry.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('agent-send-button')), findsNothing);

      await tester.tap(
        find.byKey(
          ValueKey<String>('project-thread-${directory.path}-thread-a'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('History survives failure'), findsOneWidget);
      expect(
        find.text('Thread open failed. Click this thread again to retry.'),
        findsNothing,
      );

      await tester.enterText(
        find.byKey(const ValueKey('agent-message-input')),
        'second try',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('agent-send-button')));
      await tester.pumpAndSettle();

      expect(resumeAttempts, 2);
      expect(_headerTitleText(tester), 'Recovered thread');
      expect(provider.sentMessages, <String>['second try']);
    },
  );

  testWidgets(
    'shows answered request_user_input entries without placeholders',
    (tester) async {
      final session = _MemorySessionStore();
      final directory = Directory.systemTemp.createTempSync('zeta_test_');
      tempDirectories.add(directory);
      File(
        '${directory.path}${Platform.pathSeparator}sample.txt',
      ).writeAsStringSync('hello from zeta');
      final now = DateTime.now();

      final provider = _FakeAgentProvider(
        threadHistories: <String, AgentThreadHistorySnapshot>{
          'thread-a': AgentThreadHistorySnapshot(
            threadId: 'thread-a',
            turns: <AgentHistoryTurn>[
              const AgentHistoryTurn(
                id: 'turn-a-qa',
                entries: <AgentHistoryEntry>[
                  AgentHistoryEventEntry(
                    id: 'history-event-qa',
                    kind: AgentHistoryEventKind.permission,
                    title: 'Requested user input',
                    qaPairs: <AgentUserInputQaPair>[
                      AgentUserInputQaPair(
                        questionId: 'command_scope',
                        question: '命令集要把哪些条目合并进去？',
                        answers: <String>['所有工具调用和搜索事件'],
                      ),
                      AgentUserInputQaPair(
                        questionId: 'group_target',
                        question: '这个折叠分组要应用到哪里？',
                        answers: <String>['Agent 时间线'],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        },
        threadPages: <AgentThreadPage>[
          AgentThreadPage(
            threads: <AgentThreadSummary>[
              _agentThread(
                id: 'thread-a',
                projectPath: directory.path,
                title: 'Answered thread',
                preview: 'Need answers',
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
          agentProviderFactory: _FakeAgentProviderFactory(provider),
          agentProviderConfigStore: MemoryAgentProviderConfigStore(),
        ),
      );

      await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
      await tester.runAsync(_waitForIo);
      await tester.pump();

      await tester.tap(
        find.byKey(
          ValueKey<String>('project-thread-${directory.path}-thread-a'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('命令集要把哪些条目合并进去？'), findsOneWidget);
      expect(find.text('所有工具调用和搜索事件'), findsOneWidget);
      expect(find.text('这个折叠分组要应用到哪里？'), findsOneWidget);
      expect(find.text('Agent 时间线'), findsOneWidget);
      expect(find.text('—'), findsNothing);
    },
  );

  testWidgets(
    'groups historical tools and searches into a collapsed command set',
    (tester) async {
      final session = _MemorySessionStore();
      final directory = Directory.systemTemp.createTempSync('zeta_test_');
      tempDirectories.add(directory);
      File(
        '${directory.path}${Platform.pathSeparator}sample.txt',
      ).writeAsStringSync('hello from zeta');

      final provider = _FakeAgentProvider(
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
                    text: 'Please summarize the run',
                  ),
                  AgentHistoryToolEntry(
                    toolCall: AgentToolCall(
                      id: 'history-tool-1',
                      title: 'Run tests',
                      kind: AgentToolKind.execute,
                      status: AgentToolStatus.completed,
                      content: 'flutter test\nhidden log line',
                    ),
                  ),
                  const AgentHistoryEventEntry(
                    id: 'history-search-1',
                    kind: AgentHistoryEventKind.search,
                    title: 'Web search',
                    description: 'OpenAI docs',
                    content: 'OpenAI docs\nHidden result line',
                  ),
                ],
              ),
            ],
          ),
        },
        threadPages: <AgentThreadPage>[
          AgentThreadPage(
            threads: <AgentThreadSummary>[
              _agentThread(
                id: 'thread-a',
                projectPath: directory.path,
                title: 'Grouped history',
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
          agentProviderFactory: _FakeAgentProviderFactory(provider),
          agentProviderConfigStore: MemoryAgentProviderConfigStore(),
        ),
      );

      await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
      await tester.runAsync(_waitForIo);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(
          ValueKey<String>('project-thread-${directory.path}-thread-a'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 次执行 · 1 次搜索'), findsOneWidget);
      expect(find.text('Run tests'), findsNothing);
      expect(find.text('OpenAI docs'), findsNothing);
      expect(find.text('hidden log line'), findsNothing);
      expect(find.text('Hidden result line'), findsNothing);

      await tester.tap(
        find.byKey(
          ValueKey<String>(
            'agent-command-group-header-${_commandGroupId('turn-a-1', 'tool-history-tool-1')}',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Run tests'), findsOneWidget);
      expect(find.text('Web search · OpenAI docs'), findsOneWidget);
      expect(find.text('flutter test'), findsNothing);
      expect(find.text('OpenAI docs'), findsNothing);
      expect(find.text('hidden log line'), findsNothing);
      expect(find.text('Hidden result line'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('agent-tool-body-history-tool-1')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'renders file edits in a separate file edit group with file-level details',
    (tester) async {
      final session = _MemorySessionStore();
      final directory = Directory.systemTemp.createTempSync('zeta_test_');
      tempDirectories.add(directory);
      File(
        '${directory.path}${Platform.pathSeparator}sample.txt',
      ).writeAsStringSync('hello from zeta');

      final provider = _FakeAgentProvider(
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
                    text: 'Apply edits',
                  ),
                  AgentHistoryToolEntry(
                    toolCall: AgentToolCall(
                      id: 'history-edit-1',
                      title: 'Apply patch',
                      kind: AgentToolKind.edit,
                      status: AgentToolStatus.completed,
                      locations: <String>['lib/main.dart', 'README.md'],
                      rawOutput: _patchApplyChanges(<String, String?>{
                        'lib/main.dart': '@@ -1 +1 @@\n-old line\n+new line\n',
                        'README.md': '@@ -0,0 +1 @@\n+docs line\n',
                      }),
                    ),
                  ),
                  AgentHistoryToolEntry(
                    toolCall: AgentToolCall(
                      id: 'history-tool-1',
                      title: 'Run tests',
                      kind: AgentToolKind.execute,
                      status: AgentToolStatus.completed,
                    ),
                  ),
                ],
              ),
            ],
          ),
        },
        threadPages: <AgentThreadPage>[
          AgentThreadPage(
            threads: <AgentThreadSummary>[
              _agentThread(
                id: 'thread-a',
                projectPath: directory.path,
                title: 'Edit group history',
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
          agentProviderFactory: _FakeAgentProviderFactory(provider),
          agentProviderConfigStore: MemoryAgentProviderConfigStore(),
        ),
      );

      await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
      await tester.runAsync(_waitForIo);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(
          ValueKey<String>('project-thread-${directory.path}-thread-a'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2 个文件 · +2 / -1', findRichText: true), findsOneWidget);
      expect(find.text('1 次执行'), findsOneWidget);
      expect(find.text('Run tests'), findsNothing);

      await tester.tap(
        find.byKey(
          ValueKey<String>(
            'agent-file-edit-group-header-${_fileEditGroupId('turn-a-1', 'history-edit-1')}',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('main.dart'), findsOneWidget);
      expect(find.text('README.md'), findsOneWidget);
      expect(find.text('+1 / -1', findRichText: true), findsOneWidget);
      expect(find.text('+1 / -0', findRichText: true), findsOneWidget);
      expect(find.text('Run tests'), findsNothing);

      final historyGroupSummaryFinder = find.byKey(
        ValueKey<String>(
          'agent-file-edit-group-summary-${_fileEditGroupId('turn-a-1', 'history-edit-1')}',
        ),
      );
      final historyGroupSummary = tester.widget<Text>(
        historyGroupSummaryFinder,
      );
      final historyGroupSpan = historyGroupSummary.textSpan! as TextSpan;
      expect(historyGroupSpan.toPlainText(), '2 个文件 · +2 / -1');
      final historyGroupChildren = historyGroupSpan.children!;
      expect(
        (historyGroupChildren[2] as TextSpan).style?.color,
        ideAccentColor.withValues(alpha: 0.98),
      );
      expect(
        (historyGroupChildren[4] as TextSpan).style?.color,
        ideWarningColor.withValues(alpha: 0.98),
      );

      final historyLineStatsFinder = find.byKey(
        const ValueKey<String>(
          'agent-file-edit-item-line-stats-file-edit-history-edit-1-lib/main.dart',
        ),
      );
      final historyLineStats = tester.widget<Text>(historyLineStatsFinder);
      final historyLineSpan = historyLineStats.textSpan! as TextSpan;
      expect(historyLineSpan.toPlainText(), '+1 / -1');
      final historyLineChildren = historyLineSpan.children!;
      expect(
        (historyLineChildren[0] as TextSpan).style?.color,
        ideAccentColor.withValues(alpha: 0.98),
      );
      expect(
        (historyLineChildren[2] as TextSpan).style?.color,
        ideWarningColor.withValues(alpha: 0.98),
      );

      await tester.tap(
        find.byKey(
          const ValueKey<String>(
            'agent-file-edit-item-row-file-edit-history-edit-1-lib/main.dart',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const ValueKey<String>(
            'agent-file-edit-item-details-file-edit-history-edit-1-lib/main.dart',
          ),
        ),
        findsOneWidget,
      );
      final historyDetailsFinder = find.byKey(
        const ValueKey<String>(
          'agent-file-edit-item-details-file-edit-history-edit-1-lib/main.dart',
        ),
      );
      expect(
        find.descendant(
          of: historyDetailsFinder,
          matching: find.textContaining('@@ -1 +1 @@', findRichText: true),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: historyDetailsFinder,
          matching: find.textContaining('+new line', findRichText: true),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: historyDetailsFinder,
          matching: find.textContaining('+docs line', findRichText: true),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: historyDetailsFinder,
          matching: find.textContaining('*** Begin Patch', findRichText: true),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('disables file edit item expansion when no details exist', (
    tester,
  ) async {
    final session = _MemorySessionStore();
    final directory = Directory.systemTemp.createTempSync('zeta_test_');
    tempDirectories.add(directory);
    File(
      '${directory.path}${Platform.pathSeparator}sample.txt',
    ).writeAsStringSync('hello from zeta');

    final provider = _FakeAgentProvider(
      threadHistories: <String, AgentThreadHistorySnapshot>{
        'thread-a': AgentThreadHistorySnapshot(
          threadId: 'thread-a',
          turns: <AgentHistoryTurn>[
            AgentHistoryTurn(
              id: 'turn-a-1',
              entries: <AgentHistoryEntry>[
                AgentHistoryToolEntry(
                  toolCall: AgentToolCall(
                    id: 'history-edit-nodetail',
                    title: 'File change',
                    kind: AgentToolKind.edit,
                    status: AgentToolStatus.completed,
                    rawOutput: _patchApplyChanges(<String, String?>{
                      'lib/main.dart': null,
                    }),
                  ),
                ),
              ],
            ),
          ],
        ),
      },
      threadPages: <AgentThreadPage>[
        AgentThreadPage(
          threads: <AgentThreadSummary>[
            _agentThread(
              id: 'thread-a',
              projectPath: directory.path,
              title: 'No detail edits',
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
        agentProviderFactory: _FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
    await tester.runAsync(_waitForIo);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(ValueKey<String>('project-thread-${directory.path}-thread-a')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        ValueKey<String>(
          'agent-file-edit-group-header-${_fileEditGroupId('turn-a-1', 'history-edit-nodetail')}',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final toggleFinder = find.byKey(
      const ValueKey<String>(
        'agent-file-edit-item-toggle-file-edit-history-edit-nodetail-lib/main.dart',
      ),
    );
    expect(toggleFinder, findsOneWidget);

    await tester.tap(
      find.byKey(
        const ValueKey<String>(
          'agent-file-edit-item-row-file-edit-history-edit-nodetail-lib/main.dart',
        ),
      ),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey<String>(
          'agent-file-edit-item-details-file-edit-history-edit-nodetail-lib/main.dart',
        ),
      ),
      findsNothing,
    );
  });

  testWidgets('shows live header token usage while a turn is running', (
    tester,
  ) async {
    final session = _MemorySessionStore();
    final provider = _FakeAgentProvider(
      completeTurns: false,
      sessionTitle: 'Running thread',
      tokenUsageDuringTurn: const AgentTokenUsage(
        inputTokens: 1000,
        cachedInputTokens: 200,
        outputTokens: 300,
        reasoningOutputTokens: 50,
        totalTokens: 1300,
      ),
    );

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: _FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('agent-message-input')),
      'Keep running',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('agent-send-button')));
    await tester.pumpAndSettle();

    expect(_headerTitleText(tester), 'Running thread');
    expect(
      find.byKey(const ValueKey('agent-header-running-icon')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('agent-header-token')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('agent-header-token')),
        matching: find.text('1.3k tokens'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('keeps the flattened agent pane stable in a narrow window', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(920, 820);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final session = _MemorySessionStore();
    final provider = _FakeAgentProvider(
      completeTurns: false,
      sessionTitle: 'Long running thread title for narrow layout',
      tokenUsageDuringTurn: const AgentTokenUsage(
        inputTokens: 3200,
        cachedInputTokens: 1200,
        outputTokens: 640,
        reasoningOutputTokens: 180,
        totalTokens: 3840,
      ),
    );

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: _FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('agent-message-input')),
      'Keep the layout stable',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('agent-send-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('agent-pane-host')), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-header-token')), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-cancel-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps command group scroll position when toggling grouped history', (
    tester,
  ) async {
    final session = _MemorySessionStore();
    final directory = Directory.systemTemp.createTempSync('zeta_test_');
    tempDirectories.add(directory);
    File(
      '${directory.path}${Platform.pathSeparator}sample.txt',
    ).writeAsStringSync('hello from zeta');

    final provider = _FakeAgentProvider(
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
                  text: 'Scroll test question',
                ),
                AgentHistoryToolEntry(
                  toolCall: AgentToolCall(
                    id: 'history-tool-a',
                    title: 'History command',
                    kind: AgentToolKind.execute,
                    status: AgentToolStatus.completed,
                    content: 'flutter test',
                  ),
                ),
                const AgentHistoryEventEntry(
                  id: 'history-search-a',
                  kind: AgentHistoryEventKind.search,
                  title: 'Tool search',
                  description: 'rip_grep_packages',
                ),
                for (var index = 0; index < 30; index++)
                  AgentHistoryMessageEntry(
                    id: 'history-agent-$index',
                    role: AgentMessageRole.agent,
                    text: 'Trailing message $index',
                  ),
              ],
            ),
          ],
        ),
      },
      threadPages: <AgentThreadPage>[
        AgentThreadPage(
          threads: <AgentThreadSummary>[
            _agentThread(
              id: 'thread-a',
              projectPath: directory.path,
              title: 'Scrollable grouped thread',
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
        agentProviderFactory: _FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
    await tester.runAsync(_waitForIo);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(ValueKey<String>('project-thread-${directory.path}-thread-a')),
    );
    await tester.pumpAndSettle();

    final listFinder = find.byKey(const ValueKey('agent-message-list'));
    final controller = tester
        .widget<SingleChildScrollView>(listFinder)
        .controller!;
    controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(controller.offset, 0);

    await tester.tap(
      find.byKey(
        ValueKey<String>(
          'agent-command-group-header-${_commandGroupId('turn-a-1', 'tool-history-tool-a')}',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.offset, lessThan(40));
    expect(find.text('History command'), findsOneWidget);
    expect(find.text('Tool search'), findsOneWidget);
    expect(find.text('rip_grep_packages'), findsNothing);
    expect(
      find.byKey(
        ValueKey<String>(
          'agent-command-group-body-${_commandGroupId('turn-a-1', 'tool-history-tool-a')}',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('keeps single command group scroll position stable', (
    tester,
  ) async {
    final session = _MemorySessionStore();
    final directory = Directory.systemTemp.createTempSync('zeta_test_');
    tempDirectories.add(directory);
    File(
      '${directory.path}${Platform.pathSeparator}sample.txt',
    ).writeAsStringSync('hello from zeta');

    final provider = _FakeAgentProvider(
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
                  text: 'Scroll test question',
                ),
                AgentHistoryToolEntry(
                  toolCall: AgentToolCall(
                    id: 'history-tool-jump',
                    title: 'History command',
                    kind: AgentToolKind.execute,
                    status: AgentToolStatus.completed,
                    content: 'long output',
                  ),
                ),
                for (var index = 0; index < 30; index++)
                  AgentHistoryMessageEntry(
                    id: 'history-agent-$index',
                    role: AgentMessageRole.agent,
                    text: 'Trailing message $index',
                  ),
              ],
            ),
          ],
        ),
      },
      threadPages: <AgentThreadPage>[
        AgentThreadPage(
          threads: <AgentThreadSummary>[
            _agentThread(
              id: 'thread-a',
              projectPath: directory.path,
              title: 'Scrollable thread',
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
        agentProviderFactory: _FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
    await tester.runAsync(_waitForIo);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(ValueKey<String>('project-thread-${directory.path}-thread-a')),
    );
    await tester.pumpAndSettle();

    final listFinder = find.byKey(const ValueKey('agent-message-list'));
    final controller = tester
        .widget<SingleChildScrollView>(listFinder)
        .controller!;
    controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(controller.offset, 0);

    await tester.tap(
      find.byKey(
        ValueKey<String>(
          'agent-command-group-header-${_commandGroupId('turn-a-1', 'tool-history-tool-jump')}',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.offset, lessThan(40));
    expect(find.text('History command'), findsOneWidget);
    expect(find.text('long output'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('agent-tool-body-history-tool-jump')),
      findsNothing,
    );
  });

  testWidgets('adds local agent messages from the composer', (tester) async {
    final session = _MemorySessionStore();
    final provider = _FakeAgentProvider();

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: _FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('agent-message-input')),
      'Summarize the current work',
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('agent-send-button')));
    await tester.pumpAndSettle();

    expect(find.text('Summarize the current work'), findsOneWidget);
    expect(
      find.textContaining('Fake response from provider', findRichText: true),
      findsOneWidget,
    );
    expect(provider.sentMessages.single, 'Summarize the current work');
  });

  testWidgets('keeps manual scroll position during live agent streaming', (
    tester,
  ) async {
    final session = _MemorySessionStore();
    final provider = _FakeAgentProvider(
      completeTurns: false,
      responseText: List<String>.generate(
        160,
        (index) => 'Streaming line $index',
      ).join('\n'),
    );

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: _FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('agent-message-input')),
      'Keep streaming',
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('agent-send-button')));
    await tester.pumpAndSettle();

    final listFinder = find.byKey(const ValueKey('agent-message-list'));
    final controller = tester
        .widget<SingleChildScrollView>(listFinder)
        .controller!;
    expect(controller.position.maxScrollExtent, greaterThan(400));

    controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(controller.offset, 0);

    provider.emit(
      const AgentMessageDeltaEvent(
        messageId: 'message-1',
        delta: '\nFollow-up streaming line',
        role: AgentMessageRole.agent,
        phase: AgentMessagePhase.response,
        sessionId: 'thread-1',
        turnId: 'turn-1',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(controller.offset, lessThan(40));
  });

  testWidgets('merges live tool calls into a single command group', (
    tester,
  ) async {
    final session = _MemorySessionStore();
    final provider = _FakeAgentProvider(completeTurns: false);

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: _FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('agent-message-input')),
      'Run grouped tools',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('agent-send-button')));
    await tester.pumpAndSettle();

    provider.emit(
      const AgentToolCallEvent(
        AgentToolCall(
          id: 'live-tool-1',
          title: 'Run tests',
          kind: AgentToolKind.execute,
          status: AgentToolStatus.inProgress,
          content: 'flutter test\nhidden log line',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 次执行'), findsOneWidget);
    expect(find.text('Run tests'), findsNothing);

    provider.emit(
      const AgentToolCallEvent(
        AgentToolCall(
          id: 'live-tool-2',
          title: 'Tool search',
          kind: AgentToolKind.search,
          status: AgentToolStatus.completed,
          content: 'rip_grep_packages\nhidden result line',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 次执行 · 1 次搜索'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('agent-tool-header-live-tool-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('agent-tool-header-live-tool-2')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(
        ValueKey<String>(
          'agent-command-group-header-${_commandGroupId('turn-1', 'tool-live-tool-1')}',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Run tests'), findsOneWidget);
    expect(find.text('Tool search'), findsOneWidget);
    expect(find.text('flutter test'), findsNothing);
    expect(find.text('rip_grep_packages'), findsNothing);
    expect(find.text('hidden log line'), findsNothing);
    expect(find.text('hidden result line'), findsNothing);
  });

  testWidgets('renders live file edits as a separate expandable file edit group', (
    tester,
  ) async {
    final session = _MemorySessionStore();
    final provider = _FakeAgentProvider(completeTurns: false);

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: _FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('agent-message-input')),
      'Apply a patch',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('agent-send-button')));
    await tester.pumpAndSettle();

    provider.emit(
      const AgentToolCallEvent(
        AgentToolCall(
          id: 'live-edit-1',
          title: 'Apply patch',
          kind: AgentToolKind.edit,
          status: AgentToolStatus.inProgress,
          locations: <String>['lib/main.dart', 'README.md'],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 个文件', findRichText: true), findsOneWidget);

    provider.emit(
      AgentToolCallEvent(
        AgentToolCall(
          id: 'live-edit-1',
          title: 'Apply patch',
          kind: AgentToolKind.edit,
          status: AgentToolStatus.completed,
          locations: const <String>['lib/main.dart', 'README.md'],
          rawOutput: _patchApplyChanges(<String, String?>{
            'lib/main.dart': '@@ -1 +1 @@\n-old line\n+new line\n',
            'README.md': '@@ -0,0 +1 @@\n+docs line\n',
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 个文件 · +2 / -1', findRichText: true), findsOneWidget);
    expect(
      find.byKey(
        ValueKey<String>(
          'agent-file-edit-group-header-${_fileEditGroupId('turn-1', 'live-edit-1')}',
        ),
      ),
      findsOneWidget,
    );

    provider.emit(
      const AgentToolCallEvent(
        AgentToolCall(
          id: 'live-tool-3',
          title: 'Run tests',
          kind: AgentToolKind.execute,
          status: AgentToolStatus.completed,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 次执行'), findsOneWidget);

    await tester.tap(
      find.byKey(
        ValueKey<String>(
          'agent-file-edit-group-header-${_fileEditGroupId('turn-1', 'live-edit-1')}',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('main.dart'), findsOneWidget);
    expect(find.text('README.md'), findsOneWidget);
    expect(find.text('+1 / -1', findRichText: true), findsOneWidget);
    expect(find.text('+1 / -0', findRichText: true), findsOneWidget);

    await tester.tap(
      find.byKey(
        const ValueKey<String>(
          'agent-file-edit-item-row-file-edit-live-edit-1-lib/main.dart',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey<String>(
          'agent-file-edit-item-details-file-edit-live-edit-1-lib/main.dart',
        ),
      ),
      findsOneWidget,
    );
    final liveDetailsFinder = find.byKey(
      const ValueKey<String>(
        'agent-file-edit-item-details-file-edit-live-edit-1-lib/main.dart',
      ),
    );
    expect(
      find.descendant(
        of: liveDetailsFinder,
        matching: find.textContaining('@@ -1 +1 @@', findRichText: true),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: liveDetailsFinder,
        matching: find.textContaining('+new line', findRichText: true),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: liveDetailsFinder,
        matching: find.textContaining('+docs line', findRichText: true),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: liveDetailsFinder,
        matching: find.textContaining('*** Begin Patch', findRichText: true),
      ),
      findsNothing,
    );
  });

  testWidgets('shows completed commentary messages by default', (tester) async {
    final session = _MemorySessionStore();
    final provider = _FakeAgentProvider(
      responseText: 'Hidden commentary with `code`',
      emitCompletedCommentary: true,
    );

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: _FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('agent-message-input')),
      'Explain internally',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('agent-send-button')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Hidden commentary', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('renders ordinary agent messages as Markdown', (tester) async {
    final session = _MemorySessionStore();
    final provider = _FakeAgentProvider(
      responseText:
          '- First markdown item\n\nInline `code` sample\n\n```dart\nvoid main() {}\n```',
    );

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: _FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('agent-message-input')),
      'Render markdown',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('agent-send-button')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('First markdown item', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('code', findRichText: true), findsWidgets);
    expect(
      find.textContaining('void main', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('renders plan messages as collapsible markdown cards', (
    tester,
  ) async {
    final session = _MemorySessionStore();
    final directory = Directory.systemTemp.createTempSync('zeta_test_');
    tempDirectories.add(directory);
    final now = DateTime.now();
    final provider = _FakeAgentProvider(
      threadHistories: <String, AgentThreadHistorySnapshot>{
        'thread-plan': AgentThreadHistorySnapshot(
          threadId: 'thread-plan',
          turns: <AgentHistoryTurn>[
            AgentHistoryTurn(
              id: 'turn-plan',
              entries: <AgentHistoryEntry>[
                const AgentHistoryMessageEntry(
                  id: 'user-plan',
                  role: AgentMessageRole.user,
                  text: 'Show the plan',
                ),
                AgentHistoryMessageEntry(
                  id: 'turn-plan-plan',
                  role: AgentMessageRole.agent,
                  text:
                      '# 命令集折叠分组\n\n## Summary\n\n- 第一项\n\n```dart\nvoid main() {}\n```',
                  status: AgentMessageStatus.completed,
                  raw: <String, Object?>{'type': 'plan'},
                ),
              ],
            ),
          ],
        ),
      },
      threadPages: <AgentThreadPage>[
        AgentThreadPage(
          threads: <AgentThreadSummary>[
            _agentThread(
              id: 'thread-plan',
              projectPath: directory.path,
              title: 'Plan thread',
              lastActiveAt: now,
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
        agentProviderFactory: _FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
    await tester.runAsync(_waitForIo);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        ValueKey<String>('project-thread-${directory.path}-thread-plan'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('agent-plan-card-turn-plan-plan')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('agent-plan-preview-turn-plan-plan')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('agent-plan-body-turn-plan-plan')),
      findsNothing,
    );
    expect(find.text('命令集折叠分组'), findsOneWidget);
    expect(find.textContaining('第一项', findRichText: true), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('agent-plan-toggle-turn-plan-plan')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('agent-plan-body-turn-plan-plan')),
      findsOneWidget,
    );
    expect(find.textContaining('第一项', findRichText: true), findsOneWidget);
    expect(
      find.textContaining('void main', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('renders tool calls, approval cards, and approval responses', (
    tester,
  ) async {
    final session = _MemorySessionStore();
    final provider = _FakeAgentProvider(emitToolAndApproval: true);

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: _FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('agent-message-input')),
      'Run the checks',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('agent-send-button')));
    await tester.pumpAndSettle();

    expect(find.text('1 次执行'), findsOneWidget);
    expect(find.text('Run tests'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('agent-tool-body-tool-1')),
      findsNothing,
    );
    expect(find.text('Approve command'), findsOneWidget);

    await tester.tap(
      find.byKey(
        ValueKey<String>(
          'agent-command-group-header-${_commandGroupId('turn-1', 'tool-tool-1')}',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Run tests'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('agent-tool-body-tool-1')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('agent-permission-approve-approval-1')),
    );
    await tester.pump();

    expect(provider.approvedRequests, <String>['approval-1']);
  });

  testWidgets('cancel button interrupts an active provider turn', (
    tester,
  ) async {
    final session = _MemorySessionStore();
    final provider = _FakeAgentProvider(completeTurns: false);

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: _FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('agent-message-input')),
      'Keep working',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('agent-send-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('agent-cancel-button')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('agent-cancel-button')));
    await tester.pump();

    expect(provider.cancelledTurns, <String>['turn-1']);
  });

  testWidgets('shows provider unavailable when the provider cannot start', (
    tester,
  ) async {
    final session = _MemorySessionStore();
    final provider = _FakeAgentProvider(unavailable: true);

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: _FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('agent-message-input')),
      'Hello',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('agent-send-button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('codex missing'), findsWidgets);
  });

  testWidgets('restores the previous project and selected file on restart', (
    tester,
  ) async {
    final session = _MemorySessionStore();
    final directory = Directory.systemTemp.createTempSync('zeta_test_');
    tempDirectories.add(directory);

    final file = File('${directory.path}${Platform.pathSeparator}sample.txt');
    file.writeAsStringSync('hello from zeta');

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        directoryPicker: () async => directory.path,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: _FakeAgentProviderFactory(_FakeAgentProvider()),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
    await tester.runAsync(_waitForIo);
    await tester.pump();

    await tester.tap(find.byKey(_fileNodeKey('sample.txt')));
    await tester.runAsync(_waitForIo);
    await tester.pump();
    await _pumpSessionSave(tester);

    expect(session.value, isNotNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: _FakeAgentProviderFactory(_FakeAgentProvider()),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );
    await tester.runAsync(_waitForIo);
    await tester.pump();

    expect(find.text('sample.txt'), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-context-chip')), findsNothing);
    expect(find.byIcon(Icons.save_outlined), findsNothing);
  });

  testWidgets('restores expanded file tree folders on restart', (tester) async {
    final session = _MemorySessionStore();
    final directory = Directory.systemTemp.createTempSync('zeta_test_');
    tempDirectories.add(directory);

    final folder = Directory('${directory.path}${Platform.pathSeparator}lib')
      ..createSync();
    File(
      '${folder.path}${Platform.pathSeparator}main.dart',
    ).writeAsStringSync('void main() {}');

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        directoryPicker: () async => directory.path,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: _FakeAgentProviderFactory(_FakeAgentProvider()),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
    await tester.runAsync(_waitForIo);
    await tester.pump();

    expect(find.text('main.dart'), findsNothing);

    await tester.tap(find.byKey(_fileNodeKey('lib')));
    await tester.pumpAndSettle();
    await _pumpSessionSave(tester);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: _FakeAgentProviderFactory(_FakeAgentProvider()),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );
    await tester.runAsync(_waitForIo);
    await tester.pump();

    expect(find.text('lib'), findsOneWidget);
    expect(find.text('main.dart'), findsOneWidget);
  });

  testWidgets(
    'restores project root contents without showing the root folder',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync('zeta_test_');
      tempDirectories.add(directory);

      File(
        '${directory.path}${Platform.pathSeparator}sample.txt',
      ).writeAsStringSync('hello from zeta');

      final session = _MemorySessionStore(
        jsonEncode(<String, Object?>{
          'version': 1,
          'projectPaths': <String>[directory.path],
          'activeProjectPath': directory.path,
          'currentFilePath': null,
          'expandedDirectoryPaths': <String>[],
          'selectedTreeKey': directory.path,
        }),
      );

      await tester.pumpWidget(
        MainApp(
          enableNativeWindowFrame: false,
          sessionLoader: session.load,
          sessionSaver: session.save,
          agentProviderFactory: _FakeAgentProviderFactory(_FakeAgentProvider()),
          agentProviderConfigStore: MemoryAgentProviderConfigStore(),
        ),
      );
      await tester.runAsync(_waitForIo);
      await tester.pump();

      expect(find.byKey(_fileNodeKey(fileName(directory.path))), findsNothing);
      expect(find.text('sample.txt'), findsOneWidget);
    },
  );

  testWidgets('ignores missing paths when restoring a session', (tester) async {
    final session = _MemorySessionStore(
      jsonEncode(<String, Object?>{
        'version': 1,
        'projectPaths': <String>['/zeta/missing/project'],
        'activeProjectPath': '/zeta/missing/project',
        'currentFilePath': '/zeta/missing/project/main.dart',
        'expandedDirectoryPaths': <String>['/zeta/missing/project'],
        'selectedTreeKey': '/zeta/missing/project/main.dart',
      }),
    );

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        sessionLoader: session.load,
        sessionSaver: session.save,
      ),
    );
    await tester.runAsync(_waitForIo);
    await tester.pump();

    expect(find.text('No folder opened'), findsOneWidget);
    expect(find.text('No file tree'), findsOneWidget);
    expect(find.text('No file context'), findsNothing);
  });

  testWidgets(
    'does not let a slow session restore replace a user-opened folder',
    (tester) async {
      final restoreCompleter = Completer<String?>();
      final savedSession = _MemorySessionStore();
      final restoredDirectory = Directory.systemTemp.createTempSync(
        'zeta_restore_',
      );
      final chosenDirectory = Directory.systemTemp.createTempSync(
        'zeta_chosen_',
      );
      tempDirectories
        ..add(restoredDirectory)
        ..add(chosenDirectory);

      final restoredFile = File(
        '${restoredDirectory.path}${Platform.pathSeparator}restored.txt',
      )..writeAsStringSync('restored');
      File(
        '${chosenDirectory.path}${Platform.pathSeparator}chosen.txt',
      ).writeAsStringSync('chosen');

      await tester.pumpWidget(
        MainApp(
          enableNativeWindowFrame: false,
          directoryPicker: () async => chosenDirectory.path,
          sessionLoader: () => restoreCompleter.future,
          sessionSaver: savedSession.save,
          agentProviderFactory: _FakeAgentProviderFactory(_FakeAgentProvider()),
          agentProviderConfigStore: MemoryAgentProviderConfigStore(),
        ),
      );

      await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
      await tester.runAsync(_waitForIo);
      await tester.pump();

      expect(find.text('chosen.txt'), findsOneWidget);
      expect(find.text('restored.txt'), findsNothing);

      restoreCompleter.complete(
        _sessionJson(
          projectPath: restoredDirectory.path,
          currentFilePath: restoredFile.path,
        ),
      );
      await tester.runAsync(_waitForIo);
      await tester.pump();
      await _pumpSessionSave(tester);

      expect(find.text('chosen.txt'), findsOneWidget);
      expect(find.text('restored.txt'), findsNothing);
    },
  );
}

ValueKey<String> _fileNodeKey(String label) {
  return ValueKey<String>('file-node-$label');
}

Future<void> _waitForIo() {
  return Future<void>.delayed(const Duration(milliseconds: 300));
}

Future<void> _pumpSessionSave(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 450));
  await tester.pump();
}

String _sessionJson({required String projectPath, String? currentFilePath}) {
  return jsonEncode(<String, Object?>{
    'version': 1,
    'projectPaths': <String>[projectPath],
    'activeProjectPath': projectPath,
    'currentFilePath': currentFilePath,
    'expandedDirectoryPaths': <String>[projectPath],
    'selectedTreeKey': currentFilePath ?? projectPath,
  });
}

String? _headerTitleText(WidgetTester tester) {
  return tester
      .widget<Text>(find.byKey(const ValueKey('agent-header-title')))
      .data;
}

String _commandGroupId(String turnId, String firstEntryId) {
  return 'command-group-$turnId-$firstEntryId';
}

String _fileEditGroupId(String turnId, String toolCallId) {
  return 'file-edit-group-$turnId-$toolCallId';
}

Map<String, Object?> _patchApplyChanges(Map<String, String?> diffsByPath) {
  return <String, Object?>{
    'changes': <String, Object?>{
      for (final entry in diffsByPath.entries)
        entry.key: <String, Object?>{
          'type': 'update',
          if (entry.value != null) 'unified_diff': entry.value,
        },
    },
  };
}

AgentThreadSummary _agentThread({
  required String id,
  required String projectPath,
  required String title,
  String? preview,
  DateTime? lastActiveAt,
}) {
  final activeAt = lastActiveAt ?? DateTime.fromMillisecondsSinceEpoch(2);
  return AgentThreadSummary(
    id: id,
    providerId: defaultAgentProviderId,
    projectPath: projectPath,
    title: title,
    sessionPath: '$projectPath/$id.jsonl',
    preview: preview ?? title,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1),
    updatedAt: activeAt,
    recencyAt: activeAt,
    status: AgentThreadRuntimeStatus.idle,
  );
}

class _MemorySessionStore {
  _MemorySessionStore([this.value]);

  String? value;

  Future<String?> load() async => value;

  Future<void> save(String newValue) async {
    value = newValue;
  }
}

class _FakeAgentProviderFactory implements AgentProviderFactory {
  const _FakeAgentProviderFactory(this.provider);

  final _FakeAgentProvider provider;

  @override
  AgentProvider create(AgentProviderConfig config) => provider;
}

class _FakeAgentProvider implements AgentProvider {
  _FakeAgentProvider({
    this.emitToolAndApproval = false,
    this.emitCompletedCommentary = false,
    this.completeTurns = true,
    this.unavailable = false,
    this.sessionTitle,
    this.tokenUsageDuringTurn,
    this.responseText = 'Fake response from provider',
    this.onResumeSession,
    List<AgentThreadPage> threadPages = const <AgentThreadPage>[],
    Map<String, AgentThreadHistorySnapshot> threadHistories =
        const <String, AgentThreadHistorySnapshot>{},
  }) : _threadPages = List<AgentThreadPage>.from(threadPages),
       _threadHistories = Map<String, AgentThreadHistorySnapshot>.from(
         threadHistories,
       );

  final bool emitToolAndApproval;
  final bool emitCompletedCommentary;
  final bool completeTurns;
  final bool unavailable;
  final String? sessionTitle;
  final AgentTokenUsage? tokenUsageDuringTurn;
  final String responseText;
  final Future<AgentSession> Function(String sessionId)? onResumeSession;
  final List<AgentThreadPage> _threadPages;
  final Map<String, AgentThreadHistorySnapshot> _threadHistories;
  final StreamController<AgentEvent> _events =
      StreamController<AgentEvent>.broadcast();
  final List<String> sentMessages = <String>[];
  final List<String> steeredMessages = <String>[];
  final List<AgentThreadListQuery> listQueries = <AgentThreadListQuery>[];
  final List<String> readHistories = <String>[];
  final List<String?> readHistorySessionPaths = <String?>[];
  final List<String> resumedSessions = <String>[];
  final List<String> approvedRequests = <String>[];
  final List<String> deniedRequests = <String>[];
  final List<String> cancelledTurns = <String>[];

  @override
  AgentProviderConfig get config => AgentProviderConfig.defaultCodex;

  @override
  Stream<AgentEvent> get events => _events.stream;

  @override
  Future<void> initialize() async {
    if (unavailable) {
      throw const ProcessException('codex', <String>[], 'codex missing');
    }
  }

  @override
  Future<AgentSession> startSession({required AgentContext context}) async {
    await initialize();
    return AgentSession(
      id: 'thread-1',
      providerId: defaultAgentProviderId,
      title: sessionTitle,
    );
  }

  @override
  Future<AgentSession> resumeSession(
    String sessionId, {
    required AgentContext context,
  }) async {
    await initialize();
    resumedSessions.add(sessionId);
    final onResumeSession = this.onResumeSession;
    if (onResumeSession != null) {
      return onResumeSession(sessionId);
    }
    return AgentSession(
      id: sessionId,
      providerId: defaultAgentProviderId,
      title: sessionTitle,
    );
  }

  @override
  Future<AgentThreadPage> listThreads({
    required AgentThreadListQuery query,
  }) async {
    await initialize();
    listQueries.add(query);
    if (_threadPages.isEmpty) {
      return const AgentThreadPage(
        threads: <AgentThreadSummary>[],
        nextCursor: null,
      );
    }
    return _threadPages.removeAt(0);
  }

  @override
  Future<AgentThreadHistorySnapshot> readThreadHistory({
    required String threadId,
    String? sessionPath,
  }) async {
    await initialize();
    readHistories.add(threadId);
    readHistorySessionPaths.add(sessionPath);
    return _threadHistories[threadId] ??
        AgentThreadHistorySnapshot(
          threadId: threadId,
          turns: const <AgentHistoryTurn>[],
        );
  }

  @override
  Future<AgentTurn> sendMessage({
    required AgentSession session,
    required String message,
    required AgentContext context,
  }) async {
    sentMessages.add(message);
    final turn = AgentTurn(id: 'turn-1', sessionId: session.id);
    _events
      ..add(AgentTurnStartedEvent(turn))
      ..add(
        AgentMessageDeltaEvent(
          messageId: 'message-1',
          delta: responseText,
          role: AgentMessageRole.agent,
          phase: emitCompletedCommentary
              ? AgentMessagePhase.commentary
              : AgentMessagePhase.response,
          sessionId: session.id,
          turnId: turn.id,
        ),
      );
    if (tokenUsageDuringTurn != null) {
      _events.add(
        AgentTokenUsageEvent(
          sessionId: session.id,
          turnId: turn.id,
          tokenUsage: tokenUsageDuringTurn!,
        ),
      );
    }
    if (emitCompletedCommentary) {
      _events.add(
        AgentMessageUpdatedEvent(
          messageId: 'message-1',
          phase: AgentMessagePhase.commentary,
          status: AgentMessageStatus.completed,
          duration: Duration(seconds: 102),
          sessionId: session.id,
          turnId: turn.id,
        ),
      );
    }
    if (emitToolAndApproval) {
      _events
        ..add(
          AgentToolCallEvent(
            AgentToolCall(
              id: 'tool-1',
              title: 'Run tests',
              kind: AgentToolKind.execute,
              status: AgentToolStatus.inProgress,
              content: 'flutter test',
              sessionId: session.id,
              turnId: turn.id,
            ),
          ),
        )
        ..add(
          AgentPermissionRequestedEvent(
            AgentPermissionRequest(
              id: 'approval-1',
              title: 'Approve command',
              kind: AgentPermissionKind.commandExecution,
              command: 'flutter test',
              sessionId: session.id,
              turnId: turn.id,
            ),
          ),
        );
    }
    if (completeTurns) {
      _events.add(
        AgentTurnCompletedEvent(sessionId: session.id, turnId: turn.id),
      );
    }
    return turn;
  }

  @override
  Future<void> steerTurn({
    required AgentSession session,
    required String message,
    required AgentContext context,
  }) async {
    steeredMessages.add(message);
  }

  @override
  Future<void> cancelTurn(AgentTurn turn) async {
    cancelledTurns.add(turn.id);
    _events.add(
      AgentTurnCompletedEvent(sessionId: turn.sessionId, turnId: turn.id),
    );
  }

  @override
  Future<AgentModelList> listModels({
    int limit = 20,
    bool includeHidden = false,
  }) async {
    return const AgentModelList(models: <AgentModelInfo>[]);
  }

  @override
  void updateModelSelection(AgentModelSelection selection) {}

  @override
  Future<void> respondToPermission(AgentPermissionDecision decision) async {
    if (decision.approved) {
      approvedRequests.add(decision.requestId);
    } else {
      deniedRequests.add(decision.requestId);
    }
  }

  @override
  Future<void> dispose() async {
    await _events.close();
  }

  void emit(AgentEvent event) {
    _events.add(event);
  }
}

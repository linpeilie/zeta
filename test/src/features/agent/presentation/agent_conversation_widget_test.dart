// ignore_for_file: deprecated_member_use

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixin_markdown_widget/mixin_markdown_widget.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta/main.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_view_model.dart';
import 'package:zeta/src/features/agent/presentation/agent_pane.dart';
import 'package:zeta/src/ui/core/app_theme.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';
import 'package:zeta/src/ui/features/ide/view_models/active_agent_provider_controller.dart';

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

  testWidgets('loads older turns without jumping the viewport', (tester) async {
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
            agentThread(
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
        agentProviderFactory: FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
    await tester.runAsync(waitForIo);
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
            agentThread(
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
        agentProviderFactory: FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
    await tester.runAsync(waitForIo);
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
            agentThread(
              id: 'thread-a',
              projectPath: directory.path,
              title: 'Thread A',
            ),
            agentThread(
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
        agentProviderFactory: FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
    await tester.runAsync(waitForIo);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(ValueKey<String>('project-thread-${directory.path}-thread-a')),
    );
    // 该历史回合处于 running，界面会持续播放 spinner，不能等待所有动画结束。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('History A'), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-cancel-button')), findsOneWidget);

    await tester.tap(
      find.byKey(ValueKey<String>('project-thread-${directory.path}-thread-b')),
    );
    await pumpUntilCondition(
      tester,
      () => find.text('History B').evaluate().isNotEmpty,
      failureMessage: 'Thread B history did not become visible',
    );

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
              agentThread(
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
      // 运行中的历史回合会持续播放 spinner，仅推进有限帧等待 thread 切换完成。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(provider.resumedSessions, <String>['thread-a']);
      expect(provider.sentMessages, isEmpty);
      expect(provider.steeredMessages, <String>['follow up']);
    },
  );

  testWidgets(
    'keeps history visible and requires reselect after resume failure on first send',
    (tester) async {
      final session = MemorySessionStore();
      final directory = Directory.systemTemp.createTempSync('zeta_test_');
      tempDirectories.add(directory);
      File(
        '${directory.path}${Platform.pathSeparator}sample.txt',
      ).writeAsStringSync('hello from zeta');
      var resumeAttempts = 0;

      final provider = FakeAgentProvider(
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
              agentThread(
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
      // 项目线程列表中的正式标题优先于 resume 返回的临时 session 标题。
      expect(headerTitleText(tester), 'Retryable thread');
      expect(provider.sentMessages, <String>['second try']);
    },
  );

  testWidgets(
    'shows answered request_user_input entries without placeholders',
    (tester) async {
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
              agentThread(
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
          agentProviderFactory: FakeAgentProviderFactory(provider),
          agentProviderConfigStore: MemoryAgentProviderConfigStore(),
        ),
      );

      await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
      await tester.runAsync(waitForIo);
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
                entries: <AgentHistoryEntry>[
                  const AgentHistoryMessageEntry(
                    id: 'history-user-1',
                    role: AgentMessageRole.user,
                    text: 'Please summarize the run',
                  ),
                  AgentHistoryToolEntry(
                    toolCall: AgentToolCall(
                      id: 'history-tool-1',
                      title: 'call-abc123',
                      kind: AgentToolKind.execute,
                      status: AgentToolStatus.completed,
                      content: 'flutter test\nhidden log line',
                      rawInput: const <String, Object?>{
                        'command': 'flutter test',
                      },
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
              agentThread(
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

      expect(find.text('1 次执行 · 1 次搜索'), findsOneWidget);
      expect(find.text('执行 · flutter test'), findsNothing);
      expect(find.text('OpenAI docs'), findsNothing);
      expect(find.text('hidden log line'), findsNothing);
      expect(find.text('Hidden result line'), findsNothing);

      await tester.tap(
        find.byKey(
          ValueKey<String>(
            'agent-command-group-header-${commandGroupId('turn-a-1', 'tool-history-tool-1')}',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('执行 · flutter test'), findsOneWidget);
      expect(find.text('搜索 · Web search · OpenAI docs'), findsOneWidget);
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

  testWidgets('composer hides image and policy controls for Grok', (
    tester,
  ) async {
    final provider = FakeAgentProvider(
      config: AgentProviderConfig.defaultGrok,
      declaredCapabilities: AgentProviderCapabilities.grokAcp,
    );
    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        directoryPicker: () async => null,
        sessionLoader: () async => null,
        sessionSaver: (_) async {},
        agentProviderFactory: FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(
          const AgentProviderSettings(
            providers: <AgentProviderConfig>[AgentProviderConfig.defaultGrok],
            activeProviderId: grokAgentProviderId,
          ),
        ),
      ),
    );
    final attachImageButton = find.byKey(
      const ValueKey('agent-attach-image-button'),
    );
    final permissionPolicySelector = find.byKey(
      const ValueKey('agent-permission-policy-selector'),
    );
    final mentionFileButton = find.byKey(
      const ValueKey('agent-mention-file-button'),
    );
    await pumpUntilCondition(
      tester,
      () =>
          attachImageButton.evaluate().isEmpty &&
          permissionPolicySelector.evaluate().isEmpty &&
          mentionFileButton.evaluate().isNotEmpty,
      failureMessage: 'Grok composer controls did not become ready',
    );

    expect(attachImageButton, findsNothing);
    expect(permissionPolicySelector, findsNothing);
    expect(mentionFileButton, findsOneWidget);
  });

  testWidgets(
    'renders file edits in a separate file edit group with file-level details',
    (tester) async {
      // 该测试断言深色主题下的具体颜色；固定系统亮度为 dark，使「跟随系统」
      // 的默认主题解析为深色，与历史断言一致。
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

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
                      rawOutput: patchApplyChanges(<String, String?>{
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
              agentThread(
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

      expect(find.text('2 个文件 · +2 / -1', findRichText: true), findsOneWidget);
      expect(find.text('1 次执行'), findsOneWidget);
      expect(find.text('Run tests'), findsNothing);

      await tester.tap(
        find.byKey(
          ValueKey<String>(
            'agent-file-edit-group-header-${fileEditGroupId('turn-a-1', 'history-edit-1')}',
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
          'agent-file-edit-group-summary-${fileEditGroupId('turn-a-1', 'history-edit-1')}',
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
        IdeColors.dark.success.withValues(alpha: 0.98),
      );
      expect(
        (historyGroupChildren[4] as TextSpan).style?.color,
        IdeColors.dark.error.withValues(alpha: 0.98),
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
        IdeColors.dark.success.withValues(alpha: 0.98),
      );
      expect(
        (historyLineChildren[2] as TextSpan).style?.color,
        IdeColors.dark.error.withValues(alpha: 0.98),
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
              entries: <AgentHistoryEntry>[
                AgentHistoryToolEntry(
                  toolCall: AgentToolCall(
                    id: 'history-edit-nodetail',
                    title: 'File change',
                    kind: AgentToolKind.edit,
                    status: AgentToolStatus.completed,
                    rawOutput: patchApplyChanges(<String, String?>{
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
            agentThread(
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
        agentProviderFactory: FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
    await tester.runAsync(waitForIo);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(ValueKey<String>('project-thread-${directory.path}-thread-a')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        ValueKey<String>(
          'agent-file-edit-group-header-${fileEditGroupId('turn-a-1', 'history-edit-nodetail')}',
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

  testWidgets(
    'updates header title when server renames a newly started thread',
    (tester) async {
      final provider = FakeAgentProvider();
      final controller = ActiveAgentProviderController(
        providerFactory: FakeAgentProviderFactory(provider),
        configStore: MemoryAgentProviderConfigStore(),
      );
      addTearDown(controller.dispose);
      final viewModel = AgentConversationViewModel(
        providerController: controller,
      );
      addTearDown(viewModel.dispose);
      viewModel.updateWorkspace(projectPath: '/repo', contextFilePath: null);

      final lightIdeTheme = buildIdeThemeData(
        brightness: Brightness.light,
        codeFontFamily: 'CodeFont',
      );
      final darkIdeTheme = buildIdeThemeData(
        brightness: Brightness.dark,
        codeFontFamily: 'CodeFont',
      );
      await tester.pumpWidget(
        IdeThemeScope(
          themeMode: ThemeMode.dark,
          lightTheme: lightIdeTheme,
          darkTheme: darkIdeTheme,
          child: sf.ShadcnApp(
            theme: buildShadcnTheme(lightIdeTheme),
            darkTheme: buildShadcnTheme(darkIdeTheme),
            materialTheme: buildMaterialTheme(darkIdeTheme),
            themeMode: sf.ThemeMode.dark,
            home: sf.Scaffold(child: AgentPane(viewModel: viewModel)),
          ),
        ),
      );
      await tester.pump();
      expect(headerTitleText(tester), 'New thread');

      await viewModel.sendMessage('Start a brand new conversation');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      // 新会话先显示首条用户消息，再被服务端/本地 generated_title 覆盖。
      expect(headerTitleText(tester), 'Start a brand new conversation');

      provider.emit(
        const AgentThreadNameUpdatedEvent(
          threadId: 'thread-1',
          threadName: 'Brand new conversation',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(headerTitleText(tester), 'Brand new conversation');
    },
  );

  testWidgets('renames the current thread from the header more menu', (
    tester,
  ) async {
    final provider = FakeAgentProvider();
    final controller = ActiveAgentProviderController(
      providerFactory: FakeAgentProviderFactory(provider),
      configStore: MemoryAgentProviderConfigStore(),
    );
    addTearDown(controller.dispose);
    final viewModel = AgentConversationViewModel(
      providerController: controller,
    );
    addTearDown(viewModel.dispose);
    viewModel.updateWorkspace(projectPath: '/repo', contextFilePath: null);
    await viewModel.switchThread(
      agentThread(
        id: 'thread-a',
        projectPath: '/repo',
        title: 'Original title',
      ),
    );

    final lightIdeTheme = buildIdeThemeData(
      brightness: Brightness.light,
      codeFontFamily: 'CodeFont',
    );
    final darkIdeTheme = buildIdeThemeData(
      brightness: Brightness.dark,
      codeFontFamily: 'CodeFont',
    );
    await tester.pumpWidget(
      IdeThemeScope(
        themeMode: ThemeMode.dark,
        lightTheme: lightIdeTheme,
        darkTheme: darkIdeTheme,
        child: sf.ShadcnApp(
          theme: buildShadcnTheme(lightIdeTheme),
          darkTheme: buildShadcnTheme(darkIdeTheme),
          materialTheme: buildMaterialTheme(darkIdeTheme),
          themeMode: sf.ThemeMode.dark,
          home: sf.Scaffold(child: AgentPane(viewModel: viewModel)),
        ),
      ),
    );
    await tester.pump();
    expect(headerTitleText(tester), 'Original title');

    await tester.tap(find.byKey(const ValueKey('agent-header-more')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const ValueKey('agent-header-menu-rename')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('agent-header-menu-rename')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final dialogFinder = find.byKey(
      const ValueKey('agent-header-rename-dialog'),
    );
    expect(dialogFinder, findsOneWidget);

    await tester.enterText(
      find.descendant(of: dialogFinder, matching: find.byType(EditableText)),
      'Renamed from header',
    );
    await tester.tap(find.text('确认'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(provider.renamedThreads, hasLength(1));
    expect(provider.renamedThreads.single.threadId, 'thread-a');
    expect(provider.renamedThreads.single.name, 'Renamed from header');
    expect(headerTitleText(tester), 'Renamed from header');
  });

  testWidgets('opens the context details panel from the header more menu', (
    tester,
  ) async {
    final createdAt = DateTime(2024, 1, 15, 10, 30);
    final lastActiveAt = DateTime(2024, 6, 20, 14, 5);
    final provider = FakeAgentProvider(
      threadHistories: <String, AgentThreadHistorySnapshot>{
        'thread-ctx': AgentThreadHistorySnapshot(
          threadId: 'thread-ctx',
          turns: <AgentHistoryTurn>[
            AgentHistoryTurn(
              id: 'turn-1',
              status: AgentHistoryTurnStatus.completed,
              modelContextWindow: 200000,
              tokenUsage: const AgentTokenUsage(
                inputTokens: 100,
                cachedInputTokens: 20,
                outputTokens: 30,
                totalTokens: 130,
                modelContextWindow: 200000,
              ),
              entries: <AgentHistoryEntry>[
                AgentHistoryMessageEntry(
                  id: 'msg-user-1',
                  role: AgentMessageRole.user,
                  text: 'Hello',
                  raw: <String, Object?>{
                    'type': 'response_item',
                    'timestamp': 1700000000,
                    'marker': 'ctx-user-raw',
                  },
                ),
                AgentHistoryMessageEntry(
                  id: 'msg-agent-1',
                  role: AgentMessageRole.agent,
                  text: 'Hi there',
                  raw: <String, Object?>{
                    'type': 'event_msg',
                    'timestamp': 1700000005,
                    'marker': 'ctx-agent-raw',
                  },
                ),
              ],
            ),
          ],
        ),
      },
    );
    final controller = ActiveAgentProviderController(
      providerFactory: FakeAgentProviderFactory(provider),
      configStore: MemoryAgentProviderConfigStore(),
    );
    addTearDown(controller.dispose);
    final viewModel = AgentConversationViewModel(
      providerController: controller,
    );
    addTearDown(viewModel.dispose);
    viewModel.updateWorkspace(projectPath: '/repo', contextFilePath: null);
    await viewModel.switchThread(
      AgentThreadSummary(
        id: 'thread-ctx',
        providerId: defaultAgentProviderId,
        projectPath: '/repo',
        title: 'Context thread',
        preview: 'Context thread',
        sessionPath: '/repo/thread-ctx.jsonl',
        createdAt: createdAt,
        updatedAt: lastActiveAt,
        recencyAt: lastActiveAt,
        status: AgentThreadRuntimeStatus.idle,
      ),
    );

    final lightIdeTheme = buildIdeThemeData(
      brightness: Brightness.light,
      codeFontFamily: 'CodeFont',
    );
    final darkIdeTheme = buildIdeThemeData(
      brightness: Brightness.dark,
      codeFontFamily: 'CodeFont',
    );
    await tester.pumpWidget(
      IdeThemeScope(
        themeMode: ThemeMode.dark,
        lightTheme: lightIdeTheme,
        darkTheme: darkIdeTheme,
        child: sf.ShadcnApp(
          theme: buildShadcnTheme(lightIdeTheme),
          darkTheme: buildShadcnTheme(darkIdeTheme),
          materialTheme: buildMaterialTheme(darkIdeTheme),
          themeMode: sf.ThemeMode.dark,
          home: sf.Scaffold(child: AgentPane(viewModel: viewModel)),
        ),
      ),
    );
    await tester.pump();

    // 默认隐藏。
    expect(find.byKey(const ValueKey('agent-context-panel')), findsNothing);

    // 通过头栏「更多」菜单的「上下文」项打开面板。
    await tester.tap(find.byKey(const ValueKey('agent-header-more')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const ValueKey('agent-header-menu-context')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('agent-header-menu-context')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const ValueKey('agent-context-panel')), findsOneWidget);

    // 概览信息：会话名称、消息数、提供商、token 与时间。
    expect(find.text('Context thread'), findsWidgets);
    expect(find.text('2'), findsOneWidget);
    // 头栏 provider 切换器与上下文面板都会展示提供商名，限定在面板内断言。
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('agent-context-panel')),
        matching: find.text('Codex CLI'),
      ),
      findsOneWidget,
    );
    expect(find.text('200k'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('agent-context-panel')),
        matching: find.text('130'),
      ),
      findsOneWidget,
    );
    expect(find.text('2024-01-15 10:30'), findsOneWidget);
    expect(find.text('2024-06-20 14:05'), findsOneWidget);

    // 原始消息列表：ID 与角色。
    expect(find.text('msg-user-1'), findsOneWidget);
    expect(find.text('用户'), findsOneWidget);
    expect(find.text('msg-agent-1'), findsOneWidget);
    expect(find.text('助手'), findsOneWidget);

    // 折叠态下不渲染 raw 原文区。
    expect(
      find.byKey(const ValueKey('agent-context-raw-body-msg-user-1')),
      findsNothing,
    );
    // 展开后渲染 raw 原文区。
    await tester.tap(
      find.byKey(const ValueKey('agent-context-raw-msg-user-1')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('agent-context-raw-body-msg-user-1')),
      findsOneWidget,
    );

    // 关闭按钮收起面板。
    await tester.tap(find.byKey(const ValueKey('agent-context-panel-close')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('agent-context-panel')), findsNothing);
  });

  testWidgets(
    'shows session total token usage in header and context window in composer while running',
    (tester) async {
      final session = MemorySessionStore();
      final provider = FakeAgentProvider(
        completeTurns: false,
        sessionTitle: 'Running thread',
        tokenUsageDuringTurn: const AgentTokenUsage(
          inputTokens: 1000,
          cachedInputTokens: 200,
          outputTokens: 350,
          totalTokens: 1300,
          lastInputTokens: 900,
          lastCachedInputTokens: 180,
          lastOutputTokens: 320,
          lastTotalTokens: 1200,
          modelContextWindow: 2000,
        ),
      );

      await tester.pumpWidget(
        MainApp(
          enableNativeWindowFrame: false,
          sessionLoader: session.load,
          sessionSaver: session.save,
          agentProviderFactory: FakeAgentProviderFactory(provider),
          agentProviderConfigStore: MemoryAgentProviderConfigStore(),
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('agent-message-input')),
        'Keep running',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('agent-send-button')));
      // 执行中 spinner 为无限动画，不能 pumpAndSettle。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(headerTitleText(tester), 'Running thread');
      expect(
        find.byKey(const ValueKey('agent-header-running-icon')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('agent-header-running-icon')),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('agent-header-token')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('agent-header-token')),
          matching: find.textContaining('%'),
        ),
        findsNothing,
      );
      // 头栏展示会话累计 totalTokens（1300），与上下文面板「总 Token」一致。
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('agent-header-token')),
          matching: find.text('1.3k tokens'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('agent-composer-token-usage')),
        findsOneWidget,
      );
      final progress = tester.widget<CircularProgressIndicator>(
        find.byKey(const ValueKey('agent-composer-token-progress')),
      );
      expect(progress.value, closeTo(0.6, 0.001));

      // 对话流内进行中状态条（与 header 同源；fake provider 会先推 agent delta → 回复中）。
      expect(
        find.byKey(const ValueKey('agent-live-activity-status')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('agent-live-activity-label')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('agent-live-activity-status')),
          matching: find.textContaining('回复中'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('agent-header-running-status')),
        findsOneWidget,
      );

      final tooltip = tester.widget<IdeTooltip>(
        find.ancestor(
          of: find.byKey(const ValueKey('agent-composer-token-usage')),
          matching: find.byType(IdeTooltip),
        ),
      );
      expect(tooltip.message, contains('Usage: 60%'));
      expect(tooltip.message, contains('Used: 1.2k'));
      expect(tooltip.message, contains('Total: 2k'));
      expect(tooltip.message, contains('input_tokens: 900'));
      expect(tooltip.message, contains('output_tokens: 320'));
      expect(tooltip.message, contains('cached_input_tokens: 180'));
    },
  );

  testWidgets(
    'shows running icons in both the header and project thread list for an active thread',
    (tester) async {
      final session = MemorySessionStore();
      final directory = Directory.systemTemp.createTempSync('zeta_test_');
      tempDirectories.add(directory);
      File(
        '${directory.path}${Platform.pathSeparator}sample.txt',
      ).writeAsStringSync('hello from zeta');

      final provider = FakeAgentProvider(
        completeTurns: false,
        sessionTitle: 'Running thread',
        threadPages: <AgentThreadPage>[
          AgentThreadPage(
            threads: <AgentThreadSummary>[
              agentThread(
                id: 'thread-a',
                projectPath: directory.path,
                title: 'Running thread',
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

      await tester.enterText(
        find.byKey(const ValueKey('agent-message-input')),
        'Keep running',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('agent-send-button')));
      // 执行中 spinner 为无限动画，不能 pumpAndSettle。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final headerRunning = find.byKey(
        const ValueKey('agent-header-running-icon'),
      );
      final listRunning = find.byKey(
        ValueKey<String>(
          'project-thread-running-icon-${directory.path}-thread-a',
        ),
      );
      expect(headerRunning, findsOneWidget);
      expect(listRunning, findsOneWidget);
      expect(
        find.descendant(
          of: headerRunning,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: listRunning,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('agent-cancel-button')));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(headerRunning, findsNothing);
      expect(listRunning, findsNothing);
    },
  );

  testWidgets('keeps the flattened agent pane stable in a narrow window', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(920, 820);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final session = MemorySessionStore();
    final provider = FakeAgentProvider(
      completeTurns: false,
      sessionTitle: 'Long running thread title for narrow layout',
      tokenUsageDuringTurn: const AgentTokenUsage(
        inputTokens: 3200,
        cachedInputTokens: 1200,
        outputTokens: 820,
        totalTokens: 3840,
        lastInputTokens: 1800,
        lastCachedInputTokens: 760,
        lastOutputTokens: 540,
        lastTotalTokens: 2340,
        modelContextWindow: 4000,
      ),
    );

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('agent-message-input')),
      'Keep the layout stable',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('agent-send-button')));
    // 用例故意保持 turn 运行，spinner 不会 settle。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const ValueKey('agent-pane-host')), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-header-token')), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-cancel-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps command group scroll position when toggling grouped history', (
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
            agentThread(
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
        agentProviderFactory: FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
    await tester.runAsync(waitForIo);
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
          'agent-command-group-header-${commandGroupId('turn-a-1', 'tool-history-tool-a')}',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.offset, lessThan(40));
    expect(
      find.byKey(
        const ValueKey<String>('agent-command-group-item-tool-history-tool-a'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>(
          'agent-command-group-item-history-event-history-search-a',
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('rip_grep_packages'), findsNothing);
    expect(
      find.byKey(
        ValueKey<String>(
          'agent-command-group-body-${commandGroupId('turn-a-1', 'tool-history-tool-a')}',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('keeps single command group scroll position stable', (
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
            agentThread(
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
        agentProviderFactory: FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
    await tester.runAsync(waitForIo);
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
          'agent-command-group-header-${commandGroupId('turn-a-1', 'tool-history-tool-jump')}',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.offset, lessThan(40));
    expect(
      find.byKey(
        const ValueKey<String>(
          'agent-command-group-item-tool-history-tool-jump',
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('long output'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('agent-tool-body-history-tool-jump')),
      findsNothing,
    );
  });

  testWidgets('adds local agent messages from the composer', (tester) async {
    final session = MemorySessionStore();
    final provider = FakeAgentProvider();

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: FakeAgentProviderFactory(provider),
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

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('agent-message-list')),
        matching: find.text('Summarize the current work'),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Fake response from provider', findRichText: true),
      findsOneWidget,
    );
    expect(provider.sentMessages.single, 'Summarize the current work');
  });

  testWidgets('renders user messages as selectable text for copy', (
    tester,
  ) async {
    final session = MemorySessionStore();
    final provider = FakeAgentProvider();

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('agent-message-input')),
      'Copy this user message',
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('agent-send-button')));
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(SelectableText, 'Copy this user message'),
      findsOneWidget,
    );
  });

  testWidgets('keeps manual scroll position during live agent streaming', (
    tester,
  ) async {
    final session = MemorySessionStore();
    final provider = FakeAgentProvider(
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
        agentProviderFactory: FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('agent-message-input')),
      'Keep streaming',
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('agent-send-button')));
    await pumpLiveAgentUi(tester);

    final listFinder = find.byKey(const ValueKey('agent-message-list'));
    final controller = tester
        .widget<SingleChildScrollView>(listFinder)
        .controller!;
    expect(controller.position.maxScrollExtent, greaterThan(400));

    controller.jumpTo(0);
    await pumpLiveAgentUi(tester);
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
    final session = MemorySessionStore();
    final provider = FakeAgentProvider(completeTurns: false);

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('agent-message-input')),
      'Run grouped tools',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('agent-send-button')));
    await pumpLiveAgentUi(tester);

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
    await pumpLiveAgentUi(tester);

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
    await pumpLiveAgentUi(tester);

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
          'agent-command-group-header-${commandGroupId('turn-1', 'tool-live-tool-1')}',
        ),
      ),
    );
    await pumpLiveAgentUi(tester);

    expect(
      find.byKey(
        const ValueKey<String>('agent-command-group-item-tool-live-tool-1'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>('agent-command-group-item-tool-live-tool-2'),
      ),
      findsOneWidget,
    );
    expect(find.text('flutter test'), findsNothing);
    expect(find.text('rip_grep_packages'), findsNothing);
    expect(find.text('hidden log line'), findsNothing);
    expect(find.text('hidden result line'), findsNothing);
  });

  testWidgets('renders live file edits as a separate expandable file edit group', (
    tester,
  ) async {
    final session = MemorySessionStore();
    final provider = FakeAgentProvider(completeTurns: false);

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('agent-message-input')),
      'Apply a patch',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('agent-send-button')));
    await pumpLiveAgentUi(tester);

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
    await pumpLiveAgentUi(tester);

    expect(find.text('2 个文件', findRichText: true), findsOneWidget);

    provider.emit(
      AgentToolCallEvent(
        AgentToolCall(
          id: 'live-edit-1',
          title: 'Apply patch',
          kind: AgentToolKind.edit,
          status: AgentToolStatus.completed,
          locations: const <String>['lib/main.dart', 'README.md'],
          rawOutput: patchApplyChanges(<String, String?>{
            'lib/main.dart': '@@ -1 +1 @@\n-old line\n+new line\n',
            'README.md': '@@ -0,0 +1 @@\n+docs line\n',
          }),
        ),
      ),
    );
    await pumpLiveAgentUi(tester);

    expect(find.text('2 个文件 · +2 / -1', findRichText: true), findsOneWidget);
    expect(
      find.byKey(
        ValueKey<String>(
          'agent-file-edit-group-header-${fileEditGroupId('turn-1', 'live-edit-1')}',
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
    await pumpLiveAgentUi(tester);

    expect(find.text('1 次执行'), findsOneWidget);

    await tester.tap(
      find.byKey(
        ValueKey<String>(
          'agent-file-edit-group-header-${fileEditGroupId('turn-1', 'live-edit-1')}',
        ),
      ),
    );
    await pumpLiveAgentUi(tester);

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
    await pumpLiveAgentUi(tester);

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
    final session = MemorySessionStore();
    final provider = FakeAgentProvider(
      responseText: 'Hidden commentary with `code`',
      emitCompletedCommentary: true,
    );

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: FakeAgentProviderFactory(provider),
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

  testWidgets('renders final_answer agent messages as summary markdown cards', (
    tester,
  ) async {
    final session = MemorySessionStore();
    final provider = FakeAgentProvider(
      responseText:
          '- First markdown item\n\nInline `code` sample\n\n```dart\nvoid main() {}\n```',
    );

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: FakeAgentProviderFactory(provider),
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
      find.byKey(const ValueKey('agent-final-answer-card-message-1')),
      findsOneWidget,
    );
    expect(find.text('完成汇总'), findsOneWidget);
    expect(
      find.textContaining('First markdown item', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('void main', findRichText: true),
      findsOneWidget,
    );
    final markdownWidget = tester
        .widgetList<MarkdownWidget>(find.byType(MarkdownWidget))
        .singleWhere(
          (widget) => widget.data?.contains('First markdown item') ?? false,
        );
    expect(markdownWidget.data, isNotNull);
    expect(markdownWidget.controller, isNull);
    expect(markdownWidget.useColumn, isTrue);
    expect(markdownWidget.selectable, isTrue);
    expect(markdownWidget.padding, EdgeInsets.zero);
    expect(markdownWidget.enableCopyFullDocumentShortcut, isFalse);
    expect(markdownWidget.showCopyAllInContextMenu, isFalse);
  });

  testWidgets('does not render final-answer card for commentary-only turns', (
    tester,
  ) async {
    final session = MemorySessionStore();
    final provider = FakeAgentProvider(
      responseText: 'Only interim commentary',
      emitCompletedCommentary: true,
    );

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('agent-message-input')),
      'Talk',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('agent-send-button')));
    await tester.pumpAndSettle();

    expect(find.text('完成汇总'), findsNothing);
    expect(
      find.byKey(const ValueKey('agent-final-answer-card-message-1')),
      findsNothing,
    );
    expect(
      find.textContaining('Only interim commentary', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('renders plan messages as collapsible markdown cards', (
    tester,
  ) async {
    final session = MemorySessionStore();
    final directory = Directory.systemTemp.createTempSync('zeta_test_');
    tempDirectories.add(directory);
    final now = DateTime.now();
    final provider = FakeAgentProvider(
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
            agentThread(
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
        agentProviderFactory: FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
    await tester.runAsync(waitForIo);
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
    final planMarkdownWidget = tester.widget<MarkdownWidget>(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('agent-plan-body-turn-plan-plan'),
        ),
        matching: find.byType(MarkdownWidget),
      ),
    );
    expect(planMarkdownWidget.data, isNotNull);
    expect(planMarkdownWidget.controller, isNull);
  });

  testWidgets('renders tool calls, approval cards, and approval responses', (
    tester,
  ) async {
    final session = MemorySessionStore();
    final provider = FakeAgentProvider(emitToolAndApproval: true);

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: FakeAgentProviderFactory(provider),
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
    final dock = find.byKey(const ValueKey('agent-pending-interaction-dock'));
    final approveButton = find.byKey(
      const ValueKey('agent-permission-approve-approval-1'),
    );
    expect(dock, findsOneWidget);
    expect(find.descendant(of: dock, matching: approveButton), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('agent-message-list')),
        matching: approveButton,
      ),
      findsNothing,
    );

    await tester.tap(
      find.byKey(
        ValueKey<String>(
          'agent-command-group-header-${commandGroupId('turn-1', 'tool-tool-1')}',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey<String>('agent-command-group-item-tool-tool-1'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('agent-tool-body-tool-1')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('agent-permission-approve-approval-1')),
    );
    await tester.pump();

    expect(provider.approvedRequests, <String>['approval-1']);
    expect(dock, findsNothing);

    provider.emit(
      const AgentPermissionRequestedEvent(
        AgentPermissionRequest(
          id: 'approval-remote',
          title: 'Remote approval',
          kind: AgentPermissionKind.permissions,
          sessionId: 'thread-1',
          turnId: 'turn-1',
        ),
      ),
    );
    await tester.pump();
    expect(dock, findsOneWidget);

    provider.emit(
      const AgentPermissionResolvedEvent(
        requestId: 'approval-remote',
        threadId: 'thread-1',
      ),
    );
    await tester.pump();
    expect(dock, findsNothing);
  });

  testWidgets('cancel button interrupts an active provider turn', (
    tester,
  ) async {
    final session = MemorySessionStore();
    final provider = FakeAgentProvider(completeTurns: false);

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('agent-message-input')),
      'Keep working',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('agent-send-button')));
    await pumpLiveAgentUi(tester);

    expect(find.byKey(const ValueKey('agent-cancel-button')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('agent-cancel-button')));
    await tester.pump();

    expect(provider.cancelledTurns, <String>['turn-1']);
  });

  testWidgets('shows provider unavailable when the provider cannot start', (
    tester,
  ) async {
    final session = MemorySessionStore();
    final provider = FakeAgentProvider(unavailable: true);

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: FakeAgentProviderFactory(provider),
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
}

/// 运行中 turn 会持续播放 spinner；只推进足够渲染状态的有限帧。
Future<void> pumpLiveAgentUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

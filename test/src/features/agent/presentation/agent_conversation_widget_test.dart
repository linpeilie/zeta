// ignore_for_file: deprecated_member_use

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixin_markdown_widget/mixin_markdown_widget.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta/main.dart';
import 'package:zeta/src/features/agent/application/agent_provider_runtime_registry.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_view_model.dart';
import 'package:zeta/src/features/agent/presentation/agent_pane.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_file_change_evidence_views.dart';
import 'package:zeta/src/features/ide_session/domain/ide_session_state.dart';
import 'package:zeta/src/features/ide_session/domain/ide_workbench_layout_state.dart';
import 'package:zeta/src/ui/core/app_theme.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_motion.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';
import 'package:zeta/src/features/agent/application/agent_provider_settings_controller.dart';

import '../../../testing/ide_test_harness.dart';
import '../../../testing/agent_conversation_binding_test_harness.dart';

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

  testWidgets('starts with no welcome placeholder in the timeline', (
    tester,
  ) async {
    // Arrange
    final session = activeProjectSessionStore(tempDirectories);

    // Act
    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: FakeAgentProviderFactory(
          FakeAgentProvider(includeConversationTestThread: true),
        ),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );
    await pumpUntilAgentComposer(tester);

    // Assert
    expect(find.byKey(const ValueKey('agent-message-input')), findsOneWidget);
    expect(
      find.text(
        'Ready. Select a file or send a request to start an Agent thread.',
      ),
      findsNothing,
    );
  });

  testWidgets('shows unavailable reason for a retired Cursor selection', (
    tester,
  ) async {
    // Arrange
    final session = activeProjectSessionStore(tempDirectories);
    final provider = FakeAgentProvider(
      includeConversationTestThread: true,
      conversationThreadProviderId: cursorAgentProviderId,
    );
    final configStore = MemoryAgentProviderConfigStore(
      AgentProviderSettings(
        providers: <AgentProviderConfig>[
          AgentProviderConfig.defaultCodex,
          AgentProviderConfig.defaultGrok,
          AgentProviderConfig.defaultCursor.copyWith(enabled: true),
        ],
        activeProviderId: cursorAgentProviderId,
      ),
    );

    // Act
    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: FakeAgentProviderFactory(provider),
        agentProviderConfigStore: configStore,
      ),
    );
    await openConversationTestThread(tester);
    await tester.pumpAndSettle();

    // Assert
    final notice = find.byKey(
      const ValueKey('agent-provider-unavailable-notice'),
    );
    expect(notice, findsOneWidget);
    expect(
      find.descendant(
        of: notice,
        matching: find.text('Cursor Agent unavailable'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: notice, matching: find.textContaining('已临时回退')),
      findsOneWidget,
    );
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
    // 历史快照中的 running 不升 live、不驱动 isTurnRunning，故无 Cancel；
    // 界面也可能没有无限 spinner，但仍推进有限帧等待 thread 切换完成。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('History A'), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-cancel-button')), findsNothing);

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
    'shows Cancel for a live running turn until text is entered, then steers on Send',
    (tester) async {
      final session = MemorySessionStore();
      final directory = Directory.systemTemp.createTempSync('zeta_test_');
      tempDirectories.add(directory);
      File(
        '${directory.path}${Platform.pathSeparator}sample.txt',
      ).writeAsStringSync('hello from zeta');

      // Cancel/Steer 仅绑定本进程 live turn；历史 running 不升 live。
      final provider = FakeAgentProvider(
        completeTurns: false,
        threadHistories: <String, AgentThreadHistorySnapshot>{
          'thread-a': AgentThreadHistorySnapshot(
            threadId: 'thread-a',
            turns: const <AgentHistoryTurn>[
              AgentHistoryTurn(
                id: 'turn-a-1',
                status: AgentHistoryTurnStatus.completed,
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
      await tester.pumpAndSettle();

      // 先发一条消息进入本进程 live running，再验证 Cancel / Steer 切换。
      await tester.enterText(
        find.byKey(const ValueKey('agent-message-input')),
        'start live turn',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('agent-send-button')));
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
      expect(provider.sentMessages, <String>['start live turn']);
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

  testWidgets('composer more actions filters unsupported Grok controls', (
    tester,
  ) async {
    final session = activeProjectSessionStore(tempDirectories);
    final provider = FakeAgentProvider(
      config: AgentProviderConfig.defaultGrok,
      declaredCapabilities: AgentProviderCapabilities.grokAcp,
      includeConversationTestThread: true,
      permissionOptions: const <AgentPermissionOption>[
        AgentPermissionOption(
          id: 'ask',
          label: 'Ask',
          description: 'Ask',
          allowed: true,
        ),
        AgentPermissionOption(
          id: 'auto',
          label: 'Auto',
          description: 'Auto',
          allowed: true,
        ),
        AgentPermissionOption(
          id: 'always-approve',
          label: 'Always approve',
          description: 'Always approve',
          allowed: true,
        ),
      ],
    );
    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        directoryPicker: () async => null,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(
          const AgentProviderSettings(
            providers: <AgentProviderConfig>[AgentProviderConfig.defaultGrok],
            activeProviderId: grokAgentProviderId,
          ),
        ),
      ),
    );
    final moreActionsButton = find.byKey(
      const ValueKey('agent-more-actions-button'),
    );
    final attachImageButton = find.byKey(
      const ValueKey('agent-attach-image-button'),
    );
    final permissionPolicySelector = find.byKey(
      const ValueKey('agent-permission-option-selector'),
    );
    final mentionFileButton = find.byKey(
      const ValueKey('agent-mention-file-button'),
    );
    final planAction = find.byKey(const ValueKey('agent-more-actions-plan'));
    await openConversationTestThread(tester);
    await pumpUntilCondition(
      tester,
      () =>
          moreActionsButton.evaluate().isNotEmpty &&
          permissionPolicySelector.evaluate().isNotEmpty,
      failureMessage: 'Grok composer controls did not become ready',
    );

    // Grok 支持权限策略选择：选择器可见；catalog 为 Ask/Auto/Always approve。
    expect(permissionPolicySelector, findsOneWidget);
    await tester.tap(permissionPolicySelector);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final permissionPopover = find.byKey(
      const ValueKey('agent-permission-option-popover'),
    );
    expect(permissionPopover, findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent-permission-option-ask')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('agent-permission-option-auto')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('agent-permission-option-always-approve')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('agent-permission-option-default')),
      findsNothing,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(permissionPopover, findsNothing);

    expect(attachImageButton, findsNothing);
    expect(mentionFileButton, findsNothing);
    expect(planAction, findsNothing);

    await tester.tap(moreActionsButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const ValueKey('agent-more-actions-popover')),
      findsOneWidget,
    );
    expect(attachImageButton, findsNothing);
    expect(planAction, findsNothing);
    expect(mentionFileButton, findsOneWidget);
  });

  testWidgets(
    'Grok permission picker selects options, persists and syncs provider',
    (tester) async {
      final session = activeProjectSessionStore(tempDirectories);
      final configStore = MemoryAgentProviderConfigStore(
        AgentProviderSettings(
          providers: <AgentProviderConfig>[
            AgentProviderConfig.defaultGrok.copyWith(
              selectedPermissionOptionId: 'ask',
            ),
          ],
          activeProviderId: grokAgentProviderId,
        ),
      );
      final provider = FakeAgentProvider(
        config: AgentProviderConfig.defaultGrok.copyWith(
          selectedPermissionOptionId: 'ask',
        ),
        declaredCapabilities: AgentProviderCapabilities.grokAcp,
        includeConversationTestThread: true,
        permissionOptions: const <AgentPermissionOption>[
          AgentPermissionOption(
            id: 'ask',
            label: 'Ask',
            description: 'Ask',
            allowed: true,
          ),
          AgentPermissionOption(
            id: 'auto',
            label: 'Auto',
            description: 'Auto',
            allowed: true,
          ),
          AgentPermissionOption(
            id: 'always-approve',
            label: 'Always approve',
            description: 'Always approve',
            allowed: true,
          ),
        ],
      );

      await tester.pumpWidget(
        MainApp(
          enableNativeWindowFrame: false,
          directoryPicker: () async => null,
          sessionLoader: session.load,
          sessionSaver: session.save,
          agentProviderFactory: FakeAgentProviderFactory(provider),
          agentProviderConfigStore: configStore,
        ),
      );
      await openConversationTestThread(tester);
      final permissionSelector = find.byKey(
        const ValueKey('agent-permission-option-selector'),
      );
      await pumpUntilCondition(
        tester,
        () => permissionSelector.evaluate().isNotEmpty,
        failureMessage: 'Grok permission selector did not appear',
      );

      // 触发器短标签 Ask，无 Default。
      expect(find.text('Ask'), findsWidgets);
      expect(find.text('Default'), findsNothing);

      Future<void> selectPermission(String profileId) async {
        await tester.tap(permissionSelector);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        final item = find.byKey(
          ValueKey<String>('agent-permission-option-$profileId'),
        );
        expect(item, findsOneWidget);
        await tester.tap(item);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }

      // 打开历史尚未 beginTurn：dormant 只持久化偏好，不立刻打 session port。
      await selectPermission('always-approve');
      expect(find.text('Always approve'), findsWidgets);
      expect(provider.lastAppliedPermissionOptionId, isNull);
      expect(provider.permissionApplyCount, 0);

      var settings = await configStore.load();
      var grok = settings.providers.singleWhere(
        (p) => p.id == grokAgentProviderId,
      );
      expect(grok.selectedPermissionOptionId, 'always-approve');

      await tester.enterText(
        find.byKey(const ValueKey('agent-message-input')),
        'attach runtime',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('agent-send-button')));
      await tester.pumpAndSettle();

      final updatesBefore = provider.permissionApplyCount;
      await selectPermission('auto');
      expect(find.text('Auto'), findsWidgets);
      expect(provider.lastAppliedPermissionOptionId, 'auto');
      expect(provider.permissionApplyCount, greaterThan(updatesBefore));
      settings = await configStore.load();
      grok = settings.providers.singleWhere((p) => p.id == grokAgentProviderId);
      expect(grok.selectedPermissionOptionId, 'auto');

      // 切回 Ask：触发器短标签，runtime 已附着时同步 optionId=ask。
      await selectPermission('ask');
      expect(find.text('Ask'), findsWidgets);
      expect(provider.lastAppliedPermissionOptionId, 'ask');
      settings = await configStore.load();
      grok = settings.providers.singleWhere((p) => p.id == grokAgentProviderId);
      expect(grok.selectedPermissionOptionId, 'ask');
    },
  );

  testWidgets('renders one friendly Grok prompt error and allows retry', (
    tester,
  ) async {
    const errorMessage = 'Grok rate limit reached. Please try again later.';
    final session = activeProjectSessionStore(tempDirectories);
    final provider = FakeAgentProvider(
      config: AgentProviderConfig.defaultGrok,
      declaredCapabilities: AgentProviderCapabilities.grokAcp,
      turnErrorMessage: errorMessage,
      includeConversationTestThread: true,
    );

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(
          const AgentProviderSettings(
            providers: <AgentProviderConfig>[AgentProviderConfig.defaultGrok],
            activeProviderId: grokAgentProviderId,
          ),
        ),
      ),
    );
    await pumpUntilAgentComposer(tester);

    await tester.enterText(
      find.byKey(const ValueKey('agent-message-input')),
      'Trigger the rate limit',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('agent-send-button')));
    await tester.pumpAndSettle();

    expect(find.textContaining(errorMessage), findsOneWidget);
    expect(find.textContaining('用量或速率额度已用尽'), findsOneWidget);
    expect(find.textContaining('Agent request failed'), findsNothing);
    expect(find.textContaining('Turn failed'), findsNothing);
    expect(find.textContaining('prompt_error'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('agent-turn-footer-turn-1')),
      findsOneWidget,
    );

    await pumpUntilAgentComposer(tester);
    await tester.enterText(
      find.byKey(const ValueKey('agent-message-input')),
      'Retry manually',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('agent-send-button')));
    await tester.pumpAndSettle();
    expect(provider.sentMessages, <String>[
      'Trigger the rate limit',
      'Retry manually',
    ]);
  });

  testWidgets(
    'renders Grok Claude Code and Codex typed file evidence in one group',
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
                      id: 'history-grok-edit',
                      title: 'Replace text',
                      kind: AgentToolKind.edit,
                      status: AgentToolStatus.completed,
                      fileChanges: AgentFileChangeSnapshot(
                        revision: 1,
                        replayability: AgentFileChangeReplayability.replayable,
                        changes: const <AgentFileChange>[
                          AgentFileChange(
                            id: 'grok-replace',
                            path: 'lib/main.dart',
                            kind: AgentFileChangeKind.modified,
                            evidence: AgentTextReplacementEvidence(
                              oldText: 'old line',
                              newText: 'new line',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  AgentHistoryToolEntry(
                    toolCall: AgentToolCall(
                      id: 'history-claude-write',
                      title: 'Write file',
                      kind: AgentToolKind.edit,
                      status: AgentToolStatus.completed,
                      fileChanges: AgentFileChangeSnapshot(
                        revision: 1,
                        replayability: AgentFileChangeReplayability.replayable,
                        changes: const <AgentFileChange>[
                          AgentFileChange(
                            id: 'claude-write',
                            path: 'README.md',
                            kind: AgentFileChangeKind.modified,
                            evidence: AgentWrittenContentEvidence(
                              content: 'docs line',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  AgentHistoryToolEntry(
                    toolCall: AgentToolCall(
                      id: 'history-codex-patch',
                      title: 'Apply patch',
                      kind: AgentToolKind.edit,
                      status: AgentToolStatus.completed,
                      fileChanges: AgentFileChangeSnapshot(
                        revision: 1,
                        replayability: AgentFileChangeReplayability.replayable,
                        changes: const <AgentFileChange>[
                          AgentFileChange(
                            id: 'codex-patch',
                            path: 'CHANGELOG.md',
                            kind: AgentFileChangeKind.modified,
                            evidence: AgentUnifiedPatchEvidence(
                              patch: '@@ -0,0 +1 @@\n+release note\n',
                            ),
                          ),
                        ],
                      ),
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

      expect(find.text('3 个文件 · +2 / -1', findRichText: true), findsOneWidget);
      expect(find.text('1 次执行'), findsOneWidget);
      expect(find.text('Run tests'), findsNothing);

      await tester.tap(
        find.byKey(
          ValueKey<String>(
            'agent-file-edit-group-header-${fileEditGroupId('turn-a-1', 'history-grok-edit')}',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('lib/main.dart'), findsOneWidget);
      expect(find.text('README.md'), findsOneWidget);
      expect(find.text('CHANGELOG.md'), findsOneWidget);
      expect(find.text('Run tests'), findsNothing);

      final historyGroupSummaryFinder = find.byKey(
        ValueKey<String>(
          'agent-file-edit-group-summary-${fileEditGroupId('turn-a-1', 'history-grok-edit')}',
        ),
      );
      final historyGroupSummary = tester.widget<Text>(
        historyGroupSummaryFinder,
      );
      final historyGroupSpan = historyGroupSummary.textSpan! as TextSpan;
      expect(historyGroupSpan.toPlainText(), '3 个文件 · +2 / -1');
      final historyGroupChildren = historyGroupSpan.children!;
      expect(
        (historyGroupChildren[2] as TextSpan).style?.color,
        IdeColors.dark.success.withValues(alpha: 0.98),
      );
      expect(
        (historyGroupChildren[4] as TextSpan).style?.color,
        IdeColors.dark.error.withValues(alpha: 0.98),
      );

      final grokHeader = find.byKey(
        agentFileChangeEvidenceKey(
          'tool-history-grok-edit',
          'grok-replace',
          'header',
        ),
      );
      await tester.ensureVisible(grokHeader);
      await tester.tap(grokHeader);
      await tester.pumpAndSettle();
      expect(find.text('替换前'), findsOneWidget);
      expect(find.text('替换后'), findsOneWidget);
      expect(
        find.textContaining('old line', findRichText: true),
        findsOneWidget,
      );
      await tester.tap(grokHeader);
      await tester.pumpAndSettle();

      final claudeHeader = find.byKey(
        agentFileChangeEvidenceKey(
          'tool-history-claude-write',
          'claude-write',
          'header',
        ),
      );
      await tester.ensureVisible(claudeHeader);
      await tester.tap(claudeHeader);
      await tester.pumpAndSettle();
      expect(find.text('写入内容 · 已完成'), findsOneWidget);
      expect(
        find.textContaining('docs line', findRichText: true),
        findsOneWidget,
      );
      await tester.tap(claudeHeader);
      await tester.pumpAndSettle();

      final codexHeader = find.byKey(
        agentFileChangeEvidenceKey(
          'tool-history-codex-patch',
          'codex-patch',
          'header',
        ),
      );
      await tester.ensureVisible(codexHeader);
      await tester.tap(codexHeader);
      await tester.pumpAndSettle();
      expect(find.text('统一差异'), findsWidgets);
      expect(
        find.textContaining('+release note', findRichText: true),
        findsOneWidget,
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
                    fileChanges: AgentFileChangeSnapshot(
                      revision: 1,
                      replayability: AgentFileChangeReplayability.replayable,
                      changes: const <AgentFileChange>[
                        AgentFileChange(
                          id: 'main-change',
                          path: 'lib/main.dart',
                          kind: AgentFileChangeKind.modified,
                        ),
                      ],
                    ),
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
      agentFileChangeEvidenceKey(
        'tool-history-edit-nodetail',
        'main-change',
        'toggle',
      ),
    );
    expect(toggleFinder, findsOneWidget);

    await tester.tap(
      find.byKey(
        agentFileChangeEvidenceKey(
          'tool-history-edit-nodetail',
          'main-change',
          'header',
        ),
      ),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        agentFileChangeEvidenceKey(
          'tool-history-edit-nodetail',
          'main-change',
          'body',
        ),
      ),
      findsNothing,
    );
  });

  testWidgets(
    'updates header title when server renames a newly started thread',
    (tester) async {
      final provider = FakeAgentProvider();
      final registry = AgentProviderRuntimeRegistry(
        providerFactory: FakeAgentProviderFactory(provider),
      );
      addTearDown(registry.close);
      final controller = AgentProviderSettingsController(
        runtimeRegistry: registry,
        configStore: MemoryAgentProviderConfigStore(),
      );
      addTearDown(controller.dispose);
      final bindingHarness = AgentConversationBindingTestHarness(
        registry: registry,
        settings: controller,
      );
      addTearDown(bindingHarness.close);
      final bindingLease = bindingHarness.acquireDraft(provider.config);
      final viewModel = AgentConversationViewModel(
        providerController: controller,
        conversationBinding: bindingLease.binding,
        globalRuntime: bindingHarness.globalRuntime,
      );
      addTearDown(viewModel.dispose);
      viewModel.updateContext(projectPath: '/repo', contextFilePath: null);

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
    final registry = AgentProviderRuntimeRegistry(
      providerFactory: FakeAgentProviderFactory(provider),
    );
    addTearDown(registry.close);
    final controller = AgentProviderSettingsController(
      runtimeRegistry: registry,
      configStore: MemoryAgentProviderConfigStore(),
    );
    addTearDown(controller.dispose);
    final bindingHarness = AgentConversationBindingTestHarness(
      registry: registry,
      settings: controller,
    );
    addTearDown(bindingHarness.close);
    final thread = agentThread(
      id: 'thread-a',
      projectPath: '/repo',
      title: 'Original title',
    );
    final bindingLease = bindingHarness.acquireThread(
      config: provider.config,
      threadId: thread.id,
    );
    final viewModel = AgentConversationViewModel(
      providerController: controller,
      conversationBinding: bindingLease.binding,
      globalRuntime: bindingHarness.globalRuntime,
      initialProjectPath: '/repo',
      initialThread: thread,
    );
    addTearDown(viewModel.dispose);
    await viewModel.initialization;

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
                AgentHistoryToolEntry(
                  toolCall: AgentToolCall(
                    id: 'ctx-edit-1',
                    title: 'Replace context file',
                    kind: AgentToolKind.edit,
                    status: AgentToolStatus.completed,
                    raw: const <String, Object?>{
                      'sentinel': 'FILE_RAW_SENTINEL',
                    },
                    rawInput: const <String, Object?>{
                      'oldText': 'WIRE_OLD_SENTINEL',
                    },
                    rawOutput: const <String, Object?>{
                      'newText': 'WIRE_NEW_SENTINEL',
                    },
                    fileChanges: AgentFileChangeSnapshot(
                      revision: 4,
                      replayability: AgentFileChangeReplayability.replayable,
                      changes: const <AgentFileChange>[
                        AgentFileChange(
                          id: 'ctx-replacement',
                          path: 'lib/context.dart',
                          kind: AgentFileChangeKind.modified,
                          evidence: AgentTextReplacementEvidence(
                            oldText: 'typed before',
                            newText: 'typed after',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      },
    );
    final registry = AgentProviderRuntimeRegistry(
      providerFactory: FakeAgentProviderFactory(provider),
    );
    addTearDown(registry.close);
    final controller = AgentProviderSettingsController(
      runtimeRegistry: registry,
      configStore: MemoryAgentProviderConfigStore(),
    );
    addTearDown(controller.dispose);
    final bindingHarness = AgentConversationBindingTestHarness(
      registry: registry,
      settings: controller,
    );
    addTearDown(bindingHarness.close);
    final thread = AgentThreadSummary(
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
    );
    final bindingLease = bindingHarness.acquireThread(
      config: provider.config,
      threadId: thread.id,
    );
    final viewModel = AgentConversationViewModel(
      providerController: controller,
      conversationBinding: bindingLease.binding,
      globalRuntime: bindingHarness.globalRuntime,
      initialProjectPath: '/repo',
      initialThread: thread,
    );
    addTearDown(viewModel.dispose);
    await viewModel.initialization;

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
    // 正文支持文本选择复制。
    expect(
      find.byKey(const ValueKey('agent-context-panel-selection')),
      findsOneWidget,
    );

    // 概览信息：会话名称、会话 ID、消息数、提供商、token 与时间。
    expect(find.text('Context thread'), findsWidgets);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('agent-context-panel')),
        matching: find.text('会话 ID'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('agent-context-panel')),
        matching: find.text('thread-ctx'),
      ),
      findsOneWidget,
    );
    expect(find.text('2'), findsOneWidget);
    // 头栏 provider 切换器与上下文面板都会展示提供商名，限定在面板内断言。
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('agent-context-panel')),
        matching: find.text('Codex'),
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

    // 面板监听 typed header state，而不是完整 ViewModel ChangeNotifier。
    viewModel.syncThreadTitleIfCurrent('thread-ctx', 'Context thread renamed');
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('agent-context-panel')),
        matching: find.text('Context thread renamed'),
      ),
      findsOneWidget,
    );

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

    // 文件编辑上下文只展示 typed snapshot；raw/wire sentinel 不得回流。
    await tester.tap(find.byKey(const ValueKey('agent-context-raw-filter')));
    await tester.pumpAndSettle();
    expect(find.text('ctx-edit-1'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('agent-context-raw-ctx-edit-1')),
    );
    await tester.pumpAndSettle();
    final editContextBody = find.byKey(
      const ValueKey('agent-context-raw-body-ctx-edit-1'),
    );
    expect(editContextBody, findsOneWidget);
    expect(
      find.descendant(
        of: editContextBody,
        matching: find.textContaining('lib/context.dart', findRichText: true),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: editContextBody,
        matching: find.textContaining('typed before', findRichText: true),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: editContextBody,
        matching: find.textContaining('FILE_RAW_SENTINEL', findRichText: true),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: editContextBody,
        matching: find.textContaining('WIRE_OLD_SENTINEL', findRichText: true),
      ),
      findsNothing,
    );

    // 关闭按钮收起面板。
    await tester.tap(find.byKey(const ValueKey('agent-context-panel-close')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('agent-context-panel')), findsNothing);
  });

  testWidgets('forks the current thread from the header more menu', (
    tester,
  ) async {
    final createdAt = DateTime(2024, 1, 15, 10, 30);
    AgentSession? selectedFork;
    final provider = FakeAgentProvider(
      threadHistories: <String, AgentThreadHistorySnapshot>{
        'thread-fork': AgentThreadHistorySnapshot(
          threadId: 'thread-fork',
          turns: <AgentHistoryTurn>[
            AgentHistoryTurn(
              id: 'turn-1',
              status: AgentHistoryTurnStatus.completed,
              entries: <AgentHistoryEntry>[
                const AgentHistoryMessageEntry(
                  id: 'msg-user-fork',
                  role: AgentMessageRole.user,
                  text: 'Hello',
                ),
              ],
            ),
          ],
        ),
      },
    );
    final registry = AgentProviderRuntimeRegistry(
      providerFactory: FakeAgentProviderFactory(provider),
    );
    addTearDown(registry.close);
    final controller = AgentProviderSettingsController(
      runtimeRegistry: registry,
      configStore: MemoryAgentProviderConfigStore(),
    );
    addTearDown(controller.dispose);
    final bindingHarness = AgentConversationBindingTestHarness(
      registry: registry,
      settings: controller,
    );
    addTearDown(bindingHarness.close);
    final thread = AgentThreadSummary(
      id: 'thread-fork',
      providerId: defaultAgentProviderId,
      projectPath: '/repo',
      title: 'Fork thread',
      preview: 'Fork thread',
      sessionPath: '/repo/thread-fork.jsonl',
      createdAt: createdAt,
      updatedAt: createdAt,
      recencyAt: createdAt,
      status: AgentThreadRuntimeStatus.idle,
    );
    final bindingLease = bindingHarness.acquireThread(
      config: provider.config,
      threadId: thread.id,
    );
    final viewModel = AgentConversationViewModel(
      providerController: controller,
      conversationBinding: bindingLease.binding,
      globalRuntime: bindingHarness.globalRuntime,
      initialProjectPath: '/repo',
      initialThread: thread,
      onCreatedThread:
          ({required session, required context, String? initialMessage}) async {
            selectedFork = session;
          },
    );
    addTearDown(viewModel.dispose);
    await viewModel.initialization;

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

    // 分叉不再作为标题栏独立按钮常驻。
    expect(find.byKey(const ValueKey('agent-header-fork')), findsNothing);

    // 通过「更多」菜单进入分叉。
    await tester.tap(find.byKey(const ValueKey('agent-header-more')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 菜单顺序：上下文 → 分隔符 → 重命名 → 分叉当前会话 → 归档。
    final menuKeys = <String>[
      'agent-header-menu-context',
      'agent-header-menu-rename',
      'agent-header-menu-fork',
      'agent-header-menu-archive',
    ];
    final tops = <double>[];
    for (final key in menuKeys) {
      final finder = find.byKey(ValueKey<String>(key));
      expect(finder, findsOneWidget);
      tops.add(tester.getTopLeft(finder).dy);
    }
    for (var index = 1; index < tops.length; index += 1) {
      expect(tops[index], greaterThan(tops[index - 1]));
    }
    // 分隔符恰好一个，位于「上下文」与「重命名」之间。
    expect(find.byType(sf.MenuDivider), findsOneWidget);
    final dividerTop = tester.getTopLeft(find.byType(sf.MenuDivider)).dy;
    expect(dividerTop, greaterThan(tops[0]));
    expect(dividerTop, lessThan(tops[1]));

    final forkAction = find.byKey(const ValueKey('agent-header-menu-fork'));
    await tester.tap(forkAction);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(provider.forkedThreads, contains('thread-fork'));
    expect(selectedFork?.id, 'forked-thread-fork');
  });

  testWidgets(
    'shows session total token usage in header and context window in composer while running',
    (tester) async {
      final session = activeProjectSessionStore(tempDirectories);
      final provider = FakeAgentProvider(
        completeTurns: false,
        sessionTitle: 'Running thread',
        includeConversationTestThread: true,
        tokenUsageDuringTurn: const AgentTokenUsage(
          // 普通字段模拟 thread 累计；last* 才是当前请求快照。
          inputTokens: 10000,
          cachedInputTokens: 9000,
          outputTokens: 300,
          totalTokens: 10300,
          lastInputTokens: 1000,
          lastCachedInputTokens: 200,
          lastOutputTokens: 350,
          lastTotalTokens: 1300,
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

      await pumpUntilAgentComposer(tester);
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
        find.byKey(const ValueKey('agent-header-project-name-text')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('agent-header-running-icon')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('agent-header-token')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('agent-header-token')),
          matching: find.textContaining('%'),
        ),
        findsNothing,
      );
      // 头栏展示会话累计 totalTokens（10.3k），与上下文面板「总 Token」一致。
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('agent-header-token')),
          matching: find.text('10.3k tokens'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('agent-composer-token-usage')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('agent-compact-banner')), findsNothing);
      final progress = tester.widget<IdeBusySpinner>(
        find.byKey(const ValueKey('agent-composer-token-progress')),
      );
      expect(progress.value, closeTo(0.65, 0.001));

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
        find.descendant(
          of: find.byKey(const ValueKey('agent-live-activity-status')),
          matching: find.textContaining('tokens'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('agent-header-running-status')),
        findsNothing,
      );

      final tooltip = tester.widget<IdeTooltip>(
        find.ancestor(
          of: find.byKey(const ValueKey('agent-composer-token-usage')),
          matching: find.byType(IdeTooltip),
        ),
      );
      expect(tooltip.message, contains('Usage: 65%'));
      expect(tooltip.message, contains('Used: 1.3k'));
      expect(tooltip.message, contains('Total: 2k'));
      expect(tooltip.message, isNot(contains('input_tokens')));
      expect(tooltip.message, isNot(contains('output_tokens')));
      expect(tooltip.message, isNot(contains('cached_input_tokens')));
    },
  );

  testWidgets(
    'updates composer context progress from live occupancy snapshots',
    (tester) async {
      final session = activeProjectSessionStore(tempDirectories);
      final provider = FakeAgentProvider(
        completeTurns: false,
        sessionTitle: 'Live context thread',
        includeConversationTestThread: true,
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

      await pumpUntilAgentComposer(tester);
      await tester.enterText(
        find.byKey(const ValueKey('agent-message-input')),
        'Track live context',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('agent-send-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.byKey(const ValueKey('agent-composer-token-progress')),
        findsNothing,
      );

      provider.emit(
        const AgentContextWindowUsageEvent(
          sessionId: 'thread-1',
          turnId: 'turn-1',
          usedTokens: 500,
          modelContextWindow: 2000,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      var progress = tester.widget<IdeBusySpinner>(
        find.byKey(const ValueKey('agent-composer-token-progress')),
      );
      expect(progress.value, closeTo(0.25, 0.001));
      expect(find.byKey(const ValueKey('agent-header-token')), findsNothing);

      provider.emit(
        const AgentContextWindowUsageEvent(
          sessionId: 'thread-1',
          turnId: 'turn-1',
          usedTokens: 1000,
          modelContextWindow: 2000,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      progress = tester.widget<IdeBusySpinner>(
        find.byKey(const ValueKey('agent-composer-token-progress')),
      );
      expect(progress.value, closeTo(0.5, 0.001));
      expect(find.byKey(const ValueKey('agent-header-token')), findsNothing);
    },
  );

  testWidgets(
    'keeps running feedback in the project thread list for an active thread',
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
      final projectName = directory.path.replaceAll('\\', '/').split('/').last;
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('agent-header-project-name-text')),
            )
            .data,
        projectName,
      );
      expect(
        find.byKey(const ValueKey('agent-composer-running-glow')),
        findsNothing,
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

      final listRunning = find.byKey(
        ValueKey<String>(
          'project-thread-running-icon-${directory.path}-thread-a',
        ),
      );
      expect(listRunning, findsOneWidget);
      expect(
        find.byKey(const ValueKey('agent-composer-running-glow')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: listRunning,
          matching: find.byType(sf.CircularProgressIndicator),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('agent-cancel-button')));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('agent-header-running-icon')),
        findsNothing,
      );
      expect(listRunning, findsNothing);
      expect(
        find.byKey(const ValueKey('agent-composer-running-glow')),
        findsNothing,
      );
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

    final session = activeProjectSessionStore(tempDirectories);
    final provider = FakeAgentProvider(
      completeTurns: false,
      sessionTitle: 'Long running thread title for narrow layout',
      includeConversationTestThread: true,
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

    await pumpUntilAgentComposer(tester);
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
    final controller = tester.widget<ScrollView>(listFinder).controller!;
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
    final controller = tester.widget<ScrollView>(listFinder).controller!;
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
    final session = activeProjectSessionStore(tempDirectories);
    final provider = FakeAgentProvider(includeConversationTestThread: true);

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await pumpUntilAgentComposer(tester);
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
    final session = activeProjectSessionStore(tempDirectories);
    final provider = FakeAgentProvider(includeConversationTestThread: true);

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await pumpUntilAgentComposer(tester);
    await tester.enterText(
      find.byKey(const ValueKey('agent-message-input')),
      'Copy this user message',
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('agent-send-button')));
    await tester.pumpAndSettle();

    // 用户消息走与 Agent 相同的 Markdown 渲染管线，可复制语义由 selectable 保留。
    expect(
      find.descendant(
        of: find.byType(MarkdownWidget),
        matching: find.text('Copy this user message', findRichText: true),
      ),
      findsOneWidget,
    );
  });

  testWidgets('renders user message markdown with the bubble theme', (
    tester,
  ) async {
    final session = activeProjectSessionStore(tempDirectories);
    final provider = FakeAgentProvider(includeConversationTestThread: true);

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: FakeAgentProviderFactory(provider),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await pumpUntilAgentComposer(tester);
    await tester.enterText(
      find.byKey(const ValueKey('agent-message-input')),
      '**bold**\n\n```\ncode line\n```',
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('agent-send-button')));
    await tester.pumpAndSettle();

    // 原始 markdown 语法不应出现在 Markdown 渲染子树中（头栏标题为纯文本，已排除）。
    expect(
      find.descendant(
        of: find.byType(MarkdownWidget),
        matching: find.text('**bold**', findRichText: true),
      ),
      findsNothing,
    );
    // 解析后的加粗文本与代码块内容应当可见。
    expect(
      find.descendant(
        of: find.byType(MarkdownWidget),
        matching: find.textContaining('bold', findRichText: true),
      ),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: find.byType(MarkdownWidget),
        matching: find.textContaining('code line', findRichText: true),
      ),
      findsWidgets,
    );
  });

  testWidgets('keeps manual scroll position during live agent streaming', (
    tester,
  ) async {
    final session = activeProjectSessionStore(tempDirectories);
    final provider = FakeAgentProvider(
      completeTurns: false,
      includeConversationTestThread: true,
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

    await pumpUntilAgentComposer(tester);
    await tester.enterText(
      find.byKey(const ValueKey('agent-message-input')),
      'Keep streaming',
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('agent-send-button')));
    await pumpLiveAgentUi(tester);

    final listFinder = find.byKey(const ValueKey('agent-message-list'));
    final controller = tester.widget<ScrollView>(listFinder).controller!;
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

  testWidgets('hides reasoning data while preserving live thinking status', (
    tester,
  ) async {
    final session = activeProjectSessionStore(tempDirectories);
    final provider = FakeAgentProvider(
      completeTurns: false,
      includeConversationTestThread: true,
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
    await pumpUntilAgentComposer(tester);
    await tester.enterText(
      find.byKey(const ValueKey('agent-message-input')),
      'Check normalized order',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('agent-send-button')));
    await pumpLiveAgentUi(tester);

    provider
      ..emit(
        const AgentMessageDeltaEvent(
          messageId: 'message-seg1',
          sourceMessageId: 'provider-message-a',
          delta: 'Before tool',
          role: AgentMessageRole.agent,
          sessionId: 'thread-1',
          turnId: 'turn-1',
        ),
      )
      ..emit(
        const AgentToolCallEvent(
          AgentToolCall(
            id: 'tool-read',
            title: 'Read file',
            kind: AgentToolKind.read,
            status: AgentToolStatus.pending,
            sessionId: 'thread-1',
            turnId: 'turn-1',
          ),
        ),
      )
      ..emit(
        const AgentMessageDeltaEvent(
          messageId: 'message-seg2',
          sourceMessageId: 'provider-message-a',
          delta: 'After tool',
          role: AgentMessageRole.agent,
          sessionId: 'thread-1',
          turnId: 'turn-1',
        ),
      )
      ..emit(
        const AgentReasoningDeltaEvent(
          itemId: 'reasoning-phase1',
          sourceItemId: 'provider-reasoning-a',
          kind: AgentReasoningDeltaKind.text,
          delta: 'Think before run',
          sessionId: 'thread-1',
          turnId: 'turn-1',
        ),
      )
      ..emit(
        const AgentToolCallEvent(
          AgentToolCall(
            id: 'tool-run',
            title: 'Run tests',
            kind: AgentToolKind.execute,
            status: AgentToolStatus.pending,
            sessionId: 'thread-1',
            turnId: 'turn-1',
          ),
        ),
      )
      ..emit(
        const AgentReasoningDeltaEvent(
          itemId: 'reasoning-phase2',
          sourceItemId: 'provider-reasoning-a',
          kind: AgentReasoningDeltaKind.text,
          delta: 'Think after run',
          sessionId: 'thread-1',
          turnId: 'turn-1',
        ),
      );
    await pumpLiveAgentUi(tester);

    final message1 = find.byKey(
      const ValueKey<String>('turn-block-turn-1-message-message-seg1'),
    );
    final toolGroup = find.byKey(
      const ValueKey<String>(
        'turn-block-turn-1-command-group-turn-1-tool-tool-read',
      ),
    );
    final message2 = find.byKey(
      const ValueKey<String>('turn-block-turn-1-message-message-seg2'),
    );
    expect(message1, findsOneWidget);
    expect(toolGroup, findsOneWidget);
    expect(message2, findsOneWidget);
    expect(
      tester.getTopLeft(message1).dy,
      lessThan(tester.getTopLeft(toolGroup).dy),
    );
    expect(
      tester.getTopLeft(toolGroup).dy,
      lessThan(tester.getTopLeft(message2).dy),
    );

    const reasoningGroupId = 'command-group-turn-1-tool-reasoning-phase1';
    expect(
      find.byKey(const ValueKey<String>('turn-block-turn-1-$reasoningGroupId')),
      findsNothing,
    );
    expect(find.text('Think before run'), findsNothing);
    expect(find.text('Think after run'), findsNothing);
    final runToolGroup = find.byKey(
      const ValueKey<String>(
        'turn-block-turn-1-command-group-turn-1-tool-tool-run',
      ),
    );
    expect(runToolGroup, findsOneWidget);
    final activityStatus = find.byKey(
      const ValueKey<String>('agent-live-activity-status'),
    );
    expect(activityStatus, findsOneWidget);
    expect(
      find.descendant(of: activityStatus, matching: find.textContaining('思考中')),
      findsOneWidget,
    );

    provider.emit(
      const AgentTurnCompletedEvent(sessionId: 'thread-1', turnId: 'turn-1'),
    );
    await pumpLiveAgentUi(tester);

    expect(activityStatus, findsNothing);
    expect(find.text('Think before run'), findsNothing);
    expect(find.text('Think after run'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('turn-block-turn-1-$reasoningGroupId')),
      findsNothing,
    );
  });

  testWidgets('merges live tool calls into a single command group', (
    tester,
  ) async {
    final session = activeProjectSessionStore(tempDirectories);
    final provider = FakeAgentProvider(
      completeTurns: false,
      includeConversationTestThread: true,
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

    await pumpUntilAgentComposer(tester);
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
    final session = activeProjectSessionStore(tempDirectories);
    final provider = FakeAgentProvider(
      completeTurns: false,
      includeConversationTestThread: true,
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

    await pumpUntilAgentComposer(tester);
    await tester.enterText(
      find.byKey(const ValueKey('agent-message-input')),
      'Apply a patch',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('agent-send-button')));
    await pumpLiveAgentUi(tester);

    provider.emit(
      AgentToolCallEvent(
        AgentToolCall(
          id: 'live-edit-1',
          title: 'Apply patch',
          kind: AgentToolKind.edit,
          status: AgentToolStatus.inProgress,
          fileChanges: AgentFileChangeSnapshot(
            revision: 1,
            replayability: AgentFileChangeReplayability.replayable,
            changes: const <AgentFileChange>[
              AgentFileChange(
                id: 'main-change',
                path: 'lib/main.dart',
                kind: AgentFileChangeKind.modified,
              ),
              AgentFileChange(
                id: 'readme-change',
                path: 'README.md',
                kind: AgentFileChangeKind.modified,
              ),
            ],
          ),
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
          fileChanges: AgentFileChangeSnapshot(
            revision: 2,
            replayability: AgentFileChangeReplayability.replayable,
            changes: const <AgentFileChange>[
              AgentFileChange(
                id: 'main-change',
                path: 'lib/main.dart',
                kind: AgentFileChangeKind.modified,
                evidence: AgentUnifiedPatchEvidence(
                  patch: '@@ -1 +1 @@\n-old line\n+new line\n',
                ),
              ),
              AgentFileChange(
                id: 'readme-change',
                path: 'README.md',
                kind: AgentFileChangeKind.modified,
                evidence: AgentUnifiedPatchEvidence(
                  patch: '@@ -0,0 +1 @@\n+docs line\n',
                ),
              ),
            ],
          ),
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

    expect(find.text('lib/main.dart'), findsOneWidget);
    expect(find.text('README.md'), findsOneWidget);

    await tester.tap(
      find.byKey(
        agentFileChangeEvidenceKey('tool-live-edit-1', 'main-change', 'header'),
      ),
    );
    await pumpLiveAgentUi(tester);

    expect(
      find.byKey(
        agentFileChangeEvidenceKey('tool-live-edit-1', 'main-change', 'body'),
      ),
      findsOneWidget,
    );
    final liveDetailsFinder = find.byKey(
      agentFileChangeEvidenceKey('tool-live-edit-1', 'main-change', 'body'),
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
    final session = activeProjectSessionStore(tempDirectories);
    final provider = FakeAgentProvider(
      responseText: 'Hidden commentary with `code`',
      emitCompletedCommentary: true,
      includeConversationTestThread: true,
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

    await pumpUntilAgentComposer(tester);
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
    final session = activeProjectSessionStore(tempDirectories);
    final provider = FakeAgentProvider(
      responseText:
          '- First markdown item\n\nInline `code` sample\n\n```dart\nvoid main() {}\n```',
      includeConversationTestThread: true,
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

    await pumpUntilAgentComposer(tester);
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
          (widget) =>
              widget.controller?.data.contains('First markdown item') ?? false,
        );
    expect(markdownWidget.data, isNull);
    expect(markdownWidget.controller, isNotNull);
    expect(markdownWidget.useColumn, isTrue);
    expect(markdownWidget.selectable, isTrue);
    expect(markdownWidget.padding, EdgeInsets.zero);
    expect(markdownWidget.enableCopyFullDocumentShortcut, isFalse);
    expect(markdownWidget.showCopyAllInContextMenu, isFalse);
    expect(markdownWidget.contextMenuBuilder, isNotNull);
  });

  testWidgets('does not render final-answer card for commentary-only turns', (
    tester,
  ) async {
    final session = activeProjectSessionStore(tempDirectories);
    final provider = FakeAgentProvider(
      responseText: 'Only interim commentary',
      emitCompletedCommentary: true,
      includeConversationTestThread: true,
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

    await pumpUntilAgentComposer(tester);
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

  testWidgets(
    'shows a responsive active plan above the composer and preserves expansion',
    (tester) async {
      const longPlanStep =
          'Build the compact floating plan panel and verify its overflow tooltip';
      final session = activeProjectSessionStore(tempDirectories);
      final provider = FakeAgentProvider(
        completeTurns: false,
        includeConversationTestThread: true,
        responseText: List<String>.generate(
          80,
          (index) => 'Scrollable response line $index',
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
      await pumpUntilAgentComposer(tester);
      await tester.enterText(
        find.byKey(const ValueKey('agent-message-input')),
        'Run a multi-step task',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('agent-send-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      provider.emit(
        const AgentPlanUpdatedEvent(
          entries: <AgentPlanEntry>[
            AgentPlanEntry(content: 'Only step', status: 'inProgress'),
          ],
          sessionId: 'thread-1',
          turnId: 'turn-1',
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('agent-active-plan-card-turn-1')),
        findsNothing,
      );

      final entries = <AgentPlanEntry>[
        const AgentPlanEntry(content: 'Inspect code', status: 'pending'),
        const AgentPlanEntry(content: longPlanStep, status: 'inProgress'),
        for (var index = 3; index <= 12; index += 1)
          AgentPlanEntry(content: 'Pending step $index', status: 'pending'),
      ];
      provider.emit(
        AgentPlanUpdatedEvent(
          entries: entries,
          sessionId: 'thread-1',
          turnId: 'turn-1',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final card = find.byKey(
        const ValueKey<String>('agent-active-plan-card-turn-1'),
      );
      final summary = find.byKey(
        const ValueKey<String>('agent-active-plan-summary-turn-1'),
      );
      final body = find.byKey(
        const ValueKey<String>('agent-active-plan-body-turn-1'),
      );
      final progress = find.byKey(
        const ValueKey<String>('agent-active-plan-progress-turn-1'),
      );
      expect(card, findsOneWidget);
      expect(summary, findsOneWidget);
      expect(body, findsNothing);
      // 实时步骤进度与当前活动信息不等价，两者应同时展示。
      expect(
        find.byKey(const ValueKey('agent-live-activity-status')),
        findsOneWidget,
      );
      final planSurface = tester.widget<PanelCard>(
        find.descendant(of: card, matching: find.byType(PanelCard)),
      );
      expect(planSurface.color!.a, closeTo(0.8, 0.001));
      final floatingPanel = find.byKey(
        const ValueKey('agent-floating-panel-position'),
      );
      final footer = find.byKey(const ValueKey('agent-conversation-footer'));
      expect(
        tester.getRect(card).bottom,
        closeTo(tester.getRect(floatingPanel).bottom, 0.5),
      );
      expect(
        tester.getRect(card).bottom,
        closeTo(tester.getRect(footer).top, 0.5),
      );
      expect(
        find.descendant(of: progress, matching: find.text('2/12')),
        findsOneWidget,
      );
      final summaryText = find.descendant(
        of: summary,
        matching: find.text(longPlanStep),
      );
      final summaryTooltip = find.ancestor(
        of: summaryText,
        matching: find.byType(IdeTooltip),
      );
      expect(tester.widget<IdeTooltip>(summaryTooltip).enabled, isTrue);
      expect(tester.getSize(card).width, lessThanOrEqualTo(340));
      expect(
        tester.getCenter(card).dx,
        closeTo(
          tester
              .getCenter(
                find.byKey(const ValueKey('agent-composer-focus-ring')),
              )
              .dx,
          0.5,
        ),
      );

      final messageList = find.byKey(const ValueKey('agent-message-list'));
      final timelineController = tester
          .widget<ScrollView>(messageList)
          .controller!;
      expect(timelineController.position.maxScrollExtent, greaterThan(100));
      // 浮层叠在时间线之上：viewport 仍铺到 footer，两侧可透出对话流。
      expect(
        tester.getRect(messageList).bottom,
        closeTo(tester.getRect(footer).top, 0.5),
      );
      final cardRect = tester.getRect(card);
      final sidePoint = Offset(cardRect.left - 12, cardRect.center.dy);
      expect(tester.getRect(messageList).contains(sidePoint), isTrue);
      // 滚动内容底部 inset ≈ 浮层高度，滑到底时末项可停在浮层上方。
      await tester.pump(); // 等待 extent reporter microtask
      await tester.pump();
      final collapsedMaxExtent = timelineController.position.maxScrollExtent;
      final panelHeight = tester.getSize(floatingPanel).height;
      expect(panelHeight, greaterThan(0));
      timelineController.jumpTo(timelineController.position.maxScrollExtent);
      await tester.pump();
      // inset 生效后，内容可滚动越过浮层顶部一段距离。
      expect(
        timelineController.position.maxScrollExtent,
        greaterThanOrEqualTo(panelHeight * 0.5),
      );
      timelineController.jumpTo(0);
      await tester.pump();
      await tester.dragFrom(sidePoint, const Offset(0, -120));
      await tester.pump();
      expect(timelineController.offset, greaterThan(0));

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(summaryText));
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        find.descendant(
          of: find.byType(sf.TooltipContainer),
          matching: find.text(longPlanStep),
        ),
        findsOneWidget,
      );
      await mouse.moveTo(Offset.zero);
      await tester.pump();

      await tester.tap(
        find.byKey(const ValueKey<String>('agent-active-plan-toggle-turn-1')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final scroll = find.byKey(
        const ValueKey<String>('agent-active-plan-scroll-turn-1'),
      );
      expect(summary, findsNothing);
      expect(body, findsOneWidget);
      expect(scroll, findsOneWidget);
      expect(tester.getSize(scroll).height, lessThanOrEqualTo(200));
      // 展开后浮层变高，底部滚动 inset 随之增大；viewport 仍铺满。
      await tester.pump();
      await tester.pump();
      expect(
        tester.getRect(messageList).bottom,
        closeTo(tester.getRect(footer).top, 0.5),
      );
      expect(
        timelineController.position.maxScrollExtent,
        greaterThan(collapsedMaxExtent),
      );
      expect(find.bySemanticsLabel('已完成：Inspect code'), findsOneWidget);
      expect(find.bySemanticsLabel('进行中：$longPlanStep'), findsOneWidget);
      final shortStepText = find.descendant(
        of: body,
        matching: find.text('Inspect code'),
      );
      final shortStepTooltip = find.ancestor(
        of: shortStepText,
        matching: find.byType(IdeTooltip),
      );
      expect(tester.widget<IdeTooltip>(shortStepTooltip).enabled, isFalse);
      final longStepText = find.descendant(
        of: body,
        matching: find.text(longPlanStep),
      );
      final longStepTooltip = find.ancestor(
        of: longStepText,
        matching: find.byType(IdeTooltip),
      );
      expect(tester.widget<IdeTooltip>(longStepTooltip).enabled, isTrue);
      await mouse.moveTo(tester.getCenter(longStepText));
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        find.descendant(
          of: find.byType(sf.TooltipContainer),
          matching: find.text(longPlanStep),
        ),
        findsOneWidget,
      );
      await mouse.moveTo(Offset.zero);
      await tester.pump();

      await tester.binding.setSurfaceSize(const Size(460, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.getSize(card).width, lessThanOrEqualTo(340));
      expect(tester.takeException(), isNull);

      provider.emit(
        const AgentPermissionRequestedEvent(
          AgentPermissionRequest(
            id: 'plan-blocker',
            title: 'Approve task',
            kind: AgentPermissionKind.commandExecution,
            sessionId: 'thread-1',
            turnId: 'turn-1',
          ),
        ),
      );
      await tester.pump();
      expect(card, findsNothing);

      provider.emit(
        const AgentPermissionResolvedEvent(
          requestId: 'plan-blocker',
          threadId: 'thread-1',
        ),
      );
      await tester.pump();
      expect(card, findsOneWidget);
      expect(body, findsOneWidget);

      provider.emit(
        AgentPlanUpdatedEvent(
          entries: <AgentPlanEntry>[
            for (final entry in entries)
              AgentPlanEntry(content: entry.content, status: 'completed'),
          ],
          sessionId: 'thread-1',
          turnId: 'turn-1',
        ),
      );
      await tester.pump();
      expect(
        find.descendant(of: progress, matching: find.text('12/12')),
        findsOneWidget,
      );
      expect(card, findsOneWidget);

      provider.emit(
        const AgentTurnCompletedEvent(sessionId: 'thread-1', turnId: 'turn-1'),
      );
      await tester.pump();
      expect(card, findsNothing);
    },
  );

  testWidgets(
    'keeps Plan output and request_user_input usable in a narrow viewport',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(460, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final session = activeProjectSessionStore(
        tempDirectories,
        leftSidebarVisible: false,
      );
      final provider = _ModeCapableFakeAgentProvider(completeTurns: false);

      await tester.pumpWidget(
        MainApp(
          enableNativeWindowFrame: false,
          sessionLoader: session.load,
          sessionSaver: session.save,
          agentProviderFactory: FakeAgentProviderFactory(provider),
          agentProviderConfigStore: MemoryAgentProviderConfigStore(),
        ),
      );
      await pumpUntilAgentComposer(tester);
      final moreActionsButton = find.byKey(
        const ValueKey<String>('agent-more-actions-button'),
      );
      await pumpUntilCondition(
        tester,
        () => moreActionsButton.evaluate().isNotEmpty,
        failureMessage: 'Composer more-actions button did not become ready',
      );

      await tester.tap(moreActionsButton);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(
        find.byKey(const ValueKey<String>('agent-more-actions-plan')),
      );
      await pumpUntilCondition(
        tester,
        () => find
            .byKey(const ValueKey<String>('agent-composer-plan-badge'))
            .evaluate()
            .isNotEmpty,
        failureMessage: 'Plan badge did not appear after selecting Plan',
      );
      expect(
        find.byKey(const ValueKey<String>('agent-composer-plan-badge')),
        findsOneWidget,
      );
      // Binding：先 send 附着 live Pipeline，再注入 plan 事件。
      await tester.enterText(
        find.byKey(const ValueKey('agent-message-input')),
        'draft a plan',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('agent-send-button')));
      await pumpLiveAgentUi(tester);

      provider
        ..emit(
          const AgentMessageDeltaEvent(
            messageId: 'plan-live',
            delta: '# Live plan\n',
            role: AgentMessageRole.agent,
            kind: AgentMessageKind.plan,
            sessionId: 'thread-1',
            turnId: 'turn-1',
          ),
        )
        ..emit(
          const AgentMessageDeltaEvent(
            messageId: 'plan-live',
            delta: '\n- Inspect\n- Implement',
            role: AgentMessageRole.agent,
            kind: AgentMessageKind.plan,
            sessionId: 'thread-1',
            turnId: 'turn-1',
          ),
        )
        ..emit(
          const AgentPlanUpdatedEvent(
            entries: <AgentPlanEntry>[
              AgentPlanEntry(content: 'Inspect', status: 'completed'),
              AgentPlanEntry(content: 'Implement', status: 'inProgress'),
            ],
            sessionId: 'thread-1',
            turnId: 'turn-1',
          ),
        );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byKey(const ValueKey<String>('agent-plan-card-plan-live')),
        findsOneWidget,
      );
      expect(find.text('Live plan'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('agent-active-plan-card-turn-1')),
        findsOneWidget,
      );

      provider.emit(
        const AgentQuestionRequestedEvent(
          AgentQuestionRequest(
            id: 'question-live',
            title: 'Choose scope',
            sessionId: 'thread-1',
            turnId: 'turn-1',
            questions: <AgentUserInputQaPair>[
              AgentUserInputQaPair(
                questionId: 'scope',
                question: 'Select scopes',
                allowMultiple: true,
                optionItems: <AgentUserInputOption>[
                  AgentUserInputOption(id: 'source', label: 'Source code'),
                  AgentUserInputOption(id: 'tests', label: 'Tests'),
                ],
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('agent-message-input')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(
          const ValueKey<String>('agent-question-question-live-scope-source'),
        ),
      );
      await tester.tap(
        find.byKey(
          const ValueKey<String>('agent-question-question-live-scope-tests'),
        ),
      );
      await tester.pump(IdeMotion.durationFast);
      await tester.tap(
        find.byKey(
          const ValueKey<String>('agent-question-submit-question-live-scope'),
        ),
      );
      await tester.pump();

      expect(provider.questionResponses, hasLength(1));
      expect(provider.questionResponses.single.answers['scope'], <String>[
        'source',
        'tests',
      ]);
      expect(provider.permissionDecisions, isEmpty);
      expect(
        find.byKey(const ValueKey<String>('agent-message-input')),
        findsOneWidget,
      );

      provider.emit(
        const AgentMessageUpdatedEvent(
          messageId: 'plan-live',
          kind: AgentMessageKind.plan,
          text: '# Final plan\n\n- Inspect\n- Implement\n- Verify',
          role: AgentMessageRole.agent,
          status: AgentMessageStatus.completed,
          sessionId: 'thread-1',
          turnId: 'turn-1',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Final plan'), findsOneWidget);
      expect(find.text('Live plan'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

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
                  kind: AgentMessageKind.plan,
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
    expect(planMarkdownWidget.data, isNull);
    expect(planMarkdownWidget.controller, isNotNull);
  });

  testWidgets('renders tool calls, approval cards, and approval responses', (
    tester,
  ) async {
    final session = activeProjectSessionStore(tempDirectories);
    final provider = FakeAgentProvider(
      emitToolAndApproval: true,
      includeConversationTestThread: true,
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

    await pumpUntilAgentComposer(tester);
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
    final session = activeProjectSessionStore(tempDirectories);
    final provider = FakeAgentProvider(
      completeTurns: false,
      includeConversationTestThread: true,
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

    await pumpUntilAgentComposer(tester);
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
    // globalRuntime 在 listThreads 前会 initialize；不可用时无法从远端拉列表。
    // 用会话缓存露出 thread，打开历史时同样会 initialize 并展示错误。
    final directory = Directory.systemTemp.createTempSync(
      'zeta_agent_conversation_project_',
    );
    tempDirectories.add(directory);
    final now = DateTime.fromMillisecondsSinceEpoch(1, isUtc: true);
    final session = MemorySessionStore(
      IdeSessionState(
        projectPaths: <String>[directory.path],
        activeProjectPath: directory.path,
        projectThreadExpansionByProject: <String, bool>{directory.path: false},
        projectHomeActive: true,
        cachedThreadsByProject: <String, List<AgentThreadSummary>>{
          directory.path: <AgentThreadSummary>[
            AgentThreadSummary(
              id: conversationTestThreadId,
              providerId: defaultAgentProviderId,
              projectPath: directory.path,
              title: 'Conversation test thread',
              sessionPath: '$directory/$conversationTestThreadId.jsonl',
              preview: 'Conversation test thread',
              createdAt: now,
              updatedAt: now,
              recencyAt: now,
              status: AgentThreadRuntimeStatus.idle,
            ),
          ],
        },
      ).encode(),
    );
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

    await openConversationTestThread(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining('codex missing'), findsWidgets);
  });
}

MemorySessionStore activeProjectSessionStore(
  List<Directory> tempDirectories, {
  bool leftSidebarVisible = true,
}) {
  final directory = Directory.systemTemp.createTempSync(
    'zeta_agent_conversation_project_',
  );
  tempDirectories.add(directory);
  return MemorySessionStore(
    IdeSessionState(
      projectPaths: <String>[directory.path],
      activeProjectPath: directory.path,
      projectThreadExpansionByProject: <String, bool>{directory.path: false},
      projectHomeActive: true,
      workbenchLayout: IdeWorkbenchLayoutState(
        leftSidebarVisible: leftSidebarVisible,
      ),
    ).encode(),
  );
}

Future<void> openConversationTestThread(WidgetTester tester) async {
  final thread = find.byKey(
    const ValueKey<String>('project-home-thread-$conversationTestThreadId'),
  );
  await pumpUntilCondition(
    tester,
    () => thread.hitTestable().evaluate().isNotEmpty,
    failureMessage: 'Conversation test thread did not become ready',
  );
  await tester.tap(thread);
  await tester.pump();
}

Future<void> pumpUntilAgentComposer(WidgetTester tester) async {
  final input = find.byKey(const ValueKey<String>('agent-message-input'));
  if (input.hitTestable().evaluate().isEmpty) {
    // 恢复后按产品行为先停留在项目首页，测试需显式打开列表会话。
    await openConversationTestThread(tester);
  }
  await pumpUntilCondition(
    tester,
    () => input.hitTestable().evaluate().isNotEmpty,
    failureMessage: 'Agent composer did not become ready',
  );
}

/// 运行中 turn 会持续播放 spinner；只推进足够渲染状态的有限帧。
Future<void> pumpLiveAgentUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

class _ModeCapableFakeAgentProvider extends FakeAgentProvider
    implements AgentConversationModeCatalogProvider {
  _ModeCapableFakeAgentProvider({required super.completeTurns})
    : super(
        includeConversationTestThread: true,
        declaredCapabilities: AgentProviderCapabilities.codexAppServer.copyWith(
          supportsModeSelection: true,
        ),
      );

  @override
  Future<AgentModelList> listModels({
    int limit = 20,
    bool includeHidden = false,
  }) async {
    return const AgentModelList(
      models: <AgentModelInfo>[
        AgentModelInfo(
          id: 'gpt-5.6',
          model: 'gpt-5.6',
          displayName: 'GPT-5.6',
          supportedReasoningEfforts: <AgentModelReasoningEffort>[
            AgentModelReasoningEffort(effort: 'medium'),
            AgentModelReasoningEffort(effort: 'high'),
          ],
          defaultReasoningEffort: 'high',
          isDefault: true,
        ),
      ],
    );
  }

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

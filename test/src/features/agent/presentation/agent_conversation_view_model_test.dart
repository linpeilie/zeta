import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/ui/features/ide/view_models/active_agent_provider_controller.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_view_model.dart';

void main() {
  group('AgentConversationViewModel', () {
    test('uses New thread as the default header title', () {
      final viewModel = _createViewModel(_FakeAgentProvider());
      addTearDown(viewModel.dispose);

      expect(
        viewModel.currentThreadTitle,
        AgentConversationViewModel.defaultThreadTitle,
      );
      expect(viewModel.currentTurnTokenUsage, isNull);
      expect(viewModel.currentThreadTokenUsage, isNull);
    });

    test('loads history for a selected thread without resuming', () async {
      final provider = _FakeAgentProvider(
        historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
          'thread-1': _historySnapshot(
            threadId: 'thread-1',
            userText: 'What changed?',
            agentText: 'The provider layer changed.',
          ),
        },
      );
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.switchThread(_thread());

      expect(provider.calls, <String>['read:thread-1']);
      expect(provider.readSessionPaths, <String>['/repo/thread-1.jsonl']);
      expect(viewModel.status.state, AgentProviderConnectionState.ready);
      expect(viewModel.threadOpenPhase, AgentThreadOpenPhase.idle);
      expect(viewModel.isTurnRunning, isFalse);
      expect(viewModel.canSubmitMessage, isTrue);
      expect(
        viewModel.timelineEntries.whereType<AgentMessageTimelineEntry>().map(
          (entry) => entry.message.text,
        ),
        containsAll(<String>['What changed?', 'The provider layer changed.']),
      );
      expect(
        viewModel.timelineEntries
            .whereType<AgentToolTimelineEntry>()
            .single
            .toolCall
            .title,
        'Run tests',
      );
      expect(
        viewModel.timelineEntries
            .whereType<AgentHistoryEventTimelineEntry>()
            .single
            .event
            .title,
        'Tool search',
      );
      expect(viewModel.currentThreadTitle, 'Thread one');
    });

    test(
      'uses provider session title after resuming a selected thread',
      () async {
        final provider = _FakeAgentProvider(
          resumeSessionTitle: 'Resolved title',
        );
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.switchThread(_thread());
        await viewModel.sendMessage('hello');

        expect(provider.calls, <String>[
          'read:thread-1',
          'resume:thread-1',
          'send:thread-1',
        ]);
        expect(viewModel.currentThreadTitle, 'Resolved title');
      },
    );

    test('uses provider session title after starting a new thread', () async {
      final provider = _FakeAgentProvider(startSessionTitle: 'Started title');
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.sendMessage('hello');

      expect(viewModel.currentThreadTitle, 'Started title');
      expect(provider.calls, contains('start'));
    });

    test('resets header title after project switch', () async {
      final provider = _FakeAgentProvider();
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.switchThread(_thread());
      await Future<void>.delayed(Duration.zero);
      viewModel.updateWorkspace(
        projectPath: '/other-repo',
        contextFilePath: null,
      );

      expect(
        viewModel.currentThreadTitle,
        AgentConversationViewModel.defaultThreadTitle,
      );
    });

    test('does not resume when history loading fails', () async {
      final provider = _FakeAgentProvider(failHistory: true);
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.switchThread(_thread());

      expect(provider.calls, <String>['read:thread-1']);
      expect(viewModel.status.state, AgentProviderConnectionState.error);
      expect(viewModel.status.message, 'Could not load thread history');
      expect(viewModel.threadOpenPhase, AgentThreadOpenPhase.openFailed);
      final texts = viewModel.timelineEntries
          .whereType<AgentMessageTimelineEntry>()
          .map((entry) => entry.message.text)
          .toList();
      expect(
        texts.any((text) => text.contains('Could not load thread history')),
        isTrue,
      );
      expect(viewModel.canSubmitMessage, isFalse);
    });

    test('keeps loaded history when first resume fails', () async {
      final provider = _FakeAgentProvider(
        failResume: true,
        historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
          'thread-1': const AgentThreadHistorySnapshot(
            threadId: 'thread-1',
            turns: <AgentHistoryTurn>[
              AgentHistoryTurn(
                id: 'turn-1',
                entries: <AgentHistoryEntry>[
                  AgentHistoryMessageEntry(
                    id: 'user-1',
                    role: AgentMessageRole.user,
                    text: 'Keep this history',
                  ),
                ],
              ),
            ],
          ),
        },
      );
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.switchThread(_thread());
      await viewModel.sendMessage('Resume this thread');

      expect(provider.calls, <String>['read:thread-1', 'resume:thread-1']);
      expect(viewModel.status.state, AgentProviderConnectionState.error);
      expect(viewModel.threadOpenPhase, AgentThreadOpenPhase.openFailed);
      expect(viewModel.canSubmitMessage, isFalse);
      expect(provider.calls, isNot(contains('start')));
      final texts = viewModel.timelineEntries
          .whereType<AgentMessageTimelineEntry>()
          .map((entry) => entry.message.text)
          .toList();
      expect(texts, contains('Keep this history'));
      expect(texts, contains('Resume this thread'));
    });

    test('switchThread allows switching away from a running thread', () async {
      final provider = _FakeAgentProvider(
        historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
          'thread-1': const AgentThreadHistorySnapshot(
            threadId: 'thread-1',
            turns: <AgentHistoryTurn>[
              AgentHistoryTurn(
                id: 'turn-running',
                status: AgentHistoryTurnStatus.running,
                entries: <AgentHistoryEntry>[
                  AgentHistoryMessageEntry(
                    id: 'history-a',
                    role: AgentMessageRole.user,
                    text: 'Thread one history',
                  ),
                ],
              ),
            ],
          ),
          'thread-2': _historySnapshot(
            threadId: 'thread-2',
            userText: 'Thread two history',
          ),
        },
      );
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.switchThread(_thread(id: 'thread-1'));
      expect(viewModel.isTurnRunning, isTrue);

      await viewModel.switchThread(
        _thread(id: 'thread-2', title: 'Thread two'),
      );

      expect(viewModel.currentThreadTitle, 'Thread two');
      expect(viewModel.threadOpenPhase, AgentThreadOpenPhase.idle);
      expect(
        viewModel.timelineEntries.whereType<AgentMessageTimelineEntry>().map(
          (entry) => entry.message.text,
        ),
        contains('Thread two history'),
      );
      expect(
        viewModel.timelineEntries.whereType<AgentMessageTimelineEntry>().map(
          (entry) => entry.message.text,
        ),
        isNot(contains('Thread one history')),
      );
      expect(provider.calls, <String>['read:thread-1', 'read:thread-2']);
    });

    test('running selected thread resumes and steers on first send', () async {
      final provider = _FakeAgentProvider(
        historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
          'thread-1': const AgentThreadHistorySnapshot(
            threadId: 'thread-1',
            turns: <AgentHistoryTurn>[
              AgentHistoryTurn(
                id: 'turn-running',
                status: AgentHistoryTurnStatus.running,
                entries: <AgentHistoryEntry>[
                  AgentHistoryMessageEntry(
                    id: 'history-user-1',
                    role: AgentMessageRole.user,
                    text: 'Historical context',
                  ),
                ],
              ),
            ],
          ),
        },
      );
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.switchThread(_thread());
      expect(viewModel.isTurnRunning, isTrue);
      expect(viewModel.canSubmitMessage, isTrue);

      await viewModel.sendMessage('hello while running');

      expect(provider.calls, <String>[
        'read:thread-1',
        'resume:thread-1',
        'steer:thread-1',
      ]);
      expect(
        viewModel.timelineEntries.whereType<AgentMessageTimelineEntry>().map(
          (entry) => entry.message.text,
        ),
        contains('hello while running'),
      );
    });

    test(
      'cancels the selected thread running turn without a resumed session',
      () async {
        final provider = _FakeAgentProvider(
          historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
            'thread-1': const AgentThreadHistorySnapshot(
              threadId: 'thread-1',
              turns: <AgentHistoryTurn>[
                AgentHistoryTurn(
                  id: 'turn-running',
                  status: AgentHistoryTurnStatus.running,
                  entries: <AgentHistoryEntry>[
                    AgentHistoryMessageEntry(
                      id: 'history-user-1',
                      role: AgentMessageRole.user,
                      text: 'Historical context',
                    ),
                  ],
                ),
              ],
            ),
          },
        );
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.switchThread(_thread());
        await viewModel.cancelActiveTurn();

        expect(provider.calls, <String>[
          'read:thread-1',
          'cancel:thread-1:turn-running',
        ]);
      },
    );

    test(
      'ignores realtime events from a non-selected thread after switching',
      () async {
        final provider = _FakeAgentProvider(
          historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
            'thread-1': _historySnapshot(
              threadId: 'thread-1',
              userText: 'Thread one history',
            ),
            'thread-2': _historySnapshot(
              threadId: 'thread-2',
              userText: 'Thread two history',
            ),
          },
        );
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.switchThread(_thread(id: 'thread-1'));
        await viewModel.switchThread(
          _thread(id: 'thread-2', title: 'Thread two'),
        );
        provider.emit(
          const AgentMessageDeltaEvent(
            messageId: 'late-message',
            delta: 'Late update from thread one',
            role: AgentMessageRole.agent,
            sessionId: 'thread-1',
            turnId: 'thread-1-turn-1',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        final texts = viewModel.timelineEntries
            .whereType<AgentMessageTimelineEntry>()
            .map((entry) => entry.message.text)
            .toList();
        expect(texts, contains('Thread two history'));
        expect(texts, isNot(contains('Late update from thread one')));
      },
    );

    test(
      'merges realtime agent message metadata into existing message',
      () async {
        final provider = _FakeAgentProvider();
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.sendMessage('hello');
        provider.emit(
          const AgentMessageDeltaEvent(
            messageId: 'agent-1',
            delta: 'Streaming commentary',
            role: AgentMessageRole.agent,
            phase: AgentMessagePhase.commentary,
            status: AgentMessageStatus.streaming,
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(
          viewModel.timelineEntries
              .whereType<AgentMessageTimelineEntry>()
              .last
              .message
              .isCompletedCommentary,
          isFalse,
        );

        provider.emit(
          const AgentMessageUpdatedEvent(
            messageId: 'agent-1',
            phase: AgentMessagePhase.commentary,
            status: AgentMessageStatus.completed,
            duration: Duration(seconds: 5),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        final message = viewModel.timelineEntries
            .whereType<AgentMessageTimelineEntry>()
            .last
            .message;
        expect(message.text, 'Streaming commentary');
        expect(message.isCompletedCommentary, isTrue);
        expect(message.duration, const Duration(seconds: 5));
      },
    );

    test(
      'stores plan updates as plan messages instead of tool calls',
      () async {
        final provider = _FakeAgentProvider();
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.sendMessage('hello');
        provider.emit(
          const AgentPlanUpdatedEvent(
            entries: <AgentPlanEntry>[
              AgentPlanEntry(content: 'Inspect timeline', status: 'completed'),
              AgentPlanEntry(
                content: 'Render markdown card',
                status: 'pending',
              ),
            ],
            sessionId: 'thread-1',
            turnId: 'turn-1',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        final planMessage = viewModel.timelineEntries
            .whereType<AgentMessageTimelineEntry>()
            .map((entry) => entry.message)
            .firstWhere((message) => message.id == 'turn-1-plan');
        expect(planMessage.kind, AgentConversationMessageKind.plan);
        expect(
          planMessage.text,
          '- [x] Inspect timeline\n- [ ] Render markdown card',
        );
        expect(
          viewModel.timelineEntries.whereType<AgentToolTimelineEntry>(),
          isEmpty,
        );

        final historyVersion = viewModel.historyVersion;
        final expansionVersion = viewModel.expansionVersion;
        expect(viewModel.isPlanMessageExpanded(planMessage.id), isFalse);
        viewModel.togglePlanMessage(planMessage.id);
        expect(viewModel.historyVersion, historyVersion);
        expect(viewModel.expansionVersion, greaterThan(expansionVersion));
        expect(viewModel.isPlanMessageExpanded(planMessage.id), isTrue);
      },
    );

    test('groups history entries by turn in conversationTurns', () async {
      final startedAt = DateTime.parse('2026-07-04T06:00:00.000Z');
      final completedAt = DateTime.parse('2026-07-04T06:00:03.000Z');
      final provider = _FakeAgentProvider(
        historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
          'thread-1': AgentThreadHistorySnapshot(
            threadId: 'thread-1',
            turns: <AgentHistoryTurn>[
              AgentHistoryTurn(
                id: 'turn-a',
                entries: <AgentHistoryEntry>[
                  const AgentHistoryMessageEntry(
                    id: 'user-a',
                    role: AgentMessageRole.user,
                    text: 'First request',
                  ),
                  const AgentHistoryMessageEntry(
                    id: 'agent-a',
                    role: AgentMessageRole.agent,
                    text: 'First response',
                  ),
                ],
                status: AgentHistoryTurnStatus.completed,
                startedAt: startedAt,
                completedAt: completedAt,
                duration: const Duration(seconds: 3),
                tokenUsage: const AgentTokenUsage(
                  inputTokens: 41910,
                  cachedInputTokens: 19712,
                  outputTokens: 1552,
                  reasoningOutputTokens: 780,
                  totalTokens: 43462,
                ),
              ),
              AgentHistoryTurn(
                id: 'turn-b',
                entries: <AgentHistoryEntry>[
                  const AgentHistoryMessageEntry(
                    id: 'user-b',
                    role: AgentMessageRole.user,
                    text: 'Second request',
                  ),
                ],
              ),
            ],
          ),
        },
      );
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.switchThread(_thread());
      await Future<void>.delayed(Duration.zero);

      final turns = viewModel.conversationTurns;
      // 加载历史后 welcome 消息被清空，只剩两个历史回合。
      expect(turns, hasLength(2));
      expect(turns.first.id, 'turn-a');
      expect(turns.first.isStandby, isFalse);
      expect(turns.first.status, AgentHistoryTurnStatus.completed);
      expect(turns.first.startedAt, startedAt);
      expect(turns.first.duration, const Duration(seconds: 3));
      expect(turns.first.tokenUsage, isNotNull);
      expect(turns.first.tokenUsage!.totalTokens, 43462);
      expect(turns.first.tokenUsage!.inputTokens, 41910);
      expect(turns.first.tokenUsage!.outputTokens, 1552);
      expect(turns[1].tokenUsage, isNull);
      expect(viewModel.currentThreadTokenUsage, isNotNull);
      expect(viewModel.currentThreadTokenUsage!.totalTokens, 43462);
      expect(viewModel.currentThreadTokenUsage!.inputTokens, 41910);
      expect(
        turns.first.entries.whereType<AgentMessageTimelineEntry>().map(
          (entry) => entry.message.text,
        ),
        <String>['First request', 'First response'],
      );
      expect(turns[1].id, 'turn-b');
      expect(
        (turns[1].entries.single as AgentMessageTimelineEntry).message.text,
        'Second request',
      );
      // 展平后的 timelineEntries 仍包含全部历史消息。
      expect(
        viewModel.timelineEntries.whereType<AgentMessageTimelineEntry>().map(
          (entry) => entry.message.text,
        ),
        containsAll(<String>['First request', 'Second request']),
      );
    });

    test('pages historical turns into a visible window of 3', () async {
      final provider = _FakeAgentProvider(
        historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
          'thread-1': AgentThreadHistorySnapshot(
            threadId: 'thread-1',
            turns: <AgentHistoryTurn>[
              for (var index = 1; index <= 5; index += 1)
                AgentHistoryTurn(
                  id: 'turn-$index',
                  entries: <AgentHistoryEntry>[
                    AgentHistoryMessageEntry(
                      id: 'user-$index',
                      role: AgentMessageRole.user,
                      text: 'Request $index',
                    ),
                  ],
                ),
            ],
          ),
        },
      );
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.switchThread(_thread());
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.hasOlderTurns, isTrue);
      expect(
        viewModel.visibleHistoryTurns.map((turn) => turn.id).toList(),
        <String>['turn-3', 'turn-4', 'turn-5'],
      );
      expect(
        viewModel.conversationTurns.map((turn) => turn.id).toList(),
        <String>['turn-3', 'turn-4', 'turn-5'],
      );
      expect(
        viewModel.timelineEntries.whereType<AgentMessageTimelineEntry>().map(
          (entry) => entry.message.text,
        ),
        containsAll(<String>[
          'Request 1',
          'Request 2',
          'Request 3',
          'Request 4',
          'Request 5',
        ]),
      );

      expect(viewModel.loadOlderTurns(), isTrue);

      expect(viewModel.hasOlderTurns, isFalse);
      expect(
        viewModel.conversationTurns.map((turn) => turn.id).toList(),
        <String>['turn-1', 'turn-2', 'turn-3', 'turn-4', 'turn-5'],
      );
    });

    test(
      'keeps history and composer notifiers stable during live streaming flushes',
      () async {
        final provider = _FakeAgentProvider();
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.sendMessage('hello');

        final liveTurn = viewModel.liveTurnState;
        expect(liveTurn, isNotNull);

        var historyNotifications = 0;
        var headerNotifications = 0;
        var composerNotifications = 0;
        var liveNotifications = 0;
        viewModel.historyVersionListenable.addListener(() {
          historyNotifications += 1;
        });
        viewModel.headerVersionListenable.addListener(() {
          headerNotifications += 1;
        });
        viewModel.composerVersionListenable.addListener(() {
          composerNotifications += 1;
        });
        liveTurn!.addListener(() {
          liveNotifications += 1;
        });

        final historyVersion = viewModel.historyVersion;
        final headerVersion = viewModel.headerVersion;
        final composerVersion = viewModel.composerVersion;

        provider.emit(
          const AgentMessageDeltaEvent(
            messageId: 'agent-1',
            delta: 'Streaming reply',
            role: AgentMessageRole.agent,
            phase: AgentMessagePhase.commentary,
            status: AgentMessageStatus.streaming,
          ),
        );
        provider.emit(
          const AgentTokenUsageEvent(
            tokenUsage: AgentTokenUsage(
              inputTokens: 1000,
              outputTokens: 300,
              totalTokens: 1300,
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 24));

        expect(viewModel.historyVersion, historyVersion);
        expect(viewModel.composerVersion, composerVersion);
        expect(viewModel.headerVersion, greaterThan(headerVersion));
        expect(historyNotifications, 0);
        expect(composerNotifications, 0);
        expect(headerNotifications, 1);
        expect(liveNotifications, 1);
      },
    );

    test(
      'throttles high-frequency tool output updates into a single live flush',
      () async {
        final provider = _FakeAgentProvider();
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.sendMessage('hello');

        final liveTurn = viewModel.liveTurnState;
        expect(liveTurn, isNotNull);

        var historyNotifications = 0;
        var headerNotifications = 0;
        var composerNotifications = 0;
        var liveNotifications = 0;
        var autoScrollNotifications = 0;
        viewModel.historyVersionListenable.addListener(() {
          historyNotifications += 1;
        });
        viewModel.headerVersionListenable.addListener(() {
          headerNotifications += 1;
        });
        viewModel.composerVersionListenable.addListener(() {
          composerNotifications += 1;
        });
        viewModel.autoScrollTickListenable.addListener(() {
          autoScrollNotifications += 1;
        });
        liveTurn!.addListener(() {
          liveNotifications += 1;
        });

        final historyVersion = viewModel.historyVersion;
        final headerVersion = viewModel.headerVersion;
        final composerVersion = viewModel.composerVersion;
        final autoScrollTick = viewModel.autoScrollTick;

        provider.emit(
          const AgentToolCallEvent(
            AgentToolCall(
              id: 'tool-1',
              title: 'Command output',
              kind: AgentToolKind.execute,
              status: AgentToolStatus.inProgress,
              content: 'line 1',
            ),
          ),
        );
        provider.emit(
          const AgentToolCallEvent(
            AgentToolCall(
              id: 'tool-1',
              title: 'Command output',
              kind: AgentToolKind.execute,
              status: AgentToolStatus.inProgress,
              content: 'line 2',
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 24));

        expect(viewModel.historyVersion, historyVersion);
        expect(viewModel.headerVersion, headerVersion);
        expect(viewModel.composerVersion, composerVersion);
        expect(viewModel.autoScrollTick, greaterThan(autoScrollTick));
        expect(historyNotifications, 0);
        expect(headerNotifications, 0);
        expect(composerNotifications, 0);
        expect(liveNotifications, 1);
        expect(autoScrollNotifications, 1);
        expect(
          viewModel.timelineEntries
              .whereType<AgentToolTimelineEntry>()
              .single
              .toolCall
              .content,
          'line 2',
        );
      },
    );

    test(
      'moves a completed live turn into the capped history window',
      () async {
        final provider = _FakeAgentProvider(
          historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
            'thread-1': AgentThreadHistorySnapshot(
              threadId: 'thread-1',
              turns: <AgentHistoryTurn>[
                for (var index = 1; index <= 5; index += 1)
                  AgentHistoryTurn(
                    id: 'history-$index',
                    entries: <AgentHistoryEntry>[
                      AgentHistoryMessageEntry(
                        id: 'history-user-$index',
                        role: AgentMessageRole.user,
                        text: 'Request $index',
                      ),
                    ],
                  ),
              ],
            ),
          },
        );
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.switchThread(_thread());
        await Future<void>.delayed(Duration.zero);
        await viewModel.sendMessage('hello');

        expect(
          viewModel.visibleHistoryTurns.map((turn) => turn.id).toList(),
          <String>['history-3', 'history-4', 'history-5'],
        );
        expect(viewModel.liveTurnState, isNotNull);

        provider.emit(
          const AgentTurnCompletedEvent(
            sessionId: 'thread-1',
            turnId: 'turn-1',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(viewModel.liveTurnState, isNull);
        expect(
          viewModel.visibleHistoryTurns.map((turn) => turn.id).toList(),
          <String>['history-4', 'history-5', 'turn-1'],
        );
      },
    );

    test(
      'groups live user message and agent reply into the same turn',
      () async {
        final provider = _FakeAgentProvider();
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.sendMessage('hello');
        provider.emit(
          const AgentMessageDeltaEvent(
            messageId: 'agent-1',
            delta: 'Streaming reply',
            role: AgentMessageRole.agent,
            phase: AgentMessagePhase.commentary,
            status: AgentMessageStatus.streaming,
          ),
        );
        await Future<void>.delayed(Duration.zero);

        final turns = viewModel.conversationTurns;
        // standby（welcome）+ 一个 live 回合。
        expect(turns, hasLength(2));
        expect(turns.first.isStandby, isTrue);
        final liveTurn = turns.last;
        expect(liveTurn.isStandby, isFalse);
        expect(liveTurn.status, AgentHistoryTurnStatus.running);
        final texts = liveTurn.entries
            .whereType<AgentMessageTimelineEntry>()
            .map((entry) => entry.message.text)
            .toList();
        expect(texts, containsAll(<String>['hello', 'Streaming reply']));
      },
    );

    test('attaches live token usage to the active turn group', () async {
      final provider = _FakeAgentProvider();
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.sendMessage('hello');
      provider.emit(
        const AgentTokenUsageEvent(
          tokenUsage: AgentTokenUsage(
            inputTokens: 1000,
            cachedInputTokens: 200,
            outputTokens: 300,
            reasoningOutputTokens: 50,
            totalTokens: 1300,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final liveTurn = viewModel.conversationTurns.last;
      expect(liveTurn.tokenUsage, isNotNull);
      expect(liveTurn.tokenUsage!.totalTokens, 1300);
      expect(liveTurn.tokenUsage!.inputTokens, 1000);
      expect(liveTurn.tokenUsage!.cachedInputTokens, 200);
      expect(liveTurn.tokenUsage!.outputTokens, 300);
      expect(liveTurn.tokenUsage!.reasoningOutputTokens, 50);
    });

    test(
      'exposes header token usage only while the active turn is running',
      () async {
        final provider = _FakeAgentProvider();
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.sendMessage('hello');
        provider.emit(
          const AgentTokenUsageEvent(
            tokenUsage: AgentTokenUsage(
              inputTokens: 1000,
              cachedInputTokens: 200,
              outputTokens: 300,
              reasoningOutputTokens: 50,
              totalTokens: 1300,
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(viewModel.currentTurnTokenUsage, isNotNull);
        expect(viewModel.currentTurnTokenUsage!.totalTokens, 1300);

        provider.emit(
          const AgentTurnCompletedEvent(
            sessionId: 'thread-1',
            turnId: 'turn-1',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(viewModel.currentTurnTokenUsage, isNull);
        expect(viewModel.currentThreadTokenUsage, isNotNull);
        expect(viewModel.currentThreadTokenUsage!.totalTokens, 1300);
      },
    );

    test(
      'aggregates header token usage across history and live turns',
      () async {
        final provider = _FakeAgentProvider(
          historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
            'thread-1': const AgentThreadHistorySnapshot(
              threadId: 'thread-1',
              turns: <AgentHistoryTurn>[
                AgentHistoryTurn(
                  id: 'turn-a',
                  entries: <AgentHistoryEntry>[
                    AgentHistoryMessageEntry(
                      id: 'user-a',
                      role: AgentMessageRole.user,
                      text: 'Existing request',
                    ),
                  ],
                  tokenUsage: AgentTokenUsage(
                    inputTokens: 2000,
                    cachedInputTokens: 500,
                    outputTokens: 250,
                    reasoningOutputTokens: 80,
                    totalTokens: 2250,
                  ),
                ),
              ],
            ),
          },
        );
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.switchThread(_thread());
        await Future<void>.delayed(Duration.zero);
        await viewModel.sendMessage('hello');
        provider.emit(
          const AgentTokenUsageEvent(
            tokenUsage: AgentTokenUsage(
              inputTokens: 1000,
              cachedInputTokens: 200,
              outputTokens: 300,
              reasoningOutputTokens: 50,
              totalTokens: 1300,
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(viewModel.currentThreadTokenUsage, isNotNull);
        expect(viewModel.currentThreadTokenUsage!.inputTokens, 3000);
        expect(viewModel.currentThreadTokenUsage!.cachedInputTokens, 700);
        expect(viewModel.currentThreadTokenUsage!.outputTokens, 550);
        expect(viewModel.currentThreadTokenUsage!.reasoningOutputTokens, 130);
        expect(viewModel.currentThreadTokenUsage!.totalTokens, 3550);
      },
    );

    test('handles model list event and reconciles default selection', () async {
      final provider = _FakeAgentProvider();
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      // loadModels 会建立事件订阅；fake 的 listModels 返回空列表，
      // 随后手动 emit 真实模型列表来验证事件处理。
      await viewModel.loadModels();
      provider.emit(
        const AgentModelListEvent(
          AgentModelList(
            models: <AgentModelInfo>[
              AgentModelInfo(
                id: 'gpt-5.5',
                model: 'gpt-5.5',
                displayName: 'GPT-5.5',
                isDefault: true,
                supportedReasoningEfforts: <AgentModelReasoningEffort>[
                  AgentModelReasoningEffort(effort: 'low'),
                  AgentModelReasoningEffort(effort: 'medium'),
                  AgentModelReasoningEffort(effort: 'high'),
                ],
                defaultReasoningEffort: 'medium',
                serviceTiers: <AgentModelServiceTier>[
                  AgentModelServiceTier(id: 'priority', name: 'Fast'),
                ],
              ),
              AgentModelInfo(
                id: 'gpt-5.4-mini',
                model: 'gpt-5.4-mini',
                displayName: 'GPT-5.4-Mini',
              ),
            ],
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.models, hasLength(2));
      expect(viewModel.selectedModelId, 'gpt-5.5');
      expect(viewModel.selectedReasoningEffort, 'medium');
      expect(viewModel.selectedServiceTierId, isNull);
      expect(viewModel.showReasoningEffort, isTrue);
      expect(viewModel.showServiceTier, isTrue);
    });

    test('selectModel updates selection and persists to config', () async {
      final provider = _FakeAgentProvider();
      final controller = ActiveAgentProviderController(
        providerFactory: _FakeAgentProviderFactory(provider),
        configStore: MemoryAgentProviderConfigStore(),
      );
      addTearDown(controller.dispose);
      final viewModel = AgentConversationViewModel(
        providerController: controller,
      );
      addTearDown(viewModel.dispose);
      viewModel.updateWorkspace(projectPath: '/repo', contextFilePath: null);

      await viewModel.loadModels();
      provider.emit(
        const AgentModelListEvent(
          AgentModelList(
            models: <AgentModelInfo>[
              AgentModelInfo(
                id: 'gpt-5.5',
                model: 'gpt-5.5',
                displayName: 'GPT-5.5',
                isDefault: true,
                supportedReasoningEfforts: <AgentModelReasoningEffort>[
                  AgentModelReasoningEffort(effort: 'low'),
                  AgentModelReasoningEffort(effort: 'medium'),
                ],
                defaultReasoningEffort: 'medium',
              ),
              AgentModelInfo(
                id: 'gpt-5.4-mini',
                model: 'gpt-5.4-mini',
                displayName: 'GPT-5.4-Mini',
                supportedReasoningEfforts: <AgentModelReasoningEffort>[
                  AgentModelReasoningEffort(effort: 'low'),
                ],
                defaultReasoningEffort: 'low',
              ),
            ],
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      await viewModel.selectModel('gpt-5.4-mini');

      expect(viewModel.selectedModelId, 'gpt-5.4-mini');
      // 切换模型时回退到该模型的默认推理档位。
      expect(viewModel.selectedReasoningEffort, 'low');
      // 持久化到 provider 配置。
      expect(controller.activeProviderConfig.selectedModel, 'gpt-5.4-mini');
      expect(controller.activeProviderConfig.selectedReasoningEffort, 'low');
    });
  });
}

AgentConversationViewModel _createViewModel(_FakeAgentProvider provider) {
  final controller = ActiveAgentProviderController(
    providerFactory: _FakeAgentProviderFactory(provider),
    configStore: MemoryAgentProviderConfigStore(),
  );
  addTearDown(controller.dispose);
  final viewModel = AgentConversationViewModel(providerController: controller);
  viewModel.updateWorkspace(projectPath: '/repo', contextFilePath: null);
  return viewModel;
}

AgentThreadSummary _thread({
  String id = 'thread-1',
  String title = 'Thread one',
}) {
  return AgentThreadSummary(
    id: id,
    providerId: defaultAgentProviderId,
    projectPath: '/repo',
    title: title,
    sessionPath: '/repo/$id.jsonl',
    preview: title,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(2),
    status: AgentThreadRuntimeStatus.idle,
  );
}

AgentThreadHistorySnapshot _historySnapshot({
  required String threadId,
  required String userText,
  String agentText = 'Historical answer',
}) {
  return AgentThreadHistorySnapshot(
    threadId: threadId,
    turns: <AgentHistoryTurn>[
      AgentHistoryTurn(
        id: '$threadId-turn-1',
        entries: <AgentHistoryEntry>[
          AgentHistoryMessageEntry(
            id: '$threadId-user-1',
            role: AgentMessageRole.user,
            text: userText,
          ),
          AgentHistoryMessageEntry(
            id: '$threadId-agent-1',
            role: AgentMessageRole.agent,
            text: agentText,
          ),
          AgentHistoryToolEntry(
            toolCall: AgentToolCall(
              id: '$threadId-tool-1',
              title: 'Run tests',
              kind: AgentToolKind.execute,
              status: AgentToolStatus.completed,
              content: 'flutter test',
            ),
          ),
          const AgentHistoryEventEntry(
            id: 'event-1',
            kind: AgentHistoryEventKind.search,
            title: 'Tool search',
            description: 'read_package_uris',
          ),
        ],
      ),
    ],
  );
}

class _FakeAgentProviderFactory implements AgentProviderFactory {
  const _FakeAgentProviderFactory(this.provider);

  final _FakeAgentProvider provider;

  @override
  AgentProvider create(AgentProviderConfig config) => provider;
}

class _FakeAgentProvider implements AgentProvider {
  _FakeAgentProvider({
    this.failHistory = false,
    this.failResume = false,
    this.startSessionTitle,
    this.resumeSessionTitle,
    AgentThreadHistorySnapshot? historySnapshot,
    Map<String, AgentThreadHistorySnapshot> historySnapshotsByThread =
        const <String, AgentThreadHistorySnapshot>{},
    Map<String, Completer<AgentSession>> resumeCompleters =
        const <String, Completer<AgentSession>>{},
  }) : _defaultHistorySnapshot =
           historySnapshot ??
           const AgentThreadHistorySnapshot(
             threadId: 'thread-1',
             turns: <AgentHistoryTurn>[],
           ),
       _historySnapshotsByThread = Map<String, AgentThreadHistorySnapshot>.from(
         historySnapshotsByThread,
       ),
       _resumeCompleters = Map<String, Completer<AgentSession>>.from(
         resumeCompleters,
       );

  final bool failHistory;
  final bool failResume;
  final String? startSessionTitle;
  final String? resumeSessionTitle;
  final AgentThreadHistorySnapshot _defaultHistorySnapshot;
  final Map<String, AgentThreadHistorySnapshot> _historySnapshotsByThread;
  final Map<String, Completer<AgentSession>> _resumeCompleters;
  final List<String> calls = <String>[];
  final List<String?> readSessionPaths = <String?>[];
  final StreamController<AgentEvent> _events =
      StreamController<AgentEvent>.broadcast();

  @override
  AgentProviderConfig get config => AgentProviderConfig.defaultCodex;

  @override
  Stream<AgentEvent> get events => _events.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<AgentThreadPage> listThreads({
    required AgentThreadListQuery query,
  }) async {
    return const AgentThreadPage(
      threads: <AgentThreadSummary>[],
      nextCursor: null,
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
  Future<AgentThreadHistorySnapshot> readThreadHistory({
    required String threadId,
    String? sessionPath,
  }) async {
    calls.add('read:$threadId');
    readSessionPaths.add(sessionPath);
    if (failHistory) {
      throw StateError('history failed');
    }
    return _historySnapshotsByThread[threadId] ?? _defaultHistorySnapshot;
  }

  @override
  Future<AgentSession> startSession({required AgentContext context}) async {
    calls.add('start');
    return AgentSession(
      id: 'thread-1',
      providerId: defaultAgentProviderId,
      title: startSessionTitle,
    );
  }

  @override
  Future<AgentSession> resumeSession(
    String sessionId, {
    required AgentContext context,
  }) async {
    calls.add('resume:$sessionId');
    if (failResume) {
      throw StateError('resume failed');
    }
    final completer = _resumeCompleters[sessionId];
    if (completer != null) {
      return completer.future;
    }
    return AgentSession(
      id: sessionId,
      providerId: defaultAgentProviderId,
      title: resumeSessionTitle,
    );
  }

  @override
  Future<AgentTurn> sendMessage({
    required AgentSession session,
    required String message,
    required AgentContext context,
  }) async {
    calls.add('send:${session.id}');
    return AgentTurn(id: 'turn-1', sessionId: session.id);
  }

  @override
  Future<void> steerTurn({
    required AgentSession session,
    required String message,
    required AgentContext context,
  }) async {
    calls.add('steer:${session.id}');
  }

  @override
  Future<void> cancelTurn(AgentTurn turn) async {
    calls.add('cancel:${turn.sessionId}:${turn.id}');
  }

  @override
  Future<void> respondToPermission(AgentPermissionDecision decision) async {}

  @override
  Future<void> dispose() async {
    await _events.close();
  }

  void emit(AgentEvent event) {
    _events.add(event);
  }
}

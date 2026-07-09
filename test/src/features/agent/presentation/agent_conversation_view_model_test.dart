import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/ui/features/ide/view_models/active_agent_provider_controller.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_view_model.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_grouping.dart';

import '../../../testing/agent_provider_stub_base.dart';

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
      expect(provider.calls, <String>[
        'read:thread-1',
        'unsubscribe:thread-1',
        'read:thread-2',
      ]);
      expect(provider.unsubscribedThreads, <String>['thread-1']);
    });

    test(
      'switchThread does not unsubscribe when selecting the same thread',
      () async {
        final provider = _FakeAgentProvider(
          historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
            'thread-1': _historySnapshot(
              threadId: 'thread-1',
              userText: 'Same thread',
            ),
          },
        );
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.switchThread(_thread(id: 'thread-1'));
        await viewModel.switchThread(_thread(id: 'thread-1'));

        expect(provider.unsubscribedThreads, isEmpty);
        expect(provider.calls, <String>['read:thread-1', 'read:thread-1']);
      },
    );

    test(
      'updateWorkspace unsubscribes previous thread on project change',
      () async {
        final provider = _FakeAgentProvider(
          historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
            'thread-1': _historySnapshot(
              threadId: 'thread-1',
              userText: 'Leaving project',
            ),
          },
        );
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        viewModel.updateWorkspace(
          projectPath: '/repo-a',
          contextFilePath: null,
        );
        await viewModel.switchThread(_thread(id: 'thread-1'));
        expect(provider.unsubscribedThreads, isEmpty);

        viewModel.updateWorkspace(
          projectPath: '/repo-b',
          contextFilePath: null,
        );
        await Future<void>.delayed(Duration.zero);

        expect(provider.unsubscribedThreads, <String>['thread-1']);
      },
    );

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
      'sendMessage includes localImage inputs and timeline previews',
      () async {
        final provider = _FakeAgentProvider();
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        viewModel.updateWorkspace(projectPath: '/repo', contextFilePath: null);
        await viewModel.sendMessage(
          'look at this',
          localImagePaths: const <String>[r'D:\tmp\a.png', r'D:\tmp\b.png'],
        );

        expect(provider.calls, contains('send:thread-1'));
        expect(provider.calls, contains('image:D:\\tmp\\a.png'));
        expect(provider.calls, contains('image:D:\\tmp\\b.png'));
        final userMessage = viewModel.timelineEntries
            .whereType<AgentMessageTimelineEntry>()
            .map((entry) => entry.message)
            .firstWhere((message) => message.role == AgentMessageRole.user);
        expect(userMessage.text, 'look at this');
        expect(userMessage.localImagePaths, <String>[
          r'D:\tmp\a.png',
          r'D:\tmp\b.png',
        ]);
      },
    );

    test('sendMessage allows image-only payloads', () async {
      final provider = _FakeAgentProvider();
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      viewModel.updateWorkspace(projectPath: '/repo', contextFilePath: null);
      await viewModel.sendMessage(
        '   ',
        localImagePaths: const <String>[r'D:\tmp\only.png'],
      );

      expect(provider.calls, contains('image:D:\\tmp\\only.png'));
      final userMessage = viewModel.timelineEntries
          .whereType<AgentMessageTimelineEntry>()
          .map((entry) => entry.message)
          .firstWhere((message) => message.role == AgentMessageRole.user);
      expect(userMessage.text, isEmpty);
      expect(userMessage.localImagePaths, <String>[r'D:\tmp\only.png']);
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

    test('streams reasoning deltas into an expanded think card', () async {
      final provider = _FakeAgentProvider();
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.sendMessage('hello');
      provider.emit(
        const AgentReasoningDeltaEvent(
          itemId: 'reasoning-1',
          kind: AgentReasoningDeltaKind.text,
          delta: 'raw-a',
          sessionId: 'thread-1',
          turnId: 'turn-1',
        ),
      );
      provider.emit(
        const AgentReasoningDeltaEvent(
          itemId: 'reasoning-1',
          kind: AgentReasoningDeltaKind.text,
          delta: 'raw-b',
          sessionId: 'thread-1',
          turnId: 'turn-1',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 24));

      var think = viewModel.timelineEntries
          .whereType<AgentToolTimelineEntry>()
          .single
          .toolCall;
      expect(think.kind, AgentToolKind.think);
      expect(think.title, '思考');
      expect(think.content, 'raw-araw-b');
      expect(think.status, AgentToolStatus.inProgress);
      expect(viewModel.isToolCallExpanded('reasoning-1'), isTrue);

      // 摘要到达后优先展示摘要，不再拼接原文。
      provider.emit(
        const AgentReasoningDeltaEvent(
          itemId: 'reasoning-1',
          kind: AgentReasoningDeltaKind.summaryText,
          delta: 'sum-1',
          sessionId: 'thread-1',
          turnId: 'turn-1',
        ),
      );
      provider.emit(
        const AgentReasoningDeltaEvent(
          itemId: 'reasoning-1',
          kind: AgentReasoningDeltaKind.summaryPart,
          summaryIndex: 1,
          sessionId: 'thread-1',
          turnId: 'turn-1',
        ),
      );
      provider.emit(
        const AgentReasoningDeltaEvent(
          itemId: 'reasoning-1',
          kind: AgentReasoningDeltaKind.summaryText,
          delta: 'sum-2',
          sessionId: 'thread-1',
          turnId: 'turn-1',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 24));

      think = viewModel.timelineEntries
          .whereType<AgentToolTimelineEntry>()
          .single
          .toolCall;
      expect(think.content, 'sum-1\n\nsum-2');

      // completed 带完整正文时覆盖流式缓冲。
      provider.emit(
        const AgentToolCallEvent(
          AgentToolCall(
            id: 'reasoning-1',
            title: '思考',
            kind: AgentToolKind.think,
            status: AgentToolStatus.completed,
            content: 'final summary',
            sessionId: 'thread-1',
            turnId: 'turn-1',
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      think = viewModel.timelineEntries
          .whereType<AgentToolTimelineEntry>()
          .single
          .toolCall;
      expect(think.status, AgentToolStatus.completed);
      expect(think.content, 'final summary');
    });

    test('streams plan deltas into an expanded plan card', () async {
      final provider = _FakeAgentProvider();
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.sendMessage('hello');
      provider.emit(
        const AgentMessageDeltaEvent(
          messageId: 'plan-1',
          delta: '# Plan\n',
          role: AgentMessageRole.agent,
          status: AgentMessageStatus.streaming,
          raw: <String, Object?>{'type': 'plan'},
          sessionId: 'thread-1',
          turnId: 'turn-1',
        ),
      );
      provider.emit(
        const AgentMessageDeltaEvent(
          messageId: 'plan-1',
          delta: '- Step one',
          role: AgentMessageRole.agent,
          status: AgentMessageStatus.streaming,
          raw: <String, Object?>{'type': 'plan'},
          sessionId: 'thread-1',
          turnId: 'turn-1',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 24));

      final plan = viewModel.timelineEntries
          .whereType<AgentMessageTimelineEntry>()
          .map((entry) => entry.message)
          .firstWhere((message) => message.id == 'plan-1');
      expect(plan.kind, AgentConversationMessageKind.plan);
      expect(plan.text, '# Plan\n- Step one');
      expect(viewModel.isPlanMessageExpanded(plan.id), isTrue);

      // completed item 用权威全文覆盖拼接结果。
      provider.emit(
        const AgentMessageUpdatedEvent(
          messageId: 'plan-1',
          text: '# Final Plan\n\n- Step one\n- Step two',
          role: AgentMessageRole.agent,
          status: AgentMessageStatus.completed,
          raw: <String, Object?>{'type': 'plan'},
          sessionId: 'thread-1',
          turnId: 'turn-1',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final completed = viewModel.timelineEntries
          .whereType<AgentMessageTimelineEntry>()
          .map((entry) => entry.message)
          .firstWhere((message) => message.id == 'plan-1');
      expect(completed.text, '# Final Plan\n\n- Step one\n- Step two');
      expect(completed.status, AgentMessageStatus.completed);
      expect(completed.kind, AgentConversationMessageKind.plan);
    });

    test('upserts turn-level aggregated diff into the live timeline', () async {
      final provider = _FakeAgentProvider();
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.sendMessage('hello');
      provider.emit(
        const AgentTurnDiffEvent(
          sessionId: 'thread-1',
          turnId: 'turn-1',
          diff:
              'diff --git a/lib/a.dart b/lib/a.dart\n'
              '--- a/lib/a.dart\n'
              '+++ b/lib/a.dart\n'
              '@@ -1 +1 @@\n'
              '-old\n'
              '+new\n'
              'diff --git a/lib/b.dart b/lib/b.dart\n'
              '--- a/lib/b.dart\n'
              '+++ b/lib/b.dart\n'
              '@@ -1 +1,2 @@\n'
              ' keep\n'
              '+added\n',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final entry = viewModel.timelineEntries
          .whereType<AgentTurnDiffTimelineEntry>()
          .single;
      expect(entry.turnId, 'turn-1');
      expect(entry.diff, contains('lib/a.dart'));
      expect(entry.diff, contains('lib/b.dart'));

      // 同一 turn 的后续通知覆盖全文，不追加第二条。
      provider.emit(
        const AgentTurnDiffEvent(
          sessionId: 'thread-1',
          turnId: 'turn-1',
          diff:
              'diff --git a/lib/a.dart b/lib/a.dart\n'
              '--- a/lib/a.dart\n'
              '+++ b/lib/a.dart\n'
              '@@ -1 +1 @@\n'
              '-old\n'
              '+newer\n',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        viewModel.timelineEntries.whereType<AgentTurnDiffTimelineEntry>(),
        hasLength(1),
      );
      expect(
        viewModel.timelineEntries
            .whereType<AgentTurnDiffTimelineEntry>()
            .single
            .diff,
        contains('+newer'),
      );

      // 空 diff 移除条目。
      provider.emit(
        const AgentTurnDiffEvent(
          sessionId: 'thread-1',
          turnId: 'turn-1',
          diff: '',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        viewModel.timelineEntries.whereType<AgentTurnDiffTimelineEntry>(),
        isEmpty,
      );
    });

    test('exposes waiting status capsule from thread/status/changed', () async {
      final provider = _FakeAgentProvider();
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.sendMessage('hello');
      provider.emit(
        const AgentThreadStatusChangedEvent(
          threadId: 'thread-1',
          status: AgentThreadRuntimeStatus.active,
          waitingOnApproval: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.threadWaitingOnApproval, isTrue);
      expect(viewModel.threadStatusCapsuleLabel, '等待审批');
      expect(viewModel.showRunningIndicator, isFalse);

      provider.emit(
        const AgentThreadStatusChangedEvent(
          threadId: 'thread-1',
          status: AgentThreadRuntimeStatus.active,
          waitingOnUserInput: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(viewModel.threadStatusCapsuleLabel, '等待输入');

      provider.emit(
        const AgentThreadStatusChangedEvent(
          threadId: 'thread-1',
          status: AgentThreadRuntimeStatus.idle,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(viewModel.threadWaitingOnApproval, isFalse);
      expect(viewModel.threadWaitingOnUserInput, isFalse);
      expect(viewModel.threadStatusCapsuleLabel, isNull);
    });

    test(
      'dismisses approval card when serverRequest/resolved arrives',
      () async {
        final provider = _FakeAgentProvider();
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.sendMessage('hello');
        provider.emit(
          const AgentPermissionRequestedEvent(
            AgentPermissionRequest(
              id: 'approval-1',
              title: 'Run command',
              kind: AgentPermissionKind.commandExecution,
              command: 'flutter test',
              sessionId: 'thread-1',
              turnId: 'turn-1',
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(viewModel.permissionRequests.map((item) => item.id), <String>[
          'approval-1',
        ]);
        expect(
          viewModel.timelineEntries.whereType<AgentPermissionTimelineEntry>(),
          hasLength(1),
        );

        provider.emit(
          const AgentPermissionResolvedEvent(
            requestId: 'approval-1',
            threadId: 'thread-1',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(viewModel.permissionRequests, isEmpty);
        expect(
          viewModel.timelineEntries.whereType<AgentPermissionTimelineEntry>(),
          isEmpty,
        );
      },
    );

    test('appends MCP tool progress onto the matching tool card', () async {
      final provider = _FakeAgentProvider();
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.sendMessage('hello');
      provider.emit(
        const AgentToolCallEvent(
          AgentToolCall(
            id: 'mcp-1',
            title: 'MCP · docs · search',
            kind: AgentToolKind.search,
            status: AgentToolStatus.inProgress,
            content: 'query: zeta',
            sessionId: 'thread-1',
            turnId: 'turn-1',
          ),
        ),
      );
      provider.emit(
        const AgentToolCallEvent(
          AgentToolCall(
            id: 'mcp-1',
            title: 'MCP tool',
            kind: AgentToolKind.other,
            status: AgentToolStatus.inProgress,
            content: 'Fetching resources…',
            sessionId: 'thread-1',
            turnId: 'turn-1',
            raw: <String, Object?>{'_progressAppend': true},
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final tool = viewModel.toolCalls.single;
      expect(tool.title, 'MCP · docs · search');
      expect(tool.kind, AgentToolKind.search);
      expect(tool.content, 'query: zeta\nFetching resources…');
      expect(viewModel.isToolCallExpanded('mcp-1'), isTrue);
    });

    test('shows model reroute system event and header notice', () async {
      final provider = _FakeAgentProvider();
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.sendMessage('hello');
      provider.emit(
        const AgentModelReroutedEvent(
          threadId: 'thread-1',
          turnId: 'turn-1',
          fromModel: 'gpt-5.4',
          toModel: 'gpt-5.5',
          reason: 'highRiskCyberActivity',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.systemNoticeLabel, '已改道至 gpt-5.5');
      final event = viewModel.timelineEntries
          .whereType<AgentHistoryEventTimelineEntry>()
          .single
          .event;
      expect(event.kind, AgentHistoryEventKind.system);
      expect(event.title, '模型已改道');
      expect(event.description, 'gpt-5.4 → gpt-5.5');
      expect(event.content, '原因：高风险网络活动策略');

      provider.emit(
        const AgentTurnCompletedEvent(sessionId: 'thread-1', turnId: 'turn-1'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(viewModel.systemNoticeLabel, isNull);
    });

    test('shows deprecation notice once per summary', () async {
      final provider = _FakeAgentProvider();
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.sendMessage('hello');
      const notice = AgentDeprecationNoticeEvent(
        summary: 'turn/tokenCount is deprecated',
        details: 'Use thread/tokenUsage/updated instead.',
      );
      provider.emit(notice);
      provider.emit(notice);
      await Future<void>.delayed(Duration.zero);

      final events = viewModel.timelineEntries
          .whereType<AgentHistoryEventTimelineEntry>()
          .map((entry) => entry.event)
          .toList();
      expect(events, hasLength(1));
      expect(events.single.kind, AgentHistoryEventKind.warning);
      expect(events.single.title, '适配层弃用提示');
      expect(events.single.description, 'turn/tokenCount is deprecated');
      expect(
        events.single.content,
        contains('Use thread/tokenUsage/updated instead.'),
      );
      expect(events.single.content, contains('请升级 Codex 适配层'));
    });

    test('renders system ThreadItem events on the timeline', () async {
      final provider = _FakeAgentProvider();
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.sendMessage('hello');
      provider.emit(
        const AgentSystemItemEvent(
          entry: AgentHistoryEventEntry(
            id: 'compact-1',
            kind: AgentHistoryEventKind.system,
            title: '上下文已压缩',
            description: '会话上下文已压缩以腾出窗口空间。',
          ),
          sessionId: 'thread-1',
          turnId: 'turn-1',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final event = viewModel.timelineEntries
          .whereType<AgentHistoryEventTimelineEntry>()
          .single
          .event;
      expect(event.id, 'compact-1');
      expect(event.title, '上下文已压缩');
    });

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
        // 发送后 Ready 占位已移除，只剩一个 live 回合。
        expect(turns, hasLength(1));
        final liveTurn = turns.single;
        expect(liveTurn.isStandby, isFalse);
        expect(liveTurn.status, AgentHistoryTurnStatus.running);
        final texts = liveTurn.entries
            .whereType<AgentMessageTimelineEntry>()
            .map((entry) => entry.message.text)
            .toList();
        expect(texts, containsAll(<String>['hello', 'Streaming reply']));
        expect(
          viewModel.timelineEntries.whereType<AgentMessageTimelineEntry>().map(
            (entry) => entry.message.id,
          ),
          isNot(contains('welcome')),
        );
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
      'marks failed turns and shows the failure reason inside the turn',
      () async {
        final provider = _FakeAgentProvider();
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.sendMessage('hello');
        provider.emit(
          const AgentTurnCompletedEvent(
            sessionId: 'thread-1',
            turnId: 'turn-1',
            status: AgentHistoryTurnStatus.failed,
            errorMessage: 'Model provider rejected the request',
            duration: Duration(seconds: 5),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        final turn = viewModel.conversationTurns.singleWhere(
          (turn) => turn.id == 'turn-1',
        );
        expect(turn.status, AgentHistoryTurnStatus.failed);
        expect(turn.duration, const Duration(seconds: 5));
        final failureTexts = turn.entries
            .whereType<AgentMessageTimelineEntry>()
            .map((entry) => entry.message.text)
            .where((text) => text.contains('Turn failed'))
            .toList();
        expect(failureTexts, <String>[
          'Turn failed: Model provider rejected the request',
        ]);
      },
    );

    test(
      'does not repeat a failure reason already shown by an error event',
      () async {
        final provider = _FakeAgentProvider();
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.sendMessage('hello');
        provider.emit(
          const AgentErrorEvent(
            message: 'Context window exceeded',
            code: 'contextWindowExceeded',
            willRetry: false,
            sessionId: 'thread-1',
            turnId: 'turn-1',
          ),
        );
        provider.emit(
          const AgentTurnCompletedEvent(
            sessionId: 'thread-1',
            turnId: 'turn-1',
            status: AgentHistoryTurnStatus.failed,
            errorMessage: 'Context window exceeded',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        final errorTexts = viewModel.timelineEntries
            .whereType<AgentMessageTimelineEntry>()
            .map((entry) => entry.message.text)
            .where((text) => text.contains('Context window exceeded'))
            .toList();
        expect(errorTexts, hasLength(1));
        expect(errorTexts.single, isNot(contains('Turn failed')));

        final turn = viewModel.conversationTurns.singleWhere(
          (turn) => turn.id == 'turn-1',
        );
        expect(turn.status, AgentHistoryTurnStatus.failed);
      },
    );

    test('keeps unique ids for consecutive error events', () async {
      final provider = _FakeAgentProvider();
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.sendMessage('hello');
      provider.emit(
        const AgentErrorEvent(
          message: 'Codex stderr',
          details: 'first',
          sessionId: 'thread-1',
          turnId: 'turn-1',
        ),
      );
      provider.emit(
        const AgentErrorEvent(
          message: 'Codex stderr',
          details: 'second',
          sessionId: 'thread-1',
          turnId: 'turn-1',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final errorEntries = viewModel.timelineEntries
          .whereType<AgentMessageTimelineEntry>()
          .where((entry) => entry.message.id.startsWith('error-'))
          .toList();
      expect(errorEntries, hasLength(2));
      expect(errorEntries[0].message.id, isNot(errorEntries[1].message.id));
      expect(errorEntries.map((entry) => entry.id).toSet(), hasLength(2));

      final blocks = buildAgentTimelineRenderBlocks(
        turnId: 'turn-1',
        entries: viewModel.conversationTurns
            .singleWhere((turn) => turn.id == 'turn-1')
            .entries,
      );
      expect(blocks.map((block) => block.id).toSet(), hasLength(blocks.length));
    });

    test('marks interrupted turns without adding extra messages', () async {
      final provider = _FakeAgentProvider();
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.sendMessage('hello');
      provider.emit(
        const AgentTurnCompletedEvent(
          sessionId: 'thread-1',
          turnId: 'turn-1',
          status: AgentHistoryTurnStatus.interrupted,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final turn = viewModel.conversationTurns.singleWhere(
        (turn) => turn.id == 'turn-1',
      );
      expect(turn.status, AgentHistoryTurnStatus.interrupted);
      final systemTexts = viewModel.timelineEntries
          .whereType<AgentMessageTimelineEntry>()
          .map((entry) => entry.message.text)
          .where((text) => text.contains('Turn failed'))
          .toList();
      expect(systemTexts, isEmpty);
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

    test('offers compact when context window usage is high', () async {
      final provider = _FakeAgentProvider(
        historySnapshot: AgentThreadHistorySnapshot(
          threadId: 'thread-1',
          turns: <AgentHistoryTurn>[
            AgentHistoryTurn(
              id: 'turn-1',
              status: AgentHistoryTurnStatus.completed,
              tokenUsage: const AgentTokenUsage(
                totalTokens: 900,
                modelContextWindow: 1000,
              ),
              entries: const <AgentHistoryEntry>[
                AgentHistoryMessageEntry(
                  id: 'user-1',
                  role: AgentMessageRole.user,
                  text: 'hello',
                ),
              ],
            ),
          ],
        ),
      );
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.switchThread(
        AgentThreadSummary(
          id: 'thread-1',
          providerId: defaultAgentProviderId,
          projectPath: '/repo',
          preview: 'hello',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          status: AgentThreadRuntimeStatus.idle,
        ),
      );

      expect(viewModel.contextWindowUsageRatio, closeTo(0.9, 0.001));
      expect(viewModel.shouldOfferContextCompact, isTrue);
      expect(viewModel.canEditLastUserMessage, isTrue);

      await viewModel.compactCurrentThread();
      expect(provider.calls, contains('compact:thread-1'));
      expect(viewModel.isCompacting, isTrue);

      provider.emit(
        const AgentThreadCompactedEvent(threadId: 'thread-1', turnId: 'turn-1'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(viewModel.isCompacting, isFalse);
    });

    test('edit last user message rolls back then resends', () async {
      final provider =
          _FakeAgentProvider(
              historySnapshot: AgentThreadHistorySnapshot(
                threadId: 'thread-1',
                turns: <AgentHistoryTurn>[
                  const AgentHistoryTurn(
                    id: 'turn-1',
                    status: AgentHistoryTurnStatus.completed,
                    entries: <AgentHistoryEntry>[
                      AgentHistoryMessageEntry(
                        id: 'user-1',
                        role: AgentMessageRole.user,
                        text: 'old prompt',
                      ),
                    ],
                  ),
                ],
              ),
            )
            ..rollbackResult = const AgentThreadHistorySnapshot(
              threadId: 'thread-1',
              turns: <AgentHistoryTurn>[],
            );
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.switchThread(
        AgentThreadSummary(
          id: 'thread-1',
          providerId: defaultAgentProviderId,
          projectPath: '/repo',
          preview: 'old prompt',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          status: AgentThreadRuntimeStatus.idle,
        ),
      );
      await viewModel.editLastUserMessageAndRetry('new prompt');

      expect(provider.calls, contains('rollback:thread-1:1'));
      expect(provider.calls, contains('send:thread-1'));
    });

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

class _FakeAgentProvider
    with AgentProviderThreadLifecycleStub
    implements AgentProvider {
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
  final List<String> unsubscribedThreads = <String>[];
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
  void updatePermissionSelection(AgentPermissionSelection selection) {}

  @override
  Future<List<AgentPermissionProfileSummary>> listPermissionProfiles() async {
    return const <AgentPermissionProfileSummary>[];
  }

  @override
  Future<void> approveGuardianDeniedAction({
    required String threadId,
    required Object event,
  }) async {}

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
  Future<void> unsubscribeThread(String threadId) async {
    calls.add('unsubscribe:$threadId');
    unsubscribedThreads.add(threadId);
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
    required AgentContext context,
    String? message,
    List<AgentUserInput>? inputs,
    String? clientUserMessageId,
  }) async {
    final resolved =
        inputs ?? <AgentUserInput>[AgentUserInput.text(message ?? '')];
    calls.add('send:${session.id}');
    for (final input in resolved) {
      if (input is AgentLocalImageUserInput) {
        calls.add('image:${input.path}');
      }
    }
    return AgentTurn(id: 'turn-1', sessionId: session.id);
  }

  @override
  Future<void> steerTurn({
    required AgentSession session,
    required AgentContext context,
    String? message,
    List<AgentUserInput>? inputs,
    String? clientUserMessageId,
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
  Future<AgentThreadHistorySnapshot> rollbackThread({
    required String threadId,
    required int numTurns,
  }) async {
    calls.add('rollback:$threadId:$numTurns');
    return super.rollbackThread(threadId: threadId, numTurns: numTurns);
  }

  @override
  Future<AgentSession> forkThread({
    required String threadId,
    required AgentContext context,
  }) async {
    calls.add('fork:$threadId');
    return super.forkThread(threadId: threadId, context: context);
  }

  @override
  Future<void> compactThread(String threadId) async {
    calls.add('compact:$threadId');
    return super.compactThread(threadId);
  }

  @override
  Future<void> dispose() async {
    await _events.close();
  }

  void emit(AgentEvent event) {
    _events.add(event);
  }
}

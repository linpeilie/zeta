import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_timeline_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  group('AgentConversationTimelineStore', () {
    test('pages historical turns into a visible window of 3', () {
      final store = AgentConversationTimelineStore();
      addTearDown(store.dispose);

      store.applyHistorySnapshot(
        AgentThreadHistorySnapshot(
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
        _thread(),
      );

      expect(store.hasOlderTurns, isTrue);
      expect(
        store.visibleHistoryTurns.map((turn) => turn.id).toList(),
        <String>['turn-3', 'turn-4', 'turn-5'],
      );
      expect(store.conversationTurns.map((turn) => turn.id).toList(), <String>[
        'turn-3',
        'turn-4',
        'turn-5',
      ]);

      expect(store.loadOlderTurns(), isTrue);
      expect(store.hasOlderTurns, isFalse);
      expect(store.conversationTurns.map((turn) => turn.id).toList(), <String>[
        'turn-1',
        'turn-2',
        'turn-3',
        'turn-4',
        'turn-5',
      ]);
    });

    test('stores session total and per-turn token deltas', () {
      final store = AgentConversationTimelineStore();
      addTearDown(store.dispose);

      store.applyHistorySnapshot(
        const AgentThreadHistorySnapshot(
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
              // 历史里的 total 是会话累计；首个 turn 的增量等于累计本身。
              tokenUsage: AgentTokenUsage(
                inputTokens: 2000,
                cachedInputTokens: 500,
                outputTokens: 330,
                totalTokens: 2250,
                lastInputTokens: 800,
                lastCachedInputTokens: 150,
                lastOutputTokens: 240,
                lastTotalTokens: 1040,
                modelContextWindow: 4000,
              ),
            ),
          ],
        ),
        _thread(),
      );

      expect(store.currentThreadTokenUsage, isNotNull);
      expect(store.currentThreadTokenUsage!.totalTokens, 2250);
      expect(store.conversationTurns.single.tokenUsage!.totalTokens, 2250);

      store.startPendingLiveTurn();
      store.addConversationMessage(
        const AgentConversationMessage(
          id: 'user-live',
          role: AgentMessageRole.user,
          text: 'hello',
        ),
      );
      store.beginLiveTurnGroup(
        const AgentTurn(id: 'turn-live', sessionId: 'thread-1'),
      );
      store.updateTurnTokenUsage(
        const AgentTokenUsageEvent(
          sessionId: 'thread-1',
          turnId: 'turn-live',
          // Codex 上报的是整个会话累计，不是本 turn 成本。
          tokenUsage: AgentTokenUsage(
            inputTokens: 3000,
            cachedInputTokens: 700,
            outputTokens: 680,
            totalTokens: 3550,
            lastInputTokens: 920,
            lastCachedInputTokens: 180,
            lastOutputTokens: 320,
            lastTotalTokens: 1240,
            modelContextWindow: 2000,
          ),
        ),
      );
      store.syncLiveTurnBinding();

      expect(store.liveTurnState, isNotNull);
      expect(store.currentTurnTokenUsage, isNotNull);
      expect(store.currentTurnTokenUsage!.inputTokens, 1000);
      expect(store.currentTurnTokenUsage!.cachedInputTokens, 200);
      expect(store.currentTurnTokenUsage!.outputTokens, 350);
      expect(store.currentTurnTokenUsage!.totalTokens, 1300);
      expect(store.currentThreadTokenUsage, isNotNull);
      expect(store.currentThreadTokenUsage!.inputTokens, 3000);
      expect(store.currentThreadTokenUsage!.cachedInputTokens, 700);
      expect(store.currentThreadTokenUsage!.outputTokens, 680);
      expect(store.currentThreadTokenUsage!.totalTokens, 3550);
      expect(store.currentThreadLastTokenUsage, isNotNull);
      expect(store.currentThreadLastTokenUsage!.inputTokens, 920);
      expect(store.currentThreadLastTokenUsage!.cachedInputTokens, 180);
      expect(store.currentThreadLastTokenUsage!.outputTokens, 320);
      expect(store.currentThreadLastTokenUsage!.totalTokens, 1240);
      expect(store.currentThreadLastTokenUsage!.modelContextWindow, 2000);

      store.completeLiveTurnGroup('turn-live');
      store.syncLiveTurnBinding();

      expect(store.liveTurnState, isNull);
      expect(store.currentTurnTokenUsage, isNull);
      expect(store.currentThreadTokenUsage!.totalTokens, 3550);
      expect(store.currentThreadLastTokenUsage!.totalTokens, 1240);
    });

    test('stamps tool startedAt, tracks activity phase, freezes duration', () {
      final store = AgentConversationTimelineStore();
      addTearDown(store.dispose);

      store.startPendingLiveTurn();
      expect(store.currentActivity.phase, AgentTurnActivityPhase.starting);
      expect(store.currentTurnStartedAt, isNotNull);
      expect(store.takeActivityDirty(), isTrue);

      store.appendReasoningDelta(
        const AgentReasoningDeltaEvent(
          itemId: 'think-1',
          kind: AgentReasoningDeltaKind.summaryText,
          delta: 'planning',
        ),
      );
      expect(store.currentActivity.phase, AgentTurnActivityPhase.thinking);
      final think = store.toolCalls.singleWhere((t) => t.id == 'think-1');
      expect(think.startedAt, isNotNull);
      expect(think.duration, isNull);
      expect(store.takeActivityDirty(), isTrue);

      store.upsertToolCall(
        const AgentToolCall(
          id: 'cmd-1',
          title: 'git status',
          kind: AgentToolKind.execute,
          status: AgentToolStatus.inProgress,
        ),
      );
      expect(store.currentActivity.phase, AgentTurnActivityPhase.toolRunning);
      expect(store.currentActivity.label, 'git status');
      final cmd = store.toolCalls.singleWhere((t) => t.id == 'cmd-1');
      expect(cmd.startedAt, isNotNull);
      final cmdStartedAt = cmd.startedAt!;

      store.upsertToolCall(
        const AgentToolCall(
          id: 'cmd-1',
          title: 'git status',
          kind: AgentToolKind.execute,
          status: AgentToolStatus.completed,
          content: 'ok',
        ),
      );
      final completedCmd = store.toolCalls.singleWhere((t) => t.id == 'cmd-1');
      expect(completedCmd.startedAt, cmdStartedAt);
      expect(completedCmd.duration, isNotNull);
      expect(completedCmd.duration!.inMilliseconds, greaterThanOrEqualTo(0));

      final turnId = store.selectedRunningTurnId!;
      store.completeLiveTurnGroup(turnId);
      expect(store.currentActivity.phase, AgentTurnActivityPhase.idle);
      expect(store.isTurnRunning, isFalse);
      final frozenThink = store.toolCalls.singleWhere((t) => t.id == 'think-1');
      expect(frozenThink.duration, isNotNull);
    });

    test('converts cumulative history token usage into per-turn deltas', () {
      final store = AgentConversationTimelineStore();
      addTearDown(store.dispose);

      store.applyHistorySnapshot(
        const AgentThreadHistorySnapshot(
          threadId: 'thread-1',
          turns: <AgentHistoryTurn>[
            AgentHistoryTurn(
              id: 'turn-a',
              entries: <AgentHistoryEntry>[
                AgentHistoryMessageEntry(
                  id: 'user-a',
                  role: AgentMessageRole.user,
                  text: 'First',
                ),
              ],
              tokenUsage: AgentTokenUsage(
                inputTokens: 2000,
                cachedInputTokens: 500,
                outputTokens: 330,
                totalTokens: 2250,
              ),
            ),
            AgentHistoryTurn(
              id: 'turn-b',
              entries: <AgentHistoryEntry>[
                AgentHistoryMessageEntry(
                  id: 'user-b',
                  role: AgentMessageRole.user,
                  text: 'Second',
                ),
              ],
              tokenUsage: AgentTokenUsage(
                inputTokens: 3000,
                cachedInputTokens: 700,
                outputTokens: 680,
                totalTokens: 3550,
              ),
            ),
          ],
        ),
        _thread(),
      );

      final turns = store.conversationTurns;
      expect(turns, hasLength(2));
      expect(turns[0].tokenUsage!.totalTokens, 2250);
      expect(turns[0].tokenUsage!.inputTokens, 2000);
      expect(turns[1].tokenUsage!.totalTokens, 1300);
      expect(turns[1].tokenUsage!.inputTokens, 1000);
      expect(turns[1].tokenUsage!.cachedInputTokens, 200);
      expect(turns[1].tokenUsage!.outputTokens, 350);
      expect(store.currentThreadTokenUsage!.totalTokens, 3550);
      expect(store.currentThreadTokenUsage!.inputTokens, 3000);
    });

    test('keeps Grok per-turn absolute usage without cumulative delta', () {
      final store = AgentConversationTimelineStore();
      addTearDown(store.dispose);

      store.applyHistorySnapshot(
        const AgentThreadHistorySnapshot(
          threadId: 'thread-1',
          turns: <AgentHistoryTurn>[
            AgentHistoryTurn(
              id: 'turn-a',
              entries: <AgentHistoryEntry>[
                AgentHistoryMessageEntry(
                  id: 'user-a',
                  role: AgentMessageRole.user,
                  text: 'First',
                ),
              ],
              duration: Duration(seconds: 12),
              tokenUsage: AgentTokenUsage(
                inputTokens: 500,
                outputTokens: 50,
                totalTokens: 550,
              ),
              tokenUsageIsSessionCumulative: false,
            ),
            AgentHistoryTurn(
              id: 'turn-b',
              entries: <AgentHistoryEntry>[
                AgentHistoryMessageEntry(
                  id: 'user-b',
                  role: AgentMessageRole.user,
                  text: 'Second',
                ),
              ],
              duration: Duration(milliseconds: 4500),
              tokenUsage: AgentTokenUsage(
                inputTokens: 200,
                outputTokens: 30,
                totalTokens: 230,
              ),
              tokenUsageIsSessionCumulative: false,
            ),
          ],
        ),
        _thread(),
      );

      final turns = store.conversationTurns;
      expect(turns, hasLength(2));
      // 不得相对上一 turn 做差分（230 不能被 550 减成 0）。
      expect(turns[0].tokenUsage!.totalTokens, 550);
      expect(turns[1].tokenUsage!.totalTokens, 230);
      expect(turns[0].duration, const Duration(seconds: 12));
      expect(turns[1].duration, const Duration(milliseconds: 4500));
      expect(store.currentThreadTokenUsage!.totalTokens, 780);
    });

    test(
      'applies turn-absolute usage after complete without demoting history',
      () {
        final store = AgentConversationTimelineStore();
        addTearDown(store.dispose);

        store.startPendingLiveTurn();
        store.beginLiveTurnGroup(
          const AgentTurn(id: 'turn-live', sessionId: 'thread-1'),
        );
        store.addConversationMessage(
          const AgentConversationMessage(
            id: 'user-1',
            role: AgentMessageRole.user,
            text: 'hello',
          ),
        );
        store.completeLiveTurnGroup(
          'turn-live',
          duration: const Duration(seconds: 3),
        );
        store.syncLiveTurnBinding();
        expect(store.liveTurnState, isNull);
        expect(store.isHistoryTurnId('turn-live'), isTrue);

        store.updateTurnTokenUsage(
          const AgentTokenUsageEvent(
            sessionId: 'thread-1',
            turnId: 'turn-live',
            isSessionCumulative: false,
            tokenUsage: AgentTokenUsage(
              inputTokens: 80,
              outputTokens: 20,
              totalTokens: 100,
            ),
          ),
        );

        final completed = store.conversationTurns.singleWhere(
          (turn) => turn.id == 'turn-live',
        );
        expect(completed.tokenUsage!.totalTokens, 100);
        expect(completed.duration, const Duration(seconds: 3));
        expect(store.isHistoryTurnId('turn-live'), isTrue);
        expect(store.isLiveTurnId('turn-live'), isFalse);
        expect(store.currentThreadTokenUsage!.totalTokens, 100);
      },
    );

    test('removePermissionRequest drops pending card and timeline entry', () {
      final store = AgentConversationTimelineStore();
      addTearDown(store.dispose);

      store.startPendingLiveTurn();
      store.beginLiveTurnGroup(
        const AgentTurn(id: 'turn-1', sessionId: 'thread-1'),
      );
      store.addPermissionRequest(
        const AgentPermissionRequest(
          id: 'approval-1',
          title: 'Run command',
          kind: AgentPermissionKind.commandExecution,
          command: 'flutter test',
          sessionId: 'thread-1',
          turnId: 'turn-1',
        ),
      );

      expect(store.permissionRequests, hasLength(1));
      expect(
        store.timelineEntries.whereType<AgentPermissionTimelineEntry>(),
        hasLength(1),
      );

      store.removePermissionRequest('approval-1');

      expect(store.permissionRequests, isEmpty);
      expect(
        store.timelineEntries.whereType<AgentPermissionTimelineEntry>(),
        isEmpty,
      );
    });

    test('appends MCP tool progress onto existing tool card content', () {
      final store = AgentConversationTimelineStore();
      addTearDown(store.dispose);

      store.startPendingLiveTurn();
      store.beginLiveTurnGroup(
        const AgentTurn(id: 'turn-1', sessionId: 'thread-1'),
      );
      store.upsertToolCall(
        const AgentToolCall(
          id: 'mcp-1',
          title: 'MCP · docs · search',
          kind: AgentToolKind.search,
          status: AgentToolStatus.inProgress,
          content: 'query: zeta',
          sessionId: 'thread-1',
          turnId: 'turn-1',
        ),
      );
      store.upsertToolCall(
        const AgentToolCall(
          id: 'mcp-1',
          title: 'MCP tool',
          kind: AgentToolKind.other,
          status: AgentToolStatus.inProgress,
          content: 'Fetching resources…',
          sessionId: 'thread-1',
          turnId: 'turn-1',
          raw: <String, Object?>{'_progressAppend': true},
        ),
      );
      store.upsertToolCall(
        const AgentToolCall(
          id: 'mcp-1',
          title: 'MCP tool',
          kind: AgentToolKind.other,
          status: AgentToolStatus.inProgress,
          content: 'Parsing results…',
          sessionId: 'thread-1',
          turnId: 'turn-1',
          raw: <String, Object?>{'_progressAppend': true},
        ),
      );

      final tool = store.toolCalls.single;
      expect(tool.title, 'MCP · docs · search');
      expect(tool.kind, AgentToolKind.search);
      expect(
        tool.content,
        'query: zeta\nFetching resources…\nParsing results…',
      );
      expect(store.isToolCallExpanded('mcp-1'), isTrue);
    });

    test(
      'dismisses welcome message once real conversation content arrives',
      () {
        final store = AgentConversationTimelineStore();
        addTearDown(store.dispose);

        expect(
          store.messages.map((message) => message.id),
          contains(AgentConversationTimelineStore.welcomeMessage.id),
        );

        store.startPendingLiveTurn();
        store.addConversationMessage(
          const AgentConversationMessage(
            id: 'user-1',
            role: AgentMessageRole.user,
            text: 'hello',
          ),
        );
        store.syncLiveTurnBinding();

        expect(
          store.messages.map((message) => message.id),
          isNot(contains(AgentConversationTimelineStore.welcomeMessage.id)),
        );
        expect(
          store.conversationTurns.map((turn) => turn.id).toList(),
          isNot(contains(AgentConversationTimelineStore.standbyTurnId)),
        );
        expect(store.conversationTurns, hasLength(1));
        expect(store.conversationTurns.single.isStandby, isFalse);
      },
    );

    test('replaces same-id timeline entries instead of duplicating them', () {
      final store = AgentConversationTimelineStore();
      addTearDown(store.dispose);

      store.startPendingLiveTurn();
      store.beginLiveTurnGroup(
        const AgentTurn(id: 'turn-1', sessionId: 'thread-1'),
      );
      store.addConversationMessage(
        const AgentConversationMessage(
          id: 'error-same',
          role: AgentMessageRole.system,
          text: 'first',
        ),
      );
      store.addConversationMessage(
        const AgentConversationMessage(
          id: 'error-same',
          role: AgentMessageRole.system,
          text: 'second',
        ),
      );
      store.syncLiveTurnBinding();

      final errorEntries = store.timelineEntries
          .whereType<AgentMessageTimelineEntry>()
          .where((entry) => entry.message.id == 'error-same')
          .toList();
      expect(errorEntries, hasLength(1));
      expect(errorEntries.single.message.text, 'second');
      expect(store.liveTurnState!.entries, hasLength(1));
    });
  });
}

AgentThreadSummary _thread() {
  return AgentThreadSummary(
    id: 'thread-1',
    providerId: defaultAgentProviderId,
    projectPath: '/repo',
    title: 'Thread one',
    sessionPath: '/repo/thread-1.jsonl',
    preview: 'Thread one',
    createdAt: DateTime.fromMillisecondsSinceEpoch(1),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(2),
    status: AgentThreadRuntimeStatus.idle,
  );
}

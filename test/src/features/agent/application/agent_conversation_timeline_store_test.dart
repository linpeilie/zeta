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

    test('aggregates token usage across history and live turns', () {
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
          tokenUsage: AgentTokenUsage(
            inputTokens: 1000,
            cachedInputTokens: 200,
            outputTokens: 350,
            totalTokens: 1300,
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

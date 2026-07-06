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
                outputTokens: 250,
                reasoningOutputTokens: 80,
                totalTokens: 2250,
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
            outputTokens: 300,
            reasoningOutputTokens: 50,
            totalTokens: 1300,
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
      expect(store.currentThreadTokenUsage!.outputTokens, 550);
      expect(store.currentThreadTokenUsage!.reasoningOutputTokens, 130);
      expect(store.currentThreadTokenUsage!.totalTokens, 3550);

      store.completeLiveTurnGroup('turn-live');
      store.syncLiveTurnBinding();

      expect(store.liveTurnState, isNull);
      expect(store.currentTurnTokenUsage, isNull);
      expect(store.currentThreadTokenUsage!.totalTokens, 3550);
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

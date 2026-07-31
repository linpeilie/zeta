import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_timeline_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  group('AgentConversationTimelineStore history batch', () {
    test('applyHistorySnapshot defers live binding until end', () {
      final store = AgentConversationTimelineStore();
      var liveNotifyCount = 0;
      store.liveTurnListenable.addListener(() {
        liveNotifyCount += 1;
      });

      final now = DateTime.utc(2026, 1, 1);
      store.applyHistorySnapshot(
        AgentThreadHistorySnapshot(
          threadId: 'thread-1',
          turns: <AgentHistoryTurn>[
            AgentHistoryTurn(
              id: 'turn-1',
              status: AgentHistoryTurnStatus.completed,
              entries: <AgentHistoryEntry>[
                const AgentHistoryMessageEntry(
                  id: 'm1',
                  role: AgentMessageRole.user,
                  text: 'hi',
                ),
                const AgentHistoryMessageEntry(
                  id: 'm2',
                  role: AgentMessageRole.agent,
                  text: 'hello',
                ),
              ],
            ),
            AgentHistoryTurn(
              id: 'turn-2',
              status: AgentHistoryTurnStatus.running,
              entries: <AgentHistoryEntry>[
                const AgentHistoryMessageEntry(
                  id: 'm3',
                  role: AgentMessageRole.agent,
                  text: 'streaming',
                ),
              ],
            ),
          ],
        ),
        AgentThreadSummary(
          id: 'thread-1',
          title: 't',
          providerId: 'codex',
          projectPath: '/tmp',
          preview: 'p',
          createdAt: now,
          updatedAt: now,
          status: AgentThreadRuntimeStatus.idle,
        ),
      );

      expect(store.isHistoryBatching, isFalse);
      // 历史中的 running 不升为 live；仅作 historical 未完结 turn。
      expect(store.liveTurnState, isNull);
      expect(store.isTurnRunning, isFalse);
      expect(
        store.visibleHistoryTurns.map((turn) => turn.id),
        contains('turn-2'),
      );
      // clear + final bind：允许有限次数，但绝非每个 entry 一次。
      expect(liveNotifyCount, lessThanOrEqualTo(3));
      expect(store.messages.where((m) => m.id == 'm2').length, 1);
    });

    test('nested begin/end history batch', () {
      final store = AgentConversationTimelineStore();
      store.beginHistoryBatch();
      store.beginHistoryBatch();
      expect(store.isHistoryBatching, isTrue);
      store.endHistoryBatch();
      expect(store.isHistoryBatching, isTrue);
      store.endHistoryBatch();
      expect(store.isHistoryBatching, isFalse);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

void main() {
  group('DefaultAgentTurnContextRecorder', () {
    test('upserts start then complete and ignores later null fields', () async {
      final store = MemoryAgentTurnContextStore();
      final recorder = DefaultAgentTurnContextRecorder(
        store: store,
        now: () => DateTime.utc(2026, 8, 14, 16),
      );

      recorder.recordStarted(
        providerId: 'grok',
        event: AgentTurnStartedEvent.fromModelSelection(
          turn: const AgentTurn(id: 'turn-1', sessionId: 'sess-1'),
          selection: const AgentModelSelection(
            modelId: 'grok-4',
            reasoningEffort: 'high',
          ),
          startedAt: DateTime.utc(2026, 8, 14, 15),
        ),
      );
      await recorder.flush();
      recorder.recordStarted(
        providerId: 'grok',
        event: const AgentTurnStartedEvent(
          AgentTurn(id: 'turn-1', sessionId: 'sess-1'),
        ),
      );
      await recorder.flush();
      recorder.recordCompleted(
        providerId: 'grok',
        event: const AgentTurnCompletedEvent(
          sessionId: 'sess-1',
          turnId: 'turn-1',
          status: AgentHistoryTurnStatus.completed,
          completedAt: null,
        ),
      );
      await recorder.flush();

      final loaded = await store.load(providerId: 'grok', threadId: 'sess-1');
      expect(loaded, isNotNull);
      final turn = loaded!.turns.single;
      expect(turn.modelId, 'grok-4');
      expect(turn.reasoningEffort, 'high');
      expect(turn.startedAt, DateTime.utc(2026, 8, 14, 15));
      expect(turn.completedAt, DateTime.utc(2026, 8, 14, 16));
      expect(turn.status, AgentHistoryTurnStatus.completed);
    });

    test('swallows store failures', () async {
      final recorder = DefaultAgentTurnContextRecorder(
        store: _ThrowingTurnContextStore(),
      );

      recorder.recordStarted(
        providerId: 'codex',
        event: const AgentTurnStartedEvent(
          AgentTurn(id: 'turn-1', sessionId: 'thread-1'),
          modelId: 'gpt',
        ),
      );
      await recorder.flush();
    });
  });
}

final class _ThrowingTurnContextStore implements AgentTurnContextStore {
  @override
  Future<AgentThreadTurnContext?> load({
    required String providerId,
    required String threadId,
  }) async {
    throw StateError('disk failed');
  }

  @override
  Future<void> save(AgentThreadTurnContext context) {
    throw StateError('disk failed');
  }
}

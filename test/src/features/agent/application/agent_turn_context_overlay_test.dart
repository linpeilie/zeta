import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_turn_context_overlay.dart';
import 'package:zeta/src/features/agent/domain/agent_turn_context_models.dart';
import 'package:zeta/src/features/agent/domain/agent_turn_history_models.dart';

void main() {
  group('overlayThreadTurnContext', () {
    const snapshot = AgentThreadHistorySnapshot(
      threadId: 'thread-1',
      turns: <AgentHistoryTurn>[
        AgentHistoryTurn(
          id: 'turn-1',
          modelId: 'provider-model',
          reasoningEffort: AgentHistoryReasoningEffort.unknown(),
        ),
        AgentHistoryTurn(
          id: 'turn-2',
          reasoningEffort: AgentHistoryReasoningEffort.explicit('low'),
        ),
      ],
      currentTurn: AgentHistoryTurn(
        id: 'turn-2',
        reasoningEffort: AgentHistoryReasoningEffort.explicit('low'),
      ),
    );

    test('returns the original snapshot when local context is missing', () {
      expect(overlayThreadTurnContext(snapshot, null), same(snapshot));
      expect(
        overlayThreadTurnContext(
          snapshot,
          const AgentThreadTurnContext(
            providerId: 'grok',
            threadId: 'thread-1',
          ),
        ),
        same(snapshot),
      );
    });

    test(
      'prefers Zeta effort and keeps provider values when Zeta is empty',
      () {
        final overlaid = overlayThreadTurnContext(
          snapshot,
          const AgentThreadTurnContext(
            providerId: 'grok',
            threadId: 'thread-1',
            turns: <AgentTurnContextRecord>[
              AgentTurnContextRecord(
                turnId: 'turn-1',
                modelId: 'zeta-model',
                reasoningEffort: 'high',
                startedAt: null,
              ),
              AgentTurnContextRecord(turnId: 'turn-2'),
              AgentTurnContextRecord(turnId: 'turn-missing'),
            ],
          ),
        );

        expect(overlaid.turns, hasLength(2));
        expect(overlaid.turns[0].modelId, 'zeta-model');
        expect(overlaid.turns[0].reasoningEffort.value, 'high');
        expect(overlaid.turns[0].reasoningEffort.isKnown, isTrue);
        expect(overlaid.turns[1].reasoningEffort.value, 'low');
        expect(overlaid.currentTurn?.id, 'turn-2');
        expect(
          overlaid.turns.map((turn) => turn.id),
          isNot(contains('turn-missing')),
        );
      },
    );
  });
}

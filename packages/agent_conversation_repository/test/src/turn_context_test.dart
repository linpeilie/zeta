import 'package:agent_conversation_repository/src/turn_context.dart';
import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:clock/clock.dart';
import 'package:test/test.dart';
import 'package:zeta_logging/zeta_logging.dart';

import 'test_fakes.dart';

void main() {
  test('overlay uses exact ids and preserves current-turn identity', () {
    final history = AgentThreadHistorySnapshot(
      threadId: 'thread',
      turns: <AgentHistoryTurn>[
        AgentHistoryTurn(
          id: 'turn',
          modelId: 'old',
          status: AgentHistoryTurnStatus.running,
        ),
      ],
      currentTurn: AgentHistoryTurn(id: 'turn'),
    );
    final local = AgentThreadTurnContext(
      providerId: 'provider',
      threadId: 'thread',
      turns: <AgentTurnContextRecord>[
        AgentTurnContextRecord(
          turnId: 'turn',
          modelId: 'new',
          reasoningEffort: 'high',
          serviceTierId: 'priority',
          explicitFast: true,
          startedAt: DateTime.utc(2026),
          completedAt: DateTime.utc(2026, 1, 1, 0, 0, 1),
          status: AgentHistoryTurnStatus.completed,
        ),
      ],
    );

    final result = overlayTurnContext(history, local);

    expect(result.turns.single.modelId, 'new');
    expect(result.turns.single.reasoningEffort.value, 'high');
    expect(result.turns.single.serviceTierId, 'priority');
    expect(result.turns.single.explicitFast, isTrue);
    expect(result.turns.single.status, AgentHistoryTurnStatus.completed);
    expect(result.currentTurn, same(result.turns.single));
    expect(overlayTurnContext(history, null), same(history));
    expect(
      overlayTurnContext(
        history,
        AgentThreadTurnContext(providerId: 'provider', threadId: 'thread'),
      ),
      same(history),
    );
  });

  test('overlay time fallback is reciprocal, bounded and fail-closed', () {
    final time = DateTime.utc(2026);
    final history = AgentThreadHistorySnapshot(
      threadId: 'thread',
      turns: <AgentHistoryTurn>[
        AgentHistoryTurn(id: 'history-1', startedAt: time),
        AgentHistoryTurn(
          id: 'history-2',
          startedAt: time.add(const Duration(seconds: 20)),
        ),
      ],
    );
    final local = AgentThreadTurnContext(
      providerId: 'provider',
      threadId: 'thread',
      turns: <AgentTurnContextRecord>[
        AgentTurnContextRecord(
          turnId: 'local',
          modelId: 'matched',
          completedAt: time.add(const Duration(seconds: 1)),
        ),
        AgentTurnContextRecord(
          turnId: 'far',
          modelId: 'far',
          startedAt: time.add(const Duration(minutes: 1)),
        ),
      ],
    );

    final result = overlayTurnContext(history, local);
    expect(result.turns.first.modelId, 'matched');
    expect(result.turns.last.modelId, isNull);

    final ambiguous = overlayTurnContext(
      AgentThreadHistorySnapshot(
        threadId: 'thread',
        turns: <AgentHistoryTurn>[
          AgentHistoryTurn(id: 'history', startedAt: time),
        ],
      ),
      AgentThreadTurnContext(
        providerId: 'provider',
        threadId: 'thread',
        turns: <AgentTurnContextRecord>[
          AgentTurnContextRecord(
            turnId: 'left',
            modelId: 'left',
            startedAt: time.subtract(const Duration(seconds: 1)),
          ),
          AgentTurnContextRecord(
            turnId: 'right',
            modelId: 'right',
            startedAt: time.add(const Duration(seconds: 1)),
          ),
        ],
      ),
    );
    expect(ambiguous.turns.single.modelId, isNull);
  });

  test(
    'recorder serializes start/completion and fills missing timestamps',
    () async {
      final store = TestTurnContextStore();
      final now = DateTime.utc(2026);
      final recorder = TurnContextRecorder(
        store: store,
        logger: loggerFor('turn-context-test'),
        clock: Clock.fixed(now),
      );
      await (recorder
            ..recordStarted(
              providerId: 'provider',
              event: AgentTurnStartedEvent(
                AgentTurn(id: 'turn', sessionId: 'thread'),
                modelId: 'model',
              ),
            )
            ..recordCompleted(
              providerId: 'provider',
              event: AgentTurnCompletedEvent(
                sessionId: 'thread',
                turnId: 'turn',
              ),
            ))
          .flush();

      final value = store.values['provider\u0000thread']!.turns.single;
      expect(value.modelId, 'model');
      expect(value.startedAt, now);
      expect(value.completedAt, now);
      expect(value.status, AgentHistoryTurnStatus.completed);
      expect(store.saveCalls, 2);
    },
  );

  test(
    'recorder drops invalid identities and contains persistence failures',
    () async {
      final store = TestTurnContextStore()..saveError = Exception('disk');
      final recorder = TurnContextRecorder(
        store: store,
        logger: loggerFor('turn-context-failure-test'),
      );
      await (recorder
            ..recordStarted(
              providerId: '',
              event: AgentTurnStartedEvent(
                AgentTurn(id: '', sessionId: ''),
              ),
            )
            ..recordCompleted(
              providerId: 'provider',
              event: AgentTurnCompletedEvent(
                sessionId: 'thread',
                turnId: 'turn',
              ),
            ))
          .flush();
      expect(store.saveCalls, 1);
    },
  );
}

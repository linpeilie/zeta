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

    test(
      'matches leftover local turns by startedAt within the time window',
      () {
        final t1 = DateTime.utc(2026, 8, 16, 9, 31, 34, 219);
        final t2 = DateTime.utc(2026, 8, 16, 9, 36, 21, 428);
        final history = AgentThreadHistorySnapshot(
          threadId: '01a009e9-7d7f-7460-907c-746773547a55',
          turns: <AgentHistoryTurn>[
            AgentHistoryTurn(
              id: '6ffeee79-94a9-4d61-b67c-450fbba8b238',
              modelId: 'grok-4.6',
              startedAt: t1.add(const Duration(milliseconds: 80)),
            ),
            AgentHistoryTurn(
              id: 'ca739d8c-51e6-4b43-8176-ac076d056702',
              modelId: 'grok-4.6',
              startedAt: t2.add(const Duration(milliseconds: 40)),
            ),
          ],
        );

        final overlaid = overlayThreadTurnContext(
          history,
          AgentThreadTurnContext(
            providerId: 'grok',
            threadId: '01a009e9-7d7f-7460-907c-746773547a55',
            turns: <AgentTurnContextRecord>[
              AgentTurnContextRecord(
                turnId: 'grok-turn-1786872694215-c20dc',
                modelId: 'grok-4.6',
                reasoningEffort: 'xhigh',
                startedAt: t1,
              ),
              AgentTurnContextRecord(
                turnId: 'grok-turn-1786872981428-bf5cf',
                modelId: 'grok-4.6',
                reasoningEffort: 'xhigh',
                startedAt: t2,
              ),
            ],
          ),
        );

        expect(overlaid.turns[0].id, '6ffeee79-94a9-4d61-b67c-450fbba8b238');
        expect(overlaid.turns[0].reasoningEffort.value, 'xhigh');
        expect(overlaid.turns[0].reasoningEffort.isKnown, isTrue);
        expect(overlaid.turns[1].reasoningEffort.value, 'xhigh');
      },
    );

    test(
      'does not time-match when the nearest local is outside the window',
      () {
        final startedAt = DateTime.utc(2026, 8, 16, 9, 31, 34);
        final overlaid = overlayThreadTurnContext(
          AgentThreadHistorySnapshot(
            threadId: 'thread-1',
            turns: <AgentHistoryTurn>[
              AgentHistoryTurn(
                id: 'prompt-1',
                startedAt: startedAt.add(const Duration(seconds: 6)),
              ),
            ],
          ),
          AgentThreadTurnContext(
            providerId: 'grok',
            threadId: 'thread-1',
            turns: <AgentTurnContextRecord>[
              AgentTurnContextRecord(
                turnId: 'grok-turn-local',
                reasoningEffort: 'xhigh',
                startedAt: startedAt,
              ),
            ],
          ),
        );

        expect(overlaid.turns.single.reasoningEffort.isKnown, isFalse);
      },
    );

    test('does not time-match when two locals are equally close', () {
      final startedAt = DateTime.utc(2026, 8, 16, 9, 31, 34);
      final overlaid = overlayThreadTurnContext(
        AgentThreadHistorySnapshot(
          threadId: 'thread-1',
          turns: <AgentHistoryTurn>[
            AgentHistoryTurn(id: 'prompt-1', startedAt: startedAt),
          ],
        ),
        AgentThreadTurnContext(
          providerId: 'grok',
          threadId: 'thread-1',
          turns: <AgentTurnContextRecord>[
            AgentTurnContextRecord(
              turnId: 'grok-turn-a',
              reasoningEffort: 'high',
              startedAt: startedAt.subtract(const Duration(seconds: 1)),
            ),
            AgentTurnContextRecord(
              turnId: 'grok-turn-b',
              reasoningEffort: 'low',
              startedAt: startedAt.add(const Duration(seconds: 1)),
            ),
          ],
        ),
      );

      expect(overlaid.turns.single.reasoningEffort.isKnown, isFalse);
    });

    test('does not assign one local turn to two history turns', () {
      final startedAt = DateTime.utc(2026, 8, 16, 9, 31, 34);
      final overlaid = overlayThreadTurnContext(
        AgentThreadHistorySnapshot(
          threadId: 'thread-1',
          turns: <AgentHistoryTurn>[
            AgentHistoryTurn(id: 'prompt-1', startedAt: startedAt),
            AgentHistoryTurn(
              id: 'prompt-2',
              startedAt: startedAt.add(const Duration(seconds: 1)),
            ),
          ],
        ),
        AgentThreadTurnContext(
          providerId: 'grok',
          threadId: 'thread-1',
          turns: <AgentTurnContextRecord>[
            AgentTurnContextRecord(
              turnId: 'grok-turn-only',
              reasoningEffort: 'xhigh',
              startedAt: startedAt,
            ),
          ],
        ),
      );

      expect(overlaid.turns[0].reasoningEffort.value, 'xhigh');
      expect(overlaid.turns[1].reasoningEffort.isKnown, isFalse);
    });

    test('prefers exact turnId over a closer time neighbour', () {
      final startedAt = DateTime.utc(2026, 8, 16, 9, 31, 34);
      final overlaid = overlayThreadTurnContext(
        AgentThreadHistorySnapshot(
          threadId: 'thread-1',
          turns: <AgentHistoryTurn>[
            AgentHistoryTurn(id: 'turn-exact', startedAt: startedAt),
          ],
        ),
        AgentThreadTurnContext(
          providerId: 'codex',
          threadId: 'thread-1',
          turns: <AgentTurnContextRecord>[
            AgentTurnContextRecord(
              turnId: 'turn-exact',
              reasoningEffort: 'medium',
              startedAt: startedAt.add(const Duration(seconds: 3)),
            ),
            AgentTurnContextRecord(
              turnId: 'other-live-id',
              reasoningEffort: 'xhigh',
              startedAt: startedAt,
            ),
          ],
        ),
      );

      expect(overlaid.turns.single.reasoningEffort.value, 'medium');
    });
  });
}

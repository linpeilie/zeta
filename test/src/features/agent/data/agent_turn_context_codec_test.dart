import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/agent_turn_context_codec.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

void main() {
  group('tryDecodeAgentThreadTurnContext', () {
    test('decodes a versioned whitelist payload', () {
      final decoded = tryDecodeAgentThreadTurnContext(<String, Object?>{
        'version': 1,
        'providerId': 'grok',
        'threadId': 'sess-1',
        'turns': <Object?>[
          <String, Object?>{
            'turnId': 'turn-1',
            'modelId': 'grok-4',
            'reasoningEffort': 'high',
            'startedAt': '2026-08-14T15:51:00.000Z',
            'completedAt': '2026-08-14T15:52:10.000Z',
            'status': 'completed',
            'unknown': 'ignored',
          },
        ],
        'extra': true,
      });

      expect(decoded, isNotNull);
      expect(decoded!.providerId, 'grok');
      expect(decoded.threadId, 'sess-1');
      expect(decoded.turns, hasLength(1));
      final turn = decoded.turns.single;
      expect(turn.turnId, 'turn-1');
      expect(turn.modelId, 'grok-4');
      expect(turn.reasoningEffort, 'high');
      expect(turn.status, AgentHistoryTurnStatus.completed);
      expect(turn.startedAt, DateTime.utc(2026, 8, 14, 15, 51));
    });

    test('returns null for corrupt, unknown version, or missing ids', () {
      expect(tryDecodeAgentThreadTurnContext('{broken'), isNull);
      expect(
        tryDecodeAgentThreadTurnContext(<String, Object?>{
          'version': 2,
          'providerId': 'grok',
          'threadId': 'sess-1',
        }),
        isNull,
      );
      expect(
        tryDecodeAgentThreadTurnContext(<String, Object?>{
          'version': 1,
          'providerId': ' ',
          'threadId': 'sess-1',
        }),
        isNull,
      );
      expect(tryDecodeAgentThreadTurnContext(null), isNull);
    });

    test('skips damaged turns and missing turn lists', () {
      final decoded = tryDecodeAgentThreadTurnContext(<String, Object?>{
        'version': 1,
        'providerId': 'codex',
        'threadId': 'thread-1',
        'turns': <Object?>[
          <String, Object?>{'turnId': 'turn-1', 'modelId': 'gpt'},
          <String, Object?>{'modelId': 'missing-id'},
          42,
          <String, Object?>{'turnId': 'turn-1', 'modelId': 'duplicate'},
        ],
      });

      expect(decoded, isNotNull);
      expect(decoded!.turns, hasLength(1));
      expect(decoded.turns.single.modelId, 'gpt');
    });
  });

  group('encodeAgentThreadTurnContext', () {
    test('omits empty optional fields', () {
      final encoded = encodeAgentThreadTurnContext(
        const AgentThreadTurnContext(
          providerId: 'grok',
          threadId: 'sess-1',
          turns: <AgentTurnContextRecord>[
            AgentTurnContextRecord(turnId: 'turn-1', modelId: 'grok-4'),
          ],
        ),
      );

      expect(encoded.keys, <Object?>[
        'version',
        'providerId',
        'threadId',
        'turns',
      ]);
      final turn =
          (encoded['turns']! as List<Object?>).single as Map<String, Object?>;
      expect(turn.keys, <Object?>['turnId', 'modelId']);
    });
  });
}

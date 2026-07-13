import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/mappers/acp_content_codec.dart';
import 'package:zeta/src/features/agent/data/mappers/acp_permission_mapper.dart';
import 'package:zeta/src/features/agent/data/mappers/acp_session_update_mapper.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  group('AcpSessionUpdateMapper', () {
    const mapper = AcpSessionUpdateMapper();

    test('maps a standard ACP message fixture', () {
      final mapped = mapper.mapSessionUpdate(
        params: <String, Object?>{
          'sessionId': 'session-1',
          'update': <String, Object?>{
            'sessionUpdate': 'agent_message_chunk',
            'messageId': 'message-1',
            'content': <String, Object?>{
              'type': 'text',
              'text': 'Hello from ACP',
            },
          },
        },
        runningTurnId: 'turn-1',
      );

      final event = mapped.events.single as AgentMessageDeltaEvent;
      expect(event.messageId, 'message-1');
      expect(event.delta, 'Hello from ACP');
      expect(event.sessionId, 'session-1');
      expect(event.turnId, 'turn-1');
    });

    test('maps standard usage updates as session cumulative', () {
      final mapped = mapper.mapSessionUpdate(
        params: <String, Object?>{
          'sessionId': 'session-1',
          'update': <String, Object?>{
            'sessionUpdate': 'usage_update',
            'used': 2048,
          },
        },
        runningTurnId: 'turn-1',
      );

      final event = mapped.events.single as AgentTokenUsageEvent;
      expect(event.isSessionCumulative, isTrue);
      expect(event.tokenUsage.totalTokens, 2048);
    });
  });

  test('ACP content codec preserves text and resource blocks', () {
    final blocks = AcpContentCodec.buildPromptBlocks(
      inputs: const <AgentUserInput>[
        AgentTextUserInput('Review this file'),
        AgentMentionUserInput(name: 'main.dart', path: '/repo/lib/main.dart'),
      ],
      context: const AgentContext(),
    );

    expect(blocks.first, <String, Object?>{
      'type': 'text',
      'text': 'Review this file',
    });
    expect(blocks.last['type'], 'resource_link');
    expect(blocks.last['name'], 'main.dart');
  });

  test('ACP permission mapper keeps option ids separate from labels', () {
    final mapping = AcpPermissionMapper.mapRequest(
      requestId: 7,
      params: <String, Object?>{
        'sessionId': 'session-1',
        'toolCall': <String, Object?>{'title': 'Run tests', 'kind': 'execute'},
        'options': <Object?>[
          <String, Object?>{
            'optionId': 'allow-once',
            'name': 'Allow once',
            'kind': 'allow_once',
          },
          <String, Object?>{
            'optionId': 'reject-once',
            'name': 'Reject',
            'kind': 'reject_once',
          },
        ],
      },
      runningTurnId: 'turn-1',
    );

    expect(mapping.request.id, '7');
    expect(mapping.request.title, 'Run tests');
    expect(mapping.options.first.id, 'allow-once');
    expect(mapping.options.first.name, 'Allow once');
    expect(mapping.preferredOptionId(approved: true), 'allow-once');
    expect(mapping.preferredOptionId(approved: false), 'reject-once');
  });
}

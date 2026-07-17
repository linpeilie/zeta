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

    test('falls back to eventId when agent_message_chunk omits messageId', () {
      final mapped = mapper.mapSessionUpdate(
        params: <String, Object?>{
          'sessionId': 'session-1',
          'update': <String, Object?>{
            'sessionUpdate': 'agent_message_chunk',
            'content': <String, Object?>{'type': 'text', 'text': 'Chunk'},
            '_meta': <String, Object?>{'eventId': 'evt-42'},
          },
        },
        runningTurnId: 'turn-1',
      );

      final event = mapped.events.single as AgentMessageDeltaEvent;
      expect(event.messageId, 'acp-agent_message_chunk-event-evt-42');
      expect(event.delta, 'Chunk');
    });

    test('falls back to turn scope when messageId and eventId are absent', () {
      final mapped = mapper.mapSessionUpdate(
        params: <String, Object?>{
          'sessionId': 'session-1',
          'update': <String, Object?>{
            'sessionUpdate': 'agent_message_chunk',
            'content': <String, Object?>{'type': 'text', 'text': 'Hi'},
          },
        },
        runningTurnId: 'turn-1',
      );

      final event = mapped.events.single as AgentMessageDeltaEvent;
      expect(event.messageId, 'acp-agent_message_chunk-turn-1');
    });

    test(
      'aggregates agent_thought_chunk by turn even when eventIds differ',
      () {
        AgentReasoningDeltaEvent mapThought(String eventId, String text) {
          final mapped = mapper.mapSessionUpdate(
            params: <String, Object?>{
              'sessionId': 'session-1',
              'update': <String, Object?>{
                'sessionUpdate': 'agent_thought_chunk',
                'content': <String, Object?>{'type': 'text', 'text': text},
                '_meta': <String, Object?>{'eventId': eventId},
              },
            },
            runningTurnId: 'turn-1',
          );
          return mapped.events.single as AgentReasoningDeltaEvent;
        }

        final first = mapThought('evt-thought-1', 'Thinking a');
        final second = mapThought('evt-thought-2', ' and b');

        // 不同 eventId 必须落到同一 itemId，timeline 才能拼成一张思考卡。
        expect(first.itemId, 'acp-agent_thought_chunk-turn-1');
        expect(second.itemId, first.itemId);
        expect(first.delta, 'Thinking a');
        expect(second.delta, ' and b');
      },
    );

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

    test(
      'synthesizes tool title when Grok omits title and only sends call id',
      () {
        final mapped = mapper.mapSessionUpdate(
          params: <String, Object?>{
            'sessionId': 'session-1',
            'update': <String, Object?>{
              'sessionUpdate': 'tool_call',
              'toolCallId': 'call-abc123',
              'kind': 'read',
              'status': 'in_progress',
              'locations': <Object?>[
                <String, Object?>{'path': r'D:\repo\zeta\lib\src\app.dart'},
              ],
              'rawInput': <String, Object?>{
                'path': r'D:\repo\zeta\lib\src\app.dart',
              },
            },
          },
          runningTurnId: 'turn-1',
        );

        final tool = (mapped.events.single as AgentToolCallEvent).toolCall;
        expect(tool.id, 'call-abc123');
        expect(tool.title, isNot(contains('call-abc123')));
        expect(tool.title, '读取 · src/app.dart');
        expect(tool.displayTitle, '读取 · src/app.dart');
      },
    );

    test('keeps provider title when it is already human readable', () {
      final mapped = mapper.mapSessionUpdate(
        params: <String, Object?>{
          'sessionId': 'session-1',
          'update': <String, Object?>{
            'sessionUpdate': 'tool_call_update',
            'toolCallId': 'call-1',
            'title': 'Read file',
            'kind': 'Read',
            'status': 'Completed',
          },
        },
        runningTurnId: 'turn-1',
      );

      final tool = (mapped.events.single as AgentToolCallEvent).toolCall;
      expect(tool.title, 'Read file');
      expect(tool.kind, AgentToolKind.read);
      expect(tool.status, AgentToolStatus.completed);
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

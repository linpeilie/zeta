import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/datasources/acp/acp_session_replay_collector.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  group('AcpSessionReplayCollector', () {
    test('rebuilds ordered multi-turn messages and tool updates', () {
      // Arrange
      final collector = AcpSessionReplayCollector(threadId: 'session-1');

      // Act
      collector.record(
        _params(<String, Object?>{
          'sessionUpdate': 'user_message_chunk',
          'messageId': 'user-1',
          'content': <String, Object?>{'type': 'text', 'text': 'Hello'},
        }, promptId: 'turn-1'),
      );
      collector.record(
        _params(<String, Object?>{
          'sessionUpdate': 'agent_message_chunk',
          'messageId': 'agent-1',
          'content': <String, Object?>{'type': 'text', 'text': 'Hi '},
        }, promptId: 'turn-1'),
      );
      collector.record(
        _params(<String, Object?>{
          'sessionUpdate': 'agent_message_chunk',
          'messageId': 'agent-1',
          'content': <String, Object?>{'type': 'text', 'text': 'there'},
        }, promptId: 'turn-1'),
      );
      collector.record(
        _params(<String, Object?>{
          'sessionUpdate': 'tool_call',
          'toolCallId': 'tool-1',
          'title': 'Read file',
          'kind': 'read',
          'status': 'in_progress',
        }, promptId: 'turn-1'),
      );
      collector.record(
        _params(<String, Object?>{
          'sessionUpdate': 'tool_call_update',
          'toolCallId': 'tool-1',
          'title': 'Read file',
          'kind': 'read',
          'status': 'completed',
          'content': <Object?>[
            <String, Object?>{
              'type': 'content',
              'content': <String, Object?>{'type': 'text', 'text': 'file body'},
            },
          ],
        }, promptId: 'turn-1'),
      );
      collector.record(
        _params(<String, Object?>{
          'sessionUpdate': 'turn_completed',
          'stopReason': 'end_turn',
        }, promptId: 'turn-1'),
      );
      collector.record(
        _params(<String, Object?>{
          'sessionUpdate': 'user_message_chunk',
          'messageId': 'user-2',
          'content': <String, Object?>{'type': 'text', 'text': 'Again'},
        }, promptId: 'turn-2'),
      );
      collector.record(
        _params(<String, Object?>{
          'sessionUpdate': 'agent_message_chunk',
          'messageId': 'agent-2',
          'content': <String, Object?>{'type': 'text', 'text': 'Done'},
        }, promptId: 'turn-2'),
      );
      final history = collector.build();

      // Assert
      expect(history.turns, hasLength(2));
      expect(history.turns.map((turn) => turn.id), <String>[
        'turn-1',
        'turn-2',
      ]);
      final firstEntries = history.turns.first.entries;
      expect(firstEntries, hasLength(3));
      expect((firstEntries[0] as AgentHistoryMessageEntry).text, 'Hello');
      expect((firstEntries[1] as AgentHistoryMessageEntry).text, 'Hi there');
      final tool = (firstEntries[2] as AgentHistoryToolEntry).toolCall;
      expect(tool.status, AgentToolStatus.completed);
      expect(tool.content, 'file body');
      expect(
        (history.turns.last.entries.first as AgentHistoryMessageEntry).text,
        'Again',
      );
    });

    test(
      'ignores other sessions and represents non-text user content safely',
      () {
        // Arrange
        final collector = AcpSessionReplayCollector(threadId: 'session-1');

        // Act
        collector.record(<String, Object?>{
          'sessionId': 'other-session',
          'update': <String, Object?>{
            'sessionUpdate': 'user_message_chunk',
            'content': <String, Object?>{'type': 'text', 'text': 'Hidden'},
          },
        });
        collector.record(
          _params(<String, Object?>{
            'sessionUpdate': 'user_message_chunk',
            'content': <String, Object?>{
              'type': 'image',
              'data': 'not-retained',
            },
          }),
        );
        final history = collector.build();

        // Assert
        expect(history.turns, hasLength(1));
        expect(
          (history.turns.single.entries.single as AgentHistoryMessageEntry)
              .text,
          '[Image]',
        );
      },
    );
  });
}

Map<String, Object?> _params(Map<String, Object?> update, {String? promptId}) {
  return <String, Object?>{
    'sessionId': 'session-1',
    'update': <String, Object?>{
      ...update,
      if (promptId != null) '_meta': <String, Object?>{'promptId': promptId},
    },
  };
}

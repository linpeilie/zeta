import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/datasources/local_history/grok_chat_history_parser.dart';
import 'package:zeta/src/features/agent/data/datasources/local_history/grok_updates_history_parser.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  group('GrokUpdatesHistoryParser', () {
    const parser = GrokUpdatesHistoryParser();

    test('builds multi-turn history with tools and thoughts', () {
      const content = r'''
{"timestamp":1,"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"first question"}},"_meta":{"eventId":"e1"}}}
{"timestamp":2,"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"agent_thought_chunk","content":{"type":"text","text":"thinking..."},"_meta":{"promptId":"p1"}},"_meta":{"eventId":"e2"}}}
{"timestamp":3,"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"answer one"},"messageId":"m1","_meta":{"promptId":"p1"}},"_meta":{"eventId":"e3"}}}
{"timestamp":4,"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"tool_call","toolCallId":"t1","title":"Read file","kind":"read","status":"pending"},"_meta":{"eventId":"e4"}}}
{"timestamp":5,"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"tool_call_update","toolCallId":"t1","status":"completed","content":[{"type":"content","content":{"type":"text","text":"file body"}}]},"_meta":{"eventId":"e5"}}}
{"timestamp":6,"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"turn_completed","stop_reason":"end_turn","usage":{"inputTokens":10,"outputTokens":4,"totalTokens":14}},"_meta":{"eventId":"e6"}}}
{"timestamp":7,"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"second question"}},"_meta":{"eventId":"e7"}}}
{"timestamp":8,"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"answer two"},"messageId":"m2","_meta":{"promptId":"p2"}},"_meta":{"eventId":"e8"}}}
{"timestamp":9,"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"turn_completed","stop_reason":"cancelled"},"_meta":{"eventId":"e9"}}}
''';

      final snapshot = parser.parse(threadId: 's1', content: content);

      expect(snapshot.turns, hasLength(2));
      final first = snapshot.turns[0];
      expect(first.status, AgentHistoryTurnStatus.completed);
      expect(first.tokenUsage?.totalTokens, 14);

      final user = first.entries
          .whereType<AgentHistoryMessageEntry>()
          .firstWhere((e) => e.role == AgentMessageRole.user);
      expect(user.text, 'first question');

      final agent = first.entries
          .whereType<AgentHistoryMessageEntry>()
          .firstWhere((e) => e.role == AgentMessageRole.agent);
      expect(agent.text, 'answer one');

      final thought = first.entries
          .whereType<AgentHistoryToolEntry>()
          .firstWhere((e) => e.toolCall.kind == AgentToolKind.think);
      expect(thought.toolCall.content, 'thinking...');

      final tool = first.entries.whereType<AgentHistoryToolEntry>().firstWhere(
        (e) => e.toolCall.id == 't1',
      );
      expect(tool.toolCall.status, AgentToolStatus.completed);
      expect(tool.toolCall.content, contains('file body'));

      final second = snapshot.turns[1];
      expect(second.status, AgentHistoryTurnStatus.interrupted);
      expect(
        second.entries.whereType<AgentHistoryMessageEntry>().last.text,
        'answer two',
      );
    });

    test('maps plan entries to plan messages', () {
      const content = r'''
{"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"plan this"}},"_meta":{"eventId":"u1"}}}
{"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"plan","entries":[{"content":"Step A","status":"pending"},{"content":"Step B","status":"completed"}]},"_meta":{"eventId":"p1"}}}
''';
      final snapshot = parser.parse(threadId: 's1', content: content);
      final plan = snapshot.turns.single.entries
          .whereType<AgentHistoryMessageEntry>()
          .firstWhere((e) => e.raw['type'] == 'plan');
      expect(plan.text, contains('Step A'));
      expect(plan.text, contains('Step B'));
    });
  });

  group('GrokChatHistoryParser', () {
    const parser = GrokChatHistoryParser();

    test('filters synthetic context and splits turns by user_query', () {
      const content = r'''
{"type":"system","content":"You are Grok"}
{"type":"user","content":[{"type":"text","text":"<user_info>\nOS Version: windows\n</user_info>"}]}
{"type":"user","content":[{"type":"text","text":"<system-reminder>\nPlan mode\n</system-reminder>"}]}
{"type":"user","content":[{"type":"text","text":"<user_query>\nhello world\n</user_query>"}],"prompt_index":0}
{"type":"reasoning","content":"I should greet"}
{"type":"assistant","content":"Hi there"}
{"type":"tool_result","content":"tool output","name":"read_file"}
{"type":"user","content":[{"type":"text","text":"<user_query>\nsecond\n</user_query>"}],"prompt_index":1}
{"type":"assistant","content":"second answer"}
''';

      final snapshot = parser.parse(threadId: 's1', content: content);
      expect(snapshot.turns, hasLength(2));

      final first = snapshot.turns[0];
      final user = first.entries.whereType<AgentHistoryMessageEntry>().first;
      expect(user.role, AgentMessageRole.user);
      expect(user.text, 'hello world');

      expect(
        first.entries.whereType<AgentHistoryToolEntry>().any(
          (e) => e.toolCall.kind == AgentToolKind.think,
        ),
        isTrue,
      );
      expect(
        first.entries.whereType<AgentHistoryMessageEntry>().any(
          (e) => e.role == AgentMessageRole.agent && e.text == 'Hi there',
        ),
        isTrue,
      );
      expect(
        first.entries.whereType<AgentHistoryToolEntry>().any(
          (e) => e.toolCall.title == 'read_file',
        ),
        isTrue,
      );

      final secondUser = snapshot.turns[1].entries
          .whereType<AgentHistoryMessageEntry>()
          .first;
      expect(secondUser.text, 'second');
    });
  });
}

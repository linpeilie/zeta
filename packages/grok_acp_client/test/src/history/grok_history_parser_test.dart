import 'package:agent_provider_contracts/agent_provider_contracts.dart';
// JSONL fixture literals intentionally preserve their single-line wire shape.
// ignore_for_file: lines_longer_than_80_chars

import 'package:grok_acp_client/src/history/grok_chat_history_parser.dart';
import 'package:grok_acp_client/src/history/grok_updates_history_parser.dart';
import 'package:test/test.dart';

import '../../testing/fixture_reader.dart';

void main() {
  group('GrokUpdatesHistoryParser', () {
    const parser = GrokUpdatesHistoryParser();

    test('builds multi-turn history with tools and thoughts', () {
      const content = '''
{"timestamp":1000,"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"first question"}},"_meta":{"eventId":"e1","agentTimestampMs":1000000}}}
{"timestamp":1001,"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"agent_thought_chunk","content":{"type":"text","text":"thinking..."},"_meta":{"promptId":"p1","turnStartMs":1000000}},"_meta":{"eventId":"e2"}}}
{"timestamp":1002,"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"answer one"},"messageId":"m1","_meta":{"promptId":"p1","turnStartMs":1000000}},"_meta":{"eventId":"e3"}}}
{"timestamp":1003,"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"tool_call","toolCallId":"t1","title":"Read file","kind":"read","status":"pending"},"_meta":{"eventId":"e4"}}}
{"timestamp":1004,"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"tool_call_update","toolCallId":"t1","status":"completed","content":[{"type":"content","content":{"type":"text","text":"file body"}}]},"_meta":{"eventId":"e5"}}}
{"timestamp":1005,"method":"_x.ai/session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"turn_completed","prompt_id":"p1","stop_reason":"end_turn","usage":{"inputTokens":10,"outputTokens":4,"totalTokens":14,"apiDurationMs":2500}},"_meta":{"eventId":"e6","agentTimestampMs":1002500}}}
{"timestamp":1006,"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"second question"}},"_meta":{"eventId":"e7","agentTimestampMs":2000000}}}
{"timestamp":1007,"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"answer two"},"messageId":"m2","_meta":{"promptId":"p2"}},"_meta":{"eventId":"e8"}}}
{"timestamp":1008,"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"turn_completed","stop_reason":"cancelled"},"_meta":{"eventId":"e9","agentTimestampMs":2005000}}}
''';

      final snapshot = parser.parse(threadId: 's1', content: content);

      expect(snapshot.turns, hasLength(2));
      final first = snapshot.turns[0];
      expect(first.status, AgentHistoryTurnStatus.completed);
      expect(first.tokenUsage?.totalTokens, 14);
      expect(first.tokenUsageIsSessionCumulative, isFalse);
      expect(first.duration, const Duration(milliseconds: 2500));
      expect(first.startedAt, isNotNull);
      expect(first.completedAt, isNotNull);

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
      expect(tool.toolCall.title, 'Read file');
      expect(tool.toolCall.content, contains('file body'));

      final second = snapshot.turns[1];
      expect(second.status, AgentHistoryTurnStatus.interrupted);
      expect(
        second.entries.whereType<AgentHistoryMessageEntry>().last.text,
        'answer two',
      );
    });

    test('hides provider-only user echoes but keeps the agent response', () {
      const content = r'''
{"timestamp":1000,"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"real question"}},"_meta":{"eventId":"u1","agentTimestampMs":1000000}}}
{"timestamp":1001,"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"main answer"},"_meta":{"promptId":"p1"}},"_meta":{"eventId":"a1","agentTimestampMs":1001000}}}
{"timestamp":1002,"method":"_x.ai/session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"turn_completed","prompt_id":"p1","stop_reason":"end_turn"},"_meta":{"eventId":"c1","agentTimestampMs":1002000}}}
{"timestamp":1003,"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"<system-reminder>\nBackground task completed\n</system-reminder>"},"_meta":{"promptIndex":2,"hideFromScrollback":true}},"_meta":{"eventId":"u2","agentTimestampMs":1003000}}}
{"timestamp":1004,"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"background follow-up"},"_meta":{"promptId":"task-completed-bg-1"}},"_meta":{"eventId":"a2","agentTimestampMs":1004000}}}
{"timestamp":1005,"method":"_x.ai/session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"turn_completed","prompt_id":"task-completed-bg-1","stop_reason":"end_turn"},"_meta":{"eventId":"c2","agentTimestampMs":1005000}}}
''';

      final snapshot = parser.parse(threadId: 's1', content: content);

      expect(snapshot.turns, hasLength(2));
      final backgroundTurn = snapshot.turns.last;
      final messages = backgroundTurn.entries
          .whereType<AgentHistoryMessageEntry>()
          .toList();
      expect(messages, hasLength(1));
      expect(messages.single.role, AgentMessageRole.agent);
      expect(messages.single.text, 'background follow-up');
    });

    test('keeps concrete Grok title across status-only updates', () {
      const content = '''
{"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"find it"}},"_meta":{"eventId":"u1"}}}
{"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"tool_call","toolCallId":"call-abc-0","title":"grep","rawInput":{"pattern":"sessionUpdate"}},"_meta":{"eventId":"t1"}}}
{"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"tool_call_update","toolCallId":"call-abc-0","title":"sessionUpdate","kind":"search","rawInput":{"pattern":"sessionUpdate"}},"_meta":{"eventId":"t2"}}}
{"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"tool_call_update","toolCallId":"call-abc-0","status":"completed","content":{"type":"content","content":{"type":"text","text":"found 42 matches"}}},"_meta":{"eventId":"t3"}}}
''';

      final snapshot = parser.parse(threadId: 's1', content: content);
      final tool = snapshot.turns.single.entries
          .whereType<AgentHistoryToolEntry>()
          .single
          .toolCall;

      expect(tool.kind, AgentToolKind.search);
      expect(tool.title, 'sessionUpdate');
      expect(tool.content, contains('found 42 matches'));
    });

    test('restores model id and explicit context window from updates', () {
      const content = '''
{"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"session_info_update","modelId":"grok-4.5"}}}
{"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"hello"}},"_meta":{"eventId":"u1"}}}
{"method":"_x.ai/session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"turn_completed","stop_reason":"end_turn","usage":{"inputTokens":10,"outputTokens":4,"totalTokens":14,"totalContextTokens":500000}},"_meta":{"eventId":"done"}}}
''';

      final turn = parser.parse(threadId: 's1', content: content).turns.single;

      expect(turn.modelId, 'grok-4.5');
      expect(turn.tokenUsage?.modelContextWindow, 500000);
    });

    test(
      'restores context occupancy from stream _meta, not multi-call billing total',
      () {
        // 回归：上下文占用约 379k，而 usage.totalTokens 是 5.8m 的
        // multi-call 计费合计；历史回放必须把 _meta 写入 last*。
        const content = '''
{"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"hello"}},"_meta":{"eventId":"u1"}}}
{"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"working"},"messageId":"a1"},"_meta":{"eventId":"a1","promptId":"p1","totalTokens":350000}}}
{"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"tool_call","toolCallId":"t1","title":"Read","kind":"read","status":"completed"},"_meta":{"eventId":"t1","promptId":"p1","totalTokens":378650}}}
{"method":"_x.ai/session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"turn_completed","prompt_id":"p1","stop_reason":"end_turn","usage":{"inputTokens":5791874,"outputTokens":13088,"totalTokens":5804962,"cachedReadTokens":5755904,"reasoningTokens":11625,"modelCalls":16}},"_meta":{"eventId":"done"}}}
''';

        final turn = parser
            .parse(threadId: 's1', content: content)
            .turns
            .single;
        final usage = turn.tokenUsage;
        expect(usage, isNotNull);
        expect(usage!.totalTokens, 5804962);
        expect(usage.inputTokens, 5791874);
        expect(usage.lastTotalTokens, 378650);
        expect(usage.lastInputTokens, 378650);
        expect(turn.tokenUsageIsSessionCumulative, isFalse);
      },
    );

    test('maps plan entries to plan messages', () {
      const content = '''
{"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"plan this"}},"_meta":{"eventId":"u1"}}}
{"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"plan","entries":[{"content":"Step A","status":"pending"},{"content":"Step B","status":"completed"}]},"_meta":{"eventId":"p1"}}}
''';
      final snapshot = parser.parse(threadId: 's1', content: content);
      final plan = snapshot.turns.single.entries
          .whereType<AgentHistoryMessageEntry>()
          .firstWhere((e) => e.raw['type'] == 'plan');
      expect(plan.kind, AgentMessageKind.plan);
      expect(plan.text, contains('Step A'));
      expect(plan.text, contains('Step B'));
    });

    test('merges text and local image chunks from the same prompt', () {
      const content = r'''
{"timestamp":1000,"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"fix this"},"_meta":{"promptIndex":1}},"_meta":{"eventId":"u1","agentTimestampMs":1000000}}}
{"timestamp":1000,"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"[local image: C:\\Users\\tester\\image.png]"},"_meta":{"promptIndex":1}},"_meta":{"eventId":"u2","agentTimestampMs":1000000}}}
{"timestamp":1001,"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"done"},"messageId":"a1","_meta":{"promptId":"p1"}},"_meta":{"eventId":"a1"}}}
{"timestamp":1002,"method":"_x.ai/session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"turn_completed","prompt_id":"p1","stop_reason":"end_turn"},"_meta":{"eventId":"c1"}}}
''';

      final snapshot = parser.parse(threadId: 's1', content: content);

      expect(snapshot.turns, hasLength(1));
      final userMessages = snapshot.turns.single.entries
          .whereType<AgentHistoryMessageEntry>()
          .where((entry) => entry.role == AgentMessageRole.user)
          .toList();
      expect(userMessages, hasLength(1));
      expect(userMessages.single.text, 'fix this');
      expect(userMessages.single.localImagePaths, <String>[
        r'C:\Users\tester\image.png',
      ]);
    });

    test('keeps image-only user prompts', () {
      const content = '''
{"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"[local image: /tmp/only.png]"},"_meta":{"promptIndex":2}},"_meta":{"eventId":"u1"}}}
''';

      final snapshot = parser.parse(threadId: 's1', content: content);
      final user =
          snapshot.turns.single.entries.single as AgentHistoryMessageEntry;
      expect(user.text, isEmpty);
      expect(user.localImagePaths, <String>['/tmp/only.png']);
    });

    test('restores rate-limit failure and keeps retry diagnostics raw', () {
      const content = '''
{"timestamp":1000,"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"trigger limit"}},"_meta":{"eventId":"u1","agentTimestampMs":1000000}}}
{"timestamp":1001,"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"retry_state","type":"retrying","attempt":1,"max_retries":2,"reason":"API error (status 429 Too Many Requests): subscription:free-usage-exhausted"},"_meta":{"eventId":"r1","agentTimestampMs":1001000}}}
{"timestamp":1002,"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"retry_state","type":"exhausted","attempts":2,"reason":"API error (status 429 Too Many Requests): subscription:free-usage-exhausted","is_rate_limited":true},"_meta":{"eventId":"r2","agentTimestampMs":1002000}}}
{"timestamp":1003,"method":"_x.ai/session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"turn_completed","prompt_id":"p1","stop_reason":"rate_limit"},"_meta":{"eventId":"done","agentTimestampMs":1003000}}}
''';

      final turn = parser.parse(threadId: 's1', content: content).turns.single;

      expect(turn.status, AgentHistoryTurnStatus.failed);
      expect(
        turn.errorMessage,
        'Grok rate limit reached. Please try again later.',
      );
      expect(turn.duration, const Duration(seconds: 3));
      final retryState = (turn.raw['retryState']! as Map)
          .cast<String, Object?>();
      expect(retryState['type'], 'exhausted');
      expect(retryState['is_rate_limited'], isTrue);
      expect(retryState['reason'], contains('429 Too Many Requests'));
      final terminal = (turn.raw['turnCompleted']! as Map)
          .cast<String, Object?>();
      expect(terminal['stop_reason'], 'rate_limit');
    });

    test('treats an exhausted retry without a terminal update as failed', () {
      const content = '''
{"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"trigger failure"}},"_meta":{"eventId":"u1"}}}
{"method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"retry_state","type":"exhausted","reason":"provider unavailable","is_rate_limited":false},"_meta":{"eventId":"r1"}}}
''';

      final turn = parser.parse(threadId: 's1', content: content).turns.single;

      expect(turn.status, AgentHistoryTurnStatus.failed);
      expect(turn.errorMessage, 'Grok request failed. Please try again.');
    });

    test('ignores malformed lines from the redacted updates fixture', () {
      final snapshot = parser.parse(
        threadId: 'sess-fixture',
        content: readFixtureText(
          'grok/local_history/updates_malformed_lines_redacted.jsonl',
        ),
      );

      expect(snapshot.turns, hasLength(1));
      final turn = snapshot.turns.single;
      expect(turn.status, AgentHistoryTurnStatus.completed);
      expect(turn.duration, const Duration(milliseconds: 1200));
      final messages = turn.entries
          .whereType<AgentHistoryMessageEntry>()
          .toList();
      expect(messages.first.text, 'fix baseline');
      expect(messages.last.text, 'baseline fixed');
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

    test('restores local image markers from fallback history', () {
      const content = r'''
{"type":"user","content":[{"type":"text","text":"<user_query>\ninspect this [local image: C:\\Users\\tester\\fallback.png]\n</user_query>"}],"prompt_index":0}
{"type":"assistant","content":"done"}
''';

      final snapshot = parser.parse(threadId: 's1', content: content);
      final user = snapshot.turns.single.entries
          .whereType<AgentHistoryMessageEntry>()
          .first;
      expect(user.text, 'inspect this');
      expect(user.localImagePaths, <String>[r'C:\Users\tester\fallback.png']);
    });

    test('parses the redacted legacy chat_history fixture', () {
      final snapshot = parser.parse(
        threadId: 'legacy-thread',
        content: readFixtureText(
          'grok/local_history/chat_history_legacy_redacted.jsonl',
        ),
      );

      expect(snapshot.turns, hasLength(1));
      final entries = snapshot.turns.single.entries
          .whereType<AgentHistoryMessageEntry>()
          .toList();
      expect(entries[0].text, 'legacy hello');
      expect(entries[1].text, 'legacy world');
    });
  });
}

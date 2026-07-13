import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/datasources/local_history/grok_session_history_reader.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  group('GrokSessionHistoryReader', () {
    late Directory tempRoot;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('zeta-grok-sessions-');
    });

    tearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('lists sessions from encoded project directory', () async {
      final projectPath = r'D:\Development\Workspace\zeta';
      final encoded = Uri.encodeComponent(projectPath.replaceAll('/', '\\'));
      final sessionId = '019f593a-4ad3-7533-b118-144607cf897e';
      final sessionDir = Directory(
        '${tempRoot.path}${Platform.pathSeparator}sessions'
        '${Platform.pathSeparator}$encoded'
        '${Platform.pathSeparator}$sessionId',
      );
      await sessionDir.create(recursive: true);
      final summary = File(
        '${sessionDir.path}${Platform.pathSeparator}summary.json',
      );
      await summary.writeAsString('''
{
  "info": {"id": "$sessionId", "cwd": ${jsonQuote(projectPath)}},
  "session_summary": "Implement token usage",
  "generated_title": "Token usage work",
  "created_at": "2026-07-13T02:07:00.000Z",
  "updated_at": "2026-07-13T02:28:59.000Z",
  "last_active_at": "2026-07-13T02:28:59.000Z"
}
''');

      final reader = GrokSessionHistoryReader(grokHome: tempRoot.path);
      final page = await reader.listThreads(
        query: AgentThreadListQuery(projectPath: projectPath, limit: 20),
        providerId: 'grok',
      );

      expect(page.threads, hasLength(1));
      expect(page.threads.single.id, sessionId);
      expect(page.threads.single.title, 'Token usage work');
      expect(page.threads.single.preview, 'Implement token usage');
    });

    test('prefers updates.jsonl multi-turn history over chat_history', () async {
      final projectPath = r'D:\repo\zeta';
      final encoded = Uri.encodeComponent(projectPath.replaceAll('/', '\\'));
      final sessionId = '019f593a-4ad3-7533-b118-144607cf897e';
      final sessionDir = Directory(
        '${tempRoot.path}${Platform.pathSeparator}sessions'
        '${Platform.pathSeparator}$encoded'
        '${Platform.pathSeparator}$sessionId',
      );
      await sessionDir.create(recursive: true);

      final updates = File(
        '${sessionDir.path}${Platform.pathSeparator}updates.jsonl',
      );
      await updates.writeAsString(
        '{"method":"session/update","params":{"sessionId":"$sessionId","update":{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"from updates"}},"_meta":{"eventId":"e1"}}}\n'
        '{"method":"session/update","params":{"sessionId":"$sessionId","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"reply updates"},"messageId":"m1"},"_meta":{"eventId":"e2"}}}\n'
        '{"method":"session/update","params":{"sessionId":"$sessionId","update":{"sessionUpdate":"turn_completed","stop_reason":"end_turn"},"_meta":{"eventId":"e3"}}}\n',
      );
      final history = File(
        '${sessionDir.path}${Platform.pathSeparator}chat_history.jsonl',
      );
      await history.writeAsString(
        '{"type":"user","content":[{"type":"text","text":"<user_query>from chat</user_query>"}]}\n'
        '{"type":"assistant","content":"reply chat"}\n',
      );

      final reader = GrokSessionHistoryReader(grokHome: tempRoot.path);
      final snapshot = await reader.readThreadHistory(
        threadId: sessionId,
        providerId: 'grok',
        projectPath: projectPath,
        sessionPath: sessionDir.path,
      );

      expect(snapshot.raw['source'], 'updates.jsonl');
      expect(snapshot.turns, hasLength(1));
      final texts = snapshot.turns.single.entries
          .whereType<AgentHistoryMessageEntry>()
          .map((e) => e.text)
          .toList();
      expect(texts, containsAll(<String>['from updates', 'reply updates']));
      expect(texts, isNot(contains('from chat')));
    });

    test('falls back to chat_history when updates missing', () async {
      final sessionId = '019f593a-4ad3-7533-b118-144607cf897e';
      final sessionDir = Directory(
        '${tempRoot.path}${Platform.pathSeparator}sessions'
        '${Platform.pathSeparator}manual'
        '${Platform.pathSeparator}$sessionId',
      );
      await sessionDir.create(recursive: true);
      final history = File(
        '${sessionDir.path}${Platform.pathSeparator}chat_history.jsonl',
      );
      await history.writeAsString(
        '{"type":"system","content":"ignore me"}\n'
        '{"type":"user","content":[{"type":"text","text":"<user_query>hello</user_query>"}]}\n'
        '{"type":"assistant","content":"world"}\n',
      );

      final reader = GrokSessionHistoryReader(grokHome: tempRoot.path);
      final snapshot = await reader.readThreadHistory(
        threadId: sessionId,
        providerId: 'grok',
        sessionPath: sessionDir.path,
      );

      expect(snapshot.raw['source'], 'chat_history.jsonl');
      expect(snapshot.turns, hasLength(1));
      final entries = snapshot.turns.single.entries
          .whereType<AgentHistoryMessageEntry>()
          .toList();
      expect(entries, hasLength(2));
      expect(entries[0].text, 'hello');
      expect(entries[1].role, AgentMessageRole.agent);
    });
  });
}

String jsonQuote(String value) => '"${value.replaceAll(r'\', r'\\')}"';

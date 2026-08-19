// Filesystem fixture paths and JSONL records are clearest in protocol form.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:grok_acp_client/src/history/grok_session_history_reader.dart';
import 'package:test/test.dart';

import '../../testing/fixture_reader.dart';

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
      const projectPath = r'D:\Development\Workspace\zeta';
      final encoded = Uri.encodeComponent(projectPath.replaceAll('/', r'\'));
      const sessionId = '019f593a-4ad3-7533-b118-144607cf897e';
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

      final title = await reader.readSessionDisplayTitle(
        threadId: sessionId,
        projectPath: projectPath,
      );
      expect(title, 'Token usage work');

      final snapshot = await reader.readSessionTitleSnapshot(
        threadId: sessionId,
        projectPath: projectPath,
      );
      expect(snapshot?.generatedTitle, 'Token usage work');
      expect(snapshot?.sessionSummary, 'Implement token usage');
      expect(snapshot?.authoritativeTitle, 'Token usage work');
    });

    test('finds sessions under slash-encoded Unix project dirs', () async {
      const projectPath = '/Users/linpeilie/Development/Workspace/zeta';
      final encoded = Uri.encodeComponent(projectPath);
      expect(encoded, '%2FUsers%2Flinpeilie%2FDevelopment%2FWorkspace%2Fzeta');
      const sessionId = '019f5bcb-e8c2-7191-a779-f2a40d9ee05a';
      final sessionDir = Directory(
        '${tempRoot.path}${Platform.pathSeparator}sessions'
        '${Platform.pathSeparator}$encoded'
        '${Platform.pathSeparator}$sessionId',
      );
      await sessionDir.create(recursive: true);
      await File(
        '${sessionDir.path}${Platform.pathSeparator}summary.json',
      ).writeAsString('''
{
  "info": {"id": "$sessionId", "cwd": ${jsonQuote(projectPath)}},
  "session_summary": "User Asking What AI Model This Is",
  "generated_title": "User Asking What AI Model This Is",
  "created_at": "2026-07-13T14:05:18.000Z",
  "updated_at": "2026-07-13T14:05:34.000Z",
  "last_active_at": "2026-07-13T14:05:31.000Z"
}
''');

      final reader = GrokSessionHistoryReader(grokHome: tempRoot.path);
      final page = await reader.listThreads(
        query: AgentThreadListQuery(projectPath: projectPath, limit: 20),
        providerId: 'grok',
      );
      expect(page.threads, hasLength(1));
      expect(page.threads.single.title, 'User Asking What AI Model This Is');

      final snapshot = await reader.readSessionTitleSnapshot(
        threadId: sessionId,
        projectPath: projectPath,
      );
      expect(snapshot?.generatedTitle, 'User Asking What AI Model This Is');
    });

    test('prefers updates.jsonl multi-turn history over chat_history', () async {
      const projectPath = r'D:\repo\zeta';
      final encoded = Uri.encodeComponent(projectPath.replaceAll('/', r'\'));
      const sessionId = '019f593a-4ad3-7533-b118-144607cf897e';
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
      const sessionId = '019f593a-4ad3-7533-b118-144607cf897e';
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

    test('finds a session by recursively scanning all project dirs', () async {
      const sessionId = 'grok-recursive-session-redacted';
      final sessionsRoot = Directory(
        '${tempRoot.path}${Platform.pathSeparator}sessions',
      );
      await sessionsRoot.create(recursive: true);
      await File(
        '${sessionsRoot.path}${Platform.pathSeparator}not-a-project',
      ).writeAsString('fixture');
      final sessionDir = Directory(
        '${sessionsRoot.path}${Platform.pathSeparator}unknown-project'
        '${Platform.pathSeparator}$sessionId',
      );
      await sessionDir.create(recursive: true);
      await File(
        '${sessionDir.path}${Platform.pathSeparator}chat_history.jsonl',
      ).writeAsString(
        '{"type":"user","content":"<user_query>scan</user_query>"}\n'
        '{"type":"assistant","content":"found"}\n',
      );

      final snapshot =
          await GrokSessionHistoryReader(
            grokHome: tempRoot.path,
          ).readThreadHistory(
            threadId: sessionId,
            providerId: 'grok',
          );

      expect(snapshot.raw['source'], 'chat_history.jsonl');
      expect(snapshot.turns, hasLength(1));
    });

    test(
      'falls back from unreadable updates fixture to legacy chat_history fixture',
      () async {
        const sessionId = '019f593a-4ad3-7533-b118-144607cf8988';
        final sessionDir = Directory(
          '${tempRoot.path}${Platform.pathSeparator}sessions'
          '${Platform.pathSeparator}manual'
          '${Platform.pathSeparator}$sessionId',
        );
        await sessionDir.create(recursive: true);

        await File(
          '${sessionDir.path}${Platform.pathSeparator}updates.jsonl',
        ).writeAsString(
          readFixtureText(
            'grok/local_history/updates_unreadable_redacted.jsonl',
          ),
        );
        await File(
          '${sessionDir.path}${Platform.pathSeparator}chat_history.jsonl',
        ).writeAsString(
          readFixtureText(
            'grok/local_history/chat_history_legacy_redacted.jsonl',
          ),
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
        expect(entries[0].text, 'legacy hello');
        expect(entries[1].text, 'legacy world');
      },
    );

    test('reads updates history without rewriting the source file', () async {
      const sessionId = 'grok-history-read-only-redacted';
      final sessionDir = Directory(
        '${tempRoot.path}${Platform.pathSeparator}sessions'
        '${Platform.pathSeparator}manual'
        '${Platform.pathSeparator}$sessionId',
      );
      await sessionDir.create(recursive: true);
      final updates = File(
        '${sessionDir.path}${Platform.pathSeparator}updates.jsonl',
      );
      await updates.writeAsString(
        '{"method":"session/update","params":{"sessionId":"$sessionId","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"[AGENT_TEXT_REDACTED]"},"_meta":{"promptId":"turn-redacted"}},"_meta":{"eventId":"event-redacted"}}}\n'
        '{"method":"_x.ai/session/update","params":{"sessionId":"$sessionId","update":{"sessionUpdate":"turn_completed","prompt_id":"turn-redacted","stop_reason":"end_turn"},"_meta":{"eventId":"terminal-redacted"}}}\n',
      );
      final before = await updates.readAsBytes();

      final reader = GrokSessionHistoryReader(grokHome: tempRoot.path);
      final snapshot = await reader.readThreadHistory(
        threadId: sessionId,
        providerId: 'grok',
        sessionPath: sessionDir.path,
      );

      expect(snapshot.turns, hasLength(1));
      expect(await updates.readAsBytes(), before);
    });
  });
}

String jsonQuote(String value) => '"${value.replaceAll(r'\', r'\\')}"';

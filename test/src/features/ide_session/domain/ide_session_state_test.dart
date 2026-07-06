import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/ide_session/domain/ide_session_state.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  group('IdeSessionState', () {
    test('preserves cached thread session paths across encode and decode', () {
      final state = IdeSessionState(
        projectPaths: const <String>['/repo'],
        cachedThreadsByProject: <String, List<AgentThreadSummary>>{
          '/repo': <AgentThreadSummary>[
            AgentThreadSummary(
              id: 'thread-1',
              providerId: defaultAgentProviderId,
              projectPath: '/repo',
              title: 'Thread',
              sessionPath: '/tmp/thread-1.jsonl',
              preview: 'Preview',
              createdAt: DateTime.fromMillisecondsSinceEpoch(1),
              updatedAt: DateTime.fromMillisecondsSinceEpoch(2),
              status: AgentThreadRuntimeStatus.idle,
            ),
          ],
        },
      );

      final restored = IdeSessionState.tryDecode(state.encode());

      expect(
        restored?.cachedThreadsByProject['/repo']?.single.sessionPath,
        '/tmp/thread-1.jsonl',
      );
    });

    test('restores legacy cached thread path from raw payload', () {
      final restored = IdeSessionState.tryDecode(
        '{"version":2,"cachedThreadsByProject":{"/repo":[{"id":"thread-1","providerId":"codex","projectPath":"/repo","preview":"Preview","createdAt":1,"updatedAt":2,"status":"idle","raw":{"path":"/tmp/legacy-thread.jsonl"}}]}}',
      );

      expect(
        restored?.cachedThreadsByProject['/repo']?.single.sessionPath,
        '/tmp/legacy-thread.jsonl',
      );
    });
  });
}

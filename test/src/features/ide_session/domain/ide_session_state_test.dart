import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/ide_session/domain/ide_session_state.dart';
import 'package:zeta/src/features/ide_session/domain/ide_workbench_layout_state.dart';

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

    test('round-trips project home state and defaults legacy snapshots', () {
      const state = IdeSessionState(
        projectPaths: <String>['/repo'],
        activeProjectPath: '/repo',
        projectHomeActive: true,
      );

      final restored = IdeSessionState.tryDecode(state.encode());
      final legacy = IdeSessionState.tryDecode(
        '{"version":2,"projectPaths":["/repo"],"activeProjectPath":"/repo"}',
      );

      expect(restored?.projectHomeActive, isTrue);
      expect(legacy?.projectHomeActive, isFalse);
    });

    test('round-trips project recency and preserves v3 project home', () {
      final openedAt = DateTime.utc(2026, 7, 21, 12, 30);
      final state = IdeSessionState(
        projectPaths: const <String>['/repo'],
        activeProjectPath: '/repo',
        projectLastOpenedAtByPath: <String, DateTime>{'/repo': openedAt},
        projectHomeActive: true,
      );

      final restored = IdeSessionState.tryDecode(state.encode());
      final version3 = IdeSessionState.tryDecode(
        '{"version":3,"projectPaths":["/repo"],"activeProjectPath":"/repo","projectHomeActive":true}',
      );

      expect(restored?.projectLastOpenedAtByPath['/repo'], openedAt);
      expect(version3?.projectHomeActive, isTrue);
      expect(version3?.projectLastOpenedAtByPath, isEmpty);
    });

    test('ignores malformed project recency entries without losing session', () {
      final restored = IdeSessionState.tryDecode(
        '{"version":4,"projectPaths":["/repo","/other"],"projectLastOpenedAtByPath":{"/repo":"bad","/other":42}}',
      );

      expect(restored?.projectPaths, <String>['/repo', '/other']);
      expect(restored?.projectLastOpenedAtByPath.keys, <String>['/other']);
      expect(
        restored?.projectLastOpenedAtByPath['/other'],
        DateTime.fromMillisecondsSinceEpoch(42),
      );
    });

    test('round-trips every workbench layout field in v4', () {
      const workbench = IdeWorkbenchLayoutState(
        leftSidebarVisible: false,
        agentUsageExpanded: true,
        leftSidebarWidth: 318,
        agentUsageHeightFraction: 0.46,
        selectedAgentUsageProviderId: 'grok',
      );

      final restored = IdeSessionState.tryDecode(
        const IdeSessionState(workbenchLayout: workbench).encode(),
      );

      expect(restored?.workbenchLayout, workbench);
    });

    test('isolates malformed workbench fields from projects and threads', () {
      final state = IdeSessionState(
        projectPaths: const <String>['/repo'],
        cachedThreadsByProject: <String, List<AgentThreadSummary>>{
          '/repo': <AgentThreadSummary>[
            AgentThreadSummary(
              id: 'thread-1',
              providerId: defaultAgentProviderId,
              projectPath: '/repo',
              preview: 'Preview',
              createdAt: DateTime.fromMillisecondsSinceEpoch(1),
              updatedAt: DateTime.fromMillisecondsSinceEpoch(2),
              status: AgentThreadRuntimeStatus.idle,
            ),
          ],
        },
      );
      final raw = state.toJson()
        ..['workbench'] = <String, Object?>{
          'leftSidebarVisible': false,
          'agentUsageExpanded': true,
          'leftSidebarWidth': 'broken',
          'agentUsageHeightFraction': 0.4,
          'selectedAgentUsageProviderId': ' codex ',
          'unknownFutureField': true,
        };

      final restored = IdeSessionState.tryDecode(jsonEncode(raw));

      expect(restored?.projectPaths, <String>['/repo']);
      expect(restored?.cachedThreadsByProject['/repo']?.single.id, 'thread-1');
      expect(
        restored?.workbenchLayout,
        const IdeWorkbenchLayoutState(
          leftSidebarVisible: false,
          agentUsageExpanded: true,
          agentUsageHeightFraction: 0.4,
          selectedAgentUsageProviderId: 'codex',
        ),
      );
    });

    test('tolerantly reads supported v1 through v4 snapshots', () {
      for (final version in <int>[1, 2, 3, 4]) {
        final restored = IdeSessionState.tryDecode(
          jsonEncode(<String, Object?>{
            'version': version,
            'projectPaths': <Object?>['/repo', 42, '/repo'],
            'activeProjectPath': '/repo',
            'expandedDirectoryPaths': <Object?>['/repo/lib', false],
            'selectedTreeKey': 42,
            'unknownFutureField': <String, Object?>{'enabled': true},
          }),
        );

        expect(restored, isNotNull, reason: 'version $version');
        expect(restored?.projectPaths, <String>['/repo']);
        expect(restored?.activeProjectPath, '/repo');
        expect(restored?.expandedDirectoryPaths, <String>{'/repo/lib'});
        expect(restored?.selectedTreeKey, isNull);
        expect(restored?.workbenchLayout, const IdeWorkbenchLayoutState());
      }
    });
  });
}

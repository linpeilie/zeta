import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
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

    test('round-trips project home state', () {
      const state = IdeSessionState(
        projectPaths: <String>['/repo'],
        activeProjectPath: '/repo',
        projectHomeActive: true,
      );

      final restored = IdeSessionState.tryDecode(state.encode());

      expect(restored?.projectHomeActive, isTrue);
    });

    test('round-trips project recency', () {
      final openedAt = DateTime.utc(2026, 7, 21, 12, 30);
      final state = IdeSessionState(
        projectPaths: const <String>['/repo'],
        activeProjectPath: '/repo',
        projectLastOpenedAtByPath: <String, DateTime>{'/repo': openedAt},
        projectHomeActive: true,
      );

      final restored = IdeSessionState.tryDecode(state.encode());

      expect(restored?.projectLastOpenedAtByPath['/repo'], openedAt);
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

    test('round-trips current workbench layout fields', () {
      const workbench = IdeWorkbenchLayoutState(
        leftSidebarVisible: false,
        leftSidebarWidth: 318,
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
          'leftSidebarWidth': 'broken',
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
          selectedAgentUsageProviderId: 'codex',
        ),
      );
    });

    test('rejects unsupported session versions', () {
      final restored = IdeSessionState.tryDecode(
        jsonEncode(<String, Object?>{
          'version': sessionStateVersion - 1,
          'projectPaths': <String>['/repo'],
        }),
      );

      expect(restored, const IdeSessionState());
    });
  });
}

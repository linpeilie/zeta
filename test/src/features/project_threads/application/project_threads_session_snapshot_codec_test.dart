import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/app/plugins/agent_provider_manifest.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_session_snapshot_codec.dart';
import 'package:zeta/src/features/project_threads/domain/project_thread_list_state.dart';
import 'package:zeta/src/features/project_threads/domain/project_threads_session_snapshot.dart';

void main() {
  group('Project Threads session snapshot', () {
    test('builds snapshot from current list states', () {
      final snapshot =
          buildProjectThreadsSessionSnapshot(<String, ProjectThreadListState>{
            '/repo': ProjectThreadListState(
              isExpanded: true,
              threads: _threads(2),
              selectedThreadId: 'thread-1',
            ),
            '/empty': const ProjectThreadListState(isExpanded: false),
          });

      expect(snapshot.expansionByProject, <String, bool>{
        '/repo': true,
        '/empty': false,
      });
      expect(snapshot.cachedThreadsByProject['/repo'], hasLength(2));
      expect(snapshot.cachedThreadsByProject.containsKey('/empty'), isFalse);
      expect(snapshot.selectedThreadIdsByProject['/repo'], 'thread-1');
    });

    test('builds restore plan from session snapshot', () {
      final plan = buildProjectThreadsRestorePlan(
        projectPaths: const <String>['/repo', '/other'],
        activeProjectPath: '/repo',
        snapshot: ProjectThreadsSessionSnapshot(
          expansionByProject: const <String, bool>{'/other': true},
          cachedThreadsByProject: <String, List<AgentThreadSummary>>{
            '/repo': _threads(1),
          },
          selectedThreadIdsByProject: const <String, String>{
            '/repo': 'thread-0',
          },
        ),
      );

      expect(plan.states['/repo']?.hasLoaded, isTrue);
      expect(plan.states['/repo']?.selectedThreadId, 'thread-0');
      expect(plan.states['/repo']?.threads, hasLength(1));
      expect(plan.states['/other']?.isExpanded, isTrue);
      expect(plan.projectsToLoad, <String>['/repo', '/other']);
    });

    test('restore plan only keeps the first five cached threads', () {
      final plan = buildProjectThreadsRestorePlan(
        projectPaths: const <String>['/repo'],
        activeProjectPath: '/repo',
        snapshot: ProjectThreadsSessionSnapshot(
          cachedThreadsByProject: <String, List<AgentThreadSummary>>{
            '/repo': _threads(8),
          },
        ),
      );

      expect(plan.states['/repo']?.threads.map((thread) => thread.id), <String>[
        'thread-0',
        'thread-1',
        'thread-2',
        'thread-3',
        'thread-4',
      ]);
      expect(plan.states['/repo']?.hasLoaded, isTrue);
    });

    test('restore plan keeps only one selected thread across projects', () {
      final plan = buildProjectThreadsRestorePlan(
        projectPaths: const <String>['/repo', '/other', '/third'],
        activeProjectPath: '/other',
        snapshot: const ProjectThreadsSessionSnapshot(
          selectedThreadIdsByProject: <String, String>{
            '/repo': 'thread-a',
            '/other': 'thread-b',
            '/third': 'thread-c',
          },
        ),
      );

      expect(plan.states['/other']?.selectedThreadId, 'thread-b');
      expect(plan.states['/repo']?.selectedThreadId, isNull);
      expect(plan.states['/third']?.selectedThreadId, isNull);
    });
  });
}

List<AgentThreadSummary> _threads(int count, {int start = 0}) {
  return <AgentThreadSummary>[
    for (var index = start; index < start + count; index += 1)
      _thread(
        id: 'thread-$index',
        providerId: defaultAgentProviderId,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(index),
        title: 'Thread $index',
        preview: 'Preview $index',
      ),
  ];
}

AgentThreadSummary _thread({
  required String id,
  required String providerId,
  required DateTime updatedAt,
  String title = 'Thread',
  String preview = 'Preview',
}) {
  return AgentThreadSummary(
    id: id,
    providerId: providerId,
    projectPath: '/repo',
    title: title,
    preview: preview,
    createdAt: updatedAt,
    updatedAt: updatedAt,
    recencyAt: updatedAt,
    status: AgentThreadRuntimeStatus.idle,
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/features/project_threads/application/project_threads_slice/project_threads_slice_effect.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_slice/project_threads_slice_state.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_slice/project_threads_slice_store.dart';
import 'package:zeta/src/features/project_threads/domain/project_thread_list_state.dart';

void main() {
  group('ProjectThreadsSliceStore', () {
    test('keeps selection globally unique and publishes immutable state', () {
      final runner = _RecordingRunner();
      final store = ProjectThreadsSliceStore(
        initialState: ProjectThreadsSliceState(
          statesByProject: <String, ProjectThreadListState>{
            '/a': ProjectThreadListState(
              threads: <AgentThreadSummary>[_thread('a')],
            ),
            '/b': ProjectThreadListState(
              threads: <AgentThreadSummary>[_thread('b')],
            ),
          },
        ),
        effectRunner: runner,
        now: () => DateTime.fromMillisecondsSinceEpoch(20),
      );
      addTearDown(store.dispose);
      var publishes = 0;
      store.subscribe(() => publishes += 1);

      store.selectThreadId('/a', 'a');
      store.selectThreadId('/b', 'b');

      expect(store.stateFor('/a').selectedThreadId, isNull);
      expect(store.stateFor('/b').selectedThreadId, 'b');
      expect(publishes, 2);
      expect(
        () => store.states['/c'] = const ProjectThreadListState(),
        throwsUnsupportedError,
      );
    });

    test(
      'preserves running, promotion and background completion semantics',
      () {
        final runner = _RecordingRunner();
        final store = ProjectThreadsSliceStore(
          initialState: ProjectThreadsSliceState(
            statesByProject: <String, ProjectThreadListState>{
              '/repo': ProjectThreadListState(
                threads: <AgentThreadSummary>[
                  _thread('first', updatedAt: 10),
                  _thread('background', updatedAt: 1),
                ],
                selectedThreadId: 'first',
              ),
            },
          ),
          effectRunner: runner,
          now: () => DateTime.fromMillisecondsSinceEpoch(20),
        );
        addTearDown(store.dispose);

        store.registerThreadMapping('/repo', 'background');
        store.setThreadRunning('background', isRunning: true);
        store.setThreadRunning('background', isRunning: false);

        final state = store.stateFor('/repo');
        expect(state.threads.first.id, 'background');
        expect(state.runningThreadIds, isEmpty);
        expect(state.completedThreadIds, contains('background'));
        expect(state.threads.first.status, AgentThreadRuntimeStatus.idle);
      },
    );

    test(
      'routes async commands through typed effects and settles by id',
      () async {
        final runner = _RecordingRunner();
        final store = ProjectThreadsSliceStore(
          initialState: ProjectThreadsSliceState(),
          effectRunner: runner,
        );
        addTearDown(store.dispose);

        final future = store.loadInitial('/repo');
        final effect = runner.effects.single as LoadInitialProjectThreadsEffect;
        expect(effect.projectPath, '/repo');

        store.operationSucceeded(effect.operationId);
        await future;
        store.operationSucceeded(effect.operationId);

        expect(store.staleResultCount, 1);
      },
    );

    test('registers a session without copying state into the runner', () {
      final runner = _RecordingRunner();
      final now = DateTime.fromMillisecondsSinceEpoch(42);
      final store = ProjectThreadsSliceStore(
        initialState: ProjectThreadsSliceState(),
        effectRunner: runner,
        now: () => now,
      );
      addTearDown(store.dispose);

      final thread = store.registerSession(
        '/repo',
        const AgentSession(id: 'new', providerId: defaultAgentProviderId),
        preview: 'first prompt',
        markRunning: true,
      );

      expect(thread.preview, 'first prompt');
      expect(store.stateFor('/repo').threads.single.id, 'new');
      expect(store.stateFor('/repo').selectedThreadId, 'new');
      expect(store.stateFor('/repo').runningThreadIds, contains('new'));
      expect(runner.effects, isEmpty);
    });

    test('dispose closes runner and drops late state/result ingress', () async {
      final runner = _RecordingRunner();
      final store = ProjectThreadsSliceStore(
        initialState: ProjectThreadsSliceState(),
        effectRunner: runner,
      );
      final future = store.loadInitial('/repo');
      final effect = runner.effects.single as LoadInitialProjectThreadsEffect;

      store.dispose();
      store.applyProjectState(
        '/repo',
        const ProjectThreadListState(isExpanded: true),
      );
      store.operationSucceeded(effect.operationId);

      await future;
      expect(store.stateFor('/repo').isExpanded, isFalse);
      expect(runner.closed, isTrue);
    });
  });
}

AgentThreadSummary _thread(String id, {int updatedAt = 0}) {
  final time = DateTime.fromMillisecondsSinceEpoch(updatedAt);
  return AgentThreadSummary(
    id: id,
    providerId: defaultAgentProviderId,
    projectPath: '/repo',
    preview: id,
    createdAt: time,
    updatedAt: time,
    status: AgentThreadRuntimeStatus.idle,
  );
}

final class _RecordingRunner implements ProjectThreadsSliceEffectRunner {
  final List<ProjectThreadsSliceEffect> effects = <ProjectThreadsSliceEffect>[];
  bool closed = false;

  @override
  void run(ProjectThreadsSliceEffect effect) => effects.add(effect);

  @override
  void close() => closed = true;
}

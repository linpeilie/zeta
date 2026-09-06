import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_slice/project_threads_slice_dependencies.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_slice/project_threads_slice_effect.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_slice/project_threads_slice_notifier.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_slice/project_threads_slice_state.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_state_owner.dart';
import 'package:zeta/src/features/project_threads/domain/project_thread_list_state.dart';

void main() {
  test(
    'synchronous result finds every waiter and retains original errors',
    () async {
      final runner = _SynchronousRunner();
      final container = _container((owner) => runner..owner = owner);
      addTearDown(container.dispose);
      final owner = container.read(projectThreadsSliceProvider.notifier);
      for (final command in _voidCommands(owner)) {
        await command();
      }
      expect(
        await owner.forkThread(projectPath: '/repo', threadId: 'a'),
        same(runner.session),
      );
      expect(runner.calls, 9);
      final error = UnsupportedError('external port');
      final trace = StackTrace.fromString('external stack');
      runner.error = error;
      runner.trace = trace;
      for (final command in [
        ..._voidCommands(owner),
        () => owner.forkThread(projectPath: '/repo', threadId: 'a'),
      ]) {
        Object? actual;
        StackTrace? actualTrace;
        await command().then<void>(
          (_) => fail('expected original failure'),
          onError: (Object e, StackTrace s) {
            actual = e;
            actualTrace = s;
          },
        );
        expect(actual, same(error));
        expect(actualTrace, same(trace));
      }
      final before = owner.staleResultCount;
      owner.operationSucceeded(runner.lastId!);
      expect(owner.staleResultCount, before + 1);
      expect(owner.staleResultCount, 1);
    },
  );

  test(
    'settings dependency changes and observer removal keep one owner and index',
    () async {
      var factories = 0;
      final input = NotifierProvider<_Input, int>(_Input.new);
      final runner = _PendingRunner();
      final container = ProviderContainer(
        overrides: [
          projectThreadsSliceDependenciesProvider.overrideWith((ref) {
            final version = ref.watch(input);
            return ProjectThreadsSliceDependencies(
              initialState: ProjectThreadsSliceState(),
              now: () => DateTime.fromMillisecondsSinceEpoch(version),
            );
          }),
          projectThreadsRunnerFactoryProvider.overrideWithValue((owner) {
            factories++;
            return runner;
          }),
        ],
      );
      addTearDown(container.dispose);
      final owner = container.read(projectThreadsSliceProvider.notifier);
      final subscription = container.listen(
        projectThreadsSliceProvider,
        (_, _) {},
      );
      owner.registerThreadMapping('/repo', 'outside');
      var completed = false;
      final pending = owner.loadInitial('/repo').then((_) => completed = true);
      container.read(input.notifier).change();
      subscription.close();
      await container.pump();
      expect(container.read(projectThreadsSliceProvider.notifier), same(owner));
      expect(factories, 1);
      owner.selectThreadId('/other', 'b');
      owner.setThreadRunning('outside', isRunning: true);
      expect(owner.stateFor('/repo').runningThreadIds, {'outside'});
      final session = owner.registerSession(
        '/repo',
        const AgentSession(id: 'new', providerId: 'test'),
      );
      expect(session.createdAt, DateTime.fromMillisecondsSinceEpoch(0));
      expect(completed, isFalse);
      owner.stopAcceptingCommandsAndSettleWaiters();
      await pending;
      await owner.drainExecutions();
      expect(runner.closeCalls, 1);
    },
  );

  test(
    'disposed container ignores every late ingress and a new session has a new owner',
    () async {
      final oldContainer = _container((_) => _PendingRunner());
      final old = oldContainer.read(projectThreadsSliceProvider.notifier);
      final pending = old.loadInitial('/repo');
      final fork = old.forkThread(projectPath: '/repo', threadId: 'a');
      old.stopAcceptingCommandsAndSettleWaiters();
      await pending;
      expect(await fork, isNull);
      await old.drainExecutions();
      oldContainer.dispose();
      final nextContainer = _container((_) => _PendingRunner());
      addTearDown(nextContainer.dispose);
      final next = nextContainer.read(projectThreadsSliceProvider.notifier);
      final before = next.current;
      old.applyStatesReplacement({
        '/repo': const ProjectThreadListState(isExpanded: true),
      });
      old.applyProjectState('/repo', const ProjectThreadListState());
      old.registerThreadMapping('/repo', 'late');
      old.syncRuntimeSnapshot(
        projectPath: '/repo',
        snapshot: const AgentConversationThreadSnapshot(
          sessionId: 'late',
          providerId: 'test',
          threadTitle: '',
          runtimeStatus: null,
          waitingOnApproval: false,
          waitingOnUserInput: false,
          isTurnRunning: true,
        ),
      );
      old.updateThreadTitle(
        projectPath: '/repo',
        threadId: 'late',
        title: 'late',
      );
      old.updateThreadPreview(
        projectPath: '/repo',
        threadId: 'late',
        preview: 'late',
      );
      old.setThreadRunning('late', isRunning: true);
      old.activeThreadCleared('/repo', 'late');
      old.operationSucceeded(const OperationId(scope: 'old', sequence: 1));
      expect(next, isNot(same(old)));
      expect(next.current, same(before));
      expect(next.states, isEmpty);
    },
  );

  test(
    'stop is idempotent and drain retains a failed physical completion',
    () async {
      final gate = Completer<void>();
      final runner = _PendingRunner(gate.future);
      final container = _container((_) => runner);
      addTearDown(container.dispose);
      final owner = container.read(projectThreadsSliceProvider.notifier);
      expect(owner.drainExecutions, throwsStateError);
      final pending = owner.loadInitial('/repo');
      final fork = owner.forkThread(projectPath: '/repo', threadId: 'a');
      owner.stopAcceptingCommandsAndSettleWaiters();
      owner.stopAcceptingCommandsAndSettleWaiters();
      await pending;
      expect(await fork, isNull);
      final drain = owner.drainExecutions();
      expect(owner.drainExecutions(), same(drain));
      final error = StateError('physical failure');
      final assertion = expectLater(drain, throwsA(same(error)));
      gate.completeError(error);
      await assertion;
      await expectLater(owner.drainExecutions(), throwsA(same(error)));
      expect(runner.closeCalls, 1);
    },
  );
}

ProviderContainer _container(ProjectThreadsRunnerFactory factory) =>
    ProviderContainer(
      overrides: [
        projectThreadsSliceDependenciesProvider.overrideWithValue(
          ProjectThreadsSliceDependencies(
            initialState: ProjectThreadsSliceState(),
          ),
        ),
        projectThreadsRunnerFactoryProvider.overrideWithValue(factory),
      ],
    );

List<Future<void> Function()> _voidCommands(
  ProjectThreadsSliceNotifier owner,
) => [
  () => owner.toggleProject('/repo'),
  () => owner.setArchivedView(projectPath: '/repo', archived: true),
  () => owner.loadInitial('/repo'),
  () => owner.loadMore('/repo'),
  () => owner.renameThread(projectPath: '/repo', threadId: 'a', name: 'new'),
  () => owner.archiveThread(projectPath: '/repo', threadId: 'a'),
  () => owner.unarchiveThread(projectPath: '/repo', threadId: 'a'),
  () => owner.deleteThread(projectPath: '/repo', threadId: 'a'),
];

final class _Input extends Notifier<int> {
  @override
  int build() => 0;
  void change() => state++;
}

final class _PendingRunner implements ProjectThreadsSliceEffectRunner {
  _PendingRunner([Future<void>? execution])
    : execution = execution ?? Future.value();
  final Future<void> execution;
  int closeCalls = 0;
  @override
  void run(ProjectThreadsSliceEffect effect) {}
  @override
  void close() => closeCalls++;
  @override
  Future<void> drainExecutions() => execution;
}

final class _SynchronousRunner implements ProjectThreadsSliceEffectRunner {
  late ProjectThreadsStateOwner owner;
  int calls = 0;
  Object? error;
  StackTrace? trace;
  OperationId? lastId;
  final session = const AgentSession(id: 'fork', providerId: 'test');
  @override
  void run(ProjectThreadsSliceEffect effect) {
    calls++;
    final id = switch (effect) {
      ToggleProjectThreadsEffect(:final operationId) ||
      SetArchivedProjectThreadsEffect(:final operationId) ||
      LoadInitialProjectThreadsEffect(:final operationId) ||
      LoadMoreProjectThreadsEffect(:final operationId) ||
      RenameProjectThreadEffect(:final operationId) ||
      ArchiveProjectThreadEffect(:final operationId) ||
      UnarchiveProjectThreadEffect(:final operationId) ||
      DeleteProjectThreadEffect(:final operationId) ||
      ForkProjectThreadEffect(:final operationId) => operationId,
      _ => throw StateError('unexpected synchronous effect'),
    };
    lastId = id;
    if (error case final failure?) {
      owner.operationFailed(id, failure, trace!);
    } else if (effect is ForkProjectThreadEffect) {
      owner.forkSucceeded(id, session);
    } else {
      owner.operationSucceeded(id);
    }
  }

  @override
  void close() {}
  @override
  Future<void> drainExecutions() async {}
}

import '../../../testing/project_threads_test_container.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_slice/project_threads_slice_dependencies.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/app/plugins/agent_provider_manifest.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/features/project_threads/application/project_threads_slice/project_threads_slice_effect.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_slice/project_threads_slice_state.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_slice/project_threads_slice_notifier.dart';
import 'package:zeta/src/features/project_threads/domain/project_thread_list_state.dart';

void main() {
  group('ProjectThreadsSliceNotifier', () {
    test('keeps selection globally unique and publishes immutable state', () {
      final runner = _RecordingRunner();
      final container = projectThreadsTestContainer(
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
      final store = container.read(projectThreadsSliceProvider.notifier);
      addTearDown(store.stopAcceptingCommandsAndSettleWaiters);
      var publishes = 0;
      container.listen(projectThreadsSliceProvider, (_, _) => publishes += 1);

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
        final container = projectThreadsTestContainer(
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
        final store = container.read(projectThreadsSliceProvider.notifier);
        addTearDown(store.stopAcceptingCommandsAndSettleWaiters);

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
        final container = projectThreadsTestContainer(
          initialState: ProjectThreadsSliceState(),
          effectRunner: runner,
        );
        final store = container.read(projectThreadsSliceProvider.notifier);
        addTearDown(store.stopAcceptingCommandsAndSettleWaiters);

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
      final container = projectThreadsTestContainer(
        initialState: ProjectThreadsSliceState(),
        effectRunner: runner,
        now: () => now,
      );
      final store = container.read(projectThreadsSliceProvider.notifier);
      addTearDown(store.stopAcceptingCommandsAndSettleWaiters);

      final thread = store.registerSession(
        '/repo',
        const AgentSession(id: 'new', providerId: defaultAgentProviderId),
        preview: 'first prompt',
        markRunning: true,
      );

      expect(thread.preview, 'first prompt');
      expect(thread.createdAt, now);
      expect(thread.updatedAt, now);
      expect(store.stateFor('/repo').threads.single.id, 'new');
      expect(store.stateFor('/repo').selectedThreadId, 'new');
      expect(store.stateFor('/repo').runningThreadIds, contains('new'));
      expect(runner.effects, isEmpty);
    });

    test('dispose closes runner and drops late state/result ingress', () async {
      final runner = _RecordingRunner();
      final container = projectThreadsTestContainer(
        initialState: ProjectThreadsSliceState(),
        effectRunner: runner,
      );
      final store = container.read(projectThreadsSliceProvider.notifier);
      final future = store.loadInitial('/repo');
      final effect = runner.effects.single as LoadInitialProjectThreadsEffect;

      store.stopAcceptingCommandsAndSettleWaiters();
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
  group('synchronous Project Threads operations', () {
    test('tracks running thread ids from conversation runtime snapshots', () {
      final controller = _createSyncStore(
        threads: _legacyThreads(1).reversed.toList(),
      );

      controller.syncRuntimeSnapshot(
        projectPath: '/repo',
        snapshot: const AgentConversationThreadSnapshot(
          sessionId: 'thread-0',
          providerId: defaultAgentProviderId,
          threadTitle: 'Thread 0',
          isTurnRunning: true,
          runtimeStatus: AgentThreadRuntimeStatus.active,
          waitingOnApproval: false,
          waitingOnUserInput: false,
        ),
      );

      expect(controller.stateFor('/repo').runningThreadIds, <String>{
        'thread-0',
      });

      controller.syncRuntimeSnapshot(
        projectPath: '/repo',
        snapshot: const AgentConversationThreadSnapshot(
          sessionId: 'thread-0',
          providerId: defaultAgentProviderId,
          threadTitle: 'Thread 0',
          isTurnRunning: false,
          runtimeStatus: AgentThreadRuntimeStatus.idle,
          waitingOnApproval: false,
          waitingOnUserInput: false,
        ),
      );

      expect(controller.stateFor('/repo').runningThreadIds, isEmpty);
    });

    test('syncRuntimeSnapshot updates thread preview beside title', () {
      final controller = _createSyncStore(
        threads: [
          _legacyThread(
            id: 'thread-0',
            providerId: defaultAgentProviderId,
            title: 'Formal Title',
            preview: 'first user message',
            updatedAt: DateTime.utc(2026, 7, 14),
          ),
        ],
      );

      expect(
        controller.stateFor('/repo').threads.single.preview,
        'first user message',
      );

      controller.syncRuntimeSnapshot(
        projectPath: '/repo',
        snapshot: const AgentConversationThreadSnapshot(
          sessionId: 'thread-0',
          providerId: defaultAgentProviderId,
          threadTitle: 'Formal Title',
          threadPreview: 'Last turn summary text',
          isTurnRunning: false,
          runtimeStatus: AgentThreadRuntimeStatus.idle,
          waitingOnApproval: false,
          waitingOnUserInput: false,
        ),
      );

      final thread = controller.stateFor('/repo').threads.single;
      expect(thread.title, 'Formal Title');
      expect(thread.preview, 'Last turn summary text');
      expect(thread.displayName, 'Formal Title');
    });

    test(
      'syncRuntimeSnapshot ignores placeholder New thread title for all providers',
      () {
        // Codex/Grok 新建会话 snapshot 常带「New thread」占位；写进列表 title 后
        // 会被当成正式名，挡住首条消息临时标题与 generated_title。
        final controller = _createSyncStore();

        controller.registerSession(
          '/repo',
          const AgentSession(
            id: 'new-thread',
            providerId: defaultAgentProviderId,
          ),
          preview: 'help me fix this',
        );
        expect(controller.stateFor('/repo').threads.single.title, isNull);

        controller.syncRuntimeSnapshot(
          projectPath: '/repo',
          snapshot: const AgentConversationThreadSnapshot(
            sessionId: 'new-thread',
            providerId: defaultAgentProviderId,
            threadTitle: agentDefaultThreadTitle,
            isTurnRunning: true,
            runtimeStatus: AgentThreadRuntimeStatus.active,
            waitingOnApproval: false,
            waitingOnUserInput: false,
          ),
        );

        final afterPlaceholder = controller.stateFor('/repo').threads.single;
        expect(afterPlaceholder.title, isNull);
        expect(afterPlaceholder.preview, 'help me fix this');
        expect(afterPlaceholder.displayName, 'help me fix this');

        // 正式标题仍可写回。
        controller.syncRuntimeSnapshot(
          projectPath: '/repo',
          snapshot: const AgentConversationThreadSnapshot(
            sessionId: 'new-thread',
            providerId: defaultAgentProviderId,
            threadTitle: 'Help me fix this bug',
            isTurnRunning: false,
            runtimeStatus: AgentThreadRuntimeStatus.idle,
            waitingOnApproval: false,
            waitingOnUserInput: false,
          ),
        );
        expect(
          controller.stateFor('/repo').threads.single.title,
          'Help me fix this bug',
        );
      },
    );

    test(
      'registerSession drops session placeholder title so list title stays empty',
      () {
        final controller = _createSyncStore();

        controller.registerSession(
          '/repo',
          const AgentSession(
            id: 'new-thread',
            providerId: defaultAgentProviderId,
            title: agentDefaultThreadTitle,
          ),
          preview: 'first prompt',
        );

        final thread = controller.stateFor('/repo').threads.single;
        expect(thread.title, isNull);
        expect(thread.preview, 'first prompt');
        expect(thread.createdAt, _fixedNow);
        expect(thread.updatedAt, _fixedNow);
        expect(thread.displayName, 'first prompt');
      },
    );

    test('promotes an existing thread to the top when a turn starts', () {
      // 列表按 recency 倒序：thread-2 最新在顶，thread-0 最旧在底。
      final controller = _createSyncStore(
        threads: _legacyThreads(3).reversed.toList(),
      );

      final before = controller.stateFor('/repo').threads;
      expect(before.map((thread) => thread.id).toList(), <String>[
        'thread-2',
        'thread-1',
        'thread-0',
      ]);
      final previousRecency = before.last.recencyAt ?? before.last.updatedAt;

      controller.syncRuntimeSnapshot(
        projectPath: '/repo',
        snapshot: const AgentConversationThreadSnapshot(
          sessionId: 'thread-0',
          providerId: defaultAgentProviderId,
          threadTitle: 'Thread 0',
          isTurnRunning: true,
          runtimeStatus: AgentThreadRuntimeStatus.active,
          waitingOnApproval: false,
          waitingOnUserInput: false,
        ),
      );

      final after = controller.stateFor('/repo').threads;
      expect(after.map((thread) => thread.id).toList(), <String>[
        'thread-0',
        'thread-2',
        'thread-1',
      ]);
      final promotedRecency = after.first.recencyAt ?? after.first.updatedAt;
      expect(promotedRecency.isAfter(previousRecency), isTrue);
      expect(promotedRecency, _fixedNow);
      expect(controller.stateFor('/repo').runningThreadIds, <String>{
        'thread-0',
      });

      // 同一 turn 期间再次标记 running 不应反复打乱次序或无意义重建。
      final orderAfterFirstPromote = after.map((thread) => thread.id).toList();
      controller.setThreadRunning('thread-0', isRunning: true);
      expect(
        controller
            .stateFor('/repo')
            .threads
            .map((thread) => thread.id)
            .toList(),
        orderAfterFirstPromote,
      );
    });

    test('setThreadRunning promotes mapped thread on idle-to-running edge', () {
      final controller = _createSyncStore();
      controller.applyProjectState(
        '/repo',
        ProjectThreadListState(
          hasLoaded: true,
          threads: List<AgentThreadSummary>.unmodifiable(<AgentThreadSummary>[
            _legacyThread(
              id: 'thread-a',
              providerId: defaultAgentProviderId,
              updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
              title: 'A',
            ),
            _legacyThread(
              id: 'thread-b',
              providerId: defaultAgentProviderId,
              updatedAt: DateTime.fromMillisecondsSinceEpoch(1000),
              title: 'B',
            ),
          ]),
        ),
      );
      controller.registerThreadMapping('/repo', 'thread-b');

      controller.setThreadRunning('thread-b', isRunning: true);

      final state = controller.stateFor('/repo');
      expect(state.threads.map((thread) => thread.id).toList(), <String>[
        'thread-b',
        'thread-a',
      ]);
      expect(state.runningThreadIds, <String>{'thread-b'});
      expect(state.threads.first.recencyAt, _fixedNow);
      expect(
        (state.threads.first.recencyAt ?? state.threads.first.updatedAt)
            .isAfter(DateTime.fromMillisecondsSinceEpoch(1000)),
        isTrue,
      );
    });

    test('applies waiting flags from runtime snapshots to list state', () {
      final controller = _createSyncStore(
        threads: _legacyThreads(1).reversed.toList(),
      );

      controller.syncRuntimeSnapshot(
        projectPath: '/repo',
        snapshot: const AgentConversationThreadSnapshot(
          sessionId: 'thread-0',
          providerId: defaultAgentProviderId,
          threadTitle: 'Thread 0',
          isTurnRunning: true,
          runtimeStatus: AgentThreadRuntimeStatus.active,
          waitingOnApproval: true,
          waitingOnUserInput: false,
        ),
      );

      final waiting = controller.stateFor('/repo').threads.single;
      expect(waiting.status, AgentThreadRuntimeStatus.active);
      expect(waiting.waitingOnApproval, isTrue);
      expect(controller.stateFor('/repo').runningThreadIds, <String>{
        'thread-0',
      });

      controller.syncRuntimeSnapshot(
        projectPath: '/repo',
        snapshot: const AgentConversationThreadSnapshot(
          sessionId: 'thread-0',
          providerId: defaultAgentProviderId,
          threadTitle: 'Thread 0',
          isTurnRunning: false,
          runtimeStatus: AgentThreadRuntimeStatus.idle,
          waitingOnApproval: false,
          waitingOnUserInput: false,
        ),
      );

      final idle = controller.stateFor('/repo').threads.single;
      expect(idle.status, AgentThreadRuntimeStatus.idle);
      expect(idle.waitingOnApproval, isFalse);
      expect(controller.stateFor('/repo').runningThreadIds, isEmpty);
    });

    test('selectThreadId clears selection in other projects', () {
      final controller = _createSyncStore();

      controller.selectThreadId('/repo', 'thread-a');
      controller.selectThreadId('/other', 'thread-b');

      expect(controller.stateFor('/other').selectedThreadId, 'thread-b');
      expect(controller.stateFor('/repo').selectedThreadId, isNull);

      controller.selectThreadId('/repo', 'thread-c');
      expect(controller.stateFor('/repo').selectedThreadId, 'thread-c');
      expect(controller.stateFor('/other').selectedThreadId, isNull);
    });

    test('registerSession can optimistically mark the new thread running', () {
      final controller = _createSyncStore();

      controller.registerSession(
        '/repo',
        const AgentSession(
          id: 'new-thread',
          providerId: defaultAgentProviderId,
          title: 'New thread',
        ),
        markRunning: true,
      );

      final state = controller.stateFor('/repo');
      expect(state.threads.single.id, 'new-thread');
      expect(state.runningThreadIds, <String>{'new-thread'});
      expect(state.selectedThreadId, 'new-thread');
    });

    test('setThreadRunning toggles list busy indicator for mapped threads', () {
      final controller = _createSyncStore();

      controller.registerSession(
        '/repo',
        const AgentSession(
          id: 'new-thread',
          providerId: defaultAgentProviderId,
        ),
      );
      expect(controller.stateFor('/repo').runningThreadIds, isEmpty);

      controller.setThreadRunning('new-thread', isRunning: true);
      expect(controller.stateFor('/repo').runningThreadIds, <String>{
        'new-thread',
      });

      controller.setThreadRunning('new-thread', isRunning: false);
      expect(controller.stateFor('/repo').runningThreadIds, isEmpty);
      // registerSession 会选中该 thread，当前选中完成时不显示完成提示。
      expect(controller.stateFor('/repo').completedThreadIds, isEmpty);
    });

    test(
      'background turn completion marks completed icon until dismissed or selected',
      () {
        final controller = _createSyncStore();

        controller.registerSession(
          '/repo',
          const AgentSession(
            id: 'thread-bg',
            providerId: defaultAgentProviderId,
            title: 'Background',
          ),
        );
        controller.registerSession(
          '/repo',
          const AgentSession(
            id: 'thread-fg',
            providerId: defaultAgentProviderId,
            title: 'Foreground',
          ),
        );
        // 当前选中 thread-fg，thread-bg 在后台执行。
        controller.selectThreadId('/repo', 'thread-fg');

        controller.setThreadRunning('thread-bg', isRunning: true);
        expect(controller.stateFor('/repo').runningThreadIds, <String>{
          'thread-bg',
        });

        controller.setThreadRunning('thread-bg', isRunning: false);
        expect(controller.stateFor('/repo').runningThreadIds, isEmpty);
        expect(controller.stateFor('/repo').completedThreadIds, <String>{
          'thread-bg',
        });

        controller.dismissCompletedThread(
          projectPath: '/repo',
          threadId: 'thread-bg',
        );
        expect(controller.stateFor('/repo').completedThreadIds, isEmpty);

        controller.setThreadRunning('thread-bg', isRunning: true);
        controller.setThreadRunning('thread-bg', isRunning: false);
        expect(controller.stateFor('/repo').completedThreadIds, <String>{
          'thread-bg',
        });

        // 选中该 thread 时也清除完成提示。
        controller.selectThreadId('/repo', 'thread-bg');
        expect(controller.stateFor('/repo').completedThreadIds, isEmpty);
      },
    );

    test('syncRuntimeSnapshot keeps multiple background thread states', () {
      final controller = _createSyncStore();

      controller.registerSession(
        '/repo',
        const AgentSession(
          id: 'thread-a',
          providerId: defaultAgentProviderId,
          title: 'Thread A',
        ),
      );
      controller.registerSession(
        '/repo',
        const AgentSession(
          id: 'thread-b',
          providerId: defaultAgentProviderId,
          title: 'Thread B',
        ),
      );
      controller.selectThreadId('/repo', 'thread-b');

      controller.syncRuntimeSnapshot(
        projectPath: '/repo',
        snapshot: const AgentConversationThreadSnapshot(
          sessionId: 'thread-a',
          providerId: defaultAgentProviderId,
          threadTitle: 'Thread A',
          isTurnRunning: true,
          runtimeStatus: AgentThreadRuntimeStatus.active,
          waitingOnApproval: false,
          waitingOnUserInput: false,
        ),
      );
      controller.syncRuntimeSnapshot(
        projectPath: '/repo',
        snapshot: const AgentConversationThreadSnapshot(
          sessionId: 'thread-b',
          providerId: defaultAgentProviderId,
          threadTitle: 'Thread B',
          isTurnRunning: true,
          runtimeStatus: AgentThreadRuntimeStatus.active,
          waitingOnApproval: false,
          waitingOnUserInput: true,
        ),
      );

      final state = controller.stateFor('/repo');
      expect(state.selectedThreadId, 'thread-b');
      expect(state.runningThreadIds, <String>{'thread-a', 'thread-b'});
      final waitingThread = state.threads
          .where((thread) => thread.id == 'thread-b')
          .single;
      expect(waitingThread.status, AgentThreadRuntimeStatus.active);
      expect(waitingThread.waitingOnUserInput, isTrue);
      expect(waitingThread.waitingOnApproval, isFalse);
    });

    test(
      'selected thread turn completion clears list busy when status lags active',
      () {
        // 复现：详情页仍打开时 turn 已结束，但 runtimeStatus 仍为 active
        // （status/changed→idle 迟到），侧栏 isBusy 会一直转圈。
        final controller = _createSyncStore();

        controller.registerSession(
          '/repo',
          const AgentSession(
            id: 'thread-selected',
            providerId: defaultAgentProviderId,
            title: 'Selected',
          ),
        );
        controller.selectThreadId('/repo', 'thread-selected');

        controller.syncRuntimeSnapshot(
          projectPath: '/repo',
          snapshot: const AgentConversationThreadSnapshot(
            sessionId: 'thread-selected',
            providerId: defaultAgentProviderId,
            threadTitle: 'Selected',
            isTurnRunning: true,
            runtimeStatus: AgentThreadRuntimeStatus.active,
            waitingOnApproval: false,
            waitingOnUserInput: false,
          ),
        );
        final running = controller.stateFor('/repo').threads.single;
        expect(controller.stateFor('/repo').runningThreadIds, <String>{
          'thread-selected',
        });
        expect(running.status, AgentThreadRuntimeStatus.active);
        expect(running.isBusy, isTrue);

        controller.syncRuntimeSnapshot(
          projectPath: '/repo',
          snapshot: const AgentConversationThreadSnapshot(
            sessionId: 'thread-selected',
            providerId: defaultAgentProviderId,
            threadTitle: 'Selected',
            isTurnRunning: false,
            // 服务端尚未推送 idle，详情 snapshot 仍可能带着 active。
            runtimeStatus: AgentThreadRuntimeStatus.active,
            waitingOnApproval: false,
            waitingOnUserInput: false,
          ),
        );

        final state = controller.stateFor('/repo');
        expect(state.runningThreadIds, isEmpty);
        expect(state.completedThreadIds, isEmpty);
        final idle = state.threads.single;
        expect(idle.status, AgentThreadRuntimeStatus.idle);
        expect(idle.waitingOnApproval, isFalse);
        expect(idle.waitingOnUserInput, isFalse);
        expect(idle.isBusy, isFalse);
      },
    );

    test(
      'setThreadRunning false clears sticky active status on list summary',
      () {
        final controller = _createSyncStore();
        controller.applyProjectState(
          '/repo',
          ProjectThreadListState(
            hasLoaded: true,
            selectedThreadId: 'thread-a',
            threads: List<AgentThreadSummary>.unmodifiable(<AgentThreadSummary>[
              _legacyThread(
                id: 'thread-a',
                providerId: defaultAgentProviderId,
                updatedAt: DateTime.utc(2026, 7, 15),
                title: 'A',
              ).copyWith(
                status: AgentThreadRuntimeStatus.active,
                waitingOnApproval: false,
                waitingOnUserInput: false,
              ),
            ]),
            runningThreadIds: <String>{'thread-a'},
          ),
        );
        controller.registerThreadMapping('/repo', 'thread-a');

        controller.setThreadRunning('thread-a', isRunning: false);

        final state = controller.stateFor('/repo');
        expect(state.runningThreadIds, isEmpty);
        expect(state.completedThreadIds, isEmpty);
        expect(state.threads.single.status, AgentThreadRuntimeStatus.idle);
        expect(state.threads.single.isBusy, isFalse);
      },
    );

    test('syncRuntimeSnapshot keeps waiting flags while turn still active', () {
      final controller = _createSyncStore();

      controller.registerSession(
        '/repo',
        const AgentSession(
          id: 'thread-wait',
          providerId: defaultAgentProviderId,
          title: 'Waiting',
        ),
      );

      controller.syncRuntimeSnapshot(
        projectPath: '/repo',
        snapshot: const AgentConversationThreadSnapshot(
          sessionId: 'thread-wait',
          providerId: defaultAgentProviderId,
          threadTitle: 'Waiting',
          isTurnRunning: true,
          runtimeStatus: AgentThreadRuntimeStatus.active,
          waitingOnApproval: true,
          waitingOnUserInput: false,
        ),
      );

      final thread = controller.stateFor('/repo').threads.single;
      expect(thread.status, AgentThreadRuntimeStatus.active);
      expect(thread.waitingOnApproval, isTrue);
      expect(thread.isBusy, isTrue);
      expect(controller.stateFor('/repo').runningThreadIds, <String>{
        'thread-wait',
      });
    });
  });
  group('single thread ownership index', () {
    test(
      'initial summaries and selected ids seed mappings without a runner',
      () {
        final runner = _RecordingRunner();
        final container = projectThreadsTestContainer(
          initialState: ProjectThreadsSliceState(
            statesByProject: {
              '/a': ProjectThreadListState(threads: [_thread('a')]),
              '/b': const ProjectThreadListState(selectedThreadId: 'outside'),
            },
          ),
          effectRunner: runner,
        );
        final store = container.read(projectThreadsSliceProvider.notifier);
        addTearDown(store.stopAcceptingCommandsAndSettleWaiters);
        store.setThreadRunning('a', isRunning: true);
        store.setThreadRunning('outside', isRunning: true);
        expect(store.stateFor('/a').runningThreadIds, {'a'});
        expect(store.stateFor('/b').runningThreadIds, {'outside'});
        expect(runner.effects, isEmpty);
      },
    );

    test(
      'replacement rebuilds mappings and page ingress preserves explicit outside ids',
      () {
        final store = _createSyncStore(threads: [_thread('old')]);
        store.applyStatesReplacement({
          '/other': ProjectThreadListState(threads: [_thread('restored')]),
        });
        store.setThreadRunning('old', isRunning: true);
        expect(store.states.containsKey('/repo'), isFalse);
        store.setThreadRunning('restored', isRunning: true);
        expect(store.stateFor('/other').runningThreadIds, {'restored'});
        store.registerThreadMapping('/other', 'outside');
        store.applyProjectState(
          '/other',
          ProjectThreadListState(threads: [_thread('page')]),
        );
        store.setThreadRunning('page', isRunning: true);
        store.setThreadRunning('outside', isRunning: true);
        expect(store.stateFor('/other').runningThreadIds, {'page', 'outside'});
      },
    );

    test(
      'retention removes only excluded project mappings and preserves background work',
      () {
        final store = _createSyncStore();
        store.applyProjectState(
          '/a',
          ProjectThreadListState(threads: [_thread('a')]),
        );
        store.applyProjectState(
          '/b',
          ProjectThreadListState(threads: [_thread('b')]),
        );
        store.registerThreadMapping('/a', 'outside-a');
        store.registerThreadMapping('/b', 'outside-b');
        store.setThreadRunning('b', isRunning: true);
        store.applyProjectsRetention(['/b']);
        store.setThreadRunning('a', isRunning: true);
        store.setThreadRunning('outside-a', isRunning: true);
        store.setThreadRunning('outside-b', isRunning: true);
        expect(store.states.keys, ['/b']);
        expect(store.stateFor('/b').runningThreadIds, {'b', 'outside-b'});
        store.setThreadRunning('b', isRunning: false);
        expect(store.stateFor('/b').completedThreadIds, {'b'});
      },
    );

    test(
      'thread query returns the first matching summary without provider guessing',
      () {
        final first = _thread('duplicate');
        final store = _createSyncStore(
          threads: [
            first,
            first.copyWith(title: 'later'),
          ],
        );
        expect(store.threadFor('/repo', 'duplicate'), same(first));
        expect(store.threadFor('/other', 'duplicate'), isNull);
        store.registerThreadMapping('/repo', 'outside');
        expect(store.threadFor('/repo', 'outside'), isNull);
      },
    );

    test('removal drops mapping and reports selected removal only once', () {
      final store = _createSyncStore(
        threads: [_thread('selected'), _thread('other')],
      );
      store.selectThreadId('/repo', 'selected');
      expect(
        store.applyThreadRemoval(projectPath: '/repo', threadId: 'selected'),
        isTrue,
      );
      expect(
        store.applyThreadRemoval(projectPath: '/repo', threadId: 'selected'),
        isFalse,
      );
      store.setThreadRunning('selected', isRunning: true);
      store.setThreadRunning('other', isRunning: true);
      expect(store.stateFor('/repo').runningThreadIds, {'other'});
    });

    test(
      'close settles pending operations once and rejects late ingress and new commands',
      () async {
        final runner = _RecordingRunner();
        final container = projectThreadsTestContainer(
          initialState: ProjectThreadsSliceState(
            statesByProject: {
              '/repo': ProjectThreadListState(
                threads: [_thread('selected')],
                selectedThreadId: 'selected',
              ),
            },
          ),
          effectRunner: runner,
        );
        final store = container.read(projectThreadsSliceProvider.notifier);
        final loading = store.loadInitial('/repo');
        final forking = store.forkThread(
          projectPath: '/repo',
          threadId: 'selected',
        );
        final load = runner.effects[0] as LoadInitialProjectThreadsEffect;
        final fork = runner.effects[1] as ForkProjectThreadEffect;
        var publishes = 0;
        container.listen(projectThreadsSliceProvider, (_, _) => publishes++);
        final before = store.current;
        store.stopAcceptingCommandsAndSettleWaiters();
        await loading;
        expect(await forking, isNull);
        store.applyStatesReplacement({
          '/late': ProjectThreadListState(threads: [_thread('late')]),
        });
        store.applyProjectState(
          '/late',
          ProjectThreadListState(threads: [_thread('late')]),
        );
        store.applyThreadPrepend(projectPath: '/late', thread: _thread('late'));
        store.applyThreadSelection('/late', 'late');
        store.registerThreadMapping('/late', 'late');
        store.setThreadRunning('late', isRunning: true);
        store.applyProjectsRetention([]);
        expect(
          store.applyThreadRemoval(projectPath: '/repo', threadId: 'selected'),
          isFalse,
        );
        store.operationSucceeded(load.operationId);
        store.operationFailed(
          load.operationId,
          StateError('late'),
          StackTrace.empty,
        );
        store.forkSucceeded(
          fork.operationId,
          const AgentSession(id: 'late', providerId: defaultAgentProviderId),
        );
        expect(store.current, same(before));
        expect(store.staleResultCount, 0);
        expect(publishes, 0);
        expect(runner.closed, isTrue);
        expect(() => store.loadInitial('/repo'), throwsStateError);
        expect(
          () => store.registerSession(
            '/repo',
            const AgentSession(id: 'new', providerId: defaultAgentProviderId),
          ),
          throwsStateError,
        );
      },
    );
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

  @override
  Future<void> drainExecutions() async {}
}

final _fixedNow = DateTime.utc(2026, 9, 6);

ProjectThreadsSliceNotifier _createSyncStore({
  List<AgentThreadSummary> threads = const [],
}) {
  final runner = _RecordingRunner();
  final container = projectThreadsTestContainer(
    initialState: ProjectThreadsSliceState(
      statesByProject: {
        if (threads.isNotEmpty)
          '/repo': ProjectThreadListState(hasLoaded: true, threads: threads),
      },
    ),
    effectRunner: runner,
    now: () => _fixedNow,
  );
  final store = container.read(projectThreadsSliceProvider.notifier);
  addTearDown(() {
    expect(
      runner.effects,
      isEmpty,
      reason: 'Synchronous business must not invoke Provider effects',
    );
    store.stopAcceptingCommandsAndSettleWaiters();
  });
  return store;
}

List<AgentThreadSummary> _legacyThreads(int count, {int start = 0}) {
  return <AgentThreadSummary>[
    for (var index = start; index < start + count; index += 1)
      _legacyThread(
        id: 'thread-$index',
        providerId: defaultAgentProviderId,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(index),
        title: 'Thread $index',
        preview: 'Preview $index',
      ),
  ];
}

AgentThreadSummary _legacyThread({
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

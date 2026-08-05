import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_thread_snapshot.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_controller.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_session_snapshot_codec.dart';
import 'package:zeta/src/features/project_threads/domain/project_thread_list_state.dart';
import 'package:zeta/src/features/project_threads/domain/project_threads_session_snapshot.dart';
import 'package:zeta/src/features/project_threads/presentation/project_threads_view_model.dart';
import 'package:zeta/src/ui/features/ide/view_models/active_agent_provider_controller.dart';

import '../../../testing/agent_provider_stub_base.dart';

void main() {
  group('ProjectThreadsController', () {
    test(
      'restores expanded active project and loads first 5 threads',
      () async {
        final provider = _FakeAgentProvider(
          // 聚合后客户端分页：共 10 条时首屏 5 条，游标 agg:5。
          pages: <AgentThreadPage>[_page(_threads(10), nextCursor: null)],
        );
        final controller = _createController(provider);

        controller.restoreSession(
          projectPaths: const <String>['/repo', '/other'],
          activeProjectPath: '/repo',
          snapshot: const ProjectThreadsSessionSnapshot(),
        );
        await _flushAsync();

        final state = controller.stateFor('/repo');
        expect(state.isExpanded, isTrue);
        expect(state.threads, hasLength(5));
        expect(state.nextCursor, 'agg:5');
        expect(controller.stateFor('/other').isExpanded, isFalse);
        expect(provider.listQueries.single.projectPath, '/repo');
      },
    );

    test(
      'loads more with aggregate cursor and appends unique threads',
      () async {
        final provider = _FakeAgentProvider(
          pages: <AgentThreadPage>[
            // 首轮聚合拉取：先 5 条再 10 条，共 15 条缓存后客户端分页。
            _page(_threads(5), nextCursor: 'next'),
            _page(_threads(10, start: 5), nextCursor: null),
            // loadMore 会重新聚合拉取。
            _page(_threads(5), nextCursor: 'next'),
            _page(_threads(10, start: 5), nextCursor: null),
          ],
        );
        final controller = _createController(provider);

        controller.activateProject('/repo');
        await _flushAsync();
        expect(controller.stateFor('/repo').threads, hasLength(5));
        expect(controller.stateFor('/repo').nextCursor, 'agg:5');

        await controller.loadMore('/repo');

        expect(controller.stateFor('/repo').threads, hasLength(15));
        expect(controller.stateFor('/repo').nextCursor, isNull);
      },
    );

    test('keeps cached threads when reload fails', () async {
      final provider = _FakeAgentProvider(
        pages: <AgentThreadPage>[
          _page(_threads(1), nextCursor: null),
          // 失败路径通过 failNextList 抛错；此处不预置第二页。
        ],
      );
      final controller = _createController(provider);

      controller.activateProject('/repo');
      await _flushAsync();
      expect(controller.stateFor('/repo').threads, hasLength(1));

      provider.failNextList = true;
      await controller.loadInitial('/repo');
      await _flushAsync();

      final state = controller.stateFor('/repo');
      expect(state.threads, hasLength(1));
      expect(state.errorMessage, 'Could not load threads');
      expect(state.isLoadingInitial, isFalse);
    });

    test(
      'keeps a current session when an earlier initial load omits it',
      () async {
        final pendingPage = Completer<AgentThreadPage>();
        final provider = _FakeAgentProvider(pages: const <AgentThreadPage>[])
          ..nextListCompleter = pendingPage;
        final controller = _createController(provider);

        final loading = controller.loadInitial('/repo');
        controller.registerSession(
          '/repo',
          const AgentSession(
            id: 'current-thread',
            providerId: grokAgentProviderId,
            title: 'Current Grok thread',
          ),
          preview: '刚刚活跃的会话',
          markRunning: true,
        );
        pendingPage.complete(
          const AgentThreadPage(
            threads: <AgentThreadSummary>[],
            nextCursor: null,
          ),
        );
        await loading;

        final state = controller.stateFor('/repo');
        expect(state.threads.map((thread) => thread.id), <String>[
          'current-thread',
        ]);
        expect(state.selectedThreadId, 'current-thread');
        expect(state.runningThreadIds, <String>{'current-thread'});
        expect(state.hasLoaded, isTrue);
      },
    );

    test('retired Cursor local removal path remains unreachable', () async {
      // Arrange
      final provider = _FakeAgentProvider(
        config: AgentProviderConfig.defaultCursor.copyWith(enabled: true),
        declaredCapabilities: AgentProviderCapabilities.unsupported,
        pages: <AgentThreadPage>[
          _page(<AgentThreadSummary>[
            _thread(
              id: 'cursor-local',
              providerId: cursorAgentProviderId,
              updatedAt: DateTime.utc(2026, 7, 14),
            ),
          ], nextCursor: null),
        ],
      );
      final controller = _createController(provider);
      controller.activateProject('/repo');
      await _flushAsync();

      // Act
      await controller.deleteThread(
        projectPath: '/repo',
        threadId: 'cursor-local',
      );

      // Assert
      expect(provider.listQueries, isEmpty);
      expect(provider.removedLocalThreads, isEmpty);
      expect(provider.deletedThreads, isEmpty);
      expect(controller.stateFor('/repo').threads, isEmpty);
    });

    test(
      'tracks running thread ids from provider turn lifecycle events',
      () async {
        final provider = _FakeAgentProvider(
          pages: <AgentThreadPage>[_page(_threads(1), nextCursor: null)],
        );
        final controller = _createController(provider);

        controller.activateProject('/repo');
        await _flushAsync();

        provider.emit(
          const AgentTurnStartedEvent(
            AgentTurn(id: 'turn-1', sessionId: 'thread-0'),
          ),
        );
        await _flushAsync();

        expect(controller.stateFor('/repo').runningThreadIds, <String>{
          'thread-0',
        });

        provider.emit(
          const AgentTurnStartedEvent(
            AgentTurn(id: 'turn-2', sessionId: 'thread-unknown'),
          ),
        );
        await _flushAsync();

        expect(controller.stateFor('/repo').runningThreadIds, <String>{
          'thread-0',
        });

        provider.emit(
          const AgentTurnCompletedEvent(
            sessionId: 'thread-0',
            turnId: 'turn-1',
          ),
        );
        await _flushAsync();

        expect(controller.stateFor('/repo').runningThreadIds, isEmpty);
      },
    );

    test('promotes an existing thread to the top when a turn starts', () async {
      // 列表按 recency 倒序：thread-2 最新在顶，thread-0 最旧在底。
      final provider = _FakeAgentProvider(
        pages: <AgentThreadPage>[_page(_threads(3), nextCursor: null)],
      );
      final controller = _createController(provider);

      controller.activateProject('/repo');
      await _flushAsync();

      final before = controller.stateFor('/repo').threads;
      expect(before.map((thread) => thread.id).toList(), <String>[
        'thread-2',
        'thread-1',
        'thread-0',
      ]);
      final previousRecency = before.last.recencyAt ?? before.last.updatedAt;

      provider.emit(
        const AgentTurnStartedEvent(
          AgentTurn(id: 'turn-1', sessionId: 'thread-0'),
        ),
      );
      await _flushAsync();

      final after = controller.stateFor('/repo').threads;
      expect(after.map((thread) => thread.id).toList(), <String>[
        'thread-0',
        'thread-2',
        'thread-1',
      ]);
      final promotedRecency = after.first.recencyAt ?? after.first.updatedAt;
      expect(promotedRecency.isAfter(previousRecency), isTrue);
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
      final provider = _FakeAgentProvider(pages: const <AgentThreadPage>[]);
      final viewModel = ProjectThreadsViewModel();
      final controller = _createController(provider, viewModel: viewModel);
      viewModel.setStateFor(
        '/repo',
        ProjectThreadListState(
          hasLoaded: true,
          threads: List<AgentThreadSummary>.unmodifiable(<AgentThreadSummary>[
            _thread(
              id: 'thread-a',
              providerId: defaultAgentProviderId,
              updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
              title: 'A',
            ),
            _thread(
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
      expect(
        (state.threads.first.recencyAt ?? state.threads.first.updatedAt)
            .isAfter(DateTime.fromMillisecondsSinceEpoch(1000)),
        isTrue,
      );
    });

    test('applies thread/status/changed waiting flags to list state', () async {
      final provider = _FakeAgentProvider(
        pages: <AgentThreadPage>[_page(_threads(1), nextCursor: null)],
      );
      final controller = _createController(provider);

      controller.activateProject('/repo');
      await _flushAsync();

      provider.emit(
        const AgentThreadStatusChangedEvent(
          threadId: 'thread-0',
          status: AgentThreadRuntimeStatus.active,
          waitingOnApproval: true,
        ),
      );
      await _flushAsync();

      final waiting = controller.stateFor('/repo').threads.single;
      expect(waiting.status, AgentThreadRuntimeStatus.active);
      expect(waiting.waitingOnApproval, isTrue);
      expect(controller.stateFor('/repo').runningThreadIds, <String>{
        'thread-0',
      });

      provider.emit(
        const AgentThreadStatusChangedEvent(
          threadId: 'thread-0',
          status: AgentThreadRuntimeStatus.idle,
        ),
      );
      await _flushAsync();

      final idle = controller.stateFor('/repo').threads.single;
      expect(idle.status, AgentThreadRuntimeStatus.idle);
      expect(idle.waitingOnApproval, isFalse);
      expect(controller.stateFor('/repo').runningThreadIds, isEmpty);
    });

    test(
      'ignores duplicate loads while a project is already loading',
      () async {
        final provider = _FakeAgentProvider(
          pages: <AgentThreadPage>[_page(_threads(1), nextCursor: null)],
        );
        final controller = _createController(
          provider,
          viewModel: ProjectThreadsViewModel(),
        );

        final firstLoad = controller.loadInitial('/repo');
        final secondLoad = controller.loadInitial('/repo');
        await Future.wait(<Future<void>>[firstLoad, secondLoad]);

        expect(provider.listQueries, hasLength(1));
      },
    );

    test('sorts all provider threads by global recency', () async {
      final codex = _FakeAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        pages: <AgentThreadPage>[
          _page(<AgentThreadSummary>[
            _thread(
              id: 'codex-new',
              providerId: defaultAgentProviderId,
              updatedAt: DateTime.utc(2026, 6, 1),
            ),
            _thread(
              id: 'codex-middle',
              providerId: defaultAgentProviderId,
              updatedAt: DateTime.utc(2026, 5, 1),
            ),
          ], nextCursor: null),
        ],
      );
      final grok = _FakeAgentProvider(
        config: AgentProviderConfig.defaultGrok,
        pages: <AgentThreadPage>[
          _page(<AgentThreadSummary>[
            _thread(
              id: 'grok-old',
              providerId: grokAgentProviderId,
              updatedAt: DateTime.utc(2026, 1, 1),
            ),
          ], nextCursor: null),
        ],
      );
      final controller = _createMultiProviderController(
        codex: codex,
        grok: grok,
      );

      controller.activateProject('/repo');
      await _flushAsync();

      final ids = controller
          .stateFor('/repo')
          .threads
          .map((thread) => thread.id)
          .toList();
      expect(ids, <String>['codex-new', 'codex-middle', 'grok-old']);
      expect(codex.listQueries, isNotEmpty);
      expect(grok.listQueries, isNotEmpty);
    });

    test(
      'does not create or query retired Cursor during aggregation',
      () async {
        // Arrange
        final codex = _FakeAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          pages: <AgentThreadPage>[_page(_threads(10), nextCursor: null)],
        );
        final grok = _FakeAgentProvider(
          config: AgentProviderConfig.defaultGrok,
          pages: <AgentThreadPage>[
            _page(const <AgentThreadSummary>[], nextCursor: null),
          ],
        );
        final cursor = _FakeAgentProvider(
          config: AgentProviderConfig.defaultCursor.copyWith(enabled: true),
          declaredCapabilities: AgentProviderCapabilities.unsupported,
          pages: <AgentThreadPage>[
            _page(<AgentThreadSummary>[
              _thread(
                id: 'cursor-old',
                providerId: cursorAgentProviderId,
                updatedAt: DateTime.fromMillisecondsSinceEpoch(-1),
              ),
            ], nextCursor: null),
          ],
        );
        final createdProviderIds = <String>[];
        final controller = _createMultiProviderController(
          codex: codex,
          grok: grok,
          cursor: cursor,
          createdProviderIds: createdProviderIds,
        );

        // Act
        controller.activateProject('/repo');
        await _flushAsync();

        // Assert
        final state = controller.stateFor('/repo');
        expect(state.threads, hasLength(5));
        expect(
          state.threads.map((thread) => thread.providerId),
          everyElement(defaultAgentProviderId),
        );
        expect(state.nextCursor, 'agg:5');
        expect(cursor.listQueries, isEmpty);
        expect(createdProviderIds, isNot(contains(cursorAgentProviderId)));
      },
    );
  });

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

    test('selectThreadId clears selection in other projects', () {
      final provider = _FakeAgentProvider(pages: const <AgentThreadPage>[]);
      final controller = _createController(provider);

      controller.selectThreadId('/repo', 'thread-a');
      controller.selectThreadId('/other', 'thread-b');

      expect(controller.stateFor('/other').selectedThreadId, 'thread-b');
      expect(controller.stateFor('/repo').selectedThreadId, isNull);

      controller.selectThreadId('/repo', 'thread-c');
      expect(controller.stateFor('/repo').selectedThreadId, 'thread-c');
      expect(controller.stateFor('/other').selectedThreadId, isNull);
    });

    test('passes archived and searchTerm to listThreads', () async {
      final provider = _FakeAgentProvider(
        pages: <AgentThreadPage>[_page(_threads(1), nextCursor: null)],
      );
      final controller = _createController(provider);

      controller.activateProject('/repo');
      await _flushAsync();
      await controller.setArchivedView(projectPath: '/repo', archived: true);
      await _flushAsync();

      expect(provider.listQueries.last.archived, isTrue);
      expect(controller.stateFor('/repo').archived, isTrue);

      controller.setSearchTerm(projectPath: '/repo', searchTerm: 'foo');
      await Future<void>.delayed(projectThreadSearchDebounce);
      await _flushAsync();

      expect(provider.listQueries.last.searchTerm, 'foo');
      expect(controller.stateFor('/repo').searchTerm, 'foo');
    });

    test('renames thread and applies name updated event', () async {
      final provider = _FakeAgentProvider(
        pages: <AgentThreadPage>[_page(_threads(1), nextCursor: null)],
      );
      final controller = _createController(provider);
      controller.activateProject('/repo');
      await _flushAsync();

      await controller.renameThread(
        projectPath: '/repo',
        threadId: 'thread-0',
        name: 'Renamed',
      );
      expect(provider.renamedThreads.single.name, 'Renamed');
      expect(controller.stateFor('/repo').threads.single.title, 'Renamed');

      provider.emit(
        const AgentThreadNameUpdatedEvent(
          threadId: 'thread-0',
          threadName: 'From server',
        ),
      );
      await _flushAsync();
      expect(controller.stateFor('/repo').threads.single.title, 'From server');
    });

    test('removes archived thread and notifies active clear', () async {
      final provider = _FakeAgentProvider(
        pages: <AgentThreadPage>[_page(_threads(1), nextCursor: null)],
      );
      final cleared = <(String, String)>[];
      final controller = _createController(provider);
      controller.onActiveThreadCleared = (projectPath, threadId) {
        cleared.add((projectPath, threadId));
      };
      controller.activateProject('/repo');
      await _flushAsync();
      controller.selectThreadId('/repo', 'thread-0');

      await controller.archiveThread(
        projectPath: '/repo',
        threadId: 'thread-0',
      );
      expect(provider.archivedThreads, <String>['thread-0']);
      expect(controller.stateFor('/repo').threads, isEmpty);
      expect(cleared, <(String, String)>[('/repo', 'thread-0')]);
    });

    test('caches provider ownership when a session is created', () {
      final provider = _FakeAgentProvider(pages: const <AgentThreadPage>[]);
      final controller = _createController(provider);

      controller.registerSession(
        '/repo',
        const AgentSession(
          id: 'new-thread',
          providerId: grokAgentProviderId,
          title: 'New Grok thread',
        ),
      );

      final state = controller.stateFor('/repo');
      expect(state.selectedThreadId, 'new-thread');
      expect(state.threads, hasLength(1));
      expect(state.threads.single.providerId, grokAgentProviderId);
      expect(
        controller
            .sessionSnapshot
            .cachedThreadsByProject['/repo']
            ?.single
            .providerId,
        grokAgentProviderId,
      );
    });

    test('registerSession can optimistically mark the new thread running', () {
      final provider = _FakeAgentProvider(pages: const <AgentThreadPage>[]);
      final controller = _createController(provider);

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
      final provider = _FakeAgentProvider(pages: const <AgentThreadPage>[]);
      final controller = _createController(provider);

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
        final provider = _FakeAgentProvider(pages: const <AgentThreadPage>[]);
        final controller = _createController(provider);

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
      final provider = _FakeAgentProvider(pages: const <AgentThreadPage>[]);
      final controller = _createController(provider);

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
        final provider = _FakeAgentProvider(pages: const <AgentThreadPage>[]);
        final controller = _createController(provider);

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
        final provider = _FakeAgentProvider(pages: const <AgentThreadPage>[]);
        final viewModel = ProjectThreadsViewModel();
        final controller = _createController(provider, viewModel: viewModel);
        viewModel.setStateFor(
          '/repo',
          ProjectThreadListState(
            hasLoaded: true,
            selectedThreadId: 'thread-a',
            threads: List<AgentThreadSummary>.unmodifiable(<AgentThreadSummary>[
              _thread(
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
      final provider = _FakeAgentProvider(pages: const <AgentThreadPage>[]);
      final controller = _createController(provider);

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
}

ProjectThreadsController _createController(
  _FakeAgentProvider provider, {
  ProjectThreadsViewModel? viewModel,
}) {
  // 单 provider 配置，避免默认 Codex+Grok 下同一 fake 被聚合调用两次。
  final providerController = ActiveAgentProviderController(
    providerFactory: _FakeAgentProviderFactory(provider),
    configStore: MemoryAgentProviderConfigStore(
      AgentProviderSettings(
        providers: <AgentProviderConfig>[provider.config],
        activeProviderId: provider.config.id,
      ),
    ),
  );
  final controller = ProjectThreadsController(
    providerController: providerController,
    viewModel: viewModel,
  );
  addTearDown(() {
    controller.dispose();
    providerController.dispose();
  });
  return controller;
}

ProjectThreadsController _createMultiProviderController({
  required _FakeAgentProvider codex,
  required _FakeAgentProvider grok,
  _FakeAgentProvider? cursor,
  List<String>? createdProviderIds,
  ProjectThreadsViewModel? viewModel,
}) {
  final providerController = ActiveAgentProviderController(
    providerFactory: _MultiAgentProviderFactory(
      codex: codex,
      grok: grok,
      cursor: cursor,
      createdProviderIds: createdProviderIds,
    ),
    configStore: MemoryAgentProviderConfigStore(
      AgentProviderSettings(
        providers: <AgentProviderConfig>[
          AgentProviderConfig.defaultCodex,
          AgentProviderConfig.defaultGrok,
          if (cursor != null)
            AgentProviderConfig.defaultCursor.copyWith(enabled: true),
        ],
        activeProviderId: defaultAgentProviderId,
      ),
    ),
  );
  final controller = ProjectThreadsController(
    providerController: providerController,
    viewModel: viewModel,
  );
  addTearDown(() {
    controller.dispose();
    providerController.dispose();
  });
  return controller;
}

AgentThreadPage _page(
  List<AgentThreadSummary> threads, {
  required String? nextCursor,
}) {
  return AgentThreadPage(threads: threads, nextCursor: nextCursor);
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

Future<void> _flushAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _FakeAgentProviderFactory implements AgentProviderFactory {
  const _FakeAgentProviderFactory(this.provider);

  final _FakeAgentProvider provider;

  @override
  AgentProvider create(AgentProviderConfig config) => provider;
}

class _MultiAgentProviderFactory implements AgentProviderFactory {
  _MultiAgentProviderFactory({
    required this.codex,
    required this.grok,
    this.cursor,
    List<String>? createdProviderIds,
  }) : createdProviderIds = createdProviderIds ?? <String>[];

  final _FakeAgentProvider codex;
  final _FakeAgentProvider grok;
  final _FakeAgentProvider? cursor;
  final List<String> createdProviderIds;

  @override
  AgentProvider create(AgentProviderConfig config) {
    createdProviderIds.add(config.id);
    return switch (config.id) {
      grokAgentProviderId => grok,
      cursorAgentProviderId => cursor ?? codex,
      _ => codex,
    };
  }
}

class _FakeAgentProvider
    with AgentProviderThreadLifecycleStub
    implements AgentProvider, AgentLocalThreadListProvider {
  _FakeAgentProvider({
    required List<AgentThreadPage> pages,
    this.config = AgentProviderConfig.defaultCodex,
    this.declaredCapabilities = AgentProviderCapabilities.codexAppServer,
  }) : _pages = List<AgentThreadPage>.from(pages);

  final List<AgentThreadPage> _pages;
  final List<AgentThreadListQuery> listQueries = <AgentThreadListQuery>[];
  final StreamController<AgentEvent> _events =
      StreamController<AgentEvent>.broadcast();
  bool failNextList = false;
  Completer<AgentThreadPage>? nextListCompleter;
  final List<String> removedLocalThreads = <String>[];

  @override
  final AgentProviderConfig config;

  final AgentProviderCapabilities declaredCapabilities;

  @override
  AgentProviderCapabilities get capabilities => declaredCapabilities;

  @override
  Stream<AgentEvent> get events => _events.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<AgentThreadPage> listThreads({
    required AgentThreadListQuery query,
  }) async {
    listQueries.add(query);
    if (failNextList) {
      failNextList = false;
      throw StateError('list failed');
    }
    final completer = nextListCompleter;
    if (completer != null) {
      nextListCompleter = null;
      return completer.future;
    }
    return _pages.isEmpty
        ? const AgentThreadPage(
            threads: <AgentThreadSummary>[],
            nextCursor: null,
          )
        : _pages.removeAt(0);
  }

  @override
  Future<AgentThreadHistorySnapshot> readThreadHistory({
    required String threadId,
    String? sessionPath,
    String? projectPath,
  }) async {
    return AgentThreadHistorySnapshot(
      threadId: threadId,
      turns: const <AgentHistoryTurn>[],
    );
  }

  @override
  Future<void> unsubscribeThread(String threadId) async {}

  @override
  Future<AgentSession> startSession({required AgentContext context}) async {
    return const AgentSession(
      id: 'thread-0',
      providerId: defaultAgentProviderId,
    );
  }

  @override
  Future<AgentSession> resumeSession(
    String sessionId, {
    required AgentContext context,
  }) async {
    return AgentSession(id: sessionId, providerId: defaultAgentProviderId);
  }

  @override
  Future<AgentTurn> sendMessage({
    required AgentSession session,
    required AgentContext context,
    String? message,
    List<AgentUserInput>? inputs,
    String? clientUserMessageId,
    AgentTurnConfiguration configuration = const AgentTurnConfiguration(),
  }) async {
    return AgentTurn(id: 'turn-1', sessionId: session.id);
  }

  @override
  Future<void> steerTurn({
    required AgentSession session,
    required String expectedTurnId,
    required AgentContext context,
    String? message,
    List<AgentUserInput>? inputs,
    String? clientUserMessageId,
  }) async {}

  @override
  Future<void> cancelTurn(AgentTurn turn) async {}

  @override
  Future<AgentModelList> listModels({
    int limit = 20,
    bool includeHidden = false,
  }) async {
    return const AgentModelList(models: <AgentModelInfo>[]);
  }

  @override
  void updateModelSelection(AgentModelSelection selection) {}

  @override
  void updatePermissionSelection(AgentPermissionSelectionSnapshot selection) {}

  @override
  Future<List<AgentPermissionProfileSummary>> listPermissionProfiles() async {
    return const <AgentPermissionProfileSummary>[];
  }

  @override
  Future<void> approveGuardianDeniedAction({
    required String threadId,
    required Object event,
  }) async {}

  @override
  Future<void> respondToPermission(AgentPermissionDecision decision) async {}

  @override
  Future<void> removeThreadFromList(String threadId) async {
    removedLocalThreads.add(threadId);
  }

  @override
  Future<void> dispose() async {
    await _events.close();
  }

  void emit(AgentEvent event) {
    _events.add(event);
  }
}

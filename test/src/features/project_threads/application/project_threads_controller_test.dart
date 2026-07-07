import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_controller.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_session_snapshot_codec.dart';
import 'package:zeta/src/features/project_threads/domain/project_thread_list_state.dart';
import 'package:zeta/src/features/project_threads/domain/project_threads_session_snapshot.dart';
import 'package:zeta/src/features/project_threads/presentation/project_threads_view_model.dart';
import 'package:zeta/src/ui/features/ide/view_models/active_agent_provider_controller.dart';

void main() {
  group('ProjectThreadsController', () {
    test(
      'restores expanded active project and loads first 5 threads',
      () async {
        final provider = _FakeAgentProvider(
          pages: <AgentThreadPage>[_page(_threads(5), nextCursor: 'next')],
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
        expect(state.nextCursor, 'next');
        expect(controller.stateFor('/other').isExpanded, isFalse);
        expect(provider.listQueries.single.limit, projectThreadInitialLimit);
        expect(provider.listQueries.single.projectPath, '/repo');
      },
    );

    test('loads more with page size 10 and appends unique threads', () async {
      final provider = _FakeAgentProvider(
        pages: <AgentThreadPage>[
          _page(_threads(5), nextCursor: 'next'),
          _page(_threads(10, start: 5), nextCursor: null),
        ],
      );
      final controller = _createController(provider);

      controller.activateProject('/repo');
      await _flushAsync();
      await controller.loadMore('/repo');

      expect(controller.stateFor('/repo').threads, hasLength(15));
      expect(provider.listQueries.last.limit, projectThreadPageLimit);
      expect(provider.listQueries.last.cursor, 'next');
    });

    test('keeps cached threads when reload fails', () async {
      final provider = _FakeAgentProvider(
        pages: <AgentThreadPage>[_page(_threads(1), nextCursor: null)],
      );
      final controller = _createController(provider);

      controller.activateProject('/repo');
      await _flushAsync();

      provider.failNextList = true;
      await controller.loadInitial('/repo');

      final state = controller.stateFor('/repo');
      expect(state.threads, hasLength(1));
      expect(state.errorMessage, 'Could not load threads');
      expect(state.isLoadingInitial, isFalse);
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
  });
}

ProjectThreadsController _createController(
  _FakeAgentProvider provider, {
  ProjectThreadsViewModel? viewModel,
}) {
  final controller = ActiveAgentProviderController(
    providerFactory: _FakeAgentProviderFactory(provider),
    configStore: MemoryAgentProviderConfigStore(),
  );
  addTearDown(controller.dispose);
  return ProjectThreadsController(
    providerController: controller,
    viewModel: viewModel,
  );
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
      AgentThreadSummary(
        id: 'thread-$index',
        providerId: defaultAgentProviderId,
        projectPath: '/repo',
        title: 'Thread $index',
        preview: 'Preview $index',
        createdAt: DateTime.fromMillisecondsSinceEpoch(index),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(index),
        status: AgentThreadRuntimeStatus.idle,
      ),
  ];
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

class _FakeAgentProvider implements AgentProvider {
  _FakeAgentProvider({required List<AgentThreadPage> pages})
    : _pages = List<AgentThreadPage>.from(pages);

  final List<AgentThreadPage> _pages;
  final List<AgentThreadListQuery> listQueries = <AgentThreadListQuery>[];
  final StreamController<AgentEvent> _events =
      StreamController<AgentEvent>.broadcast();
  bool failNextList = false;

  @override
  AgentProviderConfig get config => AgentProviderConfig.defaultCodex;

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
  }) async {
    return AgentThreadHistorySnapshot(
      threadId: threadId,
      turns: const <AgentHistoryTurn>[],
    );
  }

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
    required String message,
    required AgentContext context,
  }) async {
    return AgentTurn(id: 'turn-1', sessionId: session.id);
  }

  @override
  Future<void> steerTurn({
    required AgentSession session,
    required String message,
    required AgentContext context,
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
  Future<void> respondToPermission(AgentPermissionDecision decision) async {}

  @override
  Future<void> dispose() async {
    await _events.close();
  }

  void emit(AgentEvent event) {
    _events.add(event);
  }
}

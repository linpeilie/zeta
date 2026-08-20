import 'dart:async';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:agent_provider_repository/agent_provider_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:project_session_repository/project_session_repository.dart';
import 'package:zeta/project_threads/project_threads.dart';

class _MockProjectSessionRepository extends Mock
    implements ProjectSessionRepository {}

class _MockAgentProviderRepository extends Mock
    implements AgentProviderRepository {}

class _MockNamingPort extends Mock implements AgentThreadNamingPort {}

class _MockArchivalPort extends Mock implements AgentThreadArchivalPort {}

class _MockDeletionPort extends Mock implements AgentThreadDeletionPort {}

final class _FakeRuntime implements AgentRuntimePort {
  @override
  AgentProviderConfig get config => AgentProviderConfig(
    id: 'codex',
    displayName: 'Codex',
    kind: AgentProviderKind.codexAppServer,
    command: 'codex',
  );

  @override
  AgentProviderCapabilities get capabilities =>
      AgentProviderCapabilities.unsupported;

  @override
  Stream<AgentEvent> get events => const Stream<AgentEvent>.empty();

  @override
  AgentRuntimeInfo? get runtimeInfo => null;

  @override
  AgentProviderLifecycleState get lifecycleState =>
      AgentProviderLifecycleState.ready;

  @override
  AgentRuntimeScope? get runtimeScope => null;

  @override
  void updateModelSelection(AgentModelSelection selection) {}

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}
}

final class _FakeConversation implements AgentConversationPort {
  @override
  Future<AgentSession> startSession({
    required AgentContext context,
    AgentPermissionRequestSnapshot permissionSnapshot =
        const AgentPermissionRequestSnapshot.providerFallback(),
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AgentSession> resumeSession(
    String sessionId, {
    required AgentContext context,
    AgentPermissionRequestSnapshot permissionSnapshot =
        const AgentPermissionRequestSnapshot.providerFallback(),
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AgentTurn> sendMessage({
    required AgentSession session,
    required AgentContext context,
    String? message,
    List<AgentUserInput>? inputs,
    String? clientUserMessageId,
    AgentTurnConfiguration configuration = const AgentTurnConfiguration(),
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> cancelTurn(AgentTurn turn) {
    throw UnimplementedError();
  }
}

void main() {
  final createdAt = DateTime.utc(2026, 1, 2);
  final thread = AgentThreadSummary(
    id: 'thread-1',
    providerId: 'codex',
    projectPath: '/repo',
    title: 'First',
    preview: 'hello',
    createdAt: createdAt,
    updatedAt: createdAt,
    status: AgentThreadRuntimeStatus.idle,
  );
  final more = AgentThreadSummary(
    id: 'thread-2',
    providerId: 'codex',
    projectPath: '/repo',
    title: 'Second',
    preview: 'more',
    createdAt: createdAt,
    updatedAt: createdAt,
    status: AgentThreadRuntimeStatus.idle,
  );
  const sessionFailure = ProjectSessionRepositoryFailure(
    operation: ProjectSessionRepositoryOperation.threadPage,
    code: ProjectSessionRepositoryFailureCode.externalFailure,
    diagnosticCode: 'page',
  );

  group(ProjectThreadsBloc, () {
    late ProjectSessionRepository sessions;
    late AgentProviderRepository providers;
    late StreamController<ProjectSessionSnapshot?> snapshots;
    late AgentThreadNamingPort naming;
    late AgentThreadArchivalPort archival;
    late AgentThreadDeletionPort deletion;

    setUpAll(() {
      registerFallbackValue(ProjectThreadQuery(projectPath: '/repo'));
    });

    setUp(() {
      sessions = _MockProjectSessionRepository();
      providers = _MockAgentProviderRepository();
      snapshots = StreamController<ProjectSessionSnapshot?>.broadcast();
      naming = _MockNamingPort();
      archival = _MockArchivalPort();
      deletion = _MockDeletionPort();
      when(
        () => sessions.snapshotChanges,
      ).thenAnswer((_) => snapshots.stream);
      when(() => sessions.threadPage(any())).thenAnswer(
        (_) async => ProjectThreadPage(
          threads: <AgentThreadSummary>[thread],
          nextCursor: 'agg:1',
        ),
      );
      when(() => providers.bundleFor(any())).thenReturn(
        AgentProviderBundle(
          runtime: _FakeRuntime(),
          conversation: _FakeConversation(),
          threadNaming: naming,
          threadArchival: archival,
          threadDeletion: deletion,
        ),
      );
      when(
        () => naming.renameThread(
          threadId: any(named: 'threadId'),
          name: any(named: 'name'),
        ),
      ).thenAnswer((_) async {});
      when(() => archival.archiveThread(any())).thenAnswer((_) async {});
      when(() => archival.unarchiveThread(any())).thenAnswer((_) async {});
      when(() => deletion.deleteThread(any())).thenAnswer((_) async {});
    });

    tearDown(() async {
      await snapshots.close();
    });

    ProjectThreadsBloc build() {
      return ProjectThreadsBloc(
        projectSessionRepository: sessions,
        agentProviderRepository: providers,
      );
    }

    Future<void> activate(ProjectThreadsBloc bloc) async {
      bloc.add(const ProjectThreadsProjectActivated('/repo'));
      await Future<void>.delayed(Duration.zero);
    }

    blocTest<ProjectThreadsBloc, ProjectThreadsState>(
      'loads the first page after a project is activated',
      build: build,
      act: (bloc) => bloc.add(const ProjectThreadsProjectActivated('/repo')),
      expect: () => <Matcher>[
        isA<ProjectThreadsState>().having(
          (state) => state.status,
          'status',
          ProjectThreadsStatus.loading,
        ),
        isA<ProjectThreadsState>()
            .having(
              (state) => state.status,
              'status',
              ProjectThreadsStatus.ready,
            )
            .having((state) => state.hasMore, 'hasMore', isTrue)
            .having((state) => state.threads, 'threads', <AgentThreadSummary>[
              thread,
            ]),
      ],
    );

    blocTest<ProjectThreadsBloc, ProjectThreadsState>(
      'ignores blank project activation',
      build: build,
      act: (bloc) => bloc.add(const ProjectThreadsProjectActivated('  ')),
      expect: () => const <ProjectThreadsState>[],
    );

    blocTest<ProjectThreadsBloc, ProjectThreadsState>(
      'restarts search against the current project',
      build: build,
      act: (bloc) async {
        await activate(bloc);
        bloc.add(const ProjectThreadsSearchChanged('hello'));
      },
      verify: (bloc) {
        expect(bloc.state.searchTerm, 'hello');
        verify(() => sessions.threadPage(any()))
            .called(greaterThanOrEqualTo(2));
      },
    );

    blocTest<ProjectThreadsBloc, ProjectThreadsState>(
      'reloads when the archived filter changes',
      build: build,
      act: (bloc) async {
        await activate(bloc);
        bloc.add(const ProjectThreadsArchivedFilterChanged(archived: true));
      },
      verify: (bloc) {
        expect(bloc.state.archived, isTrue);
      },
    );

    blocTest<ProjectThreadsBloc, ProjectThreadsState>(
      'appends the next page when load more is requested',
      build: () {
        when(() => sessions.threadPage(any())).thenAnswer((invocation) async {
          final query =
              invocation.positionalArguments.first as ProjectThreadQuery;
          if (query.cursor == null) {
            return ProjectThreadPage(
              threads: <AgentThreadSummary>[thread],
              nextCursor: 'agg:1',
            );
          }
          return ProjectThreadPage(
            threads: <AgentThreadSummary>[more],
            nextCursor: null,
          );
        });
        return build();
      },
      act: (bloc) async {
        await activate(bloc);
        bloc.add(const ProjectThreadsLoadMoreRequested());
      },
      verify: (bloc) {
        expect(bloc.state.threads, <AgentThreadSummary>[thread, more]);
        expect(bloc.state.hasMore, isFalse);
      },
    );

    blocTest<ProjectThreadsBloc, ProjectThreadsState>(
      'emits failure when the initial page throws',
      build: () {
        when(() => sessions.threadPage(any())).thenThrow(
          const ProjectSessionRepositoryException(
            failure: sessionFailure,
            cause: 'page',
            stackTrace: StackTrace.empty,
          ),
        );
        return build();
      },
      act: (bloc) => bloc.add(const ProjectThreadsProjectActivated('/repo')),
      expect: () => <Matcher>[
        isA<ProjectThreadsState>().having(
          (state) => state.status,
          'status',
          ProjectThreadsStatus.loading,
        ),
        isA<ProjectThreadsState>()
            .having(
              (state) => state.status,
              'status',
              ProjectThreadsStatus.failure,
            )
            .having((state) => state.sessionFailure, 'failure', sessionFailure),
      ],
    );

    blocTest<ProjectThreadsBloc, ProjectThreadsState>(
      'selects a thread',
      build: build,
      act: (bloc) => bloc.add(const ProjectThreadsThreadSelected('thread-1')),
      expect: () => <ProjectThreadsState>[
        const ProjectThreadsState().copyWith(selectedThreadId: 'thread-1'),
      ],
    );

    blocTest<ProjectThreadsBloc, ProjectThreadsState>(
      'renames through the provider naming port then reloads',
      build: build,
      seed: () => ProjectThreadsState(
        status: ProjectThreadsStatus.ready,
        projectPath: '/repo',
        threads: <AgentThreadSummary>[thread],
        selectedThreadId: 'thread-1',
      ),
      act: (bloc) {
        bloc.add(
          const ProjectThreadsRenameRequested(
            threadId: 'thread-1',
            name: 'Renamed',
          ),
        );
      },
      verify: (_) {
        verify(
          () => naming.renameThread(threadId: 'thread-1', name: 'Renamed'),
        ).called(1);
      },
    );

    blocTest<ProjectThreadsBloc, ProjectThreadsState>(
      'archives, unarchives, and deletes through capability ports',
      build: build,
      seed: () => ProjectThreadsState(
        status: ProjectThreadsStatus.ready,
        projectPath: '/repo',
        threads: <AgentThreadSummary>[thread],
      ),
      act: (bloc) async {
        bloc.add(const ProjectThreadsArchiveRequested('thread-1'));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const ProjectThreadsUnarchiveRequested('thread-1'));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const ProjectThreadsDeleteRequested('thread-1'));
      },
      verify: (_) {
        verify(() => archival.archiveThread('thread-1')).called(1);
        verify(() => archival.unarchiveThread('thread-1')).called(1);
        verify(() => deletion.deleteThread('thread-1')).called(1);
      },
    );

    blocTest<ProjectThreadsBloc, ProjectThreadsState>(
      'fails closed when a write capability is missing',
      build: () {
        when(() => providers.bundleFor(any())).thenReturn(
          AgentProviderBundle(
            runtime: _FakeRuntime(),
            conversation: _FakeConversation(),
          ),
        );
        return build();
      },
      seed: () => ProjectThreadsState(
        status: ProjectThreadsStatus.ready,
        projectPath: '/repo',
        threads: <AgentThreadSummary>[thread],
      ),
      act: (bloc) {
        bloc.add(
          const ProjectThreadsRenameRequested(
            threadId: 'thread-1',
            name: 'Renamed',
          ),
        );
      },
      expect: () => <Matcher>[
        isA<ProjectThreadsState>()
            .having(
              (state) => state.status,
              'status',
              ProjectThreadsStatus.failure,
            )
            .having(
              (state) => state.providerFailure?.diagnosticCode,
              'diagnosticCode',
              'thread_naming_unavailable',
            ),
      ],
    );

    blocTest<ProjectThreadsBloc, ProjectThreadsState>(
      'emits a provider failure when bundle resolution throws',
      build: () {
        when(() => providers.bundleFor(any())).thenThrow(
          const AgentProviderRepositoryException(
            failure: AgentProviderFailure(
              code: AgentProviderFailureCode.unavailable,
              diagnosticCode: 'provider_disabled',
            ),
            operation: AgentProviderRepositoryOperation.resolveBundle,
            cause: 'disabled',
            stackTrace: StackTrace.empty,
          ),
        );
        return build();
      },
      seed: () => ProjectThreadsState(
        status: ProjectThreadsStatus.ready,
        projectPath: '/repo',
        threads: <AgentThreadSummary>[thread],
      ),
      act: (bloc) {
        bloc.add(const ProjectThreadsDeleteRequested('thread-1'));
      },
      expect: () => <Matcher>[
        isA<ProjectThreadsState>().having(
          (state) => state.providerFailure?.code,
          'code',
          AgentProviderFailureCode.unavailable,
        ),
      ],
    );

    blocTest<ProjectThreadsBloc, ProjectThreadsState>(
      'maps unexpected write errors to an unknown provider failure',
      build: () {
        when(
          () => naming.renameThread(
            threadId: any(named: 'threadId'),
            name: any(named: 'name'),
          ),
        ).thenThrow(Exception('io'));
        return build();
      },
      seed: () => ProjectThreadsState(
        status: ProjectThreadsStatus.ready,
        projectPath: '/repo',
        threads: <AgentThreadSummary>[thread],
      ),
      act: (bloc) {
        bloc.add(
          const ProjectThreadsRenameRequested(
            threadId: 'thread-1',
            name: 'Renamed',
          ),
        );
      },
      expect: () => <Matcher>[
        isA<ProjectThreadsState>().having(
          (state) => state.providerFailure?.code,
          'code',
          AgentProviderFailureCode.unknown,
        ),
      ],
    );

    blocTest<ProjectThreadsBloc, ProjectThreadsState>(
      'syncs the selected thread from session snapshot updates',
      build: build,
      seed: () => const ProjectThreadsState(projectPath: '/repo'),
      act: (bloc) async {
        bloc.add(const ProjectThreadsSubscriptionRequested());
        await Future<void>.delayed(Duration.zero);
        snapshots.add(
          ProjectSessionSnapshot(
            activeProjectPath: '/repo',
            selectedThreadIdsByProject: const <String, String>{
              '/repo': 'thread-9',
            },
          ),
        );
        await Future<void>.delayed(Duration.zero);
      },
      expect: () => <Matcher>[
        isA<ProjectThreadsState>().having(
          (state) => state.selectedThreadId,
          'selectedThreadId',
          'thread-9',
        ),
      ],
    );

    blocTest<ProjectThreadsBloc, ProjectThreadsState>(
      'does not search, filter, load more, or refresh without a project',
      build: build,
      act: (bloc) {
        bloc
          ..add(const ProjectThreadsSearchChanged('q'))
          ..add(const ProjectThreadsArchivedFilterChanged(archived: true))
          ..add(const ProjectThreadsLoadMoreRequested())
          ..add(const ProjectThreadsRefreshRequested())
          ..add(
            const ProjectThreadsRenameRequested(
              threadId: 'missing',
              name: 'n',
            ),
          );
      },
      expect: () => const <ProjectThreadsState>[],
    );

    blocTest<ProjectThreadsBloc, ProjectThreadsState>(
      'emits failure when load more throws',
      build: () {
        when(() => sessions.threadPage(any())).thenThrow(
          const ProjectSessionRepositoryException(
            failure: sessionFailure,
            cause: 'page',
            stackTrace: StackTrace.empty,
          ),
        );
        return build();
      },
      seed: () => const ProjectThreadsState(
        status: ProjectThreadsStatus.ready,
        projectPath: '/repo',
        nextCursor: 'agg:1',
      ),
      act: (bloc) => bloc.add(const ProjectThreadsLoadMoreRequested()),
      expect: () => <Matcher>[
        isA<ProjectThreadsState>().having(
          (state) => state.status,
          'status',
          ProjectThreadsStatus.loadingMore,
        ),
        isA<ProjectThreadsState>().having(
          (state) => state.sessionFailure,
          'failure',
          sessionFailure,
        ),
      ],
    );

    blocTest<ProjectThreadsBloc, ProjectThreadsState>(
      'retains partial catalog failures alongside a page',
      build: () {
        when(() => sessions.threadPage(any())).thenAnswer(
          (_) async => ProjectThreadPage(
            threads: <AgentThreadSummary>[thread],
            nextCursor: null,
            failures: const <ProjectThreadProviderFailure>[
              ProjectThreadProviderFailure(
                providerId: 'grok',
                code: ProjectThreadProviderFailureCode.externalFailure,
              ),
            ],
          ),
        );
        return build();
      },
      act: (bloc) => bloc.add(const ProjectThreadsProjectActivated('/repo')),
      verify: (bloc) {
        expect(bloc.state.catalogFailures, hasLength(1));
      },
    );

    blocTest<ProjectThreadsBloc, ProjectThreadsState>(
      'refreshes the current project',
      build: build,
      seed: () => const ProjectThreadsState(
        status: ProjectThreadsStatus.ready,
        projectPath: '/repo',
      ),
      act: (bloc) => bloc.add(const ProjectThreadsRefreshRequested()),
      verify: (bloc) {
        expect(bloc.state.status, ProjectThreadsStatus.ready);
        verify(() => sessions.threadPage(any())).called(1);
      },
    );

    test('copyWith clears optional thread fields', () {
      const failure = ProjectSessionRepositoryFailure(
        operation: ProjectSessionRepositoryOperation.threadPage,
        code: ProjectSessionRepositoryFailureCode.closed,
        diagnosticCode: 'closed',
      );
      const state = ProjectThreadsState(
        projectPath: '/repo',
        nextCursor: 'agg:1',
        selectedThreadId: 'thread-1',
        sessionFailure: failure,
        providerFailure: AgentProviderFailure(
          code: AgentProviderFailureCode.unknown,
        ),
      );
      final cleared = state.copyWith(
        clearProject: true,
        clearNextCursor: true,
        clearSelected: true,
        clearSessionFailure: true,
        clearProviderFailure: true,
      );
      expect(cleared.projectPath, isNull);
      expect(cleared.hasMore, isFalse);
      expect(cleared.selectedThreadId, isNull);
      expect(cleared.sessionFailure, isNull);
      expect(cleared.providerFailure, isNull);
    });

    test('event equality uses value props', () {
      expect(
        const ProjectThreadsSubscriptionRequested().props,
        isEmpty,
      );
      expect(
        const ProjectThreadsProjectActivated('/repo').props,
        <Object?>['/repo'],
      );
      expect(
        const ProjectThreadsSearchChanged('q').props,
        <Object?>['q'],
      );
      expect(
        const ProjectThreadsArchivedFilterChanged(archived: true).props,
        <Object?>[true],
      );
      expect(const ProjectThreadsLoadMoreRequested().props, isEmpty);
      expect(const ProjectThreadsRefreshRequested().props, isEmpty);
      expect(
        const ProjectThreadsThreadSelected('t').props,
        <Object?>['t'],
      );
      expect(
        const ProjectThreadsRenameRequested(threadId: 't', name: 'n').props,
        <Object?>['t', 'n'],
      );
      expect(const ProjectThreadsArchiveRequested('t').props, <Object?>['t']);
      expect(
        const ProjectThreadsUnarchiveRequested('t').props,
        <Object?>['t'],
      );
      expect(const ProjectThreadsDeleteRequested('t').props, <Object?>['t']);
      expect(const ProjectThreadsSnapshotUpdated(null).props, <Object?>[null]);
    });
  });
}

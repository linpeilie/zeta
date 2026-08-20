import 'dart:async';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:agent_provider_repository/agent_provider_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:project_session_repository/project_session_repository.dart';
import 'package:zeta/l10n/l10n.dart';
import 'package:zeta/project_threads/project_threads.dart';

import '../../helpers/helpers.dart';

class _MockProjectThreadsBloc
    extends MockBloc<ProjectThreadsEvent, ProjectThreadsState>
    implements ProjectThreadsBloc {}

class _MockProjectSessionRepository extends Mock
    implements ProjectSessionRepository {}

class _MockAgentProviderRepository extends Mock
    implements AgentProviderRepository {}

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

  group(ProjectThreadsPage, () {
    late ProjectSessionRepository sessions;
    late AgentProviderRepository providers;

    setUp(() {
      sessions = _MockProjectSessionRepository();
      providers = _MockAgentProviderRepository();
      when(
        () => sessions.snapshotChanges,
      ).thenAnswer((_) => const Stream<ProjectSessionSnapshot?>.empty());
      when(() => sessions.threadPage(any())).thenAnswer(
        (_) async => ProjectThreadPage(
          threads: const <AgentThreadSummary>[],
          nextCursor: null,
        ),
      );
    });

    setUpAll(() {
      registerFallbackValue(ProjectThreadQuery(projectPath: '/repo'));
    });

    testWidgets('renders $ProjectThreadsView', (tester) async {
      await tester.pumpApp(
        MultiRepositoryProvider(
          providers: <RepositoryProvider<dynamic>>[
            RepositoryProvider<ProjectSessionRepository>.value(
              value: sessions,
            ),
            RepositoryProvider<AgentProviderRepository>.value(
              value: providers,
            ),
          ],
          child: const ProjectThreadsPage(projectPath: '/repo'),
        ),
      );
      await tester.pump();
      expect(find.byType(ProjectThreadsView), findsOneWidget);
    });
  });

  group(ProjectThreadsView, () {
    late ProjectThreadsBloc bloc;

    setUp(() {
      bloc = _MockProjectThreadsBloc();
      when(() => bloc.state).thenReturn(
        const ProjectThreadsState(status: ProjectThreadsStatus.ready),
      );
    });

    testWidgets('renders an empty-session message', (tester) async {
      await tester.pumpApp(
        BlocProvider.value(value: bloc, child: const ProjectThreadsView()),
      );
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(find.text(l10n.projectNoRecentSessions), findsOneWidget);
    });

    testWidgets('selects a thread when its row is tapped', (tester) async {
      when(() => bloc.state).thenReturn(
        ProjectThreadsState(
          status: ProjectThreadsStatus.ready,
          projectPath: '/repo',
          threads: <AgentThreadSummary>[thread],
        ),
      );
      await tester.pumpApp(
        BlocProvider.value(value: bloc, child: const ProjectThreadsView()),
      );
      await tester.tap(find.text('First'));
      await tester.pump();
      verify(
        () => bloc.add(const ProjectThreadsThreadSelected('thread-1')),
      ).called(1);
    });

    testWidgets('requests archive for the selected thread', (tester) async {
      when(() => bloc.state).thenReturn(
        ProjectThreadsState(
          status: ProjectThreadsStatus.ready,
          projectPath: '/repo',
          threads: <AgentThreadSummary>[thread],
          selectedThreadId: 'thread-1',
        ),
      );
      await tester.pumpApp(
        BlocProvider.value(value: bloc, child: const ProjectThreadsView()),
      );
      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.tap(find.text(l10n.threadArchive).last);
      await tester.pump();
      verify(
        () => bloc.add(const ProjectThreadsArchiveRequested('thread-1')),
      ).called(1);
    });

    testWidgets('renders loading and failure copy', (tester) async {
      when(() => bloc.state).thenReturn(
        const ProjectThreadsState(
          status: ProjectThreadsStatus.loading,
          projectPath: '/repo',
        ),
      );
      await tester.pumpApp(
        BlocProvider.value(value: bloc, child: const ProjectThreadsView()),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders a provider failure message', (tester) async {
      when(() => bloc.state).thenReturn(
        const ProjectThreadsState(
          status: ProjectThreadsStatus.failure,
          providerFailure: AgentProviderFailure(
            code: AgentProviderFailureCode.unavailable,
            diagnosticCode: 'thread_naming_unavailable',
          ),
        ),
      );
      await tester.pumpApp(
        BlocProvider.value(value: bloc, child: const ProjectThreadsView()),
      );
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(
        find.text(
          FailureMessages(l10n).agentProviderFailure(
            AgentProviderFailureCode.unavailable,
            providerName: l10n.projectNewSession,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('renders a session failure message', (tester) async {
      when(() => bloc.state).thenReturn(
        const ProjectThreadsState(
          status: ProjectThreadsStatus.failure,
          sessionFailure: ProjectSessionRepositoryFailure(
            operation: ProjectSessionRepositoryOperation.threadPage,
            code: ProjectSessionRepositoryFailureCode.externalFailure,
            diagnosticCode: 'page',
          ),
        ),
      );
      await tester.pumpApp(
        BlocProvider.value(value: bloc, child: const ProjectThreadsView()),
      );
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(
        find.text(
          FailureMessages(l10n).projectSessionFailure(
            ProjectSessionRepositoryFailureCode.externalFailure,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('requests load more, rename, unarchive, and delete', (
      tester,
    ) async {
      when(() => bloc.state).thenReturn(
        ProjectThreadsState(
          status: ProjectThreadsStatus.ready,
          projectPath: '/repo',
          threads: <AgentThreadSummary>[thread],
          selectedThreadId: 'thread-1',
          nextCursor: 'agg:1',
        ),
      );
      await tester.pumpApp(
        BlocProvider.value(value: bloc, child: const ProjectThreadsView()),
      );
      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.tap(find.text(l10n.projectRetryLoadSessions));
      await tester.tap(find.text(l10n.threadRename));
      await tester.tap(find.text(l10n.threadUnarchive));
      await tester.tap(find.text(l10n.threadDelete));
      await tester.pump();
      verify(
        () => bloc.add(const ProjectThreadsLoadMoreRequested()),
      ).called(1);
      verify(
        () => bloc.add(
          ProjectThreadsRenameRequested(
            threadId: 'thread-1',
            name: l10n.agentRename,
          ),
        ),
      ).called(1);
      verify(
        () => bloc.add(const ProjectThreadsUnarchiveRequested('thread-1')),
      ).called(1);
      verify(
        () => bloc.add(const ProjectThreadsDeleteRequested('thread-1')),
      ).called(1);
    });

    testWidgets('dispatches search and refresh', (tester) async {
      await tester.pumpApp(
        BlocProvider.value(value: bloc, child: const ProjectThreadsView()),
      );
      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.tap(find.text(l10n.projectRefreshSessions));
      await tester.pump();
      verify(
        () => bloc.add(const ProjectThreadsSearchChanged('hello')),
      ).called(1);
      verify(
        () => bloc.add(const ProjectThreadsRefreshRequested()),
      ).called(1);
    });

    testWidgets('toggles the archived filter', (tester) async {
      await tester.pumpApp(
        BlocProvider.value(value: bloc, child: const ProjectThreadsView()),
      );
      await tester.tap(find.byType(Switch));
      await tester.pump();
      verify(
        () => bloc.add(
          const ProjectThreadsArchivedFilterChanged(archived: true),
        ),
      ).called(1);
    });
  });
}

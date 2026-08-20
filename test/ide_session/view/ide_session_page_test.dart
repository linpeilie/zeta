import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:project_session_repository/project_session_repository.dart';
import 'package:zeta/ide_session/ide_session.dart';
import 'package:zeta/l10n/l10n.dart';

import '../../helpers/helpers.dart';

class _MockIdeSessionCubit extends MockCubit<IdeSessionState>
    implements IdeSessionCubit {}

class _MockProjectSessionRepository extends Mock
    implements ProjectSessionRepository {}

void main() {
  group(IdeSessionPage, () {
    late ProjectSessionRepository repository;

    setUp(() {
      repository = _MockProjectSessionRepository();
      when(
        () => repository.snapshotChanges,
      ).thenAnswer((_) => const Stream<ProjectSessionSnapshot?>.empty());
      when(() => repository.restore()).thenAnswer((_) async => null);
    });

    testWidgets('renders $IdeSessionView', (tester) async {
      await tester.pumpApp(
        RepositoryProvider<ProjectSessionRepository>.value(
          value: repository,
          child: const IdeSessionPage(),
        ),
      );
      await tester.pump();
      expect(find.byType(IdeSessionView), findsOneWidget);
    });
  });

  group(IdeSessionView, () {
    late IdeSessionCubit cubit;

    setUp(() {
      cubit = _MockIdeSessionCubit();
      when(() => cubit.state).thenReturn(
        const IdeSessionState(status: IdeSessionStatus.ready),
      );
      when(() => cubit.flush()).thenAnswer((_) async {});
    });

    testWidgets('renders a loading indicator for $IdeSessionStatus.initial', (
      tester,
    ) async {
      when(() => cubit.state).thenReturn(const IdeSessionState());
      await tester.pumpApp(
        BlocProvider.value(value: cubit, child: const IdeSessionView()),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders the restored project path', (tester) async {
      when(() => cubit.state).thenReturn(
        const IdeSessionState(
          status: IdeSessionStatus.ready,
          initialRoute: IdeSessionInitialRoute(projectPath: '/repo'),
        ),
      );
      await tester.pumpApp(
        BlocProvider.value(value: cubit, child: const IdeSessionView()),
      );
      expect(find.text('/repo'), findsOneWidget);
    });

    testWidgets('renders welcome copy when no project is restored', (
      tester,
    ) async {
      await tester.pumpApp(
        BlocProvider.value(value: cubit, child: const IdeSessionView()),
      );
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(find.text(l10n.homeWelcomeSubtitle), findsOneWidget);
    });

    testWidgets('renders a restoring indicator', (tester) async {
      when(() => cubit.state).thenReturn(
        const IdeSessionState(status: IdeSessionStatus.restoring),
      );
      await tester.pumpApp(
        BlocProvider.value(value: cubit, child: const IdeSessionView()),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders a session failure message', (tester) async {
      when(() => cubit.state).thenReturn(
        const IdeSessionState(
          status: IdeSessionStatus.failure,
          failure: ProjectSessionRepositoryFailure(
            operation: ProjectSessionRepositoryOperation.restore,
            code: ProjectSessionRepositoryFailureCode.malformedJson,
            diagnosticCode: 'json',
          ),
        ),
      );
      await tester.pumpApp(
        BlocProvider.value(value: cubit, child: const IdeSessionView()),
      );
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(
        find.text(
          FailureMessages(l10n).projectSessionFailure(
            ProjectSessionRepositoryFailureCode.malformedJson,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('flushes the current snapshot', (tester) async {
      await tester.pumpApp(
        BlocProvider.value(value: cubit, child: const IdeSessionView()),
      );
      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.tap(find.text(l10n.projectRefreshSessions));
      await tester.pump();
      verify(() => cubit.flush()).called(1);
    });
  });
}

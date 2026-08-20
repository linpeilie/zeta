import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:desktop_platform_repository/desktop_platform_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:workspace_repository/workspace_repository.dart';
import 'package:zeta/l10n/l10n.dart';
import 'package:zeta/workspace/workspace.dart';

import '../../helpers/helpers.dart';

class _MockWorkspaceCubit extends MockCubit<WorkspaceState>
    implements WorkspaceCubit {}

class _MockWorkspaceRepository extends Mock implements WorkspaceRepository {}

class _MockDesktopPlatformRepository extends Mock
    implements DesktopPlatformRepository {}

void main() {
  final file = WorkspaceNode(
    path: '/repo/lib/main.dart',
    name: 'main.dart',
    type: WorkspaceNodeType.file,
  );
  final directory = WorkspaceNode(
    path: '/repo/lib',
    name: 'lib',
    type: WorkspaceNodeType.directory,
  );

  group(WorkspacePage, () {
    late WorkspaceRepository workspaceRepository;
    late DesktopPlatformRepository desktopPlatformRepository;

    setUp(() {
      workspaceRepository = _MockWorkspaceRepository();
      desktopPlatformRepository = _MockDesktopPlatformRepository();
      when(
        () => workspaceRepository.indexChanges,
      ).thenAnswer((_) => const Stream<WorkspaceIndex>.empty());
      when(
        () => workspaceRepository.treeChanges,
      ).thenAnswer((_) => const Stream<WorkspaceTreeChange>.empty());
      when(
        () => workspaceRepository.index(any()),
      ).thenAnswer(
        (_) async => WorkspaceIndex(
          rootPath: '/repo',
          files: <WorkspaceNode>[file],
          visitedDirectories: 1,
          truncated: false,
          revision: 1,
        ),
      );
      when(
        () => workspaceRepository.loadChildren(
          rootPath: any(named: 'rootPath'),
          directoryPath: any(named: 'directoryPath'),
        ),
      ).thenAnswer((_) async => <WorkspaceNode>[directory]);
    });

    testWidgets('renders $WorkspaceView', (tester) async {
      await tester.pumpApp(
        MultiRepositoryProvider(
          providers: <RepositoryProvider<dynamic>>[
            RepositoryProvider<WorkspaceRepository>.value(
              value: workspaceRepository,
            ),
            RepositoryProvider<DesktopPlatformRepository>.value(
              value: desktopPlatformRepository,
            ),
          ],
          child: const WorkspacePage(),
        ),
      );
      expect(find.byType(WorkspaceView), findsOneWidget);
    });

    testWidgets('indexes an initial root path', (tester) async {
      await tester.pumpApp(
        MultiRepositoryProvider(
          providers: <RepositoryProvider<dynamic>>[
            RepositoryProvider<WorkspaceRepository>.value(
              value: workspaceRepository,
            ),
            RepositoryProvider<DesktopPlatformRepository>.value(
              value: desktopPlatformRepository,
            ),
          ],
          child: const WorkspacePage(initialRootPath: '/repo'),
        ),
      );
      await tester.pump();
      expect(find.byType(WorkspaceView), findsOneWidget);
      verify(() => workspaceRepository.index('/repo')).called(1);
    });
  });

  group(WorkspaceView, () {
    late WorkspaceCubit cubit;

    setUp(() {
      cubit = _MockWorkspaceCubit();
    });

    testWidgets('renders welcome copy when no root is selected', (
      tester,
    ) async {
      when(() => cubit.state).thenReturn(const WorkspaceState());
      await tester.pumpApp(
        BlocProvider.value(value: cubit, child: const WorkspaceView()),
      );
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(find.text(l10n.homeWelcomeSubtitle), findsOneWidget);
    });

    testWidgets('renders a loading indicator before a root is chosen', (
      tester,
    ) async {
      when(() => cubit.state).thenReturn(
        const WorkspaceState(status: WorkspaceStatus.loading),
      );
      await tester.pumpApp(
        BlocProvider.value(value: cubit, child: const WorkspaceView()),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders a workspace failure message', (tester) async {
      when(() => cubit.state).thenReturn(
        const WorkspaceState(
          status: WorkspaceStatus.failure,
          rootPath: '/repo',
          failure: WorkspaceRepositoryFailure(
            operation: WorkspaceRepositoryOperation.indexWorkspace,
            code: WorkspaceRepositoryFailureCode.accessDenied,
            diagnosticCode: 'denied',
          ),
        ),
      );
      await tester.pumpApp(
        BlocProvider.value(value: cubit, child: const WorkspaceView()),
      );
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(
        find.text(
          FailureMessages(l10n).workspaceFailure(
            WorkspaceRepositoryFailureCode.accessDenied,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('renders welcome copy when the root has no children', (
      tester,
    ) async {
      when(() => cubit.state).thenReturn(
        const WorkspaceState(
          status: WorkspaceStatus.ready,
          rootPath: '/repo',
        ),
      );
      await tester.pumpApp(
        BlocProvider.value(value: cubit, child: const WorkspaceView()),
      );
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(find.text(l10n.homeWelcomeSubtitle), findsOneWidget);
    });

    testWidgets('calls pickRoot when the open folder action is tapped', (
      tester,
    ) async {
      when(() => cubit.state).thenReturn(const WorkspaceState());
      when(() => cubit.pickRoot()).thenAnswer((_) async {});
      await tester.pumpApp(
        BlocProvider.value(value: cubit, child: const WorkspaceView()),
      );
      await tester.tap(find.text('Open project folder'));
      await tester.pump();
      verify(() => cubit.pickRoot()).called(1);
    });

    testWidgets('calls reveal when a selected path is present', (tester) async {
      when(() => cubit.state).thenReturn(
        const WorkspaceState().copyWith(selectedPath: '/repo/lib'),
      );
      when(() => cubit.reveal(any())).thenAnswer((_) async {});
      await tester.pumpApp(
        BlocProvider.value(value: cubit, child: const WorkspaceView()),
      );
      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.tap(find.text(l10n.projectOpenInFileManager));
      await tester.pump();
      verify(() => cubit.reveal('/repo/lib')).called(1);
    });

    testWidgets('selects a file and toggles a directory', (tester) async {
      when(() => cubit.state).thenReturn(
        WorkspaceState(
          status: WorkspaceStatus.ready,
          rootPath: '/repo',
          expandedPaths: const <String>{'/repo/lib'},
          childrenByPath: <String, List<WorkspaceNode>>{
            '/repo': <WorkspaceNode>[directory, file],
            '/repo/lib': <WorkspaceNode>[file],
          },
        ),
      );
      when(() => cubit.select(any())).thenReturn(null);
      when(() => cubit.toggle(any())).thenAnswer((_) async {});
      await tester.pumpApp(
        BlocProvider.value(value: cubit, child: const WorkspaceView()),
      );
      expect(find.text('lib'), findsOneWidget);
      expect(find.text('main.dart'), findsWidgets);
      await tester.tap(find.text('lib'));
      await tester.pump();
      verify(() => cubit.select('/repo/lib')).called(1);
      verify(() => cubit.toggle('/repo/lib')).called(1);
      await tester.tap(find.text('main.dart').first);
      await tester.pump();
      verify(() => cubit.select('/repo/lib/main.dart')).called(1);
    });
  });
}

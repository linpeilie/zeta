import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:desktop_platform_repository/desktop_platform_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:project_session_repository/project_session_repository.dart';
import 'package:workspace_repository/workspace_repository.dart';
import 'package:zeta/ide_shell/ide_shell.dart';

class _MockWorkspaceRepository extends Mock implements WorkspaceRepository {}

class _MockProjectSessionRepository extends Mock
    implements ProjectSessionRepository {}

class _MockDesktopPlatformRepository extends Mock
    implements DesktopPlatformRepository {}

class _MockWindowCommands extends Mock implements DesktopWindowCommands {}

class _MockMenuCommands extends Mock implements DesktopMenuCommands {}

void main() {
  const workbench = ProjectWorkbenchSnapshot(
    leftSidebarVisible: false,
    agentUsageExpanded: true,
    leftSidebarWidth: 320,
  );
  final snapshot = ProjectSessionSnapshot(
    projectPaths: const <String>['/repo'],
    activeProjectPath: '/repo',
    workbench: workbench,
  );

  group(IdeShellBloc, () {
    late WorkspaceRepository workspace;
    late ProjectSessionRepository sessions;
    late DesktopPlatformRepository desktop;
    late DesktopWindowCommands window;
    late DesktopMenuCommands menu;
    late StreamController<ProjectSessionSnapshot?> snapshots;
    late StreamController<MenuCommand> commands;

    setUpAll(() {
      registerFallbackValue(ProjectSessionSnapshot());
    });

    setUp(() {
      workspace = _MockWorkspaceRepository();
      sessions = _MockProjectSessionRepository();
      desktop = _MockDesktopPlatformRepository();
      window = _MockWindowCommands();
      menu = _MockMenuCommands();
      snapshots = StreamController<ProjectSessionSnapshot?>.broadcast();
      commands = StreamController<MenuCommand>.broadcast();
      when(() => sessions.snapshotChanges).thenAnswer((_) => snapshots.stream);
      when(() => sessions.snapshot).thenReturn(snapshot);
      when(() => sessions.save(any())).thenAnswer((_) async {});
      when(() => desktop.windowCommands).thenReturn(window);
      when(() => desktop.menuCommands).thenReturn(menu);
      when(() => menu.commands).thenAnswer((_) => commands.stream);
      when(() => desktop.pickDirectory()).thenAnswer((_) async => '/picked');
      when(
        () => workspace.loadChildren(
          rootPath: any(named: 'rootPath'),
          directoryPath: any(named: 'directoryPath'),
        ),
      ).thenAnswer((_) async => const <WorkspaceNode>[]);
      when(() => window.minimize()).thenAnswer((_) async {});
      when(() => window.toggleMaximize()).thenAnswer((_) async {});
      when(() => window.close()).thenAnswer((_) async {});
    });

    tearDown(() async {
      await snapshots.close();
      await commands.close();
    });

    IdeShellBloc build() {
      return IdeShellBloc(
        workspaceRepository: workspace,
        projectSessionRepository: sessions,
        desktopPlatformRepository: desktop,
      );
    }

    blocTest<IdeShellBloc, IdeShellState>(
      'hydrates workbench and listens for external snapshots',
      build: build,
      act: (bloc) async {
        bloc.add(const IdeShellStarted());
        await Future<void>.delayed(Duration.zero);
        snapshots.add(ProjectSessionSnapshot());
      },
      expect: () => <Matcher>[
        isA<IdeShellState>()
            .having((state) => state.status, 'status', IdeShellStatus.ready)
            .having(
              (state) => state.workbench.leftSidebarVisible,
              'sidebar',
              isFalse,
            ),
        isA<IdeShellState>().having(
          (state) => state.workbench.leftSidebarVisible,
          'sidebar',
          isTrue,
        ),
      ],
    );

    blocTest<IdeShellBloc, IdeShellState>(
      'picks a project, persists it, then clears the one-shot path',
      build: build,
      act: (bloc) async {
        bloc.add(const IdeShellStarted());
        await Future<void>.delayed(Duration.zero);
        bloc.add(const IdeShellOpenProjectRequested());
      },
      expect: () => <Matcher>[
        isA<IdeShellState>().having(
          (state) => state.status,
          'status',
          IdeShellStatus.ready,
        ),
        isA<IdeShellState>().having(
          (state) => state.pickedProjectPath,
          'picked',
          '/picked',
        ),
      ],
      verify: (bloc) {
        verify(() => desktop.pickDirectory()).called(1);
        verify(() => sessions.save(any())).called(1);
      },
    );

    blocTest<IdeShellBloc, IdeShellState>(
      'opens the first project on a clean install without a snapshot',
      build: build,
      setUp: () {
        when(() => sessions.snapshot).thenReturn(null);
      },
      act: (bloc) async {
        bloc.add(const IdeShellStarted());
        await Future<void>.delayed(Duration.zero);
        bloc.add(const IdeShellOpenProjectRequested());
      },
      expect: () => <Matcher>[
        isA<IdeShellState>().having(
          (state) => state.status,
          'status',
          IdeShellStatus.ready,
        ),
        isA<IdeShellState>().having(
          (state) => state.pickedProjectPath,
          'picked',
          '/picked',
        ),
      ],
      verify: (bloc) {
        final saved =
            verify(() => sessions.save(captureAny())).captured.single
                as ProjectSessionSnapshot;
        expect(saved.projectPaths, <String>['/picked']);
        expect(saved.activeProjectPath, '/picked');
      },
    );

    blocTest<IdeShellBloc, IdeShellState>(
      'clears the one-shot picked project path',
      build: build,
      seed: () => const IdeShellState(pickedProjectPath: '/picked'),
      act: (bloc) => bloc.add(const IdeShellProjectPickedConsumed()),
      expect: () => <IdeShellState>[
        const IdeShellState(),
      ],
    );

    blocTest<IdeShellBloc, IdeShellState>(
      'ignores a cancelled directory picker',
      build: build,
      setUp: () {
        when(() => desktop.pickDirectory()).thenAnswer((_) async => null);
      },
      act: (bloc) async {
        bloc.add(const IdeShellStarted());
        await Future<void>.delayed(Duration.zero);
        bloc.add(const IdeShellOpenProjectRequested());
      },
      expect: () => <Matcher>[
        isA<IdeShellState>().having(
          (state) => state.status,
          'status',
          IdeShellStatus.ready,
        ),
      ],
    );

    blocTest<IdeShellBloc, IdeShellState>(
      'maps a native open-project menu command onto the picker',
      build: build,
      act: (bloc) async {
        bloc.add(const IdeShellStarted());
        await Future<void>.delayed(Duration.zero);
        commands.add(MenuCommand.openProject);
        await Future<void>.delayed(Duration.zero);
      },
      verify: (bloc) {
        verify(() => desktop.pickDirectory()).called(1);
      },
    );

    blocTest<IdeShellBloc, IdeShellState>(
      'persists sidebar, usage, and size workbench edits',
      build: build,
      act: (bloc) async {
        bloc.add(const IdeShellStarted());
        await Future<void>.delayed(Duration.zero);
        bloc
          ..add(const IdeShellSidebarVisibilityToggled())
          ..add(const IdeShellUsageExpandedToggled())
          ..add(const IdeShellSidebarWidthChanged(240))
          ..add(const IdeShellUsageHeightFractionChanged(0.4));
      },
      verify: (bloc) {
        verify(() => sessions.save(any())).called(4);
        expect(bloc.state.workbench.leftSidebarWidth, 240);
        expect(bloc.state.workbench.agentUsageHeightFraction, 0.4);
      },
    );

    blocTest<IdeShellBloc, IdeShellState>(
      'does not duplicate an already open project path',
      build: build,
      setUp: () {
        when(() => desktop.pickDirectory()).thenAnswer((_) async => '/repo');
      },
      act: (bloc) async {
        bloc.add(const IdeShellStarted());
        await Future<void>.delayed(Duration.zero);
        bloc.add(const IdeShellOpenProjectRequested());
      },
      verify: (bloc) {
        final captured = verify(() => sessions.save(captureAny())).captured;
        expect(
          (captured.single as ProjectSessionSnapshot).projectPaths,
          <String>['/repo'],
        );
      },
    );

    blocTest<IdeShellBloc, IdeShellState>(
      'forwards window commands through the desktop repository',
      build: build,
      act: (bloc) async {
        bloc.add(const IdeShellStarted());
        await Future<void>.delayed(Duration.zero);
        bloc
          ..add(const IdeShellWindowMinimizeRequested())
          ..add(const IdeShellWindowMaximizeToggled())
          ..add(const IdeShellWindowCloseRequested());
      },
      verify: (bloc) {
        verify(() => window.minimize()).called(1);
        verify(() => window.toggleMaximize()).called(1);
        verify(() => window.close()).called(1);
      },
    );

    blocTest<IdeShellBloc, IdeShellState>(
      'fail-closes window command errors as a platform operation',
      build: build,
      setUp: () {
        when(() => window.minimize()).thenThrow(
          const DesktopPlatformException(
            operation: DesktopPlatformOperation.minimize,
            cause: 'denied',
          ),
        );
      },
      act: (bloc) async {
        bloc.add(const IdeShellStarted());
        await Future<void>.delayed(Duration.zero);
        bloc.add(const IdeShellWindowMinimizeRequested());
      },
      expect: () => <Matcher>[
        isA<IdeShellState>().having(
          (state) => state.status,
          'status',
          IdeShellStatus.ready,
        ),
        isA<IdeShellState>().having(
          (state) => state.failure?.code,
          'code',
          IdeShellFailureCode.platformOperation,
        ),
      ],
    );

    blocTest<IdeShellBloc, IdeShellState>(
      'fail-closes picker errors as a platform operation',
      build: build,
      setUp: () {
        when(() => desktop.pickDirectory()).thenThrow(
          const DesktopPlatformException(
            operation: DesktopPlatformOperation.pickDirectory,
            cause: 'denied',
          ),
        );
      },
      act: (bloc) async {
        bloc.add(const IdeShellStarted());
        await Future<void>.delayed(Duration.zero);
        bloc.add(const IdeShellOpenProjectRequested());
      },
      expect: () => <Matcher>[
        isA<IdeShellState>().having(
          (state) => state.status,
          'status',
          IdeShellStatus.ready,
        ),
        isA<IdeShellState>()
            .having((state) => state.status, 'status', IdeShellStatus.failure)
            .having(
              (state) => state.failure?.code,
              'code',
              IdeShellFailureCode.platformOperation,
            ),
      ],
    );

    blocTest<IdeShellBloc, IdeShellState>(
      'fail-closes workbench persistence errors',
      build: build,
      setUp: () {
        when(() => sessions.save(any())).thenThrow(
          ProjectSessionRepositoryException(
            failure: const ProjectSessionRepositoryFailure(
              operation: ProjectSessionRepositoryOperation.save,
              code: ProjectSessionRepositoryFailureCode.externalFailure,
              diagnosticCode: 'save',
            ),
            cause: 'disk',
            stackTrace: StackTrace.current,
          ),
        );
      },
      act: (bloc) async {
        bloc.add(const IdeShellStarted());
        await Future<void>.delayed(Duration.zero);
        bloc.add(const IdeShellSidebarVisibilityToggled());
      },
      expect: () => <Matcher>[
        isA<IdeShellState>().having(
          (state) => state.status,
          'status',
          IdeShellStatus.ready,
        ),
        isA<IdeShellState>().having(
          (state) => state.workbench.leftSidebarVisible,
          'sidebar',
          isTrue,
        ),
        isA<IdeShellState>().having(
          (state) => state.failure?.code,
          'code',
          IdeShellFailureCode.sessionPersist,
        ),
      ],
    );

    test('releases subscriptions on close', () async {
      final bloc = build()..add(const IdeShellStarted());
      await Future<void>.delayed(Duration.zero);
      await bloc.close();
      expect(snapshots.hasListener, isFalse);
      expect(commands.hasListener, isFalse);
    });

    test('copyWith replaces and clears optional shell fields', () {
      const failure = IdeShellFailure(IdeShellFailureCode.platformOperation);
      const state = IdeShellState(
        pickedProjectPath: '/repo',
        failure: failure,
      );
      expect(
        state.copyWith(clearPickedProjectPath: true, clearFailure: true),
        const IdeShellState(),
      );
      expect(
        state.copyWith(status: IdeShellStatus.ready).status,
        IdeShellStatus.ready,
      );
    });

    test('event equality uses value props', () {
      expect(const IdeShellStarted().props, isEmpty);
      expect(
        IdeShellSnapshotUpdated(snapshot).props,
        <Object?>[snapshot],
      );
      expect(const IdeShellOpenProjectRequested().props, isEmpty);
      expect(const IdeShellProjectPickedConsumed().props, isEmpty);
      expect(const IdeShellSidebarVisibilityToggled().props, isEmpty);
      expect(const IdeShellUsageExpandedToggled().props, isEmpty);
      expect(const IdeShellSidebarWidthChanged(1).props, <Object?>[1.0]);
      expect(
        const IdeShellUsageHeightFractionChanged(0.2).props,
        <Object?>[0.2],
      );
      expect(const IdeShellWindowMinimizeRequested().props, isEmpty);
      expect(const IdeShellWindowMaximizeToggled().props, isEmpty);
      expect(const IdeShellWindowCloseRequested().props, isEmpty);
      expect(
        const IdeShellFailure(IdeShellFailureCode.platformOperation).props,
        <Object?>[IdeShellFailureCode.platformOperation],
      );
    });
  });
}

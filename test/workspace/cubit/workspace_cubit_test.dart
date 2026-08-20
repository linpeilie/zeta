import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:desktop_platform_repository/desktop_platform_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:workspace_repository/workspace_repository.dart';
import 'package:zeta/workspace/workspace.dart';

class _MockWorkspaceRepository extends Mock implements WorkspaceRepository {}

class _MockDesktopPlatformRepository extends Mock
    implements DesktopPlatformRepository {}

void main() {
  const root = '/repo';
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
  final index = WorkspaceIndex(
    rootPath: root,
    files: <WorkspaceNode>[file],
    visitedDirectories: 2,
    truncated: false,
    revision: 1,
  );
  const accessDenied = WorkspaceRepositoryFailure(
    operation: WorkspaceRepositoryOperation.indexWorkspace,
    code: WorkspaceRepositoryFailureCode.accessDenied,
    diagnosticCode: 'denied',
  );
  const cancelled = WorkspaceRepositoryFailure(
    operation: WorkspaceRepositoryOperation.indexWorkspace,
    code: WorkspaceRepositoryFailureCode.cancelled,
    diagnosticCode: 'cancelled',
  );

  WorkspaceRepositoryException exceptionFor(
    WorkspaceRepositoryFailure failure,
  ) {
    return WorkspaceRepositoryException(
      failure: failure,
      cause: Exception(),
      stackTrace: StackTrace.empty,
    );
  }

  group(WorkspaceCubit, () {
    late WorkspaceRepository workspaceRepository;
    late DesktopPlatformRepository desktopPlatformRepository;
    late StreamController<WorkspaceIndex> indexChanges;
    late StreamController<WorkspaceTreeChange> treeChanges;

    setUp(() {
      workspaceRepository = _MockWorkspaceRepository();
      desktopPlatformRepository = _MockDesktopPlatformRepository();
      indexChanges = StreamController<WorkspaceIndex>.broadcast();
      treeChanges = StreamController<WorkspaceTreeChange>.broadcast();
      when(
        () => workspaceRepository.indexChanges,
      ).thenAnswer((_) => indexChanges.stream);
      when(
        () => workspaceRepository.treeChanges,
      ).thenAnswer((_) => treeChanges.stream);
    });

    tearDown(() async {
      await indexChanges.close();
      await treeChanges.close();
    });

    WorkspaceCubit build() {
      return WorkspaceCubit(
        workspaceRepository: workspaceRepository,
        desktopPlatformRepository: desktopPlatformRepository,
      );
    }

    void stubIndex({
      List<WorkspaceNode>? children,
    }) {
      when(
        () => workspaceRepository.index(root),
      ).thenAnswer((_) async => index);
      when(
        () => workspaceRepository.loadChildren(
          rootPath: any(named: 'rootPath'),
          directoryPath: any(named: 'directoryPath'),
        ),
      ).thenAnswer(
        (_) async => children ?? <WorkspaceNode>[directory],
      );
    }

    test('initial state is $WorkspaceStatus.initial', () {
      final cubit = build();
      expect(cubit.state, const WorkspaceState());
      addTearDown(cubit.close);
    });

    test('copyWith clears optional workspace fields', () {
      final state = WorkspaceState(
        status: WorkspaceStatus.ready,
        rootPath: root,
        index: index,
        selectedPath: file.path,
        failure: accessDenied,
      );
      final cleared = state.copyWith(
        clearRoot: true,
        clearIndex: true,
        clearSelected: true,
        clearFailure: true,
      );
      expect(cleared.rootPath, isNull);
      expect(cleared.index, isNull);
      expect(cleared.selectedPath, isNull);
      expect(cleared.failure, isNull);
      expect(state.childrenOf(root), isEmpty);
      expect(state.isExpanded(root), isFalse);
    });

    blocTest<WorkspaceCubit, WorkspaceState>(
      'emits ready after index loads children',
      build: () {
        stubIndex();
        return build();
      },
      act: (cubit) => cubit.index(root),
      expect: () => <Matcher>[
        isA<WorkspaceState>().having(
          (state) => state.status,
          'status',
          WorkspaceStatus.loading,
        ),
        isA<WorkspaceState>()
            .having((state) => state.status, 'status', WorkspaceStatus.ready)
            .having((state) => state.rootPath, 'rootPath', root)
            .having((state) => state.isExpanded(root), 'expanded', isTrue)
            .having(
              (state) => state.childrenOf(root),
              'children',
              <WorkspaceNode>[directory],
            ),
      ],
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'ignores empty index roots',
      build: build,
      act: (cubit) => cubit.index('  '),
      expect: () => const <WorkspaceState>[],
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'emits failure when index throws',
      build: () {
        when(
          () => workspaceRepository.index(root),
        ).thenThrow(exceptionFor(accessDenied));
        return build();
      },
      act: (cubit) => cubit.index(root),
      expect: () => <Matcher>[
        isA<WorkspaceState>().having(
          (state) => state.status,
          'status',
          WorkspaceStatus.loading,
        ),
        isA<WorkspaceState>().having(
          (state) => state.status,
          'status',
          WorkspaceStatus.failure,
        ),
      ],
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'emits failure when index loadChildren throws',
      build: () {
        when(
          () => workspaceRepository.index(root),
        ).thenAnswer((_) async => index);
        when(
          () => workspaceRepository.loadChildren(
            rootPath: root,
            directoryPath: root,
          ),
        ).thenThrow(
          exceptionFor(
            const WorkspaceRepositoryFailure(
              operation: WorkspaceRepositoryOperation.loadChildren,
              code: WorkspaceRepositoryFailureCode.accessDenied,
              diagnosticCode: 'children',
            ),
          ),
        );
        return build();
      },
      act: (cubit) => cubit.index(root),
      expect: () => <Matcher>[
        isA<WorkspaceState>().having(
          (state) => state.status,
          'status',
          WorkspaceStatus.loading,
        ),
        isA<WorkspaceState>().having(
          (state) => state.status,
          'status',
          WorkspaceStatus.failure,
        ),
      ],
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'swallows cancelled index results',
      build: () {
        when(
          () => workspaceRepository.index(root),
        ).thenThrow(exceptionFor(cancelled));
        return build();
      },
      act: (cubit) => cubit.index(root),
      expect: () => <Matcher>[
        isA<WorkspaceState>().having(
          (state) => state.status,
          'status',
          WorkspaceStatus.loading,
        ),
      ],
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'drops stale overlapping index results',
      build: () {
        var calls = 0;
        when(() => workspaceRepository.index(root)).thenAnswer((_) async {
          calls += 1;
          if (calls == 1) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          return index;
        });
        when(
          () => workspaceRepository.loadChildren(
            rootPath: root,
            directoryPath: root,
          ),
        ).thenAnswer((_) async => <WorkspaceNode>[directory]);
        return build();
      },
      act: (cubit) async {
        final first = cubit.index(root);
        await cubit.index(root);
        await first;
      },
      verify: (cubit) {
        expect(cubit.state.status, WorkspaceStatus.ready);
        verify(() => workspaceRepository.index(root)).called(2);
      },
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'reindexes the current root from invalidate',
      build: () {
        stubIndex();
        return build();
      },
      act: (cubit) async {
        await cubit.index(root);
        await cubit.invalidate();
      },
      verify: (cubit) {
        verify(() => workspaceRepository.index(root)).called(2);
      },
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'does nothing when invalidate has no root',
      build: build,
      act: (cubit) => cubit.invalidate(),
      expect: () => const <WorkspaceState>[],
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'toggles expanded directories and loads children',
      build: () {
        stubIndex(children: <WorkspaceNode>[file]);
        return build();
      },
      act: (cubit) async {
        await cubit.index(root);
        await cubit.toggle('/repo/lib');
        await cubit.toggle('/repo/lib');
      },
      verify: (cubit) {
        expect(cubit.state.isExpanded('/repo/lib'), isFalse);
      },
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'does nothing when toggle has no root',
      build: build,
      act: (cubit) => cubit.toggle('/repo/lib'),
      expect: () => const <WorkspaceState>[],
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'emits failure when toggle loadChildren throws',
      build: () {
        stubIndex();
        when(
          () => workspaceRepository.loadChildren(
            rootPath: root,
            directoryPath: '/repo/lib',
          ),
        ).thenThrow(
          exceptionFor(
            const WorkspaceRepositoryFailure(
              operation: WorkspaceRepositoryOperation.loadChildren,
              code: WorkspaceRepositoryFailureCode.accessDenied,
              diagnosticCode: 'toggle',
            ),
          ),
        );
        return build();
      },
      act: (cubit) async {
        await cubit.index(root);
        await cubit.toggle('/repo/lib');
      },
      verify: (cubit) {
        expect(cubit.state.status, WorkspaceStatus.failure);
        expect(cubit.state.isExpanded('/repo/lib'), isFalse);
      },
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'swallows cancelled toggle results',
      build: () {
        stubIndex();
        when(
          () => workspaceRepository.loadChildren(
            rootPath: root,
            directoryPath: '/repo/lib',
          ),
        ).thenThrow(
          exceptionFor(
            const WorkspaceRepositoryFailure(
              operation: WorkspaceRepositoryOperation.loadChildren,
              code: WorkspaceRepositoryFailureCode.cancelled,
              diagnosticCode: 'toggle-cancelled',
            ),
          ),
        );
        return build();
      },
      act: (cubit) async {
        await cubit.index(root);
        await cubit.toggle('/repo/lib');
      },
      verify: (cubit) {
        expect(cubit.state.isExpanded('/repo/lib'), isTrue);
        expect(cubit.state.status, WorkspaceStatus.loading);
      },
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'drops stale overlapping toggle results',
      build: () {
        stubIndex();
        var calls = 0;
        when(
          () => workspaceRepository.loadChildren(
            rootPath: root,
            directoryPath: '/repo/lib',
          ),
        ).thenAnswer((_) async {
          calls += 1;
          if (calls == 1) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            return <WorkspaceNode>[file];
          }
          return <WorkspaceNode>[directory];
        });
        return build();
      },
      act: (cubit) async {
        await cubit.index(root);
        final first = cubit.toggle('/repo/lib');
        await cubit.toggle('/repo/lib');
        await cubit.toggle('/repo/lib');
        await first;
      },
      verify: (cubit) {
        expect(cubit.state.isExpanded('/repo/lib'), isTrue);
        expect(cubit.state.childrenOf('/repo/lib'), <WorkspaceNode>[directory]);
      },
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'selects a path',
      build: build,
      act: (cubit) => cubit.select(file.path),
      expect: () => <WorkspaceState>[
        const WorkspaceState().copyWith(selectedPath: file.path),
      ],
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'picks a root and indexes it',
      build: () {
        when(
          () => desktopPlatformRepository.pickDirectory(
            initialDirectory: any(named: 'initialDirectory'),
          ),
        ).thenAnswer((_) async => root);
        stubIndex();
        return build();
      },
      act: (cubit) => cubit.pickRoot(),
      verify: (cubit) {
        expect(cubit.state.rootPath, root);
        verify(() => workspaceRepository.index(root)).called(1);
      },
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'does nothing when directory picking is cancelled',
      build: () {
        when(
          () => desktopPlatformRepository.pickDirectory(
            initialDirectory: any(named: 'initialDirectory'),
          ),
        ).thenAnswer((_) async => null);
        return build();
      },
      act: (cubit) => cubit.pickRoot(),
      expect: () => const <WorkspaceState>[],
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'emits failure when directory picking throws',
      build: () {
        when(
          () => desktopPlatformRepository.pickDirectory(
            initialDirectory: any(named: 'initialDirectory'),
          ),
        ).thenThrow(
          const DesktopPlatformException(
            operation: DesktopPlatformOperation.pickDirectory,
            cause: 'picker',
          ),
        );
        return build();
      },
      act: (cubit) => cubit.pickRoot(),
      expect: () => <Matcher>[
        isA<WorkspaceState>()
            .having(
              (state) => state.status,
              'status',
              WorkspaceStatus.failure,
            )
            .having(
              (state) => state.failure?.diagnosticCode,
              'diagnosticCode',
              'pickDirectory',
            ),
      ],
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'reveals a path through the platform repository',
      build: () {
        when(
          () => desktopPlatformRepository.openDirectory(any()),
        ).thenAnswer((_) async {});
        return build();
      },
      act: (cubit) => cubit.reveal(file.path),
      verify: (cubit) {
        expect(cubit.state.selectedPath, file.path);
        verify(
          () => desktopPlatformRepository.openDirectory('/repo/lib'),
        ).called(1);
      },
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'reveals a Windows path through its parent directory',
      build: () {
        when(
          () => desktopPlatformRepository.openDirectory(any()),
        ).thenAnswer((_) async {});
        return build();
      },
      act: (cubit) => cubit.reveal(r'C:\repo\lib\main.dart'),
      verify: (_) {
        verify(
          () => desktopPlatformRepository.openDirectory(r'C:\repo\lib'),
        ).called(1);
      },
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'reveals a root path without a parent separator',
      build: () {
        when(
          () => desktopPlatformRepository.openDirectory(any()),
        ).thenAnswer((_) async {});
        return build();
      },
      act: (cubit) => cubit.reveal('/repo'),
      verify: (_) {
        verify(
          () => desktopPlatformRepository.openDirectory('/repo'),
        ).called(1);
      },
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'emits failure when reveal throws',
      build: () {
        when(
          () => desktopPlatformRepository.openDirectory(any()),
        ).thenThrow(
          const DesktopPlatformException(
            operation: DesktopPlatformOperation.openDirectory,
            cause: 'reveal',
          ),
        );
        return build();
      },
      act: (cubit) => cubit.reveal(file.path),
      expect: () => <Matcher>[
        isA<WorkspaceState>().having(
          (state) => state.selectedPath,
          'selectedPath',
          file.path,
        ),
        isA<WorkspaceState>()
            .having(
              (state) => state.status,
              'status',
              WorkspaceStatus.failure,
            )
            .having(
              (state) => state.failure?.diagnosticCode,
              'diagnosticCode',
              'openDirectory',
            ),
      ],
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'reindexes after an external tree change',
      build: () {
        stubIndex();
        return build();
      },
      act: (cubit) async {
        await cubit.index(root);
        treeChanges.add(
          WorkspaceTreeChange(
            rootPath: root,
            kind: WorkspaceTreeChangeKind.modify,
            path: file.path,
            isDirectory: false,
          ),
        );
        await Future<void>.delayed(Duration.zero);
      },
      verify: (cubit) {
        verify(() => workspaceRepository.index(root)).called(2);
      },
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'ignores tree changes for other roots',
      build: () {
        stubIndex();
        return build();
      },
      act: (cubit) async {
        await cubit.index(root);
        treeChanges.add(
          WorkspaceTreeChange(
            rootPath: '/other',
            kind: WorkspaceTreeChangeKind.modify,
            path: '/other/file.dart',
            isDirectory: false,
          ),
        );
        await Future<void>.delayed(Duration.zero);
      },
      verify: (_) {
        verify(() => workspaceRepository.index(root)).called(1);
      },
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'applies matching index stream updates',
      build: () {
        stubIndex();
        return build();
      },
      act: (cubit) async {
        await cubit.index(root);
        indexChanges.add(
          WorkspaceIndex(
            rootPath: root,
            files: <WorkspaceNode>[file],
            visitedDirectories: 3,
            truncated: true,
            revision: 2,
          ),
        );
      },
      verify: (cubit) {
        expect(cubit.state.index?.revision, 2);
        expect(cubit.state.index?.truncated, isTrue);
      },
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'ignores index stream updates for other roots',
      build: () {
        stubIndex();
        return build();
      },
      act: (cubit) async {
        await cubit.index(root);
        indexChanges.add(
          WorkspaceIndex(
            rootPath: '/other',
            files: const <WorkspaceNode>[],
            visitedDirectories: 1,
            truncated: false,
            revision: 1,
          ),
        );
      },
      verify: (cubit) {
        expect(cubit.state.index?.rootPath, root);
      },
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'emits failure when the tree stream reports a repository exception',
      build: build,
      act: (cubit) async {
        treeChanges.addError(exceptionFor(accessDenied));
        await Future<void>.delayed(Duration.zero);
      },
      expect: () => <Matcher>[
        isA<WorkspaceState>()
            .having(
              (state) => state.status,
              'status',
              WorkspaceStatus.failure,
            )
            .having((state) => state.failure, 'failure', accessDenied),
      ],
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'ignores non-repository tree stream errors',
      build: build,
      act: (cubit) async {
        treeChanges.addError(Exception('watch'));
        await Future<void>.delayed(Duration.zero);
      },
      expect: () => const <WorkspaceState>[],
    );
  });
}

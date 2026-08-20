import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:project_session_repository/project_session_repository.dart';
import 'package:zeta/ide_session/ide_session.dart';

class _MockProjectSessionRepository extends Mock
    implements ProjectSessionRepository {}

void main() {
  final snapshot = ProjectSessionSnapshot(
    projectPaths: const <String>['/repo'],
    activeProjectPath: '/repo',
    currentFilePath: '/repo/lib/main.dart',
    selectedThreadIdsByProject: const <String, String>{'/repo': 'thread-1'},
    projectHomeActive: true,
  );
  const failure = ProjectSessionRepositoryFailure(
    operation: ProjectSessionRepositoryOperation.restore,
    code: ProjectSessionRepositoryFailureCode.malformedJson,
    diagnosticCode: 'json',
  );

  group(IdeSessionCubit, () {
    late ProjectSessionRepository repository;
    late StreamController<ProjectSessionSnapshot?> changes;

    setUpAll(() {
      registerFallbackValue(ProjectSessionSnapshot());
    });

    setUp(() {
      repository = _MockProjectSessionRepository();
      changes = StreamController<ProjectSessionSnapshot?>.broadcast();
      when(
        () => repository.snapshotChanges,
      ).thenAnswer((_) => changes.stream);
      when(() => repository.restore()).thenAnswer((_) async => snapshot);
      when(() => repository.save(any())).thenAnswer((_) async {});
    });

    tearDown(() async {
      await changes.close();
    });

    IdeSessionCubit build() {
      return IdeSessionCubit(projectSessionRepository: repository);
    }

    blocTest<IdeSessionCubit, IdeSessionState>(
      'restores a business snapshot into an initial route',
      build: build,
      act: (cubit) => cubit.restore(),
      expect: () => <Matcher>[
        isA<IdeSessionState>().having(
          (state) => state.status,
          'status',
          IdeSessionStatus.restoring,
        ),
        isA<IdeSessionState>()
            .having((state) => state.status, 'status', IdeSessionStatus.ready)
            .having(
              (state) => state.initialRoute.projectPath,
              'projectPath',
              '/repo',
            )
            .having(
              (state) => state.initialRoute.threadId,
              'threadId',
              'thread-1',
            )
            .having(
              (state) => state.initialRoute.projectHomeActive,
              'home',
              isTrue,
            ),
      ],
    );

    blocTest<IdeSessionCubit, IdeSessionState>(
      'restores a missing snapshot as an empty initial route',
      build: () {
        when(() => repository.restore()).thenAnswer((_) async => null);
        return build();
      },
      act: (cubit) => cubit.restore(),
      expect: () => <Matcher>[
        isA<IdeSessionState>().having(
          (state) => state.status,
          'status',
          IdeSessionStatus.restoring,
        ),
        isA<IdeSessionState>()
            .having((state) => state.snapshot, 'snapshot', isNull)
            .having(
              (state) => state.initialRoute,
              'route',
              const IdeSessionInitialRoute(),
            ),
      ],
    );

    blocTest<IdeSessionCubit, IdeSessionState>(
      'emits failure when restore throws',
      build: () {
        when(() => repository.restore()).thenThrow(
          const ProjectSessionRepositoryException(
            failure: failure,
            cause: 'json',
            stackTrace: StackTrace.empty,
          ),
        );
        return build();
      },
      act: (cubit) => cubit.restore(),
      expect: () => <Matcher>[
        isA<IdeSessionState>().having(
          (state) => state.status,
          'status',
          IdeSessionStatus.restoring,
        ),
        isA<IdeSessionState>()
            .having((state) => state.status, 'status', IdeSessionStatus.failure)
            .having((state) => state.failure, 'failure', failure),
      ],
    );

    blocTest<IdeSessionCubit, IdeSessionState>(
      'saves a business snapshot without router objects',
      build: build,
      act: (cubit) => cubit.save(snapshot),
      verify: (cubit) {
        verify(() => repository.save(snapshot)).called(1);
        expect(cubit.state.snapshot, snapshot);
      },
    );

    blocTest<IdeSessionCubit, IdeSessionState>(
      'emits failure when save throws',
      build: () {
        when(() => repository.save(any())).thenThrow(
          const ProjectSessionRepositoryException(
            failure: ProjectSessionRepositoryFailure(
              operation: ProjectSessionRepositoryOperation.save,
              code: ProjectSessionRepositoryFailureCode.externalFailure,
              diagnosticCode: 'save',
            ),
            cause: 'io',
            stackTrace: StackTrace.empty,
          ),
        );
        return build();
      },
      act: (cubit) => cubit.save(snapshot),
      expect: () => <Matcher>[
        isA<IdeSessionState>().having(
          (state) => state.status,
          'status',
          IdeSessionStatus.failure,
        ),
      ],
    );

    blocTest<IdeSessionCubit, IdeSessionState>(
      'does nothing when flush has no snapshot',
      build: build,
      act: (cubit) => cubit.flush(),
      expect: () => const <IdeSessionState>[],
    );

    blocTest<IdeSessionCubit, IdeSessionState>(
      'flushes the current snapshot',
      build: build,
      seed: () => IdeSessionState(
        status: IdeSessionStatus.ready,
        snapshot: snapshot,
      ),
      act: (cubit) => cubit.flush(),
      verify: (_) {
        verify(() => repository.save(snapshot)).called(1);
      },
    );

    test('propagates unexpected save errors through the write queue', () async {
      when(() => repository.save(any())).thenThrow(Exception('io'));
      final cubit = build();
      addTearDown(cubit.close);
      await expectLater(cubit.save(snapshot), throwsA(isA<Exception>()));
    });

    blocTest<IdeSessionCubit, IdeSessionState>(
      'clears the snapshot when the repository publishes null',
      build: build,
      seed: () => IdeSessionState(
        status: IdeSessionStatus.ready,
        snapshot: snapshot,
      ),
      act: (cubit) {
        changes.add(null);
      },
      expect: () => <Matcher>[
        isA<IdeSessionState>().having(
          (state) => state.snapshot,
          'snapshot',
          isNull,
        ),
      ],
    );

    blocTest<IdeSessionCubit, IdeSessionState>(
      'applies external snapshot updates',
      build: build,
      act: (cubit) {
        changes.add(snapshot);
      },
      expect: () => <Matcher>[
        isA<IdeSessionState>()
            .having((state) => state.snapshot, 'snapshot', snapshot)
            .having(
              (state) => state.initialRoute.filePath,
              'filePath',
              '/repo/lib/main.dart',
            ),
      ],
    );

    blocTest<IdeSessionCubit, IdeSessionState>(
      'uses agentThreadIds when selected ids are absent',
      build: () {
        when(() => repository.restore()).thenAnswer(
          (_) async => ProjectSessionSnapshot(
            activeProjectPath: '/repo',
            agentThreadIdsByProject: const <String, String>{
              '/repo': 'legacy-thread',
            },
          ),
        );
        return build();
      },
      act: (cubit) => cubit.restore(),
      verify: (cubit) {
        expect(cubit.state.initialRoute.threadId, 'legacy-thread');
      },
    );

    test('copyWith clears optional session fields', () {
      final state = IdeSessionState(
        status: IdeSessionStatus.ready,
        snapshot: snapshot,
        failure: failure,
      );
      final cleared = state.copyWith(clearSnapshot: true, clearFailure: true);
      expect(cleared.snapshot, isNull);
      expect(cleared.failure, isNull);
      expect(
        const IdeSessionInitialRoute().props,
        <Object?>[null, null, null, false],
      );
    });
  });
}

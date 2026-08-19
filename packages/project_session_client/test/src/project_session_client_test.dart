import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:project_session_client/project_session_client.dart';
import 'package:test/test.dart';

void main() {
  group('SessionSnapshotCodec', () {
    const codec = SessionSnapshotCodec();

    test('round-trips every current-schema field', () {
      final source = _snapshot('thread-1');
      final encoded = codec.encode(source);
      final decoded = codec.decode(jsonDecode(jsonEncode(encoded)));

      expect(encoded['version'], projectSessionSchemaVersion);
      expect(encoded['expandedDirectoryPaths'], <String>[
        '/repo/lib',
        '/repo/test',
      ]);
      expect(decoded.projectPaths, source.projectPaths);
      expect(decoded.activeProjectPath, '/repo');
      expect(decoded.currentFilePath, '/repo/lib/main.dart');
      expect(decoded.expandedDirectoryPaths, source.expandedDirectoryPaths);
      expect(decoded.selectedTreeKey, '/repo/lib/main.dart');
      expect(decoded.activeAgentProviderId, 'codex');
      expect(decoded.agentThreadIdsByProject, <String, String>{
        '/repo': 'thread-1',
      });
      expect(decoded.projectThreadExpansionByProject, <String, bool>{
        '/repo': true,
      });
      expect(decoded.selectedThreadIdsByProject, <String, String>{
        '/repo': 'thread-1',
      });
      expect(
        decoded.projectLastOpenedAtByPath['/repo'],
        DateTime.utc(2026, 8, 20, 1, 2, 3),
      );
      expect(decoded.projectHomeActive, isTrue);
      expect(decoded.workbench.leftSidebarVisible, isFalse);
      expect(decoded.workbench.agentUsageExpanded, isTrue);
      expect(decoded.workbench.leftSidebarWidth, 312);
      expect(decoded.workbench.agentUsageHeightFraction, 0.4);
      expect(decoded.workbench.selectedAgentUsageProviderId, 'claude');

      final thread = decoded.cachedThreadsByProject['/repo']!.single;
      expect(thread.id, 'thread-1');
      expect(thread.providerId, 'codex');
      expect(thread.projectPath, '/repo');
      expect(thread.title, 'Title');
      expect(thread.sessionPath, '/sessions/thread-1.jsonl');
      expect(thread.preview, 'Preview');
      expect(thread.createdAtMilliseconds, 1);
      expect(thread.updatedAtMilliseconds, 2);
      expect(thread.recencyAtMilliseconds, 3);
      expect(thread.status, 'idle');
      expect(thread.waitingOnApproval, isTrue);
      expect(thread.waitingOnUserInput, isFalse);
      expect(thread.raw, <String, Object?>{'cursor': 'opaque'});
    });

    test('round-trips nullable thread and workbench fields', () {
      const source = SessionSnapshotResponse(
        cachedThreadsByProject: <String, List<SessionThreadSummaryResponse>>{
          '/repo': <SessionThreadSummaryResponse>[
            SessionThreadSummaryResponse(
              id: 'id',
              providerId: 'provider',
              projectPath: '/repo',
              preview: '',
              createdAtMilliseconds: 1,
              updatedAtMilliseconds: 2,
              status: 'unknown',
            ),
          ],
        },
      );

      final decoded = codec.decode(
        jsonDecode(jsonEncode(codec.encode(source))),
      );

      final thread = decoded.cachedThreadsByProject['/repo']!.single;
      expect(thread.title, isNull);
      expect(thread.sessionPath, isNull);
      expect(thread.recencyAtMilliseconds, isNull);
      expect(thread.raw, isEmpty);
      expect(decoded.workbench.leftSidebarWidth, isNull);
      expect(decoded.workbench.agentUsageHeightFraction, isNull);
      expect(decoded.workbench.selectedAgentUsageProviderId, isNull);
    });

    test('rejects invalid roots and non-current versions', () {
      expect(
        () => codec.decode(<Object?>[]),
        throwsA(_decodeFailure(ProjectSessionDecodeFailureCode.invalidRoot)),
      );
      expect(
        () => codec.decode(<String, Object?>{'version': 3}),
        throwsA(
          _decodeFailure(ProjectSessionDecodeFailureCode.unsupportedVersion),
        ),
      );
    });

    test('rejects every invalid current-schema field family', () {
      final valid = codec.encode(const SessionSnapshotResponse());
      final invalidValues = <String, Object?>{
        'projectPaths': <Object?>['/repo', 1],
        'activeProjectPath': 1,
        'currentFilePath': false,
        'expandedDirectoryPaths': 'bad',
        'selectedTreeKey': 2,
        'activeAgentProviderId': <Object?>[],
        'agentThreadIdsByProject': <String, Object?>{'/repo': 1},
        'projectThreadExpansionByProject': <String, Object?>{'/repo': 'yes'},
        'cachedThreadsByProject': <String, Object?>{'/repo': 'bad'},
        'selectedThreadIdsByProject': <String, Object?>{'/repo': false},
        'projectLastOpenedAtByPath': <String, Object?>{'/repo': 'bad-date'},
        'projectHomeActive': 'yes',
        'workbench': 'bad',
      };

      for (final entry in invalidValues.entries) {
        expect(
          () => codec.decode(<String, Object?>{
            ...valid,
            entry.key: entry.value,
          }),
          throwsA(
            isA<ProjectSessionDecodeException>()
                .having(
                  (error) => error.code,
                  'code',
                  ProjectSessionDecodeFailureCode.invalidField,
                )
                .having((error) => error.field, 'field', entry.key),
          ),
          reason: entry.key,
        );
      }
    });

    test('rejects invalid cached thread shapes and fields', () {
      final valid = codec.encode(_snapshot('thread-1'));
      final validThread = Map<String, Object?>.from(
        ((valid['cachedThreadsByProject']! as Map<String, Object?>)['/repo']!
                    as List<Object?>)
                .single!
            as Map<String, Object?>,
      );
      final cases = <Object?>[
        1,
        <String, Object?>{...validThread, 'id': ''},
        <String, Object?>{...validThread, 'providerId': 1},
        <String, Object?>{...validThread, 'projectPath': ''},
        <String, Object?>{...validThread, 'title': false},
        <String, Object?>{...validThread, 'sessionPath': false},
        <String, Object?>{...validThread, 'preview': false},
        <String, Object?>{...validThread, 'createdAt': 1.5},
        <String, Object?>{...validThread, 'updatedAt': '2'},
        <String, Object?>{...validThread, 'recencyAt': '3'},
        <String, Object?>{...validThread, 'status': ''},
        <String, Object?>{...validThread, 'waitingOnApproval': 1},
        <String, Object?>{...validThread, 'waitingOnUserInput': 1},
        <String, Object?>{...validThread, 'raw': <Object?>[]},
      ];

      for (final thread in cases) {
        expect(
          () => codec.decode(<String, Object?>{
            ...valid,
            'cachedThreadsByProject': <String, Object?>{
              '/repo': <Object?>[thread],
            },
          }),
          throwsA(
            isA<ProjectSessionDecodeException>().having(
              (error) => error.field,
              'field',
              'cachedThreadsByProject',
            ),
          ),
        );
      }
    });

    test('rejects invalid workbench fields and ranges', () {
      final valid = codec.encode(const SessionSnapshotResponse());
      final workbench = Map<String, Object?>.from(
        valid['workbench']! as Map<String, Object?>,
      );
      final cases = <Map<String, Object?>>[
        <String, Object?>{...workbench, 'leftSidebarVisible': 1},
        <String, Object?>{...workbench, 'agentUsageExpanded': 1},
        <String, Object?>{...workbench, 'leftSidebarWidth': 'wide'},
        <String, Object?>{...workbench, 'leftSidebarWidth': 0},
        <String, Object?>{...workbench, 'leftSidebarWidth': double.infinity},
        <String, Object?>{...workbench, 'agentUsageHeightFraction': 'high'},
        <String, Object?>{...workbench, 'agentUsageHeightFraction': 0},
        <String, Object?>{...workbench, 'agentUsageHeightFraction': 1},
        <String, Object?>{
          ...workbench,
          'selectedAgentUsageProviderId': false,
        },
      ];

      for (final item in cases) {
        expect(
          () => codec.decode(<String, Object?>{
            ...valid,
            'workbench': item,
          }),
          throwsA(isA<ProjectSessionDecodeException>()),
        );
      }
    });

    test('rejects invalid map roots and non-string recency values', () {
      final valid = codec.encode(const SessionSnapshotResponse());
      for (final entry in <MapEntry<String, Object?>>[
        const MapEntry<String, Object?>('cachedThreadsByProject', 'bad'),
        const MapEntry<String, Object?>('projectLastOpenedAtByPath', 'bad'),
        const MapEntry<String, Object?>(
          'projectLastOpenedAtByPath',
          <String, Object?>{'/repo': 42},
        ),
      ]) {
        expect(
          () => codec.decode(<String, Object?>{
            ...valid,
            entry.key: entry.value,
          }),
          throwsA(isA<ProjectSessionDecodeException>()),
        );
      }
    });
  });

  group('ProjectSessionStore', () {
    test('returns null for missing and blank documents', () async {
      final storage = _MemoryStorage();
      final store = ProjectSessionStore(storage: storage);

      expect(await store.load(), isNull);
      storage.value = '  ';
      expect(await store.load(), isNull);
      await store.close();
    });

    test('saves and restores a current-schema snapshot', () async {
      final storage = _MemoryStorage();
      final store = ProjectSessionStore(storage: storage);

      await store.save(_snapshot('thread-1'));
      final restored = await store.load();

      expect(restored?.cachedThreadsByProject['/repo']?.single.id, 'thread-1');
      expect(
        jsonDecode(storage.value!) as Map<String, Object?>,
        containsPair('version', 4),
      );
      await store.close();
    });

    test('reports malformed JSON without retaining its contents', () async {
      final storage = _MemoryStorage()..value = '{secret-content';
      final store = ProjectSessionStore(storage: storage);

      await expectLater(
        store.load(),
        throwsA(
          isA<ProjectSessionDecodeException>()
              .having(
                (error) => error.code,
                'code',
                ProjectSessionDecodeFailureCode.malformedJson,
              )
              .having(
                (error) => error.toString(),
                'safe text',
                isNot(contains('secret-content')),
              ),
        ),
      );
      await store.close();
    });

    test('replaces and explicitly cancels debounced writes', () async {
      final storage = _MemoryStorage();
      final store =
          ProjectSessionStore(
              storage: storage,
              writeDelay: const Duration(milliseconds: 10),
            )
            ..scheduleSave(_snapshot('old'))
            ..scheduleSave(_snapshot('new'));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(storage.writes, hasLength(1));
      expect(storage.value, contains('new'));
      store.scheduleSave(_snapshot('cancelled'));
      expect(store.cancelScheduledSave(), isTrue);
      expect(store.cancelScheduledSave(), isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(storage.writes, hasLength(1));
      await store.close();
    });

    test('immediate save cancels a pending debounce', () async {
      final storage = _MemoryStorage();
      final store = ProjectSessionStore(
        storage: storage,
        writeDelay: const Duration(milliseconds: 10),
      )..scheduleSave(_snapshot('old'));
      await store.save(_snapshot('now'));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(storage.writes, hasLength(1));
      expect(storage.value, contains('now'));
      await store.close();
    });

    test(
      'close flushes the latest pending snapshot before storage close',
      () async {
        final storage = _MemoryStorage();
        final store =
            ProjectSessionStore(
                storage: storage,
                writeDelay: const Duration(hours: 1),
              )
              ..scheduleSave(_snapshot('old'))
              ..scheduleSave(_snapshot('latest'));
        await store.close();

        expect(storage.writes, hasLength(1));
        expect(storage.value, contains('latest'));
        expect(storage.closedAfterWrites, isTrue);
        await store.close();
      },
    );

    test('close waits for already-started serial writes', () async {
      final gate = Completer<void>();
      final storage = _MemoryStorage(writeGate: gate.future);
      final store = ProjectSessionStore(storage: storage);

      final save = store.save(_snapshot('first'));
      final close = store.close();
      await Future<void>.delayed(Duration.zero);
      expect(storage.isClosed, isFalse);

      gate.complete();
      await save;
      await close;
      expect(storage.isClosed, isTrue);
    });

    test('close reports a scheduled background write failure', () async {
      final failure = StateError('write failed');
      final storage = _MemoryStorage(writeFailure: failure);
      final store = ProjectSessionStore(
        storage: storage,
        writeDelay: Duration.zero,
      )..scheduleSave(_snapshot('failed'));
      await Future<void>.delayed(Duration.zero);

      await expectLater(store.close(), throwsA(same(failure)));
      expect(storage.isClosed, isTrue);
    });

    test('close reports a failure while flushing a pending snapshot', () async {
      final failure = StateError('flush failed');
      final storage = _MemoryStorage(writeFailure: failure);
      final store = ProjectSessionStore(
        storage: storage,
        writeDelay: const Duration(hours: 1),
      )..scheduleSave(_snapshot('failed'));

      await expectLater(store.close(), throwsA(same(failure)));
      expect(storage.isClosed, isTrue);
    });

    test('close propagates storage close failures', () async {
      final failure = StateError('close failed');
      final store = ProjectSessionStore(
        storage: _MemoryStorage(closeFailure: failure),
      );

      await expectLater(store.close(), throwsA(same(failure)));
    });

    test('operations after close fail with a typed exception', () async {
      final store = ProjectSessionStore(storage: _MemoryStorage());
      await store.close();

      expect(
        const ProjectSessionClosedException().toString(),
        'ProjectSessionClosedException()',
      );

      expect(store.load, throwsA(isA<ProjectSessionClosedException>()));
      expect(
        () => store.save(const SessionSnapshotResponse()),
        throwsA(isA<ProjectSessionClosedException>()),
      );
      expect(
        () => store.scheduleSave(const SessionSnapshotResponse()),
        throwsA(isA<ProjectSessionClosedException>()),
      );
    });
  });

  test('atomic document storage persists and closes a real file', () async {
    final directory = await Directory.systemTemp.createTemp('project_session_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}session.json');
    final storage = AtomicProjectSessionDocumentStorage.fromFile(file);

    expect(await storage.read(), isNull);
    await storage.write('value');
    expect(await storage.read(), 'value');
    await storage.close();
    expect(storage.storage.isClosed, isTrue);
  });

  test('decode failures expose safe FormatException metadata', () {
    const failure = ProjectSessionDecodeException(
      code: ProjectSessionDecodeFailureCode.invalidField,
      field: 'workbench',
    );

    expect(failure.message, 'Project session document could not be decoded');
    expect(failure.offset, isNull);
    expect(failure.source, isNull);
    expect(failure.field, 'workbench');
  });
}

Matcher _decodeFailure(ProjectSessionDecodeFailureCode code) {
  return isA<ProjectSessionDecodeException>().having(
    (error) => error.code,
    'code',
    code,
  );
}

SessionSnapshotResponse _snapshot(String threadId) {
  return SessionSnapshotResponse(
    projectPaths: const <String>['/repo'],
    activeProjectPath: '/repo',
    currentFilePath: '/repo/lib/main.dart',
    expandedDirectoryPaths: const <String>{'/repo/test', '/repo/lib'},
    selectedTreeKey: '/repo/lib/main.dart',
    activeAgentProviderId: 'codex',
    agentThreadIdsByProject: <String, String>{'/repo': threadId},
    projectThreadExpansionByProject: const <String, bool>{'/repo': true},
    cachedThreadsByProject: <String, List<SessionThreadSummaryResponse>>{
      '/repo': <SessionThreadSummaryResponse>[
        SessionThreadSummaryResponse(
          id: threadId,
          providerId: 'codex',
          projectPath: '/repo',
          title: 'Title',
          sessionPath: '/sessions/$threadId.jsonl',
          preview: 'Preview',
          createdAtMilliseconds: 1,
          updatedAtMilliseconds: 2,
          recencyAtMilliseconds: 3,
          status: 'idle',
          waitingOnApproval: true,
          raw: const <String, Object?>{'cursor': 'opaque'},
        ),
      ],
    },
    selectedThreadIdsByProject: <String, String>{'/repo': threadId},
    projectLastOpenedAtByPath: <String, DateTime>{
      '/repo': DateTime.utc(2026, 8, 20, 1, 2, 3),
    },
    projectHomeActive: true,
    workbench: const SessionWorkbenchResponse(
      leftSidebarVisible: false,
      agentUsageExpanded: true,
      leftSidebarWidth: 312,
      agentUsageHeightFraction: 0.4,
      selectedAgentUsageProviderId: 'claude',
    ),
  );
}

final class _MemoryStorage implements ProjectSessionDocumentStorage {
  _MemoryStorage({this.writeGate, this.writeFailure, this.closeFailure});

  String? value;
  final Future<void>? writeGate;
  final Object? writeFailure;
  final Object? closeFailure;
  final List<String> writes = <String>[];
  bool isClosed = false;
  bool closedAfterWrites = false;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String contents) async {
    await writeGate;
    if (writeFailure case final failure?) {
      _throwFailure(failure);
    }
    writes.add(contents);
    value = contents;
  }

  @override
  Future<void> close() async {
    isClosed = true;
    closedAfterWrites = writes.isNotEmpty;
    if (closeFailure case final failure?) {
      _throwFailure(failure);
    }
  }
}

Never _throwFailure(Object failure) {
  if (failure is Exception) {
    throw failure;
  }
  if (failure is Error) {
    throw failure;
  }
  throw StateError('Invalid test failure');
}

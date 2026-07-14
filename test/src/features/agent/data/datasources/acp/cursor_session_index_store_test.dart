import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/datasources/acp/cursor_session_index_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'zeta-cursor-session-index-',
    );
  });

  tearDown(() async {
    await tempDirectory.delete(recursive: true);
  });

  group('CursorSessionIndexStore', () {
    test('tolerates damaged JSON and legacy fields', () async {
      // Arrange
      var value = '{damaged';
      final store = CallbackCursorSessionIndexStore(
        loadJson: () async => value,
        saveJson: (next) async => value = next,
      );

      // Act / Assert
      expect((await store.load()).sessions, isEmpty);

      value = jsonEncode(<String, Object?>{
        'entries': <Object?>[
          <String, Object?>{
            'id': 'legacy-session',
            'cwd': './repo/',
            'createdAt': 1000,
            'updatedAt': 2000,
            'status': 'idle',
          },
          <String, Object?>{'id': 'broken-without-cwd'},
        ],
      });
      final snapshot = await store.load();

      expect(snapshot.sessions, hasLength(1));
      expect(snapshot.sessions.single.sessionId, 'legacy-session');
      expect(
        snapshot.sessions.single.workspacePath,
        normalizeCursorWorkspacePath('./repo'),
      );
      expect(snapshot.sessions.single.providerId, cursorAgentProviderId);
    });

    test('deduplicates by newest updatedAt and filters sensitive metadata', () {
      // Arrange / Act
      final snapshot = CursorSessionIndexSnapshot.tryDecode(<String, Object?>{
        'version': 1,
        'sessions': <Object?>[
          <String, Object?>{
            'sessionId': 'session-1',
            'workspacePath': './repo',
            'title': 'Old title',
            'createdAt': '2026-01-01T00:00:00Z',
            'updatedAt': '2026-01-02T00:00:00Z',
          },
          <String, Object?>{
            'sessionId': 'session-1',
            'workspacePath': './repo/',
            'title': 'New title',
            'createdAt': '2026-01-01T00:00:00Z',
            'updatedAt': '2026-01-03T00:00:00Z',
            'metadata': <String, Object?>{
              'branch': 'main',
              'promptText': 'must not persist',
              'authToken': 'secret',
            },
          },
        ],
      });

      // Assert
      expect(snapshot.sessions, hasLength(1));
      expect(snapshot.sessions.single.title, 'New title');
      expect(snapshot.sessions.single.metadata, <String, Object?>{
        'branch': 'main',
      });
    });

    test('serializes concurrent read-modify-write updates', () async {
      // Arrange
      String? value;
      final store = CallbackCursorSessionIndexStore(
        loadJson: () async {
          await Future<void>.delayed(const Duration(milliseconds: 1));
          return value;
        },
        saveJson: (next) async {
          await Future<void>.delayed(const Duration(milliseconds: 1));
          value = next;
        },
      );
      CursorSessionIndexEntry entry(String id, int day) {
        return CursorSessionIndexEntry(
          sessionId: id,
          providerId: cursorAgentProviderId,
          workspacePath: './repo',
          createdAt: DateTime.utc(2026, 1, day),
          updatedAt: DateTime.utc(2026, 1, day),
          status: AgentThreadRuntimeStatus.idle,
        );
      }

      // Act
      await Future.wait(<Future<void>>[
        store.update((current) => current.upsert(entry('session-a', 1))),
        store.update((current) => current.upsert(entry('session-b', 2))),
      ]);

      // Assert
      expect(
        (await store.load()).sessions.map((item) => item.sessionId),
        containsAll(<String>['session-a', 'session-b']),
      );
    });

    test('removes only the requested local entry', () async {
      // Arrange
      final store = MemoryCursorSessionIndexStore(
        CursorSessionIndexSnapshot(
          sessions: <CursorSessionIndexEntry>[
            _entry('session-a'),
            _entry('session-b'),
          ],
        ),
      );

      // Act
      await store.update((current) => current.remove('session-a'));

      // Assert
      expect((await store.load()).sessions.single.sessionId, 'session-b');
    });

    test(
      'file store serializes updates and reloads them after restart',
      () async {
        // Arrange
        final file = File.fromUri(
          tempDirectory.uri.resolve('state/cursor_sessions.json'),
        );
        final store = FileCursorSessionIndexStore(file: file);
        expect((await store.load()).sessions, isEmpty);

        // Act
        await Future.wait(<Future<void>>[
          store.update((current) => current.upsert(_entry('session-a'))),
          store.update((current) => current.upsert(_entry('session-b'))),
        ]);
        final reloaded = await FileCursorSessionIndexStore(file: file).load();

        // Assert
        expect(await file.exists(), isTrue);
        expect(
          reloaded.sessions.map((entry) => entry.sessionId),
          containsAll(<String>['session-a', 'session-b']),
        );
      },
    );

    test('file store serializes updates from separate instances', () async {
      // Arrange
      final file = File.fromUri(
        tempDirectory.uri.resolve('state/cursor_sessions.json'),
      );
      final first = FileCursorSessionIndexStore(file: file);
      final second = FileCursorSessionIndexStore(file: file);

      // Act
      await Future.wait(<Future<void>>[
        first.update((current) => current.upsert(_entry('session-a'))),
        second.update((current) => current.upsert(_entry('session-b'))),
      ]);
      final reloaded = await FileCursorSessionIndexStore(file: file).load();

      // Assert
      expect(
        reloaded.sessions.map((entry) => entry.sessionId),
        containsAll(<String>['session-a', 'session-b']),
      );
    });

    test('file store treats damaged JSON as an empty snapshot', () async {
      // Arrange
      final file = File.fromUri(
        tempDirectory.uri.resolve('state/cursor_sessions.json'),
      );
      await file.parent.create(recursive: true);
      await file.writeAsString('{damaged');

      // Act
      final snapshot = await FileCursorSessionIndexStore(file: file).load();

      // Assert
      expect(snapshot.sessions, isEmpty);
    });

    test('file store treats invalid UTF-8 as an empty snapshot', () async {
      // Arrange
      final file = File.fromUri(
        tempDirectory.uri.resolve('state/cursor_sessions.json'),
      );
      await file.parent.create(recursive: true);
      await file.writeAsBytes(<int>[0xff]);

      // Act
      final snapshot = await FileCursorSessionIndexStore(file: file).load();

      // Assert
      expect(snapshot.sessions, isEmpty);
    });

    test('file store propagates write failures', () async {
      // Arrange
      final blockingParent = File.fromUri(
        tempDirectory.uri.resolve('not-a-directory'),
      );
      await blockingParent.writeAsString('blocked');
      final store = FileCursorSessionIndexStore(
        file: File.fromUri(
          tempDirectory.uri.resolve('not-a-directory/cursor_sessions.json'),
        ),
      );

      // Act / Assert
      await expectLater(
        store.update((current) => current.upsert(_entry('session-a'))),
        throwsA(isA<IOException>()),
      );
    });
  });
}

CursorSessionIndexEntry _entry(String id) {
  return CursorSessionIndexEntry(
    sessionId: id,
    providerId: cursorAgentProviderId,
    workspacePath: './repo',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}

import 'dart:async';

import 'package:test/test.dart';
import 'package:workspace_client/workspace_client.dart';

import '../helpers/fake_workspace_file_system.dart';

void main() {
  late FakeWorkspaceFileSystem fileSystem;
  late FakeGitignoreReader gitignoreReader;
  late FileWorkspaceScanner scanner;

  setUp(() {
    fileSystem = FakeWorkspaceFileSystem()
      ..types['/repo'] = WorkspaceFileSystemEntityType.directory;
    gitignoreReader = FakeGitignoreReader();
    scanner = FileWorkspaceScanner(
      fileSystem: fileSystem,
      gitignoreReader: gitignoreReader,
    );
  });

  tearDown(() => fileSystem.close());

  test(
    'recursively scans regular files in deterministic filesystem order',
    () async {
      fileSystem
        ..types['/repo/src'] = WorkspaceFileSystemEntityType.directory
        ..listings['/repo'] = <WorkspaceFileSystemEntry>[
          entry('/repo/README.md', WorkspaceFileSystemEntityType.file),
          entry('/repo/src', WorkspaceFileSystemEntityType.directory),
          entry('/repo/link', WorkspaceFileSystemEntityType.symbolicLink),
          entry('/repo/gone', WorkspaceFileSystemEntityType.notFound),
          entry('/repo/socket', WorkspaceFileSystemEntityType.other),
        ]
        ..listings['/repo/src'] = <WorkspaceFileSystemEntry>[
          entry('/repo/src/main.dart', WorkspaceFileSystemEntityType.file),
        ];

      final result = await scanner.scanFiles('/repo');

      expect(
        result.files.map((node) => node.path),
        <String>['/repo/README.md', '/repo/src/main.dart'],
      );
      expect(result.visitedDirectories, 2);
      expect(result.truncated, isFalse);
    },
  );

  test('constructs its production gitignore reader by default', () async {
    fileSystem.listings['/repo'] = const <WorkspaceFileSystemEntry>[];

    final result = await FileWorkspaceScanner(
      fileSystem: fileSystem,
    ).scanFiles('/repo');

    expect(result.files, isEmpty);
    expect(fileSystem.typeCalls, contains('/repo/.git'));
    expect(fileSystem.typeCalls, contains('/repo/.gitignore'));
  });

  test(
    'supplies scoped gitignore inputs to an injected Repository filter',
    () async {
      fileSystem
        ..types.addAll(<String, WorkspaceFileSystemEntityType>{
          '/repo/src': WorkspaceFileSystemEntityType.directory,
          '/repo/other': WorkspaceFileSystemEntityType.directory,
        })
        ..listings['/repo'] = <WorkspaceFileSystemEntry>[
          entry('/repo/root.log', WorkspaceFileSystemEntityType.file),
          entry('/repo/src', WorkspaceFileSystemEntityType.directory),
          entry('/repo/other', WorkspaceFileSystemEntityType.directory),
          entry('/repo/build', WorkspaceFileSystemEntityType.directory),
        ]
        ..listings['/repo/src'] = <WorkspaceFileSystemEntry>[
          entry('/repo/src/keep.log', WorkspaceFileSystemEntityType.file),
        ]
        ..listings['/repo/other'] = <WorkspaceFileSystemEntry>[
          entry('/repo/other/drop.log', WorkspaceFileSystemEntityType.file),
        ];
      gitignoreReader
        ..excludes['/repo'] = const GitignoreDocumentResponse(
          basePath: '/repo',
          sourcePath: '/repo/.git/info/exclude',
          contents: 'private\n',
          kind: GitignoreDocumentKindResponse.repositoryExclude,
        )
        ..gitignores['/repo'] = const GitignoreDocumentResponse(
          basePath: '/repo',
          sourcePath: '/repo/.gitignore',
          contents: '*.log\n',
          kind: GitignoreDocumentKindResponse.directoryGitignore,
        )
        ..gitignores['/repo/src'] = const GitignoreDocumentResponse(
          basePath: '/repo/src',
          sourcePath: '/repo/src/.gitignore',
          contents: '!keep.log\n',
          kind: GitignoreDocumentKindResponse.directoryGitignore,
        );
      final documentsSeen = <String, List<String>>{};

      final result = await scanner.scanFiles(
        '/repo',
        filter: (node, documents) {
          documentsSeen[node.path] = documents
              .map((document) => document.contents.trim())
              .toList();
          if (node.name == 'build') {
            return WorkspaceEntryDisposition.prune;
          }
          if (node.name == 'keep.log' &&
              documents.any(
                (document) => document.contents.contains('!keep'),
              )) {
            return WorkspaceEntryDisposition.include;
          }
          if (node.name.endsWith('.log')) {
            return WorkspaceEntryDisposition.skip;
          }
          return WorkspaceEntryDisposition.include;
        },
      );

      expect(result.files.map((node) => node.path), <String>[
        '/repo/src/keep.log',
      ]);
      expect(fileSystem.listCalls, isNot(contains('/repo/build')));
      expect(
        documentsSeen['/repo/src/keep.log'],
        <String>['private', '*.log', '!keep.log'],
      );
      expect(
        documentsSeen['/repo/other/drop.log'],
        <String>['private', '*.log'],
      );
    },
  );

  test('skip still traverses a directory while prune does not', () async {
    fileSystem
      ..types.addAll(<String, WorkspaceFileSystemEntityType>{
        '/repo/skip': WorkspaceFileSystemEntityType.directory,
        '/repo/prune': WorkspaceFileSystemEntityType.directory,
      })
      ..listings['/repo'] = <WorkspaceFileSystemEntry>[
        entry('/repo/skip', WorkspaceFileSystemEntityType.directory),
        entry('/repo/prune', WorkspaceFileSystemEntityType.directory),
      ]
      ..listings['/repo/skip'] = <WorkspaceFileSystemEntry>[
        entry('/repo/skip/kept.txt', WorkspaceFileSystemEntityType.file),
      ]
      ..listings['/repo/prune'] = <WorkspaceFileSystemEntry>[
        entry('/repo/prune/hidden.txt', WorkspaceFileSystemEntityType.file),
      ];

    final result = await scanner.scanFiles(
      '/repo',
      filter: (node, _) => switch (node.name) {
        'skip' => WorkspaceEntryDisposition.skip,
        'prune' => WorkspaceEntryDisposition.prune,
        _ => WorkspaceEntryDisposition.include,
      },
    );

    expect(result.files.single.name, 'kept.txt');
    expect(fileSystem.listCalls, contains('/repo/skip'));
    expect(fileSystem.listCalls, isNot(contains('/repo/prune')));
  });

  test('enforces maxFiles and rejects invalid limits', () async {
    fileSystem.listings['/repo'] = List<WorkspaceFileSystemEntry>.generate(
      5,
      (index) => entry(
        '/repo/$index.txt',
        WorkspaceFileSystemEntityType.file,
      ),
    );

    final result = await scanner.scanFiles('/repo', maxFiles: 3);

    expect(result.files, hasLength(3));
    expect(result.truncated, isTrue);
    await expectLater(
      scanner.scanFiles('/repo', maxFiles: 0),
      throwsArgumentError,
    );
  });

  test(
    'large scans cancel cooperatively before consuming the corpus',
    () async {
      final token = WorkspaceScanCancellationToken();
      fileSystem.listings['/repo'] = List<WorkspaceFileSystemEntry>.generate(
        1000,
        (index) => entry(
          '/repo/$index.txt',
          WorkspaceFileSystemEntityType.file,
        ),
      );
      var visited = 0;

      await expectLater(
        scanner.scanFiles(
          '/repo',
          cancellationToken: token,
          filter: (node, documents) {
            visited += 1;
            if (visited == 5) {
              token.cancel();
            }
            return WorkspaceEntryDisposition.include;
          },
        ),
        throwsA(isA<WorkspaceScanCancelledException>()),
      );
      expect(visited, 5);

      final alreadyCancelled = WorkspaceScanCancellationToken()..cancel();
      await expectLater(
        scanner.scanFiles('/repo', cancellationToken: alreadyCancelled),
        throwsA(isA<WorkspaceScanCancelledException>()),
      );
    },
  );

  test(
    'propagates denied directory access and rejects malicious entries',
    () async {
      const denied = WorkspaceFileSystemException(
        operation: WorkspaceFileSystemOperation.listDirectory,
        code: WorkspaceFileSystemFailureCode.accessDenied,
      );
      fileSystem.listErrors['/repo'] = denied;
      await expectLater(scanner.scanFiles('/repo'), throwsA(same(denied)));

      fileSystem
        ..listErrors.clear()
        ..listings['/repo'] = <WorkspaceFileSystemEntry>[
          entry('/outside/secret', WorkspaceFileSystemEntityType.file),
        ];
      await expectLater(
        scanner.scanFiles('/repo'),
        throwsA(
          isA<WorkspaceFileSystemException>().having(
            (error) => error.code,
            'code',
            WorkspaceFileSystemFailureCode.outsideRoot,
          ),
        ),
      );
    },
  );

  test(
    'readDirectory skips disappearing/link entries and sorts directories first',
    () async {
      fileSystem
        ..types['/repo/lib'] = WorkspaceFileSystemEntityType.directory
        ..listings['/repo'] = <WorkspaceFileSystemEntry>[
          entry('/repo/z.txt', WorkspaceFileSystemEntityType.file),
          entry('/repo/a.txt', WorkspaceFileSystemEntityType.file),
          entry('/repo/A.txt', WorkspaceFileSystemEntityType.file),
          entry('/repo/README.md', WorkspaceFileSystemEntityType.file),
          entry('/repo/lib', WorkspaceFileSystemEntityType.directory),
          entry('/repo/link', WorkspaceFileSystemEntityType.symbolicLink),
          entry('/repo/gone', WorkspaceFileSystemEntityType.notFound),
          entry('/repo/socket', WorkspaceFileSystemEntityType.other),
        ];

      final nodes = await scanner.readDirectory(
        rootPath: '/repo',
        directoryPath: '/repo',
        filter: (node, documents) => node.name == 'z.txt'
            ? WorkspaceEntryDisposition.skip
            : WorkspaceEntryDisposition.include,
      );

      expect(
        nodes.map((node) => node.name),
        <String>['lib', 'A.txt', 'a.txt', 'README.md'],
      );
      expect(nodes.clear, throwsUnsupportedError);

      final cancelled = WorkspaceScanCancellationToken()..cancel();
      await expectLater(
        scanner.readDirectory(
          rootPath: '/repo',
          directoryPath: '/repo',
          cancellationToken: cancelled,
        ),
        throwsA(isA<WorkspaceScanCancelledException>()),
      );
    },
  );

  test('readDirectory detects cancellation after enumeration', () async {
    final token = WorkspaceScanCancellationToken();
    fileSystem.listings['/repo'] = <WorkspaceFileSystemEntry>[
      entry('/repo/a.txt', WorkspaceFileSystemEntityType.file),
    ];

    await expectLater(
      scanner.readDirectory(
        rootPath: '/repo',
        directoryPath: '/repo',
        cancellationToken: token,
        filter: (node, documents) {
          token.cancel();
          return WorkspaceEntryDisposition.include;
        },
      ),
      throwsA(isA<WorkspaceScanCancelledException>()),
    );
  });

  test(
    'watch maps only in-root events and closes the source subscription',
    () async {
      final listening = Completer<void>();
      final received = Completer<void>();
      var cancelled = false;
      final controller = StreamController<WorkspaceFileChangeResponse>(
        onListen: listening.complete,
        onCancel: () {
          cancelled = true;
        },
      );
      fileSystem.watches['/repo'] = controller;
      final events = <WorkspaceFileChangeResponse>[];
      final subscription = scanner.watch('/repo').listen((event) {
        events.add(event);
        if (!received.isCompleted) {
          received.complete();
        }
      });
      await listening.future;

      controller
        ..add(
          const WorkspaceFileChangeResponse(
            kind: WorkspaceFileChangeKindResponse.create,
            path: '/outside/a.dart',
            isDirectory: false,
          ),
        )
        ..add(
          const WorkspaceFileChangeResponse(
            kind: WorkspaceFileChangeKindResponse.move,
            path: '/repo/a.dart',
            destinationPath: '/outside/a.dart',
            isDirectory: false,
          ),
        );
      await received.future.timeout(const Duration(seconds: 1));
      await subscription.cancel();

      expect(events, hasLength(1));
      expect(events.single.path, '/repo/a.dart');
      expect(events.single.destinationPath, isNull);
      expect(cancelled, isTrue);
    },
  );
}

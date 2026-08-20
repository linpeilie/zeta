import 'dart:async';

import 'package:test/test.dart';
import 'package:workspace_client/workspace_client.dart';
import 'package:workspace_repository/workspace_repository.dart';

import '../helpers/fake_workspace_scanner.dart';

void main() {
  late FakeWorkspaceScanner scanner;
  late WorkspaceRepository repository;

  setUp(() {
    scanner = FakeWorkspaceScanner();
    repository = WorkspaceRepository(scanner: scanner);
  });

  tearDown(() async {
    try {
      await repository.close();
    } on WorkspaceRepositoryException {
      // Individual close-failure tests assert the typed result.
    }
    await scanner.dispose();
  });

  group('index and query', () {
    test(
      'maps, freezes, publishes, caches, and revises index snapshots',
      () async {
        scanner.scanResponse = WorkspaceScanResponse(
          files: const <WorkspaceNodeResponse>[
            WorkspaceNodeResponse(
              path: '/repo/lib',
              name: 'lib',
              type: WorkspaceNodeTypeResponse.directory,
            ),
            WorkspaceNodeResponse(
              path: '/repo/lib/main.dart',
              name: 'main.dart',
              type: WorkspaceNodeTypeResponse.file,
            ),
          ],
          visitedDirectories: 2,
          truncated: false,
        );
        final changes = <WorkspaceIndex>[];
        repository.indexChanges.listen(changes.add);

        final first = await repository.index(' /repo ');
        final unchanged = await repository.index('/repo');
        scanner.scanResponse = WorkspaceScanResponse(
          files: const <WorkspaceNodeResponse>[
            WorkspaceNodeResponse(
              path: '/repo/README.md',
              name: 'README.md',
              type: WorkspaceNodeTypeResponse.file,
            ),
          ],
          visitedDirectories: 1,
          truncated: true,
        );
        final second = await repository.index('/repo', maxFiles: 1);

        expect(first.rootPath, '/repo');
        expect(first.files.first.isDirectory, isTrue);
        expect(first.files.last.isDirectory, isFalse);
        expect(first.visitedDirectories, 2);
        expect(first.truncated, isFalse);
        expect(first.revision, 1);
        expect(unchanged, same(first));
        expect(second.revision, 2);
        expect(second.truncated, isTrue);
        expect(changes, <WorkspaceIndex>[first, second]);
        expect(repository.indexFor(' /repo '), second);
        expect(scanner.watchCalls, <String>['/repo']);
        expect(
          () => second.files.add(second.files.single),
          throwsUnsupportedError,
        );
      },
    );

    test('serializes concurrent scans for the same root', () async {
      final firstGate = Completer<void>();
      scanner.scanGates.add(firstGate);

      final first = repository.index('/repo');
      final second = repository.index('/repo');
      await Future<void>.delayed(Duration.zero);
      expect(scanner.scanCount, 1);

      firstGate.complete();
      await first;
      await second;
      expect(scanner.scanCount, 2);
    });

    test(
      'queries empty and smart-case fuzzy input deterministically',
      () async {
        scanner.scanResponse = WorkspaceScanResponse(
          files: const <WorkspaceNodeResponse>[
            WorkspaceNodeResponse(
              path: '/repo/src/fooBar.dart',
              name: 'fooBar.dart',
              type: WorkspaceNodeTypeResponse.file,
            ),
            WorkspaceNodeResponse(
              path: '/repo/test/foo_bar_test.dart',
              name: 'foo_bar_test.dart',
              type: WorkspaceNodeTypeResponse.file,
            ),
            WorkspaceNodeResponse(
              path: '/repo/README.md',
              name: 'README.md',
              type: WorkspaceNodeTypeResponse.file,
            ),
          ],
          visitedDirectories: 3,
          truncated: false,
        );
        await repository.index('/repo');

        expect(repository.query('/missing', query: ''), isEmpty);
        expect(repository.query('/repo', query: '', limit: 2), hasLength(2));
        expect(
          repository.query('/repo', query: 'fbt').map((node) => node.name),
          containsAll(<String>['fooBar.dart', 'foo_bar_test.dart']),
        );
        expect(
          repository.query('/repo', query: 'B').map((node) => node.name),
          <String>['fooBar.dart'],
        );
        expect(repository.query('/repo', query: 'zzz'), isEmpty);

        scanner.scanResponse = WorkspaceScanResponse(
          files: const <WorkspaceNodeResponse>[
            WorkspaceNodeResponse(
              path: '/r/ab.dart',
              name: 'ab.dart',
              type: WorkspaceNodeTypeResponse.file,
            ),
            WorkspaceNodeResponse(
              path: '/repo/ac.dart',
              name: 'ac.dart',
              type: WorkspaceNodeTypeResponse.file,
            ),
            WorkspaceNodeResponse(
              path: '/repo/aa.dart',
              name: 'aa.dart',
              type: WorkspaceNodeTypeResponse.file,
            ),
          ],
          visitedDirectories: 1,
          truncated: false,
        );
        await repository.index('/repo');
        expect(repository.query('/repo', query: 'ab').single.name, 'ab.dart');
        expect(
          repository.query('/repo', query: 'a').map((node) => node.name),
          <String>['ab.dart', 'aa.dart', 'ac.dart'],
        );
      },
    );

    test('rejects invalid index/query input and calls after close', () async {
      expectFailure(
        () => repository.index(' '),
        WorkspaceRepositoryOperation.indexWorkspace,
        WorkspaceRepositoryFailureCode.invalidInput,
      );
      expectFailure(
        () => repository.index('/repo', maxFiles: 0),
        WorkspaceRepositoryOperation.indexWorkspace,
        WorkspaceRepositoryFailureCode.invalidInput,
      );
      expectFailure(
        () => repository.query(' ', query: ''),
        WorkspaceRepositoryOperation.query,
        WorkspaceRepositoryFailureCode.invalidInput,
      );
      expectFailure(
        () => repository.query('/repo', query: '', limit: 0),
        WorkspaceRepositoryOperation.query,
        WorkspaceRepositoryFailureCode.invalidInput,
      );
      await repository.close();
      expectFailure(
        () => repository.index('/repo'),
        WorkspaceRepositoryOperation.indexWorkspace,
        WorkspaceRepositoryFailureCode.closed,
      );
      expectFailure(
        () => repository.query('/repo', query: ''),
        WorkspaceRepositoryOperation.query,
        WorkspaceRepositoryFailureCode.closed,
      );
    });
  });

  group('ignore policy and children', () {
    test('applies defaults, anchored rules, dir rules, and negation', () async {
      scanner
        ..documents = <GitignoreDocumentResponse>[
          const GitignoreDocumentResponse(
            basePath: '/repo',
            sourcePath: '/repo/.gitignore',
            contents:
                '# comment\n*.log\nbuild/\n/src/*.tmp\n!keep.log\ntrimmed   \n',
            kind: GitignoreDocumentKindResponse.directoryGitignore,
          ),
        ]
        ..directoryResponse = const <WorkspaceNodeResponse>[
          WorkspaceNodeResponse(
            path: '/repo/.git',
            name: '.git',
            type: WorkspaceNodeTypeResponse.directory,
          ),
          WorkspaceNodeResponse(
            path: '/repo/build',
            name: 'build',
            type: WorkspaceNodeTypeResponse.directory,
          ),
          WorkspaceNodeResponse(
            path: '/repo/drop.log',
            name: 'drop.log',
            type: WorkspaceNodeTypeResponse.file,
          ),
          WorkspaceNodeResponse(
            path: '/repo/keep.log',
            name: 'keep.log',
            type: WorkspaceNodeTypeResponse.file,
          ),
          WorkspaceNodeResponse(
            path: '/repo/main.dart',
            name: 'main.dart',
            type: WorkspaceNodeTypeResponse.file,
          ),
          WorkspaceNodeResponse(
            path: '/repo/trimmed',
            name: 'trimmed',
            type: WorkspaceNodeTypeResponse.file,
          ),
        ];

      final children = await repository.loadChildren(
        rootPath: '/repo',
        directoryPath: '/repo',
      );

      expect(children.map((node) => node.name), <String>[
        'keep.log',
        'main.dart',
      ]);
      expect(children.clear, throwsUnsupportedError);
    });

    test(
      'supports escaped comment, glob depth, malformed, and Windows case',
      () async {
        scanner
          ..documents = <GitignoreDocumentResponse>[
            const GitignoreDocumentResponse(
              basePath: r'C:\Repo',
              sourcePath: r'C:\Repo\.gitignore',
              contents:
                  r'\#literal'
                  '\n**/cache/**\n[bad\nname\\ \n',
              kind: GitignoreDocumentKindResponse.directoryGitignore,
            ),
          ]
          ..directoryResponse = const <WorkspaceNodeResponse>[
            WorkspaceNodeResponse(
              path: r'C:\Repo\#LITERAL',
              name: '#LITERAL',
              type: WorkspaceNodeTypeResponse.file,
            ),
            WorkspaceNodeResponse(
              path: r'C:\Repo\deep\cache\x.txt',
              name: 'x.txt',
              type: WorkspaceNodeTypeResponse.file,
            ),
            WorkspaceNodeResponse(
              path: r'C:\Repo\ok.txt',
              name: 'ok.txt',
              type: WorkspaceNodeTypeResponse.file,
            ),
          ];

        final children = await repository.loadChildren(
          rootPath: r'C:\Repo',
          directoryPath: r'C:\Repo',
        );

        expect(children.map((node) => node.name), <String>['ok.txt']);
      },
    );

    test(
      'validates input and translates cancellation, invalid, and IO',
      () async {
        expectFailure(
          () => repository.loadChildren(rootPath: ' ', directoryPath: '/repo'),
          WorkspaceRepositoryOperation.loadChildren,
          WorkspaceRepositoryFailureCode.invalidInput,
        );
        expectFailure(
          () => repository.loadChildren(rootPath: '/repo', directoryPath: ' '),
          WorkspaceRepositoryOperation.loadChildren,
          WorkspaceRepositoryFailureCode.invalidInput,
        );
        scanner.readError = const WorkspaceScanCancelledException();
        await expectFailureAsync(
          repository.loadChildren(rootPath: '/repo', directoryPath: '/repo'),
          WorkspaceRepositoryOperation.loadChildren,
          WorkspaceRepositoryFailureCode.cancelled,
        );
        scanner.readError = StateError('read');
        await expectFailureAsync(
          repository.loadChildren(rootPath: '/repo', directoryPath: '/repo'),
          WorkspaceRepositoryOperation.loadChildren,
          WorkspaceRepositoryFailureCode.ioFailure,
        );
        scanner.readError = const WorkspaceFileSystemException(
          operation: WorkspaceFileSystemOperation.listDirectory,
          code: WorkspaceFileSystemFailureCode.notFound,
        );
        await expectFailureAsync(
          repository.loadChildren(rootPath: '/repo', directoryPath: '/repo'),
          WorkspaceRepositoryOperation.loadChildren,
          WorkspaceRepositoryFailureCode.notFound,
        );
        scanner
          ..readError = null
          ..directoryResponse = const <WorkspaceNodeResponse>[
            WorkspaceNodeResponse(
              path: '',
              name: 'bad',
              type: WorkspaceNodeTypeResponse.file,
            ),
          ];
        await expectFailureAsync(
          repository.loadChildren(rootPath: '/repo', directoryPath: '/repo'),
          WorkspaceRepositoryOperation.loadChildren,
          WorkspaceRepositoryFailureCode.invalidData,
        );
        await repository.close();
        expectFailure(
          () => repository.loadChildren(
            rootPath: '/repo',
            directoryPath: '/repo',
          ),
          WorkspaceRepositoryOperation.loadChildren,
          WorkspaceRepositoryFailureCode.closed,
        );
      },
    );
  });

  group('failures and external streams', () {
    test('translates every Data filesystem failure code', () async {
      for (final entry
          in <WorkspaceFileSystemFailureCode, WorkspaceRepositoryFailureCode>{
            WorkspaceFileSystemFailureCode.notFound:
                WorkspaceRepositoryFailureCode.notFound,
            WorkspaceFileSystemFailureCode.accessDenied:
                WorkspaceRepositoryFailureCode.accessDenied,
            WorkspaceFileSystemFailureCode.notDirectory:
                WorkspaceRepositoryFailureCode.notDirectory,
            WorkspaceFileSystemFailureCode.outsideRoot:
                WorkspaceRepositoryFailureCode.outsideRoot,
            WorkspaceFileSystemFailureCode.symbolicLink:
                WorkspaceRepositoryFailureCode.symbolicLink,
            WorkspaceFileSystemFailureCode.ioFailure:
                WorkspaceRepositoryFailureCode.ioFailure,
          }.entries) {
        scanner.scanError = WorkspaceFileSystemException(
          operation: WorkspaceFileSystemOperation.listDirectory,
          code: entry.key,
        );
        await expectFailureAsync(
          repository.index('/repo'),
          WorkspaceRepositoryOperation.indexWorkspace,
          entry.value,
        );
      }
    });

    test(
      'translates cancellation, invalid index Data, and unknown IO',
      () async {
        scanner.scanError = const WorkspaceScanCancelledException();
        await expectFailureAsync(
          repository.index('/repo'),
          WorkspaceRepositoryOperation.indexWorkspace,
          WorkspaceRepositoryFailureCode.cancelled,
        );
        scanner.scanError = StateError('scan');
        await expectFailureAsync(
          repository.index('/repo'),
          WorkspaceRepositoryOperation.indexWorkspace,
          WorkspaceRepositoryFailureCode.ioFailure,
        );
        scanner
          ..scanError = null
          ..scanResponse = WorkspaceScanResponse(
            files: const <WorkspaceNodeResponse>[],
            visitedDirectories: -1,
            truncated: false,
          );
        await expectFailureAsync(
          repository.index('/repo'),
          WorkspaceRepositoryOperation.indexWorkspace,
          WorkspaceRepositoryFailureCode.invalidData,
        );
        scanner.scanResponse = WorkspaceScanResponse(
          files: const <WorkspaceNodeResponse>[
            WorkspaceNodeResponse(
              path: ' ',
              name: 'bad',
              type: WorkspaceNodeTypeResponse.file,
            ),
          ],
          visitedDirectories: 1,
          truncated: false,
        );
        await expectFailureAsync(
          repository.index('/repo'),
          WorkspaceRepositoryOperation.indexWorkspace,
          WorkspaceRepositoryFailureCode.invalidData,
        );
      },
    );

    test('maps all tree events and translates stream errors', () async {
      final events = <WorkspaceTreeChange>[];
      final errors = <WorkspaceRepositoryException>[];
      repository.treeChanges.listen(events.add, onError: errors.add);
      await repository.index('/repo');
      final controller = scanner.watches['/repo']!;

      for (final kind in WorkspaceFileChangeKindResponse.values) {
        controller.add(
          WorkspaceFileChangeResponse(
            kind: kind,
            path: '/repo/${kind.name}',
            destinationPath: kind == WorkspaceFileChangeKindResponse.move
                ? '/repo/moved'
                : null,
            isDirectory: kind == WorkspaceFileChangeKindResponse.create,
          ),
        );
      }
      controller
        ..add(
          const WorkspaceFileChangeResponse(
            kind: WorkspaceFileChangeKindResponse.create,
            path: ' ',
            isDirectory: false,
          ),
        )
        ..addError(
          const WorkspaceFileSystemException(
            operation: WorkspaceFileSystemOperation.watchDirectory,
            code: WorkspaceFileSystemFailureCode.accessDenied,
          ),
        )
        ..addError(StateError('watch'));
      await Future<void>.delayed(Duration.zero);

      expect(events.map((event) => event.kind), WorkspaceTreeChangeKind.values);
      expect(events.first.rootPath, '/repo');
      expect(events.last.destinationPath, '/repo/moved');
      expect(errors.map((error) => error.failure.code), <Object>[
        WorkspaceRepositoryFailureCode.invalidData,
        WorkspaceRepositoryFailureCode.accessDenied,
        WorkspaceRepositoryFailureCode.ioFailure,
      ]);
    });

    test('translates a synchronous watch-start failure', () async {
      scanner.watchThrow = StateError('watch start');

      expectFailure(
        () => repository.index('/repo'),
        WorkspaceRepositoryOperation.watch,
        WorkspaceRepositoryFailureCode.ioFailure,
      );
    });

    test('close is idempotent and closes streams', () async {
      await repository.index('/repo');
      final indexDone = expectLater(repository.indexChanges, emitsDone);
      final treeDone = expectLater(repository.treeChanges, emitsDone);

      final first = repository.close();
      final second = repository.close();
      expect(identical(first, second), isTrue);
      await first;
      await indexDone;
      await treeDone;
    });

    test(
      'removes completed watches and translates cancellation failure',
      () async {
        await repository.index('/repo');
        await scanner.watches['/repo']!.close();
        await Future<void>.delayed(Duration.zero);
        scanner.watches.remove('/repo');
        await repository.index('/repo');
        expect(scanner.watchCalls, <String>['/repo', '/repo']);

        final failingScanner = FakeWorkspaceScanner()
          ..watchCancelError = StateError('cancel');
        repository = WorkspaceRepository(scanner: failingScanner);
        scanner = failingScanner;
        await repository.index('/other');

        await expectFailureAsync(
          repository.close(),
          WorkspaceRepositoryOperation.close,
          WorkspaceRepositoryFailureCode.ioFailure,
        );
      },
    );
  });
}

void expectFailure(
  Object? Function() action,
  WorkspaceRepositoryOperation operation,
  WorkspaceRepositoryFailureCode code,
) {
  expect(
    action,
    throwsA(
      isA<WorkspaceRepositoryException>()
          .having((error) => error.failure.operation, 'operation', operation)
          .having((error) => error.failure.code, 'code', code),
    ),
  );
}

Future<void> expectFailureAsync(
  Future<Object?> future,
  WorkspaceRepositoryOperation operation,
  WorkspaceRepositoryFailureCode code,
) async {
  await expectLater(
    future,
    throwsA(
      isA<WorkspaceRepositoryException>()
          .having((error) => error.failure.operation, 'operation', operation)
          .having((error) => error.failure.code, 'code', code),
    ),
  );
}

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:workspace_client/workspace_client.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('zeta-workspace-fs-');
  });

  tearDown(() async {
    if (root.existsSync()) {
      await root.delete(recursive: true);
    }
  });

  test('default IO primitives type, resolve, list, read, and watch', () async {
    const fileSystem = IoWorkspaceFileSystem();
    final directory = Directory('${root.path}${Platform.pathSeparator}lib');
    await directory.create();
    final file = File('${root.path}${Platform.pathSeparator}README.md');
    await file.writeAsString('docs');

    expect(
      await fileSystem.type(root.path),
      WorkspaceFileSystemEntityType.directory,
    );
    expect(
      await fileSystem.type(file.path),
      WorkspaceFileSystemEntityType.file,
    );
    expect(
      await fileSystem.type('${root.path}${Platform.pathSeparator}missing'),
      WorkspaceFileSystemEntityType.notFound,
    );
    expect(await fileSystem.resolvePath(root.path), isNotEmpty);
    expect(await fileSystem.list(root.path).toList(), hasLength(2));
    expect(await fileSystem.readText(file.path), 'docs');

    final eventFuture = fileSystem
        .watch(root.path)
        .first
        .timeout(
          const Duration(seconds: 5),
        );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await File(
      '${root.path}${Platform.pathSeparator}created.txt',
    ).writeAsString('created');
    expect((await eventFuture).kind, WorkspaceFileChangeKindResponse.create);
  });

  test('maps every dart:io entity and event kind', () async {
    final entityTypes = <FileSystemEntityType, WorkspaceFileSystemEntityType>{
      FileSystemEntityType.file: WorkspaceFileSystemEntityType.file,
      FileSystemEntityType.directory: WorkspaceFileSystemEntityType.directory,
      FileSystemEntityType.link: WorkspaceFileSystemEntityType.symbolicLink,
      FileSystemEntityType.notFound: WorkspaceFileSystemEntityType.notFound,
      FileSystemEntityType.pipe: WorkspaceFileSystemEntityType.other,
    };
    for (final item in entityTypes.entries) {
      final fileSystem = IoWorkspaceFileSystem(
        entityTypeReader: (_) async => item.key,
      );
      expect(await fileSystem.type('fixture'), item.value);
    }

    final events = <FileSystemEvent>[
      FileSystemCreateEvent('/repo/create', true),
      FileSystemModifyEvent('/repo/modify', false, true),
      FileSystemDeleteEvent('/repo/delete', true),
      FileSystemMoveEvent('/repo/source', false, '/repo/destination'),
    ];
    final fileSystem = IoWorkspaceFileSystem(
      directoryWatcher: (_) => Stream<FileSystemEvent>.fromIterable(events),
    );
    final mapped = await fileSystem.watch('/repo').toList();

    expect(
      mapped.map((event) => event.kind),
      <WorkspaceFileChangeKindResponse>[
        WorkspaceFileChangeKindResponse.create,
        WorkspaceFileChangeKindResponse.modify,
        WorkspaceFileChangeKindResponse.delete,
        WorkspaceFileChangeKindResponse.move,
      ],
    );
    expect(mapped.first.isDirectory, isTrue);
    expect(mapped.last.destinationPath, '/repo/destination');
  });

  test('maps OS failure codes without retaining exception contents', () async {
    for (final item in <(int, WorkspaceFileSystemFailureCode)>[
      (2, WorkspaceFileSystemFailureCode.notFound),
      (3, WorkspaceFileSystemFailureCode.notFound),
      (5, WorkspaceFileSystemFailureCode.accessDenied),
      (13, WorkspaceFileSystemFailureCode.accessDenied),
      (99, WorkspaceFileSystemFailureCode.ioFailure),
    ]) {
      final fileSystem = IoWorkspaceFileSystem(
        entityTypeReader: (_) async => throw FileSystemException(
          'sensitive',
          '/secret',
          OSError('sensitive', item.$1),
        ),
      );
      await expectLater(
        fileSystem.type('/secret'),
        throwsA(
          isA<WorkspaceFileSystemException>()
              .having(
                (error) => error.operation,
                'operation',
                WorkspaceFileSystemOperation.metadata,
              )
              .having((error) => error.code, 'code', item.$2)
              .having(
                (error) => error.toString(),
                'safe text',
                isNot(contains('secret')),
              ),
        ),
      );
    }
  });

  test('maps resolve, list, read, and watch failures by operation', () async {
    FileSystemException failure() => const FileSystemException(
      'fixture',
      '/fixture',
      OSError('fixture', 99),
    );

    final resolve = IoWorkspaceFileSystem(
      pathResolver: (_) async => throw failure(),
    );
    final list = IoWorkspaceFileSystem(
      directoryLister: (_) => Stream<FileSystemEntity>.error(failure()),
    );
    final read = IoWorkspaceFileSystem(
      textReader: (_) async => throw failure(),
    );
    final watch = IoWorkspaceFileSystem(
      directoryWatcher: (_) => Stream<FileSystemEvent>.error(failure()),
    );

    await expectOperation(
      resolve.resolvePath('/fixture'),
      WorkspaceFileSystemOperation.resolvePath,
    );
    await expectOperation(
      list.list('/fixture').drain<void>(),
      WorkspaceFileSystemOperation.listDirectory,
    );
    await expectOperation(
      read.readText('/fixture'),
      WorkspaceFileSystemOperation.readGitignore,
    );
    await expectOperation(
      watch.watch('/fixture').drain<void>(),
      WorkspaceFileSystemOperation.watchDirectory,
    );
  });

  test('list maps metadata races as list failures', () async {
    final fileSystem = IoWorkspaceFileSystem(
      directoryLister: (_) => Stream<FileSystemEntity>.value(File('/gone')),
      entityTypeReader: (_) async => throw const FileSystemException(
        'gone',
        '/gone',
        OSError('gone', 2),
      ),
    );

    await expectLater(
      fileSystem.list('/repo').drain<void>(),
      throwsA(
        isA<WorkspaceFileSystemException>()
            .having(
              (error) => error.operation,
              'operation',
              WorkspaceFileSystemOperation.listDirectory,
            )
            .having(
              (error) => error.code,
              'code',
              WorkspaceFileSystemFailureCode.notFound,
            ),
      ),
    );
  });
}

Future<void> expectOperation(
  Future<void> operation,
  WorkspaceFileSystemOperation expected,
) async {
  await expectLater(
    operation,
    throwsA(
      isA<WorkspaceFileSystemException>().having(
        (error) => error.operation,
        'operation',
        expected,
      ),
    ),
  );
}

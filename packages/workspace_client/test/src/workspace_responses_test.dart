import 'package:test/test.dart';
import 'package:workspace_client/workspace_client.dart';

void main() {
  test('workspace nodes are filesystem-only immutable values', () {
    const directory = WorkspaceNodeResponse(
      path: '/repo/lib',
      name: 'lib',
      type: WorkspaceNodeTypeResponse.directory,
    );
    const same = WorkspaceNodeResponse(
      path: '/repo/lib',
      name: 'lib',
      type: WorkspaceNodeTypeResponse.directory,
    );
    const file = WorkspaceNodeResponse(
      path: '/repo/lib/main.dart',
      name: 'main.dart',
      type: WorkspaceNodeTypeResponse.file,
    );

    expect(directory.isDirectory, isTrue);
    expect(file.isDirectory, isFalse);
    expect(directory, same);
    expect(directory.hashCode, same.hashCode);
    expect(directory, isNot(file));
    expect(directory, isNot('node'));
  });

  test('gitignore documents are immutable external values', () {
    const first = GitignoreDocumentResponse(
      basePath: '/repo',
      sourcePath: '/repo/.gitignore',
      contents: '*.log\n',
      kind: GitignoreDocumentKindResponse.directoryGitignore,
    );
    const same = GitignoreDocumentResponse(
      basePath: '/repo',
      sourcePath: '/repo/.gitignore',
      contents: '*.log\n',
      kind: GitignoreDocumentKindResponse.directoryGitignore,
    );
    const exclude = GitignoreDocumentResponse(
      basePath: '/repo',
      sourcePath: '/repo/.git/info/exclude',
      contents: 'private\n',
      kind: GitignoreDocumentKindResponse.repositoryExclude,
    );

    expect(first, same);
    expect(first.hashCode, same.hashCode);
    expect(first, isNot(exclude));
    expect(first, isNot('document'));
  });

  test('scan responses freeze files and retain bounded scan evidence', () {
    final source = <WorkspaceNodeResponse>[
      const WorkspaceNodeResponse(
        path: '/repo/a.dart',
        name: 'a.dart',
        type: WorkspaceNodeTypeResponse.file,
      ),
    ];
    final response = WorkspaceScanResponse(
      files: source,
      visitedDirectories: 2,
      truncated: true,
    );
    source.clear();

    expect(response.files, hasLength(1));
    expect(response.visitedDirectories, 2);
    expect(response.truncated, isTrue);
    expect(response.files.clear, throwsUnsupportedError);
  });

  test('change responses expose every neutral event field', () {
    const event = WorkspaceFileChangeResponse(
      kind: WorkspaceFileChangeKindResponse.move,
      path: '/repo/a.dart',
      destinationPath: '/repo/b.dart',
      isDirectory: false,
    );

    expect(event.kind, WorkspaceFileChangeKindResponse.move);
    expect(event.path, '/repo/a.dart');
    expect(event.destinationPath, '/repo/b.dart');
    expect(event.isDirectory, isFalse);
    expect(
      WorkspaceFileChangeKindResponse.values,
      containsAll(<WorkspaceFileChangeKindResponse>[
        WorkspaceFileChangeKindResponse.create,
        WorkspaceFileChangeKindResponse.modify,
        WorkspaceFileChangeKindResponse.delete,
      ]),
    );
  });

  test('typed failures and cancellation expose content-free contracts', () {
    const failure = WorkspaceFileSystemException(
      operation: WorkspaceFileSystemOperation.listDirectory,
      code: WorkspaceFileSystemFailureCode.accessDenied,
    );
    const cancelled = WorkspaceScanCancelledException();
    final token = WorkspaceScanCancellationToken();

    expect(failure.operation, WorkspaceFileSystemOperation.listDirectory);
    expect(failure.code, WorkspaceFileSystemFailureCode.accessDenied);
    expect(
      failure.toString(),
      'WorkspaceFileSystemException(listDirectory, accessDenied)',
    );
    expect(cancelled.toString(), 'WorkspaceScanCancelledException()');
    expect(token.isCancelled, isFalse);
    token.cancel();
    expect(token.isCancelled, isTrue);
    expect(
      token.throwIfCancelled,
      throwsA(isA<WorkspaceScanCancelledException>()),
    );
  });
}

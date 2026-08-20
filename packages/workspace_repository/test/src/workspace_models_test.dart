import 'package:test/test.dart';
import 'package:workspace_repository/workspace_repository.dart';

void main() {
  test('nodes normalize, compare, and validate identity', () {
    final node = WorkspaceNode(
      path: ' /repo/file.dart ',
      name: ' file.dart ',
      type: WorkspaceNodeType.file,
    );
    expect(node.path, '/repo/file.dart');
    expect(node.name, 'file.dart');
    expect(node.isDirectory, isFalse);
    expect(
      node,
      WorkspaceNode(
        path: '/repo/file.dart',
        name: 'file.dart',
        type: WorkspaceNodeType.file,
      ),
    );
    expect(
      WorkspaceNode(
        path: '/repo/lib',
        name: 'lib',
        type: WorkspaceNodeType.directory,
      ).isDirectory,
      isTrue,
    );
    expect(
      () => WorkspaceNode(path: ' ', name: 'x', type: WorkspaceNodeType.file),
      throwsArgumentError,
    );
    expect(
      () => WorkspaceNode(path: '/x', name: ' ', type: WorkspaceNodeType.file),
      throwsArgumentError,
    );
  });

  test('indices freeze, compare, and reject impossible metadata', () {
    final files = <WorkspaceNode>[
      WorkspaceNode(path: '/r/a', name: 'a', type: WorkspaceNodeType.file),
    ];
    final index = WorkspaceIndex(
      rootPath: '/r',
      files: files,
      visitedDirectories: 1,
      truncated: false,
      revision: 1,
    );
    files.clear();
    expect(index.files, hasLength(1));
    expect(
      index,
      WorkspaceIndex(
        rootPath: '/r',
        files: index.files,
        visitedDirectories: 1,
        truncated: false,
        revision: 1,
      ),
    );
    expect(index.files.clear, throwsUnsupportedError);
    expect(
      () => WorkspaceIndex(
        rootPath: '/r',
        files: const <WorkspaceNode>[],
        visitedDirectories: -1,
        truncated: false,
        revision: 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => WorkspaceIndex(
        rootPath: '/r',
        files: const <WorkspaceNode>[],
        visitedDirectories: 0,
        truncated: false,
        revision: 0,
      ),
      throwsArgumentError,
    );
  });

  test('tree changes normalize optional paths and compare structurally', () {
    final change = WorkspaceTreeChange(
      rootPath: ' /repo ',
      kind: WorkspaceTreeChangeKind.move,
      path: ' /repo/a ',
      isDirectory: false,
      destinationPath: ' /repo/b ',
    );
    expect(change.rootPath, '/repo');
    expect(change.path, '/repo/a');
    expect(change.destinationPath, '/repo/b');
    expect(
      change,
      WorkspaceTreeChange(
        rootPath: '/repo',
        kind: WorkspaceTreeChangeKind.move,
        path: '/repo/a',
        isDirectory: false,
        destinationPath: '/repo/b',
      ),
    );
    expect(
      WorkspaceTreeChange(
        rootPath: '/repo',
        kind: WorkspaceTreeChangeKind.create,
        path: '/repo/a',
        isDirectory: true,
      ).destinationPath,
      isNull,
    );
    expect(
      () => WorkspaceTreeChange(
        rootPath: '/repo',
        kind: WorkspaceTreeChangeKind.move,
        path: '/repo/a',
        isDirectory: false,
        destinationPath: ' ',
      ),
      throwsArgumentError,
    );
  });

  test('repository failures compare structurally', () {
    final diagnostic = <String>['workspace_index_ioFailure'].single;
    final failure = WorkspaceRepositoryFailure(
      operation: WorkspaceRepositoryOperation.indexWorkspace,
      code: WorkspaceRepositoryFailureCode.ioFailure,
      diagnosticCode: diagnostic,
    );
    expect(
      failure,
      WorkspaceRepositoryFailure(
        operation: WorkspaceRepositoryOperation.indexWorkspace,
        code: WorkspaceRepositoryFailureCode.ioFailure,
        diagnosticCode: diagnostic,
      ),
    );
  });
}

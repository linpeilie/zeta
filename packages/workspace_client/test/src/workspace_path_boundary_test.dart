import 'package:test/test.dart';
import 'package:workspace_client/workspace_client.dart';

import '../helpers/fake_workspace_file_system.dart';

void main() {
  group('WorkspacePathBoundary', () {
    test('accepts the root and a canonical in-root directory', () async {
      final fileSystem = FakeWorkspaceFileSystem()
        ..types['/repo'] = WorkspaceFileSystemEntityType.directory
        ..types['/repo/lib'] = WorkspaceFileSystemEntityType.directory
        ..resolvedPaths['/repo'] = '/real/repo'
        ..resolvedPaths['/repo/lib'] = '/real/repo/lib';
      final boundary = WorkspacePathBoundary(fileSystem);

      final root = await boundary.validateDirectory(
        rootPath: '/repo',
        directoryPath: '/repo',
      );
      final child = await boundary.validateDirectory(
        rootPath: '/repo',
        directoryPath: '/repo/lib',
      );

      expect(root.rootPath, '/repo');
      expect(root.directoryPath, '/repo');
      expect(child.directoryPath, '/repo/lib');
      expect(
        fileSystem.resolveCalls,
        containsAll(<String>['/repo', '/repo/lib']),
      );
    });

    test('rejects lexical and canonical escapes before scanning', () async {
      final fileSystem = FakeWorkspaceFileSystem()
        ..types['/repo'] = WorkspaceFileSystemEntityType.directory
        ..types['/repo/link/child'] = WorkspaceFileSystemEntityType.directory
        ..resolvedPaths['/repo'] = '/real/repo'
        ..resolvedPaths['/repo/link/child'] = '/outside/child';
      final boundary = WorkspacePathBoundary(fileSystem);

      await expectLater(
        boundary.validateDirectory(
          rootPath: '/repo',
          directoryPath: '/outside',
        ),
        failsWith(WorkspaceFileSystemFailureCode.outsideRoot),
      );
      await expectLater(
        boundary.validateDirectory(
          rootPath: '/repo',
          directoryPath: '/repo/link/child',
        ),
        failsWith(WorkspaceFileSystemFailureCode.outsideRoot),
      );
    });

    test('rejects root or requested-directory symbolic links', () async {
      final rootLink = FakeWorkspaceFileSystem()
        ..types['/repo'] = WorkspaceFileSystemEntityType.symbolicLink;
      final childLink = FakeWorkspaceFileSystem()
        ..types['/repo'] = WorkspaceFileSystemEntityType.directory
        ..types['/repo/link'] = WorkspaceFileSystemEntityType.symbolicLink;

      await expectLater(
        WorkspacePathBoundary(rootLink).validateDirectory(
          rootPath: '/repo',
          directoryPath: '/repo',
        ),
        failsWith(WorkspaceFileSystemFailureCode.symbolicLink),
      );
      await expectLater(
        WorkspacePathBoundary(childLink).validateDirectory(
          rootPath: '/repo',
          directoryPath: '/repo/link',
        ),
        failsWith(WorkspaceFileSystemFailureCode.symbolicLink),
      );
    });

    test('distinguishes missing and non-directory roots', () async {
      for (final entry
          in <(WorkspaceFileSystemEntityType, WorkspaceFileSystemFailureCode)>[
            (
              WorkspaceFileSystemEntityType.notFound,
              WorkspaceFileSystemFailureCode.notFound,
            ),
            (
              WorkspaceFileSystemEntityType.file,
              WorkspaceFileSystemFailureCode.notDirectory,
            ),
            (
              WorkspaceFileSystemEntityType.other,
              WorkspaceFileSystemFailureCode.notDirectory,
            ),
          ]) {
        final fileSystem = FakeWorkspaceFileSystem()..types['/repo'] = entry.$1;
        await expectLater(
          WorkspacePathBoundary(fileSystem).validateDirectory(
            rootPath: '/repo',
            directoryPath: '/repo',
          ),
          failsWith(entry.$2),
        );
      }
    });

    test('handles Windows paths without host-platform assumptions', () {
      final context = WorkspacePathBoundary.contextFor(r'C:\Repo');

      expect(
        WorkspacePathBoundary.samePath(context, r'C:\Repo', r'c:\repo'),
        isTrue,
      );
      expect(
        WorkspacePathBoundary.isWithin(context, r'C:\Repo', r'C:\Repo\lib'),
        isTrue,
      );
      expect(
        WorkspacePathBoundary.isWithin(context, r'C:\Repo', r'C:\Other'),
        isFalse,
      );
    });
  });
}

Matcher failsWith(WorkspaceFileSystemFailureCode code) {
  return throwsA(
    isA<WorkspaceFileSystemException>().having(
      (error) => error.code,
      'code',
      code,
    ),
  );
}

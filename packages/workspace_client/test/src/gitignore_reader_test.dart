import 'package:test/test.dart';
import 'package:workspace_client/workspace_client.dart';

import '../helpers/fake_workspace_file_system.dart';

void main() {
  group('FileGitignoreReader', () {
    test('reads root exclude and directory-local gitignore exactly', () async {
      final fileSystem = FakeWorkspaceFileSystem()
        ..types.addAll(<String, WorkspaceFileSystemEntityType>{
          '/repo': WorkspaceFileSystemEntityType.directory,
          '/repo/sub': WorkspaceFileSystemEntityType.directory,
          '/repo/.git': WorkspaceFileSystemEntityType.directory,
          '/repo/.git/info': WorkspaceFileSystemEntityType.directory,
          '/repo/.git/info/exclude': WorkspaceFileSystemEntityType.file,
          '/repo/.gitignore': WorkspaceFileSystemEntityType.file,
          '/repo/sub/.gitignore': WorkspaceFileSystemEntityType.file,
        })
        ..texts.addAll(<String, String>{
          '/repo/.git/info/exclude': 'private\n',
          '/repo/.gitignore': '*.log\n',
          '/repo/sub/.gitignore': '!keep.log\n',
        });
      final reader = FileGitignoreReader(fileSystem: fileSystem);

      final exclude = await reader.readRepositoryExclude('/repo');
      final root = await reader.readDirectoryGitignore(
        rootPath: '/repo',
        directoryPath: '/repo',
      );
      final nested = await reader.readDirectoryGitignore(
        rootPath: '/repo',
        directoryPath: '/repo/sub',
      );

      expect(exclude?.contents, 'private\n');
      expect(
        exclude?.kind,
        GitignoreDocumentKindResponse.repositoryExclude,
      );
      expect(root?.contents, '*.log\n');
      expect(root?.basePath, '/repo');
      expect(nested?.contents, '!keep.log\n');
      expect(nested?.basePath, '/repo/sub');
    });

    test('returns null for absent, non-file, or link inputs', () async {
      for (final type in <WorkspaceFileSystemEntityType>[
        WorkspaceFileSystemEntityType.notFound,
        WorkspaceFileSystemEntityType.directory,
        WorkspaceFileSystemEntityType.symbolicLink,
        WorkspaceFileSystemEntityType.other,
      ]) {
        final fileSystem = FakeWorkspaceFileSystem()
          ..types['/repo'] = WorkspaceFileSystemEntityType.directory
          ..types['/repo/.git'] = type
          ..types['/repo/.gitignore'] = type;
        final reader = FileGitignoreReader(fileSystem: fileSystem);

        expect(await reader.readRepositoryExclude('/repo'), isNull);
        expect(
          await reader.readDirectoryGitignore(
            rootPath: '/repo',
            directoryPath: '/repo',
          ),
          isNull,
        );
        expect(fileSystem.readCalls, isEmpty);
      }
    });

    test('does not traverse a linked .git or info directory', () async {
      final linkedGit = FakeWorkspaceFileSystem()
        ..types['/repo'] = WorkspaceFileSystemEntityType.directory
        ..types['/repo/.git'] = WorkspaceFileSystemEntityType.symbolicLink
        ..types['/repo/.git/info/exclude'] = WorkspaceFileSystemEntityType.file;
      final linkedInfo = FakeWorkspaceFileSystem()
        ..types['/repo'] = WorkspaceFileSystemEntityType.directory
        ..types['/repo/.git'] = WorkspaceFileSystemEntityType.directory
        ..types['/repo/.git/info'] = WorkspaceFileSystemEntityType.symbolicLink
        ..types['/repo/.git/info/exclude'] = WorkspaceFileSystemEntityType.file;

      expect(
        await FileGitignoreReader(
          fileSystem: linkedGit,
        ).readRepositoryExclude('/repo'),
        isNull,
      );
      expect(
        await FileGitignoreReader(
          fileSystem: linkedInfo,
        ).readRepositoryExclude('/repo'),
        isNull,
      );
      expect(linkedGit.readCalls, isEmpty);
      expect(linkedInfo.readCalls, isEmpty);
    });

    test(
      'propagates denied input reads and enforces directory boundary',
      () async {
        const denied = WorkspaceFileSystemException(
          operation: WorkspaceFileSystemOperation.readGitignore,
          code: WorkspaceFileSystemFailureCode.accessDenied,
        );
        final fileSystem = FakeWorkspaceFileSystem()
          ..types['/repo'] = WorkspaceFileSystemEntityType.directory
          ..types['/repo/.gitignore'] = WorkspaceFileSystemEntityType.file
          ..readErrors['/repo/.gitignore'] = denied;
        final reader = FileGitignoreReader(fileSystem: fileSystem);

        await expectLater(
          reader.readDirectoryGitignore(
            rootPath: '/repo',
            directoryPath: '/repo',
          ),
          throwsA(same(denied)),
        );
        await expectLater(
          reader.readDirectoryGitignore(
            rootPath: '/repo',
            directoryPath: '/outside',
          ),
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
  });
}

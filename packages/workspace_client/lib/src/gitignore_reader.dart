import 'package:path/path.dart' as p;
import 'package:workspace_client/src/workspace_file_system.dart';
import 'package:workspace_client/src/workspace_path_boundary.dart';
import 'package:workspace_client/src/workspace_responses.dart';

/// Reads raw gitignore inputs without applying domain matching policy.
abstract interface class GitignoreReader {
  /// Reads the root repository's `.git/info/exclude`, when it is regular.
  Future<GitignoreDocumentResponse?> readRepositoryExclude(String rootPath);

  /// Reads the `.gitignore` owned by [directoryPath], when it is regular.
  Future<GitignoreDocumentResponse?> readDirectoryGitignore({
    required String rootPath,
    required String directoryPath,
  });
}

/// Filesystem-backed [GitignoreReader].
final class FileGitignoreReader implements GitignoreReader {
  /// Creates a raw ignore-input reader.
  FileGitignoreReader({
    required this.fileSystem,
    WorkspacePathBoundary? boundary,
  }) : boundary = boundary ?? WorkspacePathBoundary(fileSystem);

  /// External filesystem seam.
  final WorkspaceFileSystem fileSystem;

  /// Root and symlink boundary validator.
  final WorkspacePathBoundary boundary;

  @override
  Future<GitignoreDocumentResponse?> readRepositoryExclude(
    String rootPath,
  ) async {
    final validated = await boundary.validateDirectory(
      rootPath: rootPath,
      directoryPath: rootPath,
    );
    final context = WorkspacePathBoundary.contextFor(validated.rootPath);
    final gitPath = context.join(validated.rootPath, '.git');
    if (await fileSystem.type(gitPath) !=
        WorkspaceFileSystemEntityType.directory) {
      return null;
    }
    final infoPath = context.join(gitPath, 'info');
    if (await fileSystem.type(infoPath) !=
        WorkspaceFileSystemEntityType.directory) {
      return null;
    }
    return _readRegularDocument(
      basePath: validated.rootPath,
      sourcePath: context.join(infoPath, 'exclude'),
      kind: GitignoreDocumentKindResponse.repositoryExclude,
    );
  }

  @override
  Future<GitignoreDocumentResponse?> readDirectoryGitignore({
    required String rootPath,
    required String directoryPath,
  }) async {
    final validated = await boundary.validateDirectory(
      rootPath: rootPath,
      directoryPath: directoryPath,
    );
    final context = WorkspacePathBoundary.contextFor(validated.rootPath);
    return _readRegularDocument(
      basePath: validated.directoryPath,
      sourcePath: p.Context(style: context.style).join(
        validated.directoryPath,
        '.gitignore',
      ),
      kind: GitignoreDocumentKindResponse.directoryGitignore,
    );
  }

  Future<GitignoreDocumentResponse?> _readRegularDocument({
    required String basePath,
    required String sourcePath,
    required GitignoreDocumentKindResponse kind,
  }) async {
    final type = await fileSystem.type(sourcePath);
    if (type != WorkspaceFileSystemEntityType.file) {
      return null;
    }
    return GitignoreDocumentResponse(
      basePath: basePath,
      sourcePath: sourcePath,
      contents: await fileSystem.readText(sourcePath),
      kind: kind,
    );
  }
}

import 'package:path/path.dart' as p;
import 'package:workspace_client/src/workspace_exceptions.dart';
import 'package:workspace_client/src/workspace_file_system.dart';

/// A root and target directory validated against link and path escape.
final class ValidatedWorkspaceDirectory {
  /// Creates validated directory paths.
  const ValidatedWorkspaceDirectory({
    required this.rootPath,
    required this.directoryPath,
  });

  /// Normalized declared root.
  final String rootPath;

  /// Normalized target directory.
  final String directoryPath;
}

/// Validates workspace roots and requested directory boundaries.
final class WorkspacePathBoundary {
  /// Creates a path boundary over [fileSystem].
  const WorkspacePathBoundary(this.fileSystem);

  /// Filesystem used for no-follow metadata and canonical resolution.
  final WorkspaceFileSystem fileSystem;

  /// Validates [directoryPath] as a real in-root directory.
  Future<ValidatedWorkspaceDirectory> validateDirectory({
    required String rootPath,
    required String directoryPath,
  }) async {
    final context = contextFor(rootPath);
    final root = context.normalize(context.absolute(rootPath));
    final directory = context.normalize(context.absolute(directoryPath));
    if (!isWithin(context, root, directory)) {
      throw const WorkspaceFileSystemException(
        operation: WorkspaceFileSystemOperation.resolvePath,
        code: WorkspaceFileSystemFailureCode.outsideRoot,
      );
    }
    await _requireDirectory(root);
    if (!samePath(context, root, directory)) {
      await _requireDirectory(directory);
    }
    final resolvedRoot = context.normalize(await fileSystem.resolvePath(root));
    final resolvedDirectory = context.normalize(
      samePath(context, root, directory)
          ? resolvedRoot
          : await fileSystem.resolvePath(directory),
    );
    if (!isWithin(context, resolvedRoot, resolvedDirectory)) {
      throw const WorkspaceFileSystemException(
        operation: WorkspaceFileSystemOperation.resolvePath,
        code: WorkspaceFileSystemFailureCode.outsideRoot,
      );
    }
    return ValidatedWorkspaceDirectory(
      rootPath: root,
      directoryPath: directory,
    );
  }

  Future<void> _requireDirectory(String path) async {
    final type = await fileSystem.type(path);
    switch (type) {
      case WorkspaceFileSystemEntityType.directory:
        return;
      case WorkspaceFileSystemEntityType.symbolicLink:
        throw const WorkspaceFileSystemException(
          operation: WorkspaceFileSystemOperation.metadata,
          code: WorkspaceFileSystemFailureCode.symbolicLink,
        );
      case WorkspaceFileSystemEntityType.notFound:
        throw const WorkspaceFileSystemException(
          operation: WorkspaceFileSystemOperation.metadata,
          code: WorkspaceFileSystemFailureCode.notFound,
        );
      case WorkspaceFileSystemEntityType.file:
      case WorkspaceFileSystemEntityType.other:
        throw const WorkspaceFileSystemException(
          operation: WorkspaceFileSystemOperation.metadata,
          code: WorkspaceFileSystemFailureCode.notDirectory,
        );
    }
  }

  /// Selects a Windows or POSIX path context without consulting the host OS.
  static p.Context contextFor(String path) {
    final isWindows =
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path) || path.contains(r'\');
    return p.Context(style: isWindows ? p.Style.windows : p.Style.posix);
  }

  /// Whether [candidate] equals or is nested within [root].
  static bool isWithin(p.Context context, String root, String candidate) {
    return samePath(context, root, candidate) ||
        context.isWithin(root, candidate);
  }

  /// Compares normalized paths with Windows case folding.
  static bool samePath(p.Context context, String first, String second) {
    final left = context.normalize(first);
    final right = context.normalize(second);
    if (context.style == p.Style.windows) {
      return left.toLowerCase() == right.toLowerCase();
    }
    return left == right;
  }
}

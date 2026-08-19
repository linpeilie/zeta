/// Workspace filesystem operations represented in typed failures.
enum WorkspaceFileSystemOperation {
  /// Reading entity metadata.
  metadata,

  /// Resolving a canonical path.
  resolvePath,

  /// Listing a directory.
  listDirectory,

  /// Reading a gitignore input document.
  readGitignore,

  /// Watching filesystem changes.
  watchDirectory,
}

/// Stable, content-free workspace failure codes.
enum WorkspaceFileSystemFailureCode {
  /// The requested path does not exist.
  notFound,

  /// The operating system denied access.
  accessDenied,

  /// The requested directory path is not a directory.
  notDirectory,

  /// A requested path escapes the declared workspace root.
  outsideRoot,

  /// A symbolic link was encountered at a protected boundary.
  symbolicLink,

  /// Another filesystem operation failed.
  ioFailure,
}

/// A workspace filesystem operation failed without exposing path contents.
final class WorkspaceFileSystemException implements Exception {
  /// Creates a typed workspace filesystem failure.
  const WorkspaceFileSystemException({
    required this.operation,
    required this.code,
  });

  /// Failed operation.
  final WorkspaceFileSystemOperation operation;

  /// Stable failure code.
  final WorkspaceFileSystemFailureCode code;

  @override
  String toString() {
    return 'WorkspaceFileSystemException(${operation.name}, ${code.name})';
  }
}

/// A recursive workspace scan was cancelled cooperatively.
final class WorkspaceScanCancelledException implements Exception {
  /// Creates a cancellation failure.
  const WorkspaceScanCancelledException();

  @override
  String toString() => 'WorkspaceScanCancelledException()';
}

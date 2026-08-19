import 'package:meta/meta.dart';

/// Filesystem node kinds exposed by the workspace Data boundary.
enum WorkspaceNodeTypeResponse {
  /// A regular directory.
  directory,

  /// A regular file.
  file,
}

/// One filesystem-only workspace node.
///
/// Interaction state such as selection and expansion is intentionally absent.
@immutable
final class WorkspaceNodeResponse {
  /// Creates a filesystem node response.
  const WorkspaceNodeResponse({
    required this.path,
    required this.name,
    required this.type,
  });

  /// Absolute or caller-canonical filesystem path.
  final String path;

  /// Last path component.
  final String name;

  /// Regular entity kind.
  final WorkspaceNodeTypeResponse type;

  /// Whether this node is a directory.
  bool get isDirectory => type == WorkspaceNodeTypeResponse.directory;

  @override
  bool operator ==(Object other) {
    return other is WorkspaceNodeResponse &&
        other.path == path &&
        other.name == name &&
        other.type == type;
  }

  @override
  int get hashCode => Object.hash(path, name, type);
}

/// Origin of one ignore-input document.
enum GitignoreDocumentKindResponse {
  /// Repository-local `.git/info/exclude`.
  repositoryExclude,

  /// A directory-local `.gitignore`.
  directoryGitignore,
}

/// Raw gitignore input read from the external filesystem.
@immutable
final class GitignoreDocumentResponse {
  /// Creates a raw ignore-input response.
  const GitignoreDocumentResponse({
    required this.basePath,
    required this.sourcePath,
    required this.contents,
    required this.kind,
  });

  /// Directory against which patterns are interpreted.
  final String basePath;

  /// Source document path.
  final String sourcePath;

  /// Exact external document contents.
  final String contents;

  /// Document origin.
  final GitignoreDocumentKindResponse kind;

  @override
  bool operator ==(Object other) {
    return other is GitignoreDocumentResponse &&
        other.basePath == basePath &&
        other.sourcePath == sourcePath &&
        other.contents == contents &&
        other.kind == kind;
  }

  @override
  int get hashCode => Object.hash(basePath, sourcePath, contents, kind);
}

/// Result of one bounded recursive workspace file scan.
@immutable
final class WorkspaceScanResponse {
  /// Creates a scan response and freezes [files].
  WorkspaceScanResponse({
    required List<WorkspaceNodeResponse> files,
    required this.visitedDirectories,
    required this.truncated,
  }) : files = List<WorkspaceNodeResponse>.unmodifiable(files);

  /// Regular files in deterministic depth-first traversal order.
  final List<WorkspaceNodeResponse> files;

  /// Number of directories whose listing was attempted.
  final int visitedDirectories;

  /// Whether [files] stopped at the configured safety limit.
  final bool truncated;
}

/// Neutral filesystem change kinds.
enum WorkspaceFileChangeKindResponse {
  /// An entity was created.
  create,

  /// An entity was modified.
  modify,

  /// An entity was deleted.
  delete,

  /// An entity moved or was renamed.
  move,
}

/// One external workspace filesystem change.
@immutable
final class WorkspaceFileChangeResponse {
  /// Creates a neutral change response.
  const WorkspaceFileChangeResponse({
    required this.kind,
    required this.path,
    required this.isDirectory,
    this.destinationPath,
  });

  /// Change kind.
  final WorkspaceFileChangeKindResponse kind;

  /// Source or affected path.
  final String path;

  /// Whether the event describes a directory.
  final bool isDirectory;

  /// In-root destination for move events, when available.
  final String? destinationPath;
}

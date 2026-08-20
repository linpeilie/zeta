import 'package:equatable/equatable.dart';

/// Filesystem node kinds exposed by the workspace domain.
enum WorkspaceNodeType {
  /// A regular directory.
  directory,

  /// A regular file.
  file,
}

/// One immutable workspace filesystem node.
final class WorkspaceNode extends Equatable {
  /// Creates a workspace node.
  WorkspaceNode({
    required String path,
    required String name,
    required this.type,
  }) : path = _nonEmpty(path, 'path'),
       name = _nonEmpty(name, 'name');

  /// Absolute or caller-canonical filesystem path.
  final String path;

  /// Last path component.
  final String name;

  /// Regular entity kind.
  final WorkspaceNodeType type;

  /// Whether this node is a directory.
  bool get isDirectory => type == WorkspaceNodeType.directory;

  @override
  List<Object?> get props => <Object?>[path, name, type];
}

/// One immutable recursive workspace index.
final class WorkspaceIndex extends Equatable {
  /// Creates an index and freezes [files].
  WorkspaceIndex({
    required String rootPath,
    required Iterable<WorkspaceNode> files,
    required this.visitedDirectories,
    required this.truncated,
    required this.revision,
  }) : rootPath = _nonEmpty(rootPath, 'rootPath'),
       files = List<WorkspaceNode>.unmodifiable(files) {
    if (visitedDirectories < 0) {
      throw ArgumentError.value(
        visitedDirectories,
        'visitedDirectories',
        'must not be negative',
      );
    }
    if (revision <= 0) {
      throw ArgumentError.value(revision, 'revision', 'must be positive');
    }
  }

  /// Root represented by this index.
  final String rootPath;

  /// Indexed regular files in deterministic traversal order.
  final List<WorkspaceNode> files;

  /// Number of directories visited by the Data scan.
  final int visitedDirectories;

  /// Whether the configured file bound truncated the result.
  final bool truncated;

  /// Monotonic revision for this root.
  final int revision;

  @override
  List<Object?> get props => <Object?>[
    rootPath,
    files,
    visitedDirectories,
    truncated,
    revision,
  ];
}

/// External workspace filesystem change kinds.
enum WorkspaceTreeChangeKind {
  /// An entity was created.
  create,

  /// An entity was modified.
  modify,

  /// An entity was deleted.
  delete,

  /// An entity moved or was renamed.
  move,
}

/// One provider-neutral external filesystem change.
final class WorkspaceTreeChange extends Equatable {
  /// Creates a tree change.
  WorkspaceTreeChange({
    required String rootPath,
    required this.kind,
    required String path,
    required this.isDirectory,
    String? destinationPath,
  }) : rootPath = _nonEmpty(rootPath, 'rootPath'),
       path = _nonEmpty(path, 'path'),
       destinationPath = _optionalNonEmpty(destinationPath, 'destinationPath');

  /// Indexed root whose watch produced this event.
  final String rootPath;

  /// Change kind.
  final WorkspaceTreeChangeKind kind;

  /// Source or affected path.
  final String path;

  /// Whether the event describes a directory.
  final bool isDirectory;

  /// In-root destination for a move, when supplied by the platform.
  final String? destinationPath;

  @override
  List<Object?> get props => <Object?>[
    rootPath,
    kind,
    path,
    isDirectory,
    destinationPath,
  ];
}

String _nonEmpty(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
  return normalized;
}

String? _optionalNonEmpty(String? value, String name) {
  if (value == null) {
    return null;
  }
  return _nonEmpty(value, name);
}

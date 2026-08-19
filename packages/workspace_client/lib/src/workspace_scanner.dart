import 'dart:async';

import 'package:workspace_client/src/gitignore_reader.dart';
import 'package:workspace_client/src/workspace_exceptions.dart';
import 'package:workspace_client/src/workspace_file_system.dart';
import 'package:workspace_client/src/workspace_path_boundary.dart';
import 'package:workspace_client/src/workspace_responses.dart';

/// Inclusion outcome supplied by the Repository's pure ignore policy.
enum WorkspaceEntryDisposition {
  /// Include the entry and traverse it when it is a directory.
  include,

  /// Exclude the entry but continue traversing a directory for possible rules.
  skip,

  /// Exclude the entry and prune its directory subtree.
  prune,
}

/// Pure ignore-policy callback supplied by the Repository layer.
typedef WorkspaceEntryFilter = WorkspaceEntryDisposition Function(
  WorkspaceNodeResponse entry,
  List<GitignoreDocumentResponse> activeIgnoreDocuments,
);

/// Cooperative cancellation signal for a potentially large scan.
final class WorkspaceScanCancellationToken {
  bool _isCancelled = false;

  /// Whether cancellation was requested.
  bool get isCancelled => _isCancelled;

  /// Requests cancellation.
  void cancel() => _isCancelled = true;

  /// Throws when cancellation has been requested.
  void throwIfCancelled() {
    if (_isCancelled) {
      throw const WorkspaceScanCancelledException();
    }
  }
}

/// Workspace scan, one-level directory read, and change-stream Data boundary.
abstract interface class WorkspaceScanner {
  /// Recursively scans regular files under [rootPath].
  Future<WorkspaceScanResponse> scanFiles(
    String rootPath, {
    int maxFiles = 50000,
    WorkspaceScanCancellationToken? cancellationToken,
    WorkspaceEntryFilter? filter,
  });

  /// Reads regular file/directory children directly below [directoryPath].
  Future<List<WorkspaceNodeResponse>> readDirectory({
    required String rootPath,
    required String directoryPath,
    WorkspaceScanCancellationToken? cancellationToken,
    WorkspaceEntryFilter? filter,
  });

  /// Creates a recursive external filesystem change stream for [rootPath].
  Stream<WorkspaceFileChangeResponse> watch(String rootPath);
}

/// Filesystem-backed implementation of [WorkspaceScanner].
final class FileWorkspaceScanner implements WorkspaceScanner {
  /// Creates a workspace scanner.
  FileWorkspaceScanner({
    required this.fileSystem,
    GitignoreReader? gitignoreReader,
    WorkspacePathBoundary? boundary,
  }) : boundary = boundary ?? WorkspacePathBoundary(fileSystem),
       gitignoreReader =
           gitignoreReader ?? FileGitignoreReader(fileSystem: fileSystem);

  /// External filesystem seam.
  final WorkspaceFileSystem fileSystem;

  /// Raw gitignore input reader.
  final GitignoreReader gitignoreReader;

  /// Path and symbolic-link boundary.
  final WorkspacePathBoundary boundary;

  @override
  Future<WorkspaceScanResponse> scanFiles(
    String rootPath, {
    int maxFiles = 50000,
    WorkspaceScanCancellationToken? cancellationToken,
    WorkspaceEntryFilter? filter,
  }) async {
    if (maxFiles <= 0) {
      throw ArgumentError.value(maxFiles, 'maxFiles', 'must be positive');
    }
    final token = (cancellationToken ?? WorkspaceScanCancellationToken())
      ..throwIfCancelled();
    final validated = await boundary.validateDirectory(
      rootPath: rootPath,
      directoryPath: rootPath,
    );
    final files = <WorkspaceNodeResponse>[];
    final activeDocuments = <GitignoreDocumentResponse>[];
    var visitedDirectories = 0;
    var truncated = false;

    Future<void> visit(String directoryPath) async {
      if (truncated) {
        return;
      }
      token.throwIfCancelled();
      final documents = await _readIgnoreDocuments(
        validated.rootPath,
        directoryPath,
      );
      activeDocuments.addAll(documents);
      visitedDirectories += 1;
      try {
        await for (final entry in fileSystem.list(directoryPath)) {
          token.throwIfCancelled();
          final node = _nodeForEntry(validated.rootPath, entry);
          if (node == null) {
            continue;
          }
          final disposition =
              filter?.call(
                node,
                List<GitignoreDocumentResponse>.unmodifiable(activeDocuments),
              ) ??
              WorkspaceEntryDisposition.include;
          if (node.isDirectory) {
            if (disposition != WorkspaceEntryDisposition.prune) {
              await visit(node.path);
            }
            continue;
          }
          if (disposition == WorkspaceEntryDisposition.include) {
            files.add(node);
            if (files.length >= maxFiles) {
              truncated = true;
              return;
            }
          }
        }
      } finally {
        activeDocuments.removeRange(
          activeDocuments.length - documents.length,
          activeDocuments.length,
        );
      }
    }

    await visit(validated.rootPath);
    token.throwIfCancelled();
    return WorkspaceScanResponse(
      files: files,
      visitedDirectories: visitedDirectories,
      truncated: truncated,
    );
  }

  @override
  Future<List<WorkspaceNodeResponse>> readDirectory({
    required String rootPath,
    required String directoryPath,
    WorkspaceScanCancellationToken? cancellationToken,
    WorkspaceEntryFilter? filter,
  }) async {
    final token = (cancellationToken ?? WorkspaceScanCancellationToken())
      ..throwIfCancelled();
    final validated = await boundary.validateDirectory(
      rootPath: rootPath,
      directoryPath: directoryPath,
    );
    final documents = await _readIgnoreDocuments(
      validated.rootPath,
      validated.directoryPath,
    );
    final nodes = <WorkspaceNodeResponse>[];
    await for (final entry in fileSystem.list(validated.directoryPath)) {
      token.throwIfCancelled();
      final node = _nodeForEntry(validated.rootPath, entry);
      if (node == null) {
        continue;
      }
      final disposition =
          filter?.call(node, documents) ?? WorkspaceEntryDisposition.include;
      if (disposition == WorkspaceEntryDisposition.include) {
        nodes.add(node);
      }
    }
    nodes.sort(_compareNodes);
    token.throwIfCancelled();
    return List<WorkspaceNodeResponse>.unmodifiable(nodes);
  }

  @override
  Stream<WorkspaceFileChangeResponse> watch(String rootPath) async* {
    final validated = await boundary.validateDirectory(
      rootPath: rootPath,
      directoryPath: rootPath,
    );
    final context = WorkspacePathBoundary.contextFor(validated.rootPath);
    await for (final event in fileSystem.watch(validated.rootPath)) {
      final eventPath = context.normalize(context.absolute(event.path));
      if (!WorkspacePathBoundary.isWithin(
        context,
        validated.rootPath,
        eventPath,
      )) {
        continue;
      }
      final destination = event.destinationPath;
      final normalizedDestination = destination == null
          ? null
          : context.normalize(context.absolute(destination));
      yield WorkspaceFileChangeResponse(
        kind: event.kind,
        path: eventPath,
        isDirectory: event.isDirectory,
        destinationPath:
            normalizedDestination != null &&
                WorkspacePathBoundary.isWithin(
                  context,
                  validated.rootPath,
                  normalizedDestination,
                )
            ? normalizedDestination
            : null,
      );
    }
  }

  WorkspaceNodeResponse? _nodeForEntry(
    String rootPath,
    WorkspaceFileSystemEntry entry,
  ) {
    final context = WorkspacePathBoundary.contextFor(rootPath);
    final path = context.normalize(context.absolute(entry.path));
    if (!WorkspacePathBoundary.isWithin(context, rootPath, path)) {
      throw const WorkspaceFileSystemException(
        operation: WorkspaceFileSystemOperation.listDirectory,
        code: WorkspaceFileSystemFailureCode.outsideRoot,
      );
    }
    final type = switch (entry.type) {
      WorkspaceFileSystemEntityType.file => WorkspaceNodeTypeResponse.file,
      WorkspaceFileSystemEntityType.directory =>
        WorkspaceNodeTypeResponse.directory,
      WorkspaceFileSystemEntityType.symbolicLink ||
      WorkspaceFileSystemEntityType.notFound ||
      WorkspaceFileSystemEntityType.other => null,
    };
    if (type == null) {
      return null;
    }
    return WorkspaceNodeResponse(
      path: path,
      name: context.basename(path),
      type: type,
    );
  }

  Future<List<GitignoreDocumentResponse>> _readIgnoreDocuments(
    String rootPath,
    String directoryPath,
  ) async {
    final context = WorkspacePathBoundary.contextFor(rootPath);
    final documents = <GitignoreDocumentResponse>[];
    if (WorkspacePathBoundary.samePath(context, rootPath, directoryPath)) {
      final exclude = await gitignoreReader.readRepositoryExclude(rootPath);
      if (exclude != null) {
        documents.add(exclude);
      }
    }
    final gitignore = await gitignoreReader.readDirectoryGitignore(
      rootPath: rootPath,
      directoryPath: directoryPath,
    );
    if (gitignore != null) {
      documents.add(gitignore);
    }
    return List<GitignoreDocumentResponse>.unmodifiable(documents);
  }
}

int _compareNodes(WorkspaceNodeResponse first, WorkspaceNodeResponse second) {
  if (first.isDirectory != second.isDirectory) {
    return first.isDirectory ? -1 : 1;
  }
  final folded = first.name.toLowerCase().compareTo(second.name.toLowerCase());
  return folded == 0 ? first.name.compareTo(second.name) : folded;
}

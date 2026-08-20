import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:workspace_client/workspace_client.dart';
import 'package:workspace_repository/src/workspace_ignore.dart';
import 'package:workspace_repository/src/workspace_models.dart';
import 'package:workspace_repository/src/workspace_query.dart';

// The public dependency name intentionally differs from the private field.
// ignore_for_file: prefer_initializing_formals

/// Stable workspace Repository operation categories.
enum WorkspaceRepositoryOperation {
  /// Recursively index one root.
  indexWorkspace,

  /// Read one directory level.
  loadChildren,

  /// Consume external filesystem events.
  watch,

  /// Query a completed index.
  query,

  /// Close owned watches and streams.
  close,
}

/// Stable workspace Repository failure categories.
enum WorkspaceRepositoryFailureCode {
  /// A requested path does not exist.
  notFound,

  /// Filesystem access was denied.
  accessDenied,

  /// A requested path is not a directory.
  notDirectory,

  /// A requested path escapes the root.
  outsideRoot,

  /// A symbolic link occurs at a protected boundary.
  symbolicLink,

  /// Another external filesystem operation failed.
  ioFailure,

  /// A scan was cooperatively cancelled.
  cancelled,

  /// Caller input is invalid.
  invalidInput,

  /// External Data violates its response contract.
  invalidData,

  /// The Repository is already closed.
  closed,
}

/// A content-free workspace Repository failure.
final class WorkspaceRepositoryFailure extends Equatable {
  /// Creates a workspace failure.
  const WorkspaceRepositoryFailure({
    required this.operation,
    required this.code,
    required this.diagnosticCode,
  });

  /// Operation that failed.
  final WorkspaceRepositoryOperation operation;

  /// Stable failure category.
  final WorkspaceRepositoryFailureCode code;

  /// Stable, non-localized diagnostic code.
  final String diagnosticCode;

  @override
  List<Object?> get props => <Object?>[operation, code, diagnosticCode];
}

/// A typed workspace exception retaining private diagnostic context.
final class WorkspaceRepositoryException implements Exception {
  /// Creates a workspace Repository exception.
  const WorkspaceRepositoryException({
    required this.failure,
    required this.cause,
    required this.stackTrace,
  });

  /// Safe failure exposed to callers and state.
  final WorkspaceRepositoryFailure failure;

  /// Original cause for sanitized diagnostics only.
  final Object cause;

  /// Original stack for sanitized diagnostics only.
  final StackTrace stackTrace;
}

/// Owns workspace indices and maps filesystem Data into domain snapshots.
///
/// Selection, expansion, loading, progress, retry, and user-visible failures
/// intentionally remain in WorkspaceCubit.
class WorkspaceRepository {
  /// Creates a workspace Repository over [scanner].
  WorkspaceRepository({required WorkspaceScanner scanner}) : _scanner = scanner;

  final WorkspaceScanner _scanner;
  final Map<String, WorkspaceIndex> _indices = <String, WorkspaceIndex>{};
  final Map<String, Future<void>> _indexQueues = <String, Future<void>>{};
  final Map<String, StreamSubscription<WorkspaceFileChangeResponse>>
  _watchSubscriptions =
      <String, StreamSubscription<WorkspaceFileChangeResponse>>{};
  final StreamController<WorkspaceIndex> _indexChanges =
      StreamController<WorkspaceIndex>.broadcast(sync: true);
  final StreamController<WorkspaceTreeChange> _treeChanges =
      StreamController<WorkspaceTreeChange>.broadcast(sync: true);
  Future<void>? _closeFuture;
  bool _closed = false;

  /// Successful external index changes across all roots.
  Stream<WorkspaceIndex> get indexChanges => _indexChanges.stream;

  /// External filesystem changes across roots that have been indexed.
  Stream<WorkspaceTreeChange> get treeChanges => _treeChanges.stream;

  /// Returns the current index for [rootPath], when one exists.
  WorkspaceIndex? indexFor(String rootPath) => _indices[rootPath.trim()];

  /// Scans [rootPath], stores its immutable corpus, and starts one root watch.
  Future<WorkspaceIndex> index(
    String rootPath, {
    int maxFiles = 50000,
    WorkspaceScanCancellationToken? cancellationToken,
  }) {
    _ensureOpen(WorkspaceRepositoryOperation.indexWorkspace);
    final root = _requiredText(
      rootPath,
      operation: WorkspaceRepositoryOperation.indexWorkspace,
      diagnosticCode: 'workspace_root_required',
    );
    if (maxFiles <= 0) {
      _fail(
        operation: WorkspaceRepositoryOperation.indexWorkspace,
        code: WorkspaceRepositoryFailureCode.invalidInput,
        diagnosticCode: 'workspace_max_files_invalid',
        cause: ArgumentError.value(maxFiles, 'maxFiles'),
        stackTrace: StackTrace.current,
      );
    }
    _ensureWatching(root);
    return _enqueueIndex(
      root,
      () => _indexNow(
        root,
        maxFiles: maxFiles,
        cancellationToken: cancellationToken,
      ),
    );
  }

  Future<WorkspaceIndex> _indexNow(
    String root, {
    required int maxFiles,
    required WorkspaceScanCancellationToken? cancellationToken,
  }) async {
    try {
      final response = await _scanner.scanFiles(
        root,
        maxFiles: maxFiles,
        cancellationToken: cancellationToken,
        filter: createWorkspaceEntryFilter(root),
      );
      final files = response.files.map(_mapNode).toList(growable: false);
      if (response.visitedDirectories < 0) {
        throw const _InvalidWorkspaceDataException();
      }
      final previous = _indices[root];
      if (previous != null &&
          previous.files.length == files.length &&
          _sameNodes(previous.files, files) &&
          previous.visitedDirectories == response.visitedDirectories &&
          previous.truncated == response.truncated) {
        return previous;
      }
      final next = WorkspaceIndex(
        rootPath: root,
        files: files,
        visitedDirectories: response.visitedDirectories,
        truncated: response.truncated,
        revision: (previous?.revision ?? 0) + 1,
      );
      _indices[root] = next;
      if (!_closed) {
        _indexChanges.add(next);
      }
      return next;
    } on WorkspaceScanCancelledException catch (error, stackTrace) {
      _fail(
        operation: WorkspaceRepositoryOperation.indexWorkspace,
        code: WorkspaceRepositoryFailureCode.cancelled,
        diagnosticCode: 'workspace_index_cancelled',
        cause: error,
        stackTrace: stackTrace,
      );
    } on WorkspaceFileSystemException catch (error, stackTrace) {
      throw _dataException(
        WorkspaceRepositoryOperation.indexWorkspace,
        error,
        stackTrace,
      );
    } on _InvalidWorkspaceDataException catch (error, stackTrace) {
      _fail(
        operation: WorkspaceRepositoryOperation.indexWorkspace,
        code: WorkspaceRepositoryFailureCode.invalidData,
        diagnosticCode: 'workspace_index_invalid_data',
        cause: error,
        stackTrace: stackTrace,
      );
    } on WorkspaceRepositoryException {
      rethrow;
    } on Object catch (error, stackTrace) {
      _fail(
        operation: WorkspaceRepositoryOperation.indexWorkspace,
        code: WorkspaceRepositoryFailureCode.ioFailure,
        diagnosticCode: 'workspace_index_failed',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Returns fuzzy-ranked files from the current index for [rootPath].
  List<WorkspaceNode> query(
    String rootPath, {
    required String query,
    int limit = 40,
  }) {
    _ensureOpen(WorkspaceRepositoryOperation.query);
    final root = _requiredText(
      rootPath,
      operation: WorkspaceRepositoryOperation.query,
      diagnosticCode: 'workspace_root_required',
    );
    if (limit <= 0) {
      _fail(
        operation: WorkspaceRepositoryOperation.query,
        code: WorkspaceRepositoryFailureCode.invalidInput,
        diagnosticCode: 'workspace_query_limit_invalid',
        cause: ArgumentError.value(limit, 'limit'),
        stackTrace: StackTrace.current,
      );
    }
    return fuzzyRankWorkspaceFiles(
      _indices[root]?.files ?? const <WorkspaceNode>[],
      query: query,
      limit: limit,
    );
  }

  /// Loads one directory level with default and gitignore policies applied.
  Future<List<WorkspaceNode>> loadChildren({
    required String rootPath,
    required String directoryPath,
    WorkspaceScanCancellationToken? cancellationToken,
  }) async {
    _ensureOpen(WorkspaceRepositoryOperation.loadChildren);
    final root = _requiredText(
      rootPath,
      operation: WorkspaceRepositoryOperation.loadChildren,
      diagnosticCode: 'workspace_root_required',
    );
    final directory = _requiredText(
      directoryPath,
      operation: WorkspaceRepositoryOperation.loadChildren,
      diagnosticCode: 'workspace_directory_required',
    );
    try {
      final response = await _scanner.readDirectory(
        rootPath: root,
        directoryPath: directory,
        cancellationToken: cancellationToken,
        filter: createWorkspaceEntryFilter(root),
      );
      return List<WorkspaceNode>.unmodifiable(response.map(_mapNode));
    } on WorkspaceScanCancelledException catch (error, stackTrace) {
      _fail(
        operation: WorkspaceRepositoryOperation.loadChildren,
        code: WorkspaceRepositoryFailureCode.cancelled,
        diagnosticCode: 'workspace_children_cancelled',
        cause: error,
        stackTrace: stackTrace,
      );
    } on WorkspaceFileSystemException catch (error, stackTrace) {
      throw _dataException(
        WorkspaceRepositoryOperation.loadChildren,
        error,
        stackTrace,
      );
    } on _InvalidWorkspaceDataException catch (error, stackTrace) {
      _fail(
        operation: WorkspaceRepositoryOperation.loadChildren,
        code: WorkspaceRepositoryFailureCode.invalidData,
        diagnosticCode: 'workspace_children_invalid_data',
        cause: error,
        stackTrace: stackTrace,
      );
    } on Object catch (error, stackTrace) {
      _fail(
        operation: WorkspaceRepositoryOperation.loadChildren,
        code: WorkspaceRepositoryFailureCode.ioFailure,
        diagnosticCode: 'workspace_children_failed',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Stops watches and closes external-data streams. Idempotent.
  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    _closed = true;
    await Future.wait<void>(_indexQueues.values);
    ({Object error, StackTrace stackTrace})? firstFailure;
    for (final subscription in _watchSubscriptions.values) {
      try {
        await subscription.cancel();
      } on Object catch (error, stackTrace) {
        firstFailure ??= (error: error, stackTrace: stackTrace);
      }
    }
    _watchSubscriptions.clear();
    await _indexChanges.close();
    await _treeChanges.close();
    _indices.clear();
    if (firstFailure != null) {
      throw _exception(
        operation: WorkspaceRepositoryOperation.close,
        code: WorkspaceRepositoryFailureCode.ioFailure,
        diagnosticCode: 'workspace_close_failed',
        cause: firstFailure.error,
        stackTrace: firstFailure.stackTrace,
      );
    }
  }

  void _ensureWatching(String rootPath) {
    if (_watchSubscriptions.containsKey(rootPath)) {
      return;
    }
    late final StreamSubscription<WorkspaceFileChangeResponse> subscription;
    try {
      subscription = _scanner
          .watch(rootPath)
          .listen(
            (response) {
              if (_closed) {
                return;
              }
              try {
                _treeChanges.add(_mapTreeChange(rootPath, response));
              } on Object catch (error, stackTrace) {
                _treeChanges.addError(
                  _watchException(error, stackTrace, invalidData: true),
                  stackTrace,
                );
              }
            },
            onError: (Object error, StackTrace stackTrace) {
              if (!_closed) {
                _treeChanges.addError(
                  _watchException(error, stackTrace),
                  stackTrace,
                );
              }
            },
            onDone: () {
              if (identical(_watchSubscriptions[rootPath], subscription)) {
                _watchSubscriptions.remove(rootPath);
              }
            },
            cancelOnError: false,
          );
      _watchSubscriptions[rootPath] = subscription;
    } on Object catch (error, stackTrace) {
      throw _watchException(error, stackTrace);
    }
  }

  WorkspaceRepositoryException _watchException(
    Object error,
    StackTrace stackTrace, {
    bool invalidData = false,
  }) {
    if (error is WorkspaceRepositoryException) {
      return error;
    }
    if (error is WorkspaceFileSystemException) {
      return _dataException(
        WorkspaceRepositoryOperation.watch,
        error,
        stackTrace,
      );
    }
    return _exception(
      operation: WorkspaceRepositoryOperation.watch,
      code: invalidData
          ? WorkspaceRepositoryFailureCode.invalidData
          : WorkspaceRepositoryFailureCode.ioFailure,
      diagnosticCode: invalidData
          ? 'workspace_watch_invalid_data'
          : 'workspace_watch_failed',
      cause: error,
      stackTrace: stackTrace,
    );
  }

  Future<T> _enqueueIndex<T>(String rootPath, Future<T> Function() action) {
    final completer = Completer<T>();
    final previous = _indexQueues[rootPath] ?? Future<void>.value();
    final next = previous.then((_) async {
      try {
        completer.complete(await action());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    _indexQueues[rootPath] = next;
    unawaited(
      next.then((_) {
        if (identical(_indexQueues[rootPath], next)) {
          final _ = _indexQueues.remove(rootPath);
        }
      }),
    );
    return completer.future;
  }

  void _ensureOpen(WorkspaceRepositoryOperation operation) {
    if (_closed) {
      _fail(
        operation: operation,
        code: WorkspaceRepositoryFailureCode.closed,
        diagnosticCode: 'workspace_repository_closed',
        cause: StateError('WorkspaceRepository is closed'),
        stackTrace: StackTrace.current,
      );
    }
  }
}

WorkspaceNode _mapNode(WorkspaceNodeResponse response) {
  if (response.path.trim().isEmpty || response.name.trim().isEmpty) {
    throw const _InvalidWorkspaceDataException();
  }
  return WorkspaceNode(
    path: response.path,
    name: response.name,
    type: switch (response.type) {
      WorkspaceNodeTypeResponse.directory => WorkspaceNodeType.directory,
      WorkspaceNodeTypeResponse.file => WorkspaceNodeType.file,
    },
  );
}

WorkspaceTreeChange _mapTreeChange(
  String rootPath,
  WorkspaceFileChangeResponse response,
) {
  if (rootPath.trim().isEmpty ||
      response.path.trim().isEmpty ||
      response.destinationPath?.trim().isEmpty == true) {
    throw const _InvalidWorkspaceDataException();
  }
  return WorkspaceTreeChange(
    rootPath: rootPath,
    kind: switch (response.kind) {
      WorkspaceFileChangeKindResponse.create => WorkspaceTreeChangeKind.create,
      WorkspaceFileChangeKindResponse.modify => WorkspaceTreeChangeKind.modify,
      WorkspaceFileChangeKindResponse.delete => WorkspaceTreeChangeKind.delete,
      WorkspaceFileChangeKindResponse.move => WorkspaceTreeChangeKind.move,
    },
    path: response.path,
    isDirectory: response.isDirectory,
    destinationPath: response.destinationPath,
  );
}

bool _sameNodes(List<WorkspaceNode> first, List<WorkspaceNode> second) {
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) {
      return false;
    }
  }
  return true;
}

String _requiredText(
  String value, {
  required WorkspaceRepositoryOperation operation,
  required String diagnosticCode,
}) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    _fail(
      operation: operation,
      code: WorkspaceRepositoryFailureCode.invalidInput,
      diagnosticCode: diagnosticCode,
      cause: ArgumentError.value(value),
      stackTrace: StackTrace.current,
    );
  }
  return normalized;
}

WorkspaceRepositoryException _dataException(
  WorkspaceRepositoryOperation operation,
  WorkspaceFileSystemException error,
  StackTrace stackTrace,
) {
  final code = switch (error.code) {
    WorkspaceFileSystemFailureCode.notFound =>
      WorkspaceRepositoryFailureCode.notFound,
    WorkspaceFileSystemFailureCode.accessDenied =>
      WorkspaceRepositoryFailureCode.accessDenied,
    WorkspaceFileSystemFailureCode.notDirectory =>
      WorkspaceRepositoryFailureCode.notDirectory,
    WorkspaceFileSystemFailureCode.outsideRoot =>
      WorkspaceRepositoryFailureCode.outsideRoot,
    WorkspaceFileSystemFailureCode.symbolicLink =>
      WorkspaceRepositoryFailureCode.symbolicLink,
    WorkspaceFileSystemFailureCode.ioFailure =>
      WorkspaceRepositoryFailureCode.ioFailure,
  };
  return _exception(
    operation: operation,
    code: code,
    diagnosticCode: 'workspace_${operation.name}_${code.name}',
    cause: error,
    stackTrace: stackTrace,
  );
}

Never _fail({
  required WorkspaceRepositoryOperation operation,
  required WorkspaceRepositoryFailureCode code,
  required String diagnosticCode,
  required Object cause,
  required StackTrace stackTrace,
}) {
  throw _exception(
    operation: operation,
    code: code,
    diagnosticCode: diagnosticCode,
    cause: cause,
    stackTrace: stackTrace,
  );
}

WorkspaceRepositoryException _exception({
  required WorkspaceRepositoryOperation operation,
  required WorkspaceRepositoryFailureCode code,
  required String diagnosticCode,
  required Object cause,
  required StackTrace stackTrace,
}) {
  return WorkspaceRepositoryException(
    failure: WorkspaceRepositoryFailure(
      operation: operation,
      code: code,
      diagnosticCode: diagnosticCode,
    ),
    cause: cause,
    stackTrace: stackTrace,
  );
}

final class _InvalidWorkspaceDataException implements Exception {
  const _InvalidWorkspaceDataException();
}

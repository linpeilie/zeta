import 'dart:async';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:equatable/equatable.dart';
import 'package:project_session_client/project_session_client.dart';
import 'package:project_session_repository/src/project_session_models.dart';

// Public dependency names intentionally differ from private fields.
// ignore_for_file: prefer_initializing_formals

const int _perProviderFetchCap = 50;
const int _providerPageLimit = 10;
const String _aggregateCursorPrefix = 'agg:';

/// Stable project-session Repository operation categories.
enum ProjectSessionRepositoryOperation {
  /// Restore the persisted snapshot.
  restore,

  /// Save a snapshot.
  save,

  /// Read an aggregate thread page.
  threadPage,

  /// Close owned resources.
  close,
}

/// Stable project-session Repository failure categories.
enum ProjectSessionRepositoryFailureCode {
  /// Persisted source is malformed JSON.
  malformedJson,

  /// Persisted JSON root is invalid.
  invalidRoot,

  /// Persisted schema version is unsupported.
  unsupportedVersion,

  /// A current-schema field is invalid.
  invalidField,

  /// Caller input is invalid.
  invalidInput,

  /// External persistence failed.
  externalFailure,

  /// The Repository or store is closed.
  closed,
}

/// Content-free project-session Repository failure.
final class ProjectSessionRepositoryFailure extends Equatable {
  /// Creates a safe Repository failure.
  const ProjectSessionRepositoryFailure({
    required this.operation,
    required this.code,
    required this.diagnosticCode,
  });

  /// Operation that failed.
  final ProjectSessionRepositoryOperation operation;

  /// Stable failure category.
  final ProjectSessionRepositoryFailureCode code;

  /// Stable, non-localized diagnostic code.
  final String diagnosticCode;

  @override
  List<Object?> get props => <Object?>[operation, code, diagnosticCode];
}

/// Typed exception retaining private diagnostics outside state and UI copy.
final class ProjectSessionRepositoryException implements Exception {
  /// Creates a typed Repository exception.
  const ProjectSessionRepositoryException({
    required this.failure,
    required this.cause,
    required this.stackTrace,
  });

  /// Safe failure exposed to callers.
  final ProjectSessionRepositoryFailure failure;

  /// Original cause for sanitized diagnostics only.
  final Object cause;

  /// Original stack for sanitized diagnostics only.
  final StackTrace stackTrace;
}

/// Owns current-schema snapshots and cross-Provider thread catalog data.
final class ProjectSessionRepository {
  /// Creates a Repository over persistence and available thread ports.
  ProjectSessionRepository({
    required ProjectSessionStore store,
    required Map<String, AgentThreadCatalogPort> threadCatalogs,
  }) : _store = store,
       _threadCatalogs = Map<String, AgentThreadCatalogPort>.unmodifiable(
         threadCatalogs,
       ) {
    if (_threadCatalogs.keys.any((providerId) => providerId.trim().isEmpty)) {
      throw ArgumentError.value(threadCatalogs, 'threadCatalogs');
    }
  }

  final ProjectSessionStore _store;
  final Map<String, AgentThreadCatalogPort> _threadCatalogs;
  final StreamController<ProjectSessionSnapshot?> _snapshotChanges =
      StreamController<ProjectSessionSnapshot?>.broadcast(sync: true);
  Future<void> _writeQueue = Future<void>.value();
  Future<void>? _closeFuture;
  ProjectSessionSnapshot? _snapshot;
  bool _restored = false;
  bool _closed = false;

  /// Last restored or successfully saved snapshot.
  ProjectSessionSnapshot? get snapshot => _snapshot;

  /// Whether [restore] has completed successfully, including a missing file.
  bool get isRestored => _restored;

  /// Successful external snapshot changes, including a restored missing file.
  Stream<ProjectSessionSnapshot?> get snapshotChanges =>
      _snapshotChanges.stream;

  /// Canonical Provider ids with an available thread-catalog port.
  List<String> threadCatalog() => List<String>.unmodifiable(
    _threadCatalogs.keys.toList(growable: false)..sort(),
  );

  /// Restores the current-schema persisted snapshot.
  Future<ProjectSessionSnapshot?> restore() async {
    _ensureOpen(ProjectSessionRepositoryOperation.restore);
    try {
      final response = await _store.load();
      final next = response == null ? null : _snapshotFromResponse(response);
      _snapshot = next;
      _restored = true;
      if (!_closed) {
        _snapshotChanges.add(next);
      }
      return next;
    } on ProjectSessionDecodeException catch (error, stackTrace) {
      throw _decodeException(error, stackTrace);
    } on ProjectSessionClosedException catch (error, stackTrace) {
      _fail(
        operation: ProjectSessionRepositoryOperation.restore,
        code: ProjectSessionRepositoryFailureCode.closed,
        diagnosticCode: 'project_session_store_closed',
        cause: error,
        stackTrace: stackTrace,
      );
    } on Object catch (error, stackTrace) {
      _fail(
        operation: ProjectSessionRepositoryOperation.restore,
        code: ProjectSessionRepositoryFailureCode.externalFailure,
        diagnosticCode: 'project_session_restore_failed',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Persists [snapshot] before publishing it as external current data.
  Future<void> save(ProjectSessionSnapshot snapshot) {
    _ensureOpen(ProjectSessionRepositoryOperation.save);
    return _enqueueWrite(() async {
      try {
        await _store.save(_responseFromSnapshot(snapshot));
        _snapshot = snapshot;
        _restored = true;
        if (!_closed) {
          _snapshotChanges.add(snapshot);
        }
      } on ProjectSessionClosedException catch (error, stackTrace) {
        _fail(
          operation: ProjectSessionRepositoryOperation.save,
          code: ProjectSessionRepositoryFailureCode.closed,
          diagnosticCode: 'project_session_store_closed',
          cause: error,
          stackTrace: stackTrace,
        );
      } on Object catch (error, stackTrace) {
        _fail(
          operation: ProjectSessionRepositoryOperation.save,
          code: ProjectSessionRepositoryFailureCode.externalFailure,
          diagnosticCode: 'project_session_save_failed',
          cause: error,
          stackTrace: stackTrace,
        );
      }
    });
  }

  /// Aggregates all available Provider catalogs into one stable global page.
  Future<ProjectThreadPage> threadPage(ProjectThreadQuery query) async {
    _ensureOpen(ProjectSessionRepositoryOperation.threadPage);
    final projectPath = query.projectPath.trim();
    if (projectPath.isEmpty || query.limit <= 0) {
      _invalidThreadQuery('project_thread_query_invalid');
    }
    final offset = _aggregateOffset(query.cursor);
    final groups = <String, List<AgentThreadSummary>>{};
    final failures = <ProjectThreadProviderFailure>[];
    final providerIds = threadCatalog();
    await Future.wait<void>(
      providerIds.map((providerId) async {
        try {
          groups[providerId] = await _collectProviderThreads(
            providerId: providerId,
            port: _threadCatalogs[providerId]!,
            query: query,
            projectPath: projectPath,
          );
        } on _InvalidThreadDataException {
          failures.add(
            ProjectThreadProviderFailure(
              providerId: providerId,
              code: ProjectThreadProviderFailureCode.invalidData,
            ),
          );
        } on Object {
          failures.add(
            ProjectThreadProviderFailure(
              providerId: providerId,
              code: ProjectThreadProviderFailureCode.externalFailure,
            ),
          );
        }
      }),
    );
    failures.sort(
      (first, second) => first.providerId.compareTo(second.providerId),
    );
    final merged = <AgentThreadSummary>[
      for (final providerId in providerIds) ...?groups[providerId],
    ]..sort(_compareThreadRecency);
    final threads = merged
        .skip(offset)
        .take(query.limit)
        .toList(growable: false);
    final nextOffset = offset + threads.length;
    return ProjectThreadPage(
      threads: threads,
      nextCursor: nextOffset < merged.length
          ? '$_aggregateCursorPrefix$nextOffset'
          : null,
      failures: failures,
    );
  }

  Future<List<AgentThreadSummary>> _collectProviderThreads({
    required String providerId,
    required AgentThreadCatalogPort port,
    required ProjectThreadQuery query,
    required String projectPath,
  }) async {
    final collected = <AgentThreadSummary>[];
    final seenIds = <String>{};
    final seenCursors = <String>{};
    String? cursor;
    while (collected.length < _perProviderFetchCap) {
      final remaining = _perProviderFetchCap - collected.length;
      final page = await port.listThreads(
        query: AgentThreadListQuery(
          projectPath: projectPath,
          limit: remaining < _providerPageLimit
              ? remaining
              : _providerPageLimit,
          cursor: cursor,
          archived: query.archived,
          searchTerm: query.searchTerm,
          sourceKinds: query.sourceKinds,
        ),
      );
      for (final thread in page.threads) {
        if (thread.id.trim().isEmpty ||
            thread.providerId != providerId ||
            thread.projectPath != projectPath) {
          throw const _InvalidThreadDataException();
        }
        if (seenIds.add(thread.id)) {
          collected.add(thread);
        }
        if (collected.length >= _perProviderFetchCap) {
          break;
        }
      }
      final nextCursor = page.nextCursor?.trim();
      if (nextCursor == null || nextCursor.isEmpty || page.threads.isEmpty) {
        break;
      }
      if (!seenCursors.add(nextCursor)) {
        throw const _InvalidThreadDataException();
      }
      cursor = nextCursor;
    }
    return List<AgentThreadSummary>.unmodifiable(collected);
  }

  /// Flushes persistence and closes the external snapshot stream. Idempotent.
  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    _closed = true;
    await _writeQueue;
    try {
      await _store.close();
    } on Object catch (error, stackTrace) {
      await _snapshotChanges.close();
      throw _exception(
        operation: ProjectSessionRepositoryOperation.close,
        code: ProjectSessionRepositoryFailureCode.externalFailure,
        diagnosticCode: 'project_session_close_failed',
        cause: error,
        stackTrace: stackTrace,
      );
    }
    await _snapshotChanges.close();
  }

  Future<T> _enqueueWrite<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _writeQueue = _writeQueue.then((_) async {
      try {
        completer.complete(await action());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  void _ensureOpen(ProjectSessionRepositoryOperation operation) {
    if (_closed) {
      _fail(
        operation: operation,
        code: ProjectSessionRepositoryFailureCode.closed,
        diagnosticCode: 'project_session_repository_closed',
        cause: StateError('ProjectSessionRepository is closed'),
        stackTrace: StackTrace.current,
      );
    }
  }
}

ProjectSessionSnapshot _snapshotFromResponse(SessionSnapshotResponse response) {
  return ProjectSessionSnapshot(
    projectPaths: response.projectPaths,
    activeProjectPath: response.activeProjectPath,
    currentFilePath: response.currentFilePath,
    expandedDirectoryPaths: response.expandedDirectoryPaths,
    selectedTreeKey: response.selectedTreeKey,
    activeAgentProviderId: response.activeAgentProviderId,
    agentThreadIdsByProject: response.agentThreadIdsByProject,
    projectThreadExpansionByProject: response.projectThreadExpansionByProject,
    cachedThreadsByProject: response.cachedThreadsByProject.map(
      (projectPath, threads) => MapEntry(
        projectPath,
        threads.map(_threadFromResponse).toList(growable: false),
      ),
    ),
    selectedThreadIdsByProject: response.selectedThreadIdsByProject,
    projectLastOpenedAtByPath: response.projectLastOpenedAtByPath,
    projectHomeActive: response.projectHomeActive,
    workbench: ProjectWorkbenchSnapshot(
      leftSidebarVisible: response.workbench.leftSidebarVisible,
      agentUsageExpanded: response.workbench.agentUsageExpanded,
      leftSidebarWidth: response.workbench.leftSidebarWidth,
      agentUsageHeightFraction: response.workbench.agentUsageHeightFraction,
      selectedAgentUsageProviderId:
          response.workbench.selectedAgentUsageProviderId,
    ),
  );
}

AgentThreadSummary _threadFromResponse(SessionThreadSummaryResponse response) {
  return AgentThreadSummary(
    id: response.id,
    providerId: response.providerId,
    projectPath: response.projectPath,
    title: response.title,
    sessionPath: response.sessionPath,
    preview: response.preview,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      response.createdAtMilliseconds,
    ),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      response.updatedAtMilliseconds,
    ),
    recencyAt: response.recencyAtMilliseconds == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(response.recencyAtMilliseconds!),
    status: _statusFromName(response.status),
    waitingOnApproval: response.waitingOnApproval,
    waitingOnUserInput: response.waitingOnUserInput,
    raw: response.raw,
  );
}

SessionSnapshotResponse _responseFromSnapshot(ProjectSessionSnapshot snapshot) {
  return SessionSnapshotResponse(
    projectPaths: snapshot.projectPaths,
    activeProjectPath: snapshot.activeProjectPath,
    currentFilePath: snapshot.currentFilePath,
    expandedDirectoryPaths: snapshot.expandedDirectoryPaths,
    selectedTreeKey: snapshot.selectedTreeKey,
    activeAgentProviderId: snapshot.activeAgentProviderId,
    agentThreadIdsByProject: snapshot.agentThreadIdsByProject,
    projectThreadExpansionByProject: snapshot.projectThreadExpansionByProject,
    cachedThreadsByProject: snapshot.cachedThreadsByProject.map(
      (projectPath, threads) => MapEntry(
        projectPath,
        threads.map(_threadToResponse).toList(growable: false),
      ),
    ),
    selectedThreadIdsByProject: snapshot.selectedThreadIdsByProject,
    projectLastOpenedAtByPath: snapshot.projectLastOpenedAtByPath,
    projectHomeActive: snapshot.projectHomeActive,
    workbench: SessionWorkbenchResponse(
      leftSidebarVisible: snapshot.workbench.leftSidebarVisible,
      agentUsageExpanded: snapshot.workbench.agentUsageExpanded,
      leftSidebarWidth: snapshot.workbench.leftSidebarWidth,
      agentUsageHeightFraction: snapshot.workbench.agentUsageHeightFraction,
      selectedAgentUsageProviderId:
          snapshot.workbench.selectedAgentUsageProviderId,
    ),
  );
}

SessionThreadSummaryResponse _threadToResponse(AgentThreadSummary thread) {
  return SessionThreadSummaryResponse(
    id: thread.id,
    providerId: thread.providerId,
    projectPath: thread.projectPath,
    title: thread.title,
    sessionPath: thread.sessionPath,
    preview: thread.preview,
    createdAtMilliseconds: thread.createdAt.millisecondsSinceEpoch,
    updatedAtMilliseconds: thread.updatedAt.millisecondsSinceEpoch,
    recencyAtMilliseconds: thread.recencyAt?.millisecondsSinceEpoch,
    status: thread.status.name,
    waitingOnApproval: thread.waitingOnApproval,
    waitingOnUserInput: thread.waitingOnUserInput,
    raw: thread.raw,
  );
}

AgentThreadRuntimeStatus _statusFromName(String name) {
  for (final status in AgentThreadRuntimeStatus.values) {
    if (status.name == name) {
      return status;
    }
  }
  return AgentThreadRuntimeStatus.unknown;
}

int _aggregateOffset(String? cursor) {
  if (cursor == null || cursor.isEmpty) {
    return 0;
  }
  if (!cursor.startsWith(_aggregateCursorPrefix)) {
    _invalidThreadQuery('project_thread_cursor_invalid');
  }
  final offset = int.tryParse(cursor.substring(_aggregateCursorPrefix.length));
  if (offset == null || offset < 0) {
    _invalidThreadQuery('project_thread_cursor_invalid');
  }
  return offset;
}

int _compareThreadRecency(AgentThreadSummary first, AgentThreadSummary second) {
  final firstTime = first.recencyAt ?? first.updatedAt;
  final secondTime = second.recencyAt ?? second.updatedAt;
  final byTime = secondTime.compareTo(firstTime);
  if (byTime != 0) {
    return byTime;
  }
  final byProvider = first.providerId.compareTo(second.providerId);
  return byProvider != 0 ? byProvider : first.id.compareTo(second.id);
}

Never _invalidThreadQuery(String diagnosticCode) {
  _fail(
    operation: ProjectSessionRepositoryOperation.threadPage,
    code: ProjectSessionRepositoryFailureCode.invalidInput,
    diagnosticCode: diagnosticCode,
    cause: const FormatException('Invalid project thread query'),
    stackTrace: StackTrace.current,
  );
}

ProjectSessionRepositoryException _decodeException(
  ProjectSessionDecodeException error,
  StackTrace stackTrace,
) {
  final code = switch (error.code) {
    ProjectSessionDecodeFailureCode.malformedJson =>
      ProjectSessionRepositoryFailureCode.malformedJson,
    ProjectSessionDecodeFailureCode.invalidRoot =>
      ProjectSessionRepositoryFailureCode.invalidRoot,
    ProjectSessionDecodeFailureCode.unsupportedVersion =>
      ProjectSessionRepositoryFailureCode.unsupportedVersion,
    ProjectSessionDecodeFailureCode.invalidField =>
      ProjectSessionRepositoryFailureCode.invalidField,
  };
  return _exception(
    operation: ProjectSessionRepositoryOperation.restore,
    code: code,
    diagnosticCode: 'project_session_decode_${code.name}',
    cause: error,
    stackTrace: stackTrace,
  );
}

Never _fail({
  required ProjectSessionRepositoryOperation operation,
  required ProjectSessionRepositoryFailureCode code,
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

ProjectSessionRepositoryException _exception({
  required ProjectSessionRepositoryOperation operation,
  required ProjectSessionRepositoryFailureCode code,
  required String diagnosticCode,
  required Object cause,
  required StackTrace stackTrace,
}) {
  return ProjectSessionRepositoryException(
    failure: ProjectSessionRepositoryFailure(
      operation: operation,
      code: code,
      diagnosticCode: diagnosticCode,
    ),
    cause: cause,
    stackTrace: stackTrace,
  );
}

final class _InvalidThreadDataException implements Exception {
  const _InvalidThreadDataException();
}

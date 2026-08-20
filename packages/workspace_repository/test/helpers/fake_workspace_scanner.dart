import 'dart:async';

import 'package:workspace_client/workspace_client.dart';

final class FakeWorkspaceScanner implements WorkspaceScanner {
  WorkspaceScanResponse scanResponse = WorkspaceScanResponse(
    files: const <WorkspaceNodeResponse>[],
    visitedDirectories: 1,
    truncated: false,
  );
  Object? scanError;
  Object? readError;
  Object? watchThrow;
  Object? watchCancelError;
  List<WorkspaceNodeResponse> directoryResponse = <WorkspaceNodeResponse>[];
  List<GitignoreDocumentResponse> documents = <GitignoreDocumentResponse>[];
  final List<Completer<void>> scanGates = <Completer<void>>[];
  final List<String> scanCalls = <String>[];
  final List<String> watchCalls = <String>[];
  final Map<String, StreamController<WorkspaceFileChangeResponse>> watches =
      <String, StreamController<WorkspaceFileChangeResponse>>{};
  WorkspaceEntryFilter? lastScanFilter;
  WorkspaceEntryFilter? lastDirectoryFilter;
  int readCount = 0;
  int scanCount = 0;

  @override
  Future<WorkspaceScanResponse> scanFiles(
    String rootPath, {
    int maxFiles = 50000,
    WorkspaceScanCancellationToken? cancellationToken,
    WorkspaceEntryFilter? filter,
  }) async {
    scanCalls.add(rootPath);
    lastScanFilter = filter;
    final invocation = scanCount++;
    if (invocation < scanGates.length) {
      await scanGates[invocation].future;
    }
    final error = scanError;
    if (error != null) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    return scanResponse;
  }

  @override
  Future<List<WorkspaceNodeResponse>> readDirectory({
    required String rootPath,
    required String directoryPath,
    WorkspaceScanCancellationToken? cancellationToken,
    WorkspaceEntryFilter? filter,
  }) async {
    readCount += 1;
    lastDirectoryFilter = filter;
    final error = readError;
    if (error != null) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    return directoryResponse
        .where(
          (node) =>
              filter?.call(node, documents) ==
                  WorkspaceEntryDisposition.include ||
              filter == null,
        )
        .toList(growable: false);
  }

  @override
  Stream<WorkspaceFileChangeResponse> watch(String rootPath) {
    watchCalls.add(rootPath);
    final error = watchThrow;
    if (error != null) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    return watches
        .putIfAbsent(
          rootPath,
          () => StreamController<WorkspaceFileChangeResponse>(
            onCancel: () async {
              final cancelError = watchCancelError;
              if (cancelError != null) {
                await Future<void>.error(cancelError, StackTrace.current);
              }
            },
          ),
        )
        .stream;
  }

  Future<void> dispose() async {
    for (final controller in watches.values) {
      await controller.close();
    }
  }
}

import 'dart:async';

import 'package:workspace_client/workspace_client.dart';

final class FakeWorkspaceFileSystem implements WorkspaceFileSystem {
  final Map<String, WorkspaceFileSystemEntityType> types =
      <String, WorkspaceFileSystemEntityType>{};
  final Map<String, String> resolvedPaths = <String, String>{};
  final Map<String, List<WorkspaceFileSystemEntry>> listings =
      <String, List<WorkspaceFileSystemEntry>>{};
  final Map<String, String> texts = <String, String>{};
  final Map<String, Exception> typeErrors = <String, Exception>{};
  final Map<String, Exception> resolveErrors = <String, Exception>{};
  final Map<String, Exception> listErrors = <String, Exception>{};
  final Map<String, Exception> readErrors = <String, Exception>{};
  final Map<String, StreamController<WorkspaceFileChangeResponse>> watches =
      <String, StreamController<WorkspaceFileChangeResponse>>{};
  final List<String> typeCalls = <String>[];
  final List<String> resolveCalls = <String>[];
  final List<String> listCalls = <String>[];
  final List<String> readCalls = <String>[];

  @override
  Future<WorkspaceFileSystemEntityType> type(String path) async {
    typeCalls.add(path);
    final error = typeErrors[path];
    if (error != null) {
      throw error;
    }
    return types[path] ?? WorkspaceFileSystemEntityType.notFound;
  }

  @override
  Future<String> resolvePath(String path) async {
    resolveCalls.add(path);
    final error = resolveErrors[path];
    if (error != null) {
      throw error;
    }
    return resolvedPaths[path] ?? path;
  }

  @override
  Stream<WorkspaceFileSystemEntry> list(String path) async* {
    listCalls.add(path);
    final error = listErrors[path];
    if (error != null) {
      throw error;
    }
    yield* Stream<WorkspaceFileSystemEntry>.fromIterable(
      listings[path] ?? const <WorkspaceFileSystemEntry>[],
    );
  }

  @override
  Future<String> readText(String path) async {
    readCalls.add(path);
    final error = readErrors[path];
    if (error != null) {
      throw error;
    }
    return texts[path] ?? '';
  }

  @override
  Stream<WorkspaceFileChangeResponse> watch(String path) {
    return watches
        .putIfAbsent(
          path,
          StreamController<WorkspaceFileChangeResponse>.broadcast,
        )
        .stream;
  }

  Future<void> close() async {
    for (final controller in watches.values) {
      await controller.close();
    }
  }
}

final class FakeGitignoreReader implements GitignoreReader {
  final Map<String, GitignoreDocumentResponse> excludes =
      <String, GitignoreDocumentResponse>{};
  final Map<String, GitignoreDocumentResponse> gitignores =
      <String, GitignoreDocumentResponse>{};

  @override
  Future<GitignoreDocumentResponse?> readRepositoryExclude(
    String rootPath,
  ) async {
    return excludes[rootPath];
  }

  @override
  Future<GitignoreDocumentResponse?> readDirectoryGitignore({
    required String rootPath,
    required String directoryPath,
  }) async {
    return gitignores[directoryPath];
  }
}

WorkspaceFileSystemEntry entry(
  String path,
  WorkspaceFileSystemEntityType type,
) {
  return WorkspaceFileSystemEntry(path: path, type: type);
}

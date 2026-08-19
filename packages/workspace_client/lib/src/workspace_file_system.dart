import 'dart:io';

import 'package:workspace_client/src/workspace_exceptions.dart';
import 'package:workspace_client/src/workspace_responses.dart';

/// Injectable no-follow `dart:io` entity-type reader.
typedef IoWorkspaceEntityTypeReader = Future<FileSystemEntityType> Function(
  String path,
);

/// Injectable `dart:io` canonical path resolver.
typedef IoWorkspacePathResolver = Future<String> Function(String path);

/// Injectable `dart:io` one-directory listing factory.
typedef IoWorkspaceDirectoryLister = Stream<FileSystemEntity> Function(
  String path,
);

/// Injectable `dart:io` text reader.
typedef IoWorkspaceTextReader = Future<String> Function(String path);

/// Injectable `dart:io` recursive watch factory.
typedef IoWorkspaceDirectoryWatcher = Stream<FileSystemEvent> Function(
  String path,
);

/// Entity kinds required by workspace scanning.
enum WorkspaceFileSystemEntityType {
  /// A regular file.
  file,

  /// A regular directory.
  directory,

  /// A symbolic link.
  symbolicLink,

  /// The entity disappeared or does not exist.
  notFound,

  /// A socket, pipe, or other unsupported entity.
  other,
}

/// Metadata returned while enumerating a directory.
final class WorkspaceFileSystemEntry {
  /// Creates filesystem entry metadata.
  const WorkspaceFileSystemEntry({required this.path, required this.type});

  /// Entry path.
  final String path;

  /// Entry kind without following links.
  final WorkspaceFileSystemEntityType type;
}

/// Injectable filesystem seam for workspace Data tests.
abstract interface class WorkspaceFileSystem {
  /// Reads entity type without following symbolic links.
  Future<WorkspaceFileSystemEntityType> type(String path);

  /// Resolves [path] through the operating system.
  Future<String> resolvePath(String path);

  /// Lists one directory without following symbolic links.
  Stream<WorkspaceFileSystemEntry> list(String path);

  /// Reads one UTF-8 text file.
  Future<String> readText(String path);

  /// Watches [path] recursively.
  Stream<WorkspaceFileChangeResponse> watch(String path);
}

/// `dart:io` implementation of [WorkspaceFileSystem].
final class IoWorkspaceFileSystem implements WorkspaceFileSystem {
  /// Creates a production filesystem adapter.
  const IoWorkspaceFileSystem({
    this.entityTypeReader = _defaultEntityTypeReader,
    this.pathResolver = _defaultPathResolver,
    this.directoryLister = _defaultDirectoryLister,
    this.textReader = _defaultTextReader,
    this.directoryWatcher = _defaultDirectoryWatcher,
  });

  /// No-follow entity-type primitive.
  final IoWorkspaceEntityTypeReader entityTypeReader;

  /// Canonical path primitive.
  final IoWorkspacePathResolver pathResolver;

  /// Directory listing primitive.
  final IoWorkspaceDirectoryLister directoryLister;

  /// Text-read primitive.
  final IoWorkspaceTextReader textReader;

  /// Directory-watch primitive.
  final IoWorkspaceDirectoryWatcher directoryWatcher;

  @override
  Future<WorkspaceFileSystemEntityType> type(String path) async {
    try {
      final type = await entityTypeReader(path);
      return _mapEntityType(type);
    } on FileSystemException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        _mapFileSystemException(error, WorkspaceFileSystemOperation.metadata),
        stackTrace,
      );
    }
  }

  @override
  Future<String> resolvePath(String path) async {
    try {
      return await pathResolver(path);
    } on FileSystemException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        _mapFileSystemException(
          error,
          WorkspaceFileSystemOperation.resolvePath,
        ),
        stackTrace,
      );
    }
  }

  @override
  Stream<WorkspaceFileSystemEntry> list(String path) async* {
    try {
      await for (final entity in directoryLister(path)) {
        final type = await entityTypeReader(entity.path);
        yield WorkspaceFileSystemEntry(
          path: entity.path,
          type: _mapEntityType(type),
        );
      }
    } on FileSystemException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        _mapFileSystemException(
          error,
          WorkspaceFileSystemOperation.listDirectory,
        ),
        stackTrace,
      );
    }
  }

  @override
  Future<String> readText(String path) async {
    try {
      return await textReader(path);
    } on FileSystemException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        _mapFileSystemException(
          error,
          WorkspaceFileSystemOperation.readGitignore,
        ),
        stackTrace,
      );
    }
  }

  @override
  Stream<WorkspaceFileChangeResponse> watch(String path) async* {
    try {
      await for (final event in directoryWatcher(path)) {
        yield WorkspaceFileChangeResponse(
          kind: switch (event) {
            FileSystemMoveEvent() => WorkspaceFileChangeKindResponse.move,
            FileSystemCreateEvent() => WorkspaceFileChangeKindResponse.create,
            FileSystemModifyEvent() => WorkspaceFileChangeKindResponse.modify,
            FileSystemDeleteEvent() => WorkspaceFileChangeKindResponse.delete,
          },
          path: event.path,
          isDirectory: event.isDirectory,
          destinationPath: event is FileSystemMoveEvent
              ? event.destination
              : null,
        );
      }
    } on FileSystemException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        _mapFileSystemException(
          error,
          WorkspaceFileSystemOperation.watchDirectory,
        ),
        stackTrace,
      );
    }
  }
}

Future<FileSystemEntityType> _defaultEntityTypeReader(String path) {
  return FileSystemEntity.type(path, followLinks: false);
}

Future<String> _defaultPathResolver(String path) {
  return Directory(path).resolveSymbolicLinks();
}

Stream<FileSystemEntity> _defaultDirectoryLister(String path) {
  return Directory(path).list(followLinks: false);
}

Future<String> _defaultTextReader(String path) => File(path).readAsString();

Stream<FileSystemEvent> _defaultDirectoryWatcher(String path) {
  return Directory(path).watch(recursive: true);
}

WorkspaceFileSystemEntityType _mapEntityType(FileSystemEntityType type) {
  if (type == FileSystemEntityType.file) {
    return WorkspaceFileSystemEntityType.file;
  }
  if (type == FileSystemEntityType.directory) {
    return WorkspaceFileSystemEntityType.directory;
  }
  if (type == FileSystemEntityType.link) {
    return WorkspaceFileSystemEntityType.symbolicLink;
  }
  if (type == FileSystemEntityType.notFound) {
    return WorkspaceFileSystemEntityType.notFound;
  }
  return WorkspaceFileSystemEntityType.other;
}

WorkspaceFileSystemException _mapFileSystemException(
  FileSystemException error,
  WorkspaceFileSystemOperation operation,
) {
  final errorCode = error.osError?.errorCode;
  final code = switch (errorCode) {
    2 || 3 => WorkspaceFileSystemFailureCode.notFound,
    5 || 13 => WorkspaceFileSystemFailureCode.accessDenied,
    _ => WorkspaceFileSystemFailureCode.ioFailure,
  };
  return WorkspaceFileSystemException(operation: operation, code: code);
}

// The public injection seam intentionally has a non-private parameter name.
// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:io';

import 'package:zeta_storage/zeta_storage.dart';

/// Reads an entity type without following symbolic links.
typedef AgentManagementEntityTypeReader = Future<FileSystemEntityType> Function(
  String path,
);

/// File metadata needed by management clients.
final class AgentManagementFileMetadata {
  /// Creates file metadata.
  const AgentManagementFileMetadata({
    required this.exists,
    required this.isFile,
    required this.isLink,
    required this.size,
    this.modifiedAt,
  });

  /// Missing-path metadata.
  const AgentManagementFileMetadata.missing()
    : exists = false,
      isFile = false,
      isLink = false,
      size = 0,
      modifiedAt = null;

  /// Whether an entity exists.
  final bool exists;

  /// Whether the entity is a regular file.
  final bool isFile;

  /// Whether the path itself is a symbolic link.
  final bool isLink;

  /// File size in bytes.
  final int size;

  /// Last modification time.
  final DateTime? modifiedAt;
}

/// Bounded text tail returned by [AgentManagementFileSystem.readTextTail].
final class AgentManagementTextTail {
  /// Creates a text tail.
  const AgentManagementTextTail({
    required this.contents,
    required this.skippedPrefix,
  });

  /// Malformed-UTF-8-tolerant decoded contents.
  final String contents;

  /// Whether bytes before [contents] were omitted.
  final bool skippedPrefix;
}

/// Injectable provider configuration and log filesystem boundary.
abstract interface class AgentManagementFileSystem {
  /// Reads path metadata without following symbolic links.
  Future<AgentManagementFileMetadata> metadata(String path);

  /// Reads a complete UTF-8 text file.
  Future<String> readText(String path);

  /// Atomically writes [contents], returning a backup path when one was made.
  Future<String?> writeTextAtomically(
    String path,
    String contents, {
    required String backupSuffix,
  });

  /// Lists regular files under [directoryPath].
  Future<List<String>> listFiles(
    String directoryPath, {
    bool recursive = false,
  });

  /// Reads at most [maxBytes] from the end of [path].
  Future<AgentManagementTextTail> readTextTail(
    String path, {
    required int maxBytes,
  });
}

/// `dart:io` implementation of [AgentManagementFileSystem].
final class IoAgentManagementFileSystem implements AgentManagementFileSystem {
  /// Creates the production filesystem boundary.
  const IoAgentManagementFileSystem({
    AgentManagementEntityTypeReader entityTypeReader = _readEntityType,
  }) : _entityTypeReader = entityTypeReader;

  final AgentManagementEntityTypeReader _entityTypeReader;

  @override
  Future<AgentManagementFileMetadata> metadata(String path) async {
    final type = await _entityTypeReader(path);
    if (type == FileSystemEntityType.notFound) {
      return const AgentManagementFileMetadata.missing();
    }
    if (type == FileSystemEntityType.link) {
      return const AgentManagementFileMetadata(
        exists: true,
        isFile: false,
        isLink: true,
        size: 0,
      );
    }
    if (type != FileSystemEntityType.file) {
      return const AgentManagementFileMetadata(
        exists: true,
        isFile: false,
        isLink: false,
        size: 0,
      );
    }
    final stat = await File(path).stat();
    return AgentManagementFileMetadata(
      exists: true,
      isFile: true,
      isLink: false,
      size: stat.size,
      modifiedAt: stat.modified,
    );
  }

  @override
  Future<String> readText(String path) => File(path).readAsString();

  @override
  Future<String?> writeTextAtomically(
    String path,
    String contents, {
    required String backupSuffix,
  }) async {
    final target = File(path);
    String? backupPath;
    if (await target.exists()) {
      backupPath = '$path$backupSuffix';
      await target.copy(backupPath);
    }
    await writeAtomic(target, contents);
    return backupPath;
  }

  @override
  Future<List<String>> listFiles(
    String directoryPath, {
    bool recursive = false,
  }) async {
    final directory = Directory(directoryPath);
    if (!await directory.exists()) {
      return const <String>[];
    }
    final paths = <String>[];
    await for (final entity in directory.list(
      recursive: recursive,
      followLinks: false,
    )) {
      if (entity is File) {
        paths.add(entity.path);
      }
    }
    paths.sort();
    return List<String>.unmodifiable(paths);
  }

  @override
  Future<AgentManagementTextTail> readTextTail(
    String path, {
    required int maxBytes,
  }) async {
    if (maxBytes < 0) {
      throw ArgumentError.value(maxBytes, 'maxBytes', 'must not be negative');
    }
    final file = File(path);
    final size = await file.length();
    final start = size > maxBytes ? size - maxBytes : 0;
    final contents = await file
        .openRead(start)
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    return AgentManagementTextTail(
      contents: contents,
      skippedPrefix: start > 0,
    );
  }
}

Future<FileSystemEntityType> _readEntityType(String path) {
  return FileSystemEntity.type(path, followLinks: false);
}

import 'dart:io';

import 'package:path/path.dart' as path;

import 'package:zeta_storage/src/storage_exception.dart';

/// Returns the final component of a POSIX or Windows path.
String fileName(String value) {
  final normalized = value.replaceAll(r'\', '/');
  final parts = normalized.split('/').where((part) => part.isNotEmpty);
  return parts.isEmpty ? value : parts.last;
}

/// Lexically normalizes [value] using the requested platform path rules.
String normalizePath(String value, {bool? isWindows}) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw StoragePathException(
      path: value,
      cause: ArgumentError.value(value, 'value', 'Path must not be empty'),
    );
  }
  return _context(isWindows: isWindows).normalize(trimmed);
}

/// Resolves an existing absolute directory to its canonical physical path.
///
/// Missing directories, relative paths, and symlink-resolution failures fail
/// closed with [StoragePathException].
Future<String> canonicalDirectoryPath(String value) async {
  final normalized = normalizePath(value);
  final directory = Directory(normalized);
  try {
    if (!directory.isAbsolute || !directory.existsSync()) {
      throw FileSystemException(
        'Canonical directory must exist and be absolute',
        value,
      );
    }
    return path.normalize(await directory.resolveSymbolicLinks());
  } on StorageException {
    rethrow;
  } on Object catch (error, stackTrace) {
    Error.throwWithStackTrace(
      StoragePathException(path: value, cause: error),
      stackTrace,
    );
  }
}

/// Keeps existing directory paths in first-seen order and removes duplicates.
List<String> existingDirectoryPaths(Iterable<String> paths) {
  final existing = <String>[];
  final seen = <String>{};
  for (final candidate in paths) {
    if (candidate.isEmpty || !seen.add(candidate)) {
      continue;
    }
    if (Directory(candidate).existsSync()) {
      existing.add(candidate);
    }
  }
  return List<String>.unmodifiable(existing);
}

path.Context _context({bool? isWindows}) {
  final windows = isWindows ?? Platform.isWindows;
  return path.Context(style: windows ? path.Style.windows : path.Style.posix);
}

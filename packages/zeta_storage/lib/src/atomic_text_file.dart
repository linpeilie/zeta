import 'dart:async';
import 'dart:io';

import 'package:zeta_storage/src/storage_exception.dart';

/// Builds the same-directory temporary path used by an atomic write.
typedef AtomicTemporaryPathBuilder = String Function(File target);

/// Replaces [target] with a fully-written [temporaryFile].
typedef AtomicFileReplacer = Future<void> Function(
  File temporaryFile,
  File target,
);

/// Deletes a temporary file after an atomic write settles.
typedef AtomicTemporaryFileDeleter = Future<void> Function(File temporaryFile);

var _temporarySequence = 0;

/// Atomically replaces [target] with UTF-8 [contents].
///
/// The temporary file is written and flushed in the target directory before a
/// rename. Failures are converted to typed exceptions and never delete or
/// truncate an existing target.
Future<void> writeAtomic(
  File target,
  String contents, {
  AtomicTemporaryPathBuilder? temporaryPathBuilder,
  AtomicFileReplacer? replacer,
  AtomicTemporaryFileDeleter? temporaryFileDeleter,
}) async {
  final buildTemporaryPath =
      temporaryPathBuilder ?? _defaultTemporaryPathBuilder;
  final replace = replacer ?? _defaultReplacer;
  final deleteTemporary = temporaryFileDeleter ?? _defaultTemporaryFileDeleter;
  final temporaryFile = File(buildTemporaryPath(target));
  if (temporaryFile.absolute.path == target.absolute.path) {
    throw StoragePathException(
      path: target.path,
      cause: ArgumentError('Temporary path must differ from target path'),
    );
  }

  StorageException? failure;
  StackTrace? failureStackTrace;
  var operation = StorageOperation.createDirectory;
  try {
    await target.parent.create(recursive: true);
    operation = StorageOperation.writeTemporary;
    await temporaryFile.writeAsString(contents, flush: true);
    operation = StorageOperation.replace;
    await replace(temporaryFile, target);
  } on StorageException catch (error, stackTrace) {
    failure = error;
    failureStackTrace = stackTrace;
  } on Object catch (error, stackTrace) {
    failure = StorageWriteException(
      operation: operation,
      path: target.path,
      cause: error,
    );
    failureStackTrace = stackTrace;
  }

  try {
    if (temporaryFile.existsSync()) {
      await deleteTemporary(temporaryFile);
    }
  } on Object catch (error, stackTrace) {
    failure ??= StorageWriteException(
      operation: StorageOperation.deleteTemporary,
      path: temporaryFile.path,
      cause: error,
    );
    failureStackTrace ??= stackTrace;
  }

  if (failure case final error?) {
    Error.throwWithStackTrace(error, failureStackTrace!);
  }
}

/// A serial, closeable UTF-8 text file backed by [writeAtomic].
final class AtomicTextFile {
  /// Creates atomic storage for [file].
  AtomicTextFile(
    this.file, {
    this.temporaryPathBuilder,
    this.replacer,
    this.temporaryFileDeleter,
  });

  /// The final persisted file.
  final File file;

  /// Optional deterministic temp-path seam for storage implementations/tests.
  final AtomicTemporaryPathBuilder? temporaryPathBuilder;

  /// Optional atomic replacement seam for storage implementations/tests.
  final AtomicFileReplacer? replacer;

  /// Optional temporary cleanup seam for storage implementations/tests.
  final AtomicTemporaryFileDeleter? temporaryFileDeleter;

  Future<void> _writeTail = Future<void>.value();
  bool _isClosed = false;

  /// Whether this instance has been closed.
  bool get isClosed => _isClosed;

  /// Reads the current value, or returns `null` when it does not exist.
  Future<String?> read() async {
    _ensureOpen();
    try {
      if (!file.existsSync()) {
        return null;
      }
      return await file.readAsString();
    } on StorageException {
      rethrow;
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(
        StorageReadException(path: file.path, cause: error),
        stackTrace,
      );
    }
  }

  /// Serializes and atomically replaces the current value.
  Future<void> write(String contents) {
    _ensureOpen();
    final operation = _writeTail.then(
      (_) => writeAtomic(
        file,
        contents,
        temporaryPathBuilder: temporaryPathBuilder,
        replacer: replacer,
        temporaryFileDeleter: temporaryFileDeleter,
      ),
    );
    _writeTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  /// Rejects future operations after all queued writes have settled.
  Future<void> close() async {
    if (_isClosed) {
      return;
    }
    _isClosed = true;
    await _writeTail;
  }

  void _ensureOpen() {
    if (_isClosed) {
      throw StorageClosedException(file.path);
    }
  }
}

String _defaultTemporaryPathBuilder(File target) {
  _temporarySequence += 1;
  return '${target.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.'
      '$_temporarySequence.tmp';
}

Future<void> _defaultReplacer(File temporaryFile, File target) async {
  await temporaryFile.rename(target.path);
}

Future<void> _defaultTemporaryFileDeleter(File temporaryFile) async {
  await temporaryFile.delete();
}

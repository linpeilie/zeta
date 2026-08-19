/// The storage operation that failed.
enum StorageOperation {
  /// Reading an existing value.
  read,

  /// Creating a parent directory.
  createDirectory,

  /// Writing and flushing a temporary value.
  writeTemporary,

  /// Replacing the destination with a completed temporary value.
  replace,

  /// Removing a temporary value after an operation.
  deleteTemporary,

  /// Resolving or validating a path.
  resolvePath,

  /// Using a closed storage object.
  close,
}

/// Base class for failures raised by Zeta storage primitives.
sealed class StorageException implements Exception {
  /// Creates a typed storage failure.
  const StorageException({
    required this.operation,
    required this.path,
    required this.cause,
  });

  /// The operation that failed.
  final StorageOperation operation;

  /// The affected path.
  final String path;

  /// The original failure, retained for programmatic diagnostics.
  final Object cause;

  @override
  String toString() {
    return 'StorageException(operation: ${operation.name})';
  }
}

/// A storage read failed.
final class StorageReadException extends StorageException {
  /// Creates a read failure.
  const StorageReadException({required super.path, required super.cause})
    : super(operation: StorageOperation.read);
}

/// An atomic write step failed.
final class StorageWriteException extends StorageException {
  /// Creates a write failure for [operation].
  const StorageWriteException({
    required super.operation,
    required super.path,
    required super.cause,
  });
}

/// A path was missing, invalid, or could not be resolved safely.
final class StoragePathException extends StorageException {
  /// Creates a path failure.
  const StoragePathException({required super.path, required super.cause})
    : super(operation: StorageOperation.resolvePath);
}

/// An operation was attempted after a storage object was closed.
final class StorageClosedException extends StorageException {
  /// Creates a closed-storage failure.
  StorageClosedException(String path)
    : super(
        operation: StorageOperation.close,
        path: path,
        cause: StateError('Storage is closed'),
      );
}

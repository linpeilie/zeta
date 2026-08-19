/// Current usage-index decode failure categories.
enum UsageIndexDecodeFailureCode {
  /// The root is not a JSON object.
  invalidRoot,

  /// The root is not the current schema version.
  unsupportedVersion,

  /// A current-schema field is invalid.
  invalidField,
}

/// Content-free failure for a corrupt rebuildable index.
final class UsageIndexDecodeException implements FormatException {
  /// Creates a typed index failure.
  const UsageIndexDecodeException({required this.code, this.field});

  /// Stable failure category.
  final UsageIndexDecodeFailureCode code;

  /// Invalid top-level field, when known.
  final String? field;

  @override
  String get message => 'Usage index could not be decoded';

  @override
  int? get offset => null;

  @override
  Object? get source => null;

  @override
  String toString() => 'UsageIndexDecodeException(code: ${code.name})';
}

/// An operation was attempted after the store was closed.
final class UsageStorageClosedException implements Exception {
  /// Creates a closed-store failure.
  const UsageStorageClosedException();

  @override
  String toString() => 'UsageStorageClosedException()';
}

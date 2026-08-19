/// Current project-session decode failure categories.
enum ProjectSessionDecodeFailureCode {
  /// The document is not valid JSON.
  malformedJson,

  /// The JSON root is not an object.
  invalidRoot,

  /// The document does not use the current schema version.
  unsupportedVersion,

  /// A current-schema field has an invalid or missing value.
  invalidField,
}

/// Content-free failure raised for an invalid current session document.
final class ProjectSessionDecodeException implements FormatException {
  /// Creates a typed decode failure.
  const ProjectSessionDecodeException({required this.code, this.field});

  /// Stable failure category.
  final ProjectSessionDecodeFailureCode code;

  /// Top-level field whose shape was invalid, when known.
  final String? field;

  @override
  String get message => 'Project session document could not be decoded';

  @override
  int? get offset => null;

  @override
  Object? get source => null;

  @override
  String toString() => 'ProjectSessionDecodeException(code: ${code.name})';
}

/// An operation was attempted after the project session store was closed.
final class ProjectSessionClosedException implements Exception {
  /// Creates a closed-store failure.
  const ProjectSessionClosedException();

  @override
  String toString() => 'ProjectSessionClosedException()';
}

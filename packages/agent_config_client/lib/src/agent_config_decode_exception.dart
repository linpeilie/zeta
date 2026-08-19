/// Persisted document kinds owned by `agent_config_client`.
enum AgentConfigDocumentKind {
  /// Provider definitions.
  providerConfig,

  /// Provider model catalog snapshots.
  modelCatalogCache,

  /// Per-thread turn metadata.
  turnContext,
}

/// Stable categories for current-schema decode failures.
enum AgentConfigDecodeReason {
  /// The document is not valid JSON.
  invalidJson,

  /// The root or a nested value has an invalid shape.
  invalidShape,

  /// The document version is not the current version.
  unsupportedVersion,

  /// A stable identifier occurs more than once.
  duplicateIdentifier,

  /// A turn-context document belongs to another requested thread.
  identityMismatch,
}

/// A safe, typed failure raised when persisted Agent data cannot be decoded.
///
/// Raw file contents and paths are deliberately excluded from the exception.
final class AgentConfigDecodeException implements FormatException {
  /// Creates a typed decode failure.
  const AgentConfigDecodeException({
    required this.document,
    required this.reason,
  });

  /// The document being decoded.
  final AgentConfigDocumentKind document;

  /// The stable failure category.
  final AgentConfigDecodeReason reason;

  @override
  String get message =>
      'Agent config decode failed (${document.name}/${reason.name})';

  @override
  int? get offset => null;

  @override
  Object? get source => null;

  @override
  String toString() => message;
}

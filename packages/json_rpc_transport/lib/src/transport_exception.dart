/// Typed failures raised by the JSON-RPC transport boundary.
sealed class TransportException implements Exception {
  const TransportException(this.message);

  /// A payload-free diagnostic message safe to expose to callers.
  final String message;

  @override
  String toString() => message;
}

/// A frame could not be decoded as a supported JSON-RPC message.
final class TransportMalformedFrame extends TransportException {
  /// Creates a malformed-frame diagnostic without retaining its payload.
  const TransportMalformedFrame({
    required String message,
    required this.payloadLength,
    this.causeType,
  }) : super(message);

  /// Number of characters in the rejected frame.
  final int payloadLength;

  /// Runtime type of the decoding failure, without its potentially sensitive
  /// message.
  final String? causeType;
}

/// An input line exceeded the configured transport limit.
final class TransportLineTooLong extends TransportException {
  /// Creates a line-limit diagnostic.
  const TransportLineTooLong({
    required this.maximumLength,
    required this.observedLength,
  }) : super('JSON-RPC frame exceeded the configured line limit');

  /// Maximum accepted number of characters.
  final int maximumLength;

  /// Number of characters observed before the frame was discarded.
  final int observedLength;
}

/// A request did not receive a response before its deadline.
final class TransportTimeout extends TransportException {
  /// Creates a request timeout.
  const TransportTimeout({
    required this.method,
    required this.timeout,
    required this.startedAt,
  }) : super('JSON-RPC request timed out');

  /// Request method. It contains no params or payload.
  final String method;

  /// Configured request timeout.
  final Duration timeout;

  /// Timestamp supplied by the injected clock.
  final DateTime startedAt;
}

/// The child process exited or could not be started.
final class TransportProcessExited extends TransportException {
  /// Creates a process termination failure.
  const TransportProcessExited({
    required String message,
    this.exitCode,
    this.causeType,
  }) : super(message);

  /// Exit code, or null when the process could not be started.
  final int? exitCode;

  /// Runtime type of the start failure, without its potentially sensitive
  /// message.
  final String? causeType;
}

/// The transport no longer accepts work.
final class TransportClosed extends TransportException {
  /// Creates a closed-transport failure.
  const TransportClosed([super.message = 'JSON-RPC transport is closed']);
}

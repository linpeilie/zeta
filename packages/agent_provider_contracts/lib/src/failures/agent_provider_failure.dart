import 'package:equatable/equatable.dart';

/// Stable status values mapped to localized copy by Presentation.
enum AgentProviderStatusCode {
  idle,
  connecting,
  ready,
  running,
  unavailable,
  failure,
}

/// Stable provider failure categories.
enum AgentProviderFailureCode {
  unavailable,
  invalidConfiguration,
  authenticationRequired,
  permissionDenied,
  rateLimited,
  timeout,
  protocol,
  processExited,
  cancelled,
  unknown,
}

/// Vendor-neutral provider failure without renderable copy.
final class AgentProviderFailure extends Equatable {
  const AgentProviderFailure({
    required this.code,
    this.diagnosticCode,
    this.diagnosticDetails,
  });

  final AgentProviderFailureCode code;
  final String? diagnosticCode;

  /// Raw diagnostic context for logs; Presentation must not render it directly.
  final String? diagnosticDetails;

  @override
  List<Object?> get props => [code, diagnosticCode, diagnosticDetails];
}

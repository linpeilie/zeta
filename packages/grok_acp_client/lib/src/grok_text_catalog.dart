import 'package:agent_provider_contracts/agent_provider_contracts.dart';

/// Stable provider-local English labels used before Presentation localization.
///
/// This catalog remains internal so the Grok Data package does not depend on
/// Flutter localization or application-level text services.
final class GrokTextCatalog {
  /// Creates the provider-local catalog.
  const GrokTextCatalog();

  /// Human-readable tool kind.
  String toolKindLabel(AgentToolKind kind) => switch (kind) {
    AgentToolKind.read => 'Read',
    AgentToolKind.edit => 'Edit',
    AgentToolKind.delete => 'Delete',
    AgentToolKind.move => 'Move',
    AgentToolKind.search => 'Search',
    AgentToolKind.execute => 'Execute',
    AgentToolKind.think => 'Think',
    AgentToolKind.fetch => 'Fetch',
    AgentToolKind.other => 'Tool call',
  };

  /// Provider-ready status.
  String providerReady(String name) => '$name ready';

  /// Active-turn status.
  String get agentIsWorking => 'Agent is working';

  /// Provider-starting status.
  String startingProvider(String name) => 'Starting $name';

  /// Startup failure.
  String couldNotStart(String name) => 'Could not start $name';

  /// Protocol warning.
  String protocolWarning(String name) => '$name protocol warning';

  /// Request timeout.
  String requestTimedOut(String name) =>
      '$name request timed out. Please try again.';

  /// Closed-connection recovery hint.
  String connectionClosedRetry(String name) =>
      '$name connection closed. Reconnect and try again.';

  /// Permission-wait status.
  String waitingApprovalFor(String title) => 'Waiting for approval: $title';

  /// Question-wait status.
  String waitingAnswersFor(String title) => 'Waiting for answers: $title';

  /// Plan-wait status.
  String get waitingPlanApproval => 'Waiting for plan approval';

  /// Plan approval title.
  String get planApprovalTitle => 'Plan approval';

  /// Subscription quota label.
  String get planQuotaLabel => 'Plan quota';

  /// On-demand quota label.
  String get onDemandQuotaLabel => 'On-demand quota';
}

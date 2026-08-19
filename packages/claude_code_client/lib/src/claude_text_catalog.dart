/// Stable provider-local English labels used before Presentation localization.
///
/// This catalog is deliberately internal. Protocol and Data code must not
/// depend on Flutter localization or an application-level text service.
final class ClaudeCodeTextCatalog {
  /// Creates the provider-local catalog.
  const ClaudeCodeTextCatalog();

  /// Description for the safe default permission mode.
  String get permissionAskDescription => 'Ask before high-risk tools';

  /// Description for automatic edit approval.
  String get permissionAcceptEditsDescription =>
      'Automatically allow edits; ask for other tools';

  /// Description for read-only planning.
  String get permissionPlanDescription =>
      'Read and produce a plan without side effects';

  /// Description for bypass mode.
  String get permissionBypassDescription =>
      'Skip permission checks (high risk)';

  /// Provider-ready status.
  String providerReady(String name) => '$name ready';

  /// Provider-starting status.
  String startingProvider(String name) => 'Starting $name';

  /// Provider-preparing status.
  String preparingProvider(String name) => 'Preparing $name';

  /// Process-exited status.
  String processExited(String name) => '$name process exited';

  /// Active-turn status.
  String get agentIsWorking => 'Agent is working';

  /// Prompt-write failure.
  String get failedToSendPrompt => 'Failed to send prompt';

  /// Plan approval title.
  String get planApprovalTitle => 'Plan approval';

  /// Session identity mismatch.
  String sessionIdentityChanged(String name) =>
      '$name changed session identity unexpectedly';

  /// Session restore failure.
  String couldNotRestoreSession(String name) =>
      '$name could not restore the requested session';

  /// Permission request description.
  String permissionRequestDescription(String name, String tool) =>
      '$name requests permission to use $tool';

  /// Five-hour quota label.
  String get quotaFiveHours => '5 hours';

  /// Weekly quota label.
  String get quotaOneWeek => '1 week';

  /// Sonnet weekly quota label.
  String get quotaSonnetOneWeek => 'Sonnet · 1 week';

  /// Opus weekly quota label.
  String get quotaOpusOneWeek => 'Opus · 1 week';

  /// Account quota title.
  String get claudeCodeSubscriptionQuota => 'Claude Code subscription quota';
}

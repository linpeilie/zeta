part of 'datasources/app_server/codex_app_server_agent_provider.dart';

/// Internal, stable fallback strings for protocol values that still require a
/// human-readable label in the neutral contract.
///
/// This is not exported and is not an application localization boundary.
final class _AgentUiTextCatalog {
  const _AgentUiTextCatalog();

  String get thinkingToolTitle => 'Thinking';
  String get webSearchTitle => 'Web search';
  String get viewImageTitle => 'View image';
  String get generateImageTitle => 'Generate image';
  String get collaboratePrefix => 'Collaborate';
  String get toolCallFallbackTitle => 'Tool call';
  String get reviewModeEnteredTitle => 'Review mode entered';
  String get reviewModeExitedTitle => 'Review mode exited';
  String get contextCompactedTitle => 'Context compacted';
  String get contextCompactedDescription => 'Conversation context compacted.';
  String get hookPromptTitle => 'Hook prompt';
  String get waitingTitle => 'Waiting';
  String get subAgentActivityTitle => 'Sub-agent activity';
  String get subAgentStarted => 'Started';
  String get subAgentInteracted => 'Interacted';
  String get subAgentInterrupted => 'Interrupted';
  String get subAgentUpdated => 'Updated';
  String get userCancelled => 'User cancelled';
  String get primaryQuotaLabel => 'Primary quota';
  String get extraQuotaLabel => 'Additional quota';
  String get applyPatchTitle => 'Apply patch';
  String get toolSearchTitle => 'Tool search';
  String get historyWebSearchTitle => 'Web search';
  String get agentRequestsInput => 'Agent requests input';

  String couldNotStart(String name) => 'Could not start $name';
  String protocolWarning(String name) => '$name protocol warning';
  String appServerConnectionClosed(String name) =>
      '$name app-server connection closed';
  String sleepMinutes(String minutes) => 'Sleep for $minutes minutes';
  String sleepMinutesSeconds(String minutes, String seconds) =>
      'Sleep for $minutes minutes $seconds seconds';
  String sleepSeconds(String seconds) => 'Sleep for $seconds seconds';
}

/// Builds a stable English duration label from a window length in minutes.
String? _formatAgentUsageWindowLabelFromMinutes(
  int? minutes, {
  _AgentUiTextCatalog catalog = const _AgentUiTextCatalog(),
}) {
  if (minutes == null || minutes <= 0) {
    return null;
  }
  const weekMinutes = 7 * 24 * 60;
  const dayMinutes = 24 * 60;
  if (minutes % weekMinutes == 0) {
    final weeks = minutes ~/ weekMinutes;
    return '$weeks ${weeks == 1 ? 'week' : 'weeks'}';
  }
  if (minutes % dayMinutes == 0) {
    final days = minutes ~/ dayMinutes;
    return '$days ${days == 1 ? 'day' : 'days'}';
  }
  if (minutes % 60 == 0) {
    final hours = minutes ~/ 60;
    return '$hours ${hours == 1 ? 'hour' : 'hours'}';
  }
  if (minutes > 60) {
    return '${minutes ~/ 60} hours ${minutes % 60} minutes';
  }
  return '$minutes ${minutes == 1 ? 'minute' : 'minutes'}';
}

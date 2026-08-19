/// Current persisted IDE session schema version.
const projectSessionSchemaVersion = 4;

/// Data-layer representation of an IDE workbench snapshot.
final class SessionWorkbenchResponse {
  /// Creates a workbench response.
  const SessionWorkbenchResponse({
    this.leftSidebarVisible = true,
    this.agentUsageExpanded = false,
    this.leftSidebarWidth,
    this.agentUsageHeightFraction,
    this.selectedAgentUsageProviderId,
  });

  /// Whether the project/sidebar area is visible.
  final bool leftSidebarVisible;

  /// Persisted legacy-compatible usage expansion preference.
  final bool agentUsageExpanded;

  /// User-selected sidebar width in logical pixels.
  final double? leftSidebarWidth;

  /// Persisted usage pane height fraction.
  final double? agentUsageHeightFraction;

  /// Selected usage provider identifier.
  final String? selectedAgentUsageProviderId;
}

/// Data-layer representation of a cached agent-thread summary.
final class SessionThreadSummaryResponse {
  /// Creates a cached thread response.
  const SessionThreadSummaryResponse({
    required this.id,
    required this.providerId,
    required this.projectPath,
    required this.preview,
    required this.createdAtMilliseconds,
    required this.updatedAtMilliseconds,
    required this.status,
    this.title,
    this.sessionPath,
    this.recencyAtMilliseconds,
    this.waitingOnApproval = false,
    this.waitingOnUserInput = false,
    this.raw = const <String, Object?>{},
  });

  /// Provider thread identifier.
  final String id;

  /// Provider configuration identifier.
  final String providerId;

  /// Captured project path.
  final String projectPath;

  /// Optional user-facing title.
  final String? title;

  /// Optional provider-owned restore locator.
  final String? sessionPath;

  /// Lightweight preview text.
  final String preview;

  /// Creation timestamp in milliseconds since the Unix epoch.
  final int createdAtMilliseconds;

  /// Last-update timestamp in milliseconds since the Unix epoch.
  final int updatedAtMilliseconds;

  /// Optional provider recency timestamp in milliseconds.
  final int? recencyAtMilliseconds;

  /// Persisted provider-neutral runtime status name.
  final String status;

  /// Whether the thread was waiting for approval.
  final bool waitingOnApproval;

  /// Whether the thread was waiting for user input.
  final bool waitingOnUserInput;

  /// Provider data preserved by the current schema.
  final Map<String, Object?> raw;
}

/// Data-layer representation of the current IDE session document.
///
/// This response contains persistence facts only and has no presentation-layer
/// dependency.
final class SessionSnapshotResponse {
  /// Creates an IDE session response.
  const SessionSnapshotResponse({
    this.projectPaths = const <String>[],
    this.activeProjectPath,
    this.currentFilePath,
    this.expandedDirectoryPaths = const <String>{},
    this.selectedTreeKey,
    this.activeAgentProviderId,
    this.agentThreadIdsByProject = const <String, String>{},
    this.projectThreadExpansionByProject = const <String, bool>{},
    this.cachedThreadsByProject =
        const <String, List<SessionThreadSummaryResponse>>{},
    this.selectedThreadIdsByProject = const <String, String>{},
    this.projectLastOpenedAtByPath = const <String, DateTime>{},
    this.projectHomeActive = false,
    this.workbench = const SessionWorkbenchResponse(),
  });

  /// Open project roots in persisted order.
  final List<String> projectPaths;

  /// Active project root.
  final String? activeProjectPath;

  /// Current file path.
  final String? currentFilePath;

  /// Expanded directory paths.
  final Set<String> expandedDirectoryPaths;

  /// Selected tree key.
  final String? selectedTreeKey;

  /// Active provider configuration identifier.
  final String? activeAgentProviderId;

  /// Last agent thread identifier for each project.
  final Map<String, String> agentThreadIdsByProject;

  /// Persisted thread-list expansion values by project.
  final Map<String, bool> projectThreadExpansionByProject;

  /// Lightweight cached thread summaries by project.
  final Map<String, List<SessionThreadSummaryResponse>> cachedThreadsByProject;

  /// Selected thread identifier by project.
  final Map<String, String> selectedThreadIdsByProject;

  /// Last-opened timestamp by project.
  final Map<String, DateTime> projectLastOpenedAtByPath;

  /// Whether the active project was displaying its home screen.
  final bool projectHomeActive;

  /// Device-independent workbench persistence values.
  final SessionWorkbenchResponse workbench;
}

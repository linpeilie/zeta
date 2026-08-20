import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:equatable/equatable.dart';

/// Device-independent workbench persistence values.
final class ProjectWorkbenchSnapshot extends Equatable {
  /// Creates a workbench snapshot.
  const ProjectWorkbenchSnapshot({
    this.leftSidebarVisible = true,
    this.agentUsageExpanded = false,
    this.leftSidebarWidth,
    this.agentUsageHeightFraction,
    this.selectedAgentUsageProviderId,
  });

  /// Whether the project sidebar is visible.
  final bool leftSidebarVisible;

  /// Whether the usage pane is expanded.
  final bool agentUsageExpanded;

  /// Persisted sidebar width.
  final double? leftSidebarWidth;

  /// Persisted usage-pane height fraction.
  final double? agentUsageHeightFraction;

  /// Selected usage Provider id.
  final String? selectedAgentUsageProviderId;

  @override
  List<Object?> get props => <Object?>[
    leftSidebarVisible,
    agentUsageExpanded,
    leftSidebarWidth,
    agentUsageHeightFraction,
    selectedAgentUsageProviderId,
  ];
}

/// Immutable current-schema IDE session snapshot.
final class ProjectSessionSnapshot extends Equatable {
  /// Creates and deeply freezes a session snapshot.
  ProjectSessionSnapshot({
    Iterable<String> projectPaths = const <String>[],
    this.activeProjectPath,
    this.currentFilePath,
    Iterable<String> expandedDirectoryPaths = const <String>{},
    this.selectedTreeKey,
    this.activeAgentProviderId,
    Map<String, String> agentThreadIdsByProject = const <String, String>{},
    Map<String, bool> projectThreadExpansionByProject = const <String, bool>{},
    Map<String, List<AgentThreadSummary>> cachedThreadsByProject =
        const <String, List<AgentThreadSummary>>{},
    Map<String, String> selectedThreadIdsByProject = const <String, String>{},
    Map<String, DateTime> projectLastOpenedAtByPath =
        const <String, DateTime>{},
    this.projectHomeActive = false,
    this.workbench = const ProjectWorkbenchSnapshot(),
  }) : projectPaths = List<String>.unmodifiable(projectPaths),
       expandedDirectoryPaths = Set<String>.unmodifiable(
         expandedDirectoryPaths,
       ),
       agentThreadIdsByProject = Map<String, String>.unmodifiable(
         agentThreadIdsByProject,
       ),
       projectThreadExpansionByProject = Map<String, bool>.unmodifiable(
         projectThreadExpansionByProject,
       ),
       cachedThreadsByProject =
           Map<String, List<AgentThreadSummary>>.unmodifiable(
             cachedThreadsByProject.map(
               (key, value) => MapEntry<String, List<AgentThreadSummary>>(
                 key,
                 List<AgentThreadSummary>.unmodifiable(value),
               ),
             ),
           ),
       selectedThreadIdsByProject = Map<String, String>.unmodifiable(
         selectedThreadIdsByProject,
       ),
       projectLastOpenedAtByPath = Map<String, DateTime>.unmodifiable(
         projectLastOpenedAtByPath,
       );

  /// Open project roots in persisted order.
  final List<String> projectPaths;

  /// Active project root.
  final String? activeProjectPath;

  /// Current file path.
  final String? currentFilePath;

  /// Persisted expanded directory paths.
  final Set<String> expandedDirectoryPaths;

  /// Persisted selected tree key.
  final String? selectedTreeKey;

  /// Active Provider id.
  final String? activeAgentProviderId;

  /// Last thread id by project.
  final Map<String, String> agentThreadIdsByProject;

  /// Thread-list expansion preference by project.
  final Map<String, bool> projectThreadExpansionByProject;

  /// Lightweight cached thread summaries by project.
  final Map<String, List<AgentThreadSummary>> cachedThreadsByProject;

  /// Selected thread id by project.
  final Map<String, String> selectedThreadIdsByProject;

  /// Last-opened time by project.
  final Map<String, DateTime> projectLastOpenedAtByPath;

  /// Whether the active project showed its home screen.
  final bool projectHomeActive;

  /// Device-independent workbench values.
  final ProjectWorkbenchSnapshot workbench;

  @override
  List<Object?> get props => <Object?>[
    projectPaths,
    activeProjectPath,
    currentFilePath,
    expandedDirectoryPaths,
    selectedTreeKey,
    activeAgentProviderId,
    agentThreadIdsByProject,
    projectThreadExpansionByProject,
    cachedThreadsByProject,
    selectedThreadIdsByProject,
    projectLastOpenedAtByPath,
    projectHomeActive,
    workbench,
  ];
}

/// Cross-Provider thread page query.
final class ProjectThreadQuery extends Equatable {
  /// Creates a query. Validation occurs at the Repository boundary.
  ProjectThreadQuery({
    required this.projectPath,
    this.limit = 10,
    this.cursor,
    this.archived = false,
    String? searchTerm,
    Iterable<String> sourceKinds = const <String>[],
  }) : searchTerm = _optionalTrimmed(searchTerm),
       sourceKinds = List<String>.unmodifiable(sourceKinds);

  /// Exact project path filter.
  final String projectPath;

  /// Maximum aggregate results in this page.
  final int limit;

  /// Opaque aggregate cursor from the previous page.
  final String? cursor;

  /// Whether archived threads are requested.
  final bool archived;

  /// Optional Provider-side search input.
  final String? searchTerm;

  /// Optional Provider-native source kinds.
  final List<String> sourceKinds;

  @override
  List<Object?> get props => <Object?>[
    projectPath,
    limit,
    cursor,
    archived,
    searchTerm,
    sourceKinds,
  ];
}

/// Stable per-Provider catalog failure categories.
enum ProjectThreadProviderFailureCode {
  /// Provider catalog invocation failed.
  externalFailure,

  /// Provider returned data inconsistent with its registered identity.
  invalidData,
}

/// Content-free failure evidence retained alongside partial results.
final class ProjectThreadProviderFailure extends Equatable {
  /// Creates safe per-Provider failure evidence.
  const ProjectThreadProviderFailure({
    required this.providerId,
    required this.code,
  });

  /// Canonical Provider id.
  final String providerId;

  /// Stable failure category.
  final ProjectThreadProviderFailureCode code;

  @override
  List<Object?> get props => <Object?>[providerId, code];
}

/// One globally sorted, aggregate-cursor thread page.
final class ProjectThreadPage extends Equatable {
  /// Creates and freezes one aggregate page.
  ProjectThreadPage({
    required Iterable<AgentThreadSummary> threads,
    required this.nextCursor,
    Iterable<ProjectThreadProviderFailure> failures =
        const <ProjectThreadProviderFailure>[],
  }) : threads = List<AgentThreadSummary>.unmodifiable(threads),
       failures = List<ProjectThreadProviderFailure>.unmodifiable(failures);

  /// Globally sorted thread summaries.
  final List<AgentThreadSummary> threads;

  /// Next aggregate cursor, or null at the end.
  final String? nextCursor;

  /// Content-free partial Provider failures.
  final List<ProjectThreadProviderFailure> failures;

  @override
  List<Object?> get props => <Object?>[threads, nextCursor, failures];
}

String? _optionalTrimmed(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

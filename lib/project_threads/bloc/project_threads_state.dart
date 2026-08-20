import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:equatable/equatable.dart';
import 'package:project_session_repository/project_session_repository.dart';

export 'package:agent_provider_contracts/agent_provider_contracts.dart'
    show AgentProviderFailure, AgentThreadSummary;
export 'package:project_session_repository/project_session_repository.dart'
    show ProjectSessionRepositoryFailure, ProjectThreadProviderFailure;

enum ProjectThreadsStatus { initial, loading, ready, loadingMore, failure }

final class ProjectThreadsState extends Equatable {
  const ProjectThreadsState({
    this.status = ProjectThreadsStatus.initial,
    this.projectPath,
    this.searchTerm = '',
    this.archived = false,
    this.threads = const <AgentThreadSummary>[],
    this.nextCursor,
    this.selectedThreadId,
    this.catalogFailures = const <ProjectThreadProviderFailure>[],
    this.sessionFailure,
    this.providerFailure,
  });

  final ProjectThreadsStatus status;
  final String? projectPath;
  final String searchTerm;
  final bool archived;
  final List<AgentThreadSummary> threads;
  final String? nextCursor;
  final String? selectedThreadId;
  final List<ProjectThreadProviderFailure> catalogFailures;
  final ProjectSessionRepositoryFailure? sessionFailure;
  final AgentProviderFailure? providerFailure;

  bool get hasMore => nextCursor != null && nextCursor!.isNotEmpty;

  ProjectThreadsState copyWith({
    ProjectThreadsStatus? status,
    String? projectPath,
    String? searchTerm,
    bool? archived,
    List<AgentThreadSummary>? threads,
    String? nextCursor,
    String? selectedThreadId,
    List<ProjectThreadProviderFailure>? catalogFailures,
    ProjectSessionRepositoryFailure? sessionFailure,
    AgentProviderFailure? providerFailure,
    bool clearProject = false,
    bool clearNextCursor = false,
    bool clearSelected = false,
    bool clearSessionFailure = false,
    bool clearProviderFailure = false,
  }) {
    return ProjectThreadsState(
      status: status ?? this.status,
      projectPath: clearProject ? null : (projectPath ?? this.projectPath),
      searchTerm: searchTerm ?? this.searchTerm,
      archived: archived ?? this.archived,
      threads: threads ?? this.threads,
      nextCursor: clearNextCursor ? null : (nextCursor ?? this.nextCursor),
      selectedThreadId: clearSelected
          ? null
          : (selectedThreadId ?? this.selectedThreadId),
      catalogFailures: catalogFailures ?? this.catalogFailures,
      sessionFailure: clearSessionFailure
          ? null
          : (sessionFailure ?? this.sessionFailure),
      providerFailure: clearProviderFailure
          ? null
          : (providerFailure ?? this.providerFailure),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    status,
    projectPath,
    searchTerm,
    archived,
    threads,
    nextCursor,
    selectedThreadId,
    catalogFailures,
    sessionFailure,
    providerFailure,
  ];
}

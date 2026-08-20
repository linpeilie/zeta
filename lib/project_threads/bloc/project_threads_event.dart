import 'package:equatable/equatable.dart';
import 'package:project_session_repository/project_session_repository.dart';

sealed class ProjectThreadsEvent extends Equatable {
  const ProjectThreadsEvent();

  @override
  List<Object?> get props => const <Object?>[];
}

final class ProjectThreadsSubscriptionRequested extends ProjectThreadsEvent {
  const ProjectThreadsSubscriptionRequested();
}

final class ProjectThreadsProjectActivated extends ProjectThreadsEvent {
  const ProjectThreadsProjectActivated(this.projectPath);

  final String projectPath;

  @override
  List<Object?> get props => <Object?>[projectPath];
}

final class ProjectThreadsSearchChanged extends ProjectThreadsEvent {
  const ProjectThreadsSearchChanged(this.searchTerm);

  final String searchTerm;

  @override
  List<Object?> get props => <Object?>[searchTerm];
}

final class ProjectThreadsArchivedFilterChanged extends ProjectThreadsEvent {
  const ProjectThreadsArchivedFilterChanged({required this.archived});

  final bool archived;

  @override
  List<Object?> get props => <Object?>[archived];
}

final class ProjectThreadsLoadMoreRequested extends ProjectThreadsEvent {
  const ProjectThreadsLoadMoreRequested();
}

final class ProjectThreadsRefreshRequested extends ProjectThreadsEvent {
  const ProjectThreadsRefreshRequested();
}

final class ProjectThreadsThreadSelected extends ProjectThreadsEvent {
  const ProjectThreadsThreadSelected(this.threadId);

  final String threadId;

  @override
  List<Object?> get props => <Object?>[threadId];
}

final class ProjectThreadsRenameRequested extends ProjectThreadsEvent {
  const ProjectThreadsRenameRequested({
    required this.threadId,
    required this.name,
  });

  final String threadId;
  final String name;

  @override
  List<Object?> get props => <Object?>[threadId, name];
}

final class ProjectThreadsArchiveRequested extends ProjectThreadsEvent {
  const ProjectThreadsArchiveRequested(this.threadId);

  final String threadId;

  @override
  List<Object?> get props => <Object?>[threadId];
}

final class ProjectThreadsUnarchiveRequested extends ProjectThreadsEvent {
  const ProjectThreadsUnarchiveRequested(this.threadId);

  final String threadId;

  @override
  List<Object?> get props => <Object?>[threadId];
}

final class ProjectThreadsDeleteRequested extends ProjectThreadsEvent {
  const ProjectThreadsDeleteRequested(this.threadId);

  final String threadId;

  @override
  List<Object?> get props => <Object?>[threadId];
}

final class ProjectThreadsSnapshotUpdated extends ProjectThreadsEvent {
  const ProjectThreadsSnapshotUpdated(this.snapshot);

  final ProjectSessionSnapshot? snapshot;

  @override
  List<Object?> get props => <Object?>[snapshot];
}

import 'dart:async';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:agent_provider_repository/agent_provider_repository.dart';
import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:project_session_repository/project_session_repository.dart';
import 'package:zeta/project_threads/bloc/project_threads_event.dart';
import 'package:zeta/project_threads/bloc/project_threads_state.dart';

// Named public constructor parameters initialize private fields.
// ignore_for_file: prefer_initializing_formals

class ProjectThreadsBloc
    extends Bloc<ProjectThreadsEvent, ProjectThreadsState> {
  ProjectThreadsBloc({
    required ProjectSessionRepository projectSessionRepository,
    required AgentProviderRepository agentProviderRepository,
  }) : _projectSessionRepository = projectSessionRepository,
       _agentProviderRepository = agentProviderRepository,
       super(const ProjectThreadsState()) {
    on<ProjectThreadsSubscriptionRequested>(
      _onSubscriptionRequested,
      transformer: restartable(),
    );
    on<ProjectThreadsProjectActivated>(
      _onProjectActivated,
      transformer: restartable(),
    );
    on<ProjectThreadsSearchChanged>(
      _onSearchChanged,
      transformer: restartable(),
    );
    on<ProjectThreadsArchivedFilterChanged>(
      _onArchivedFilterChanged,
      transformer: restartable(),
    );
    on<ProjectThreadsLoadMoreRequested>(
      _onLoadMoreRequested,
      transformer: droppable(),
    );
    on<ProjectThreadsRefreshRequested>(
      _onRefreshRequested,
      transformer: restartable(),
    );
    on<ProjectThreadsThreadSelected>(
      _onThreadSelected,
      transformer: sequential(),
    );
    on<ProjectThreadsRenameRequested>(
      _onRenameRequested,
      transformer: sequential(),
    );
    on<ProjectThreadsArchiveRequested>(
      _onArchiveRequested,
      transformer: sequential(),
    );
    on<ProjectThreadsUnarchiveRequested>(
      _onUnarchiveRequested,
      transformer: sequential(),
    );
    on<ProjectThreadsDeleteRequested>(
      _onDeleteRequested,
      transformer: sequential(),
    );
    on<ProjectThreadsSnapshotUpdated>(
      _onSnapshotUpdated,
      transformer: sequential(),
    );
  }

  final ProjectSessionRepository _projectSessionRepository;
  final AgentProviderRepository _agentProviderRepository;
  StreamSubscription<ProjectSessionSnapshot?>? _snapshotSubscription;

  Future<void> _onSubscriptionRequested(
    ProjectThreadsSubscriptionRequested event,
    Emitter<ProjectThreadsState> emit,
  ) async {
    await _snapshotSubscription?.cancel();
    _snapshotSubscription = _projectSessionRepository.snapshotChanges.listen((
      snapshot,
    ) {
      add(ProjectThreadsSnapshotUpdated(snapshot));
    });
  }

  Future<void> _onProjectActivated(
    ProjectThreadsProjectActivated event,
    Emitter<ProjectThreadsState> emit,
  ) async {
    final projectPath = event.projectPath.trim();
    if (projectPath.isEmpty) {
      return;
    }
    emit(
      state.copyWith(
        status: ProjectThreadsStatus.loading,
        projectPath: projectPath,
        threads: const <AgentThreadSummary>[],
        clearNextCursor: true,
        clearSessionFailure: true,
        clearProviderFailure: true,
      ),
    );
    await _loadInitial(emit);
  }

  Future<void> _onSearchChanged(
    ProjectThreadsSearchChanged event,
    Emitter<ProjectThreadsState> emit,
  ) async {
    if (state.projectPath == null) {
      return;
    }
    emit(
      state.copyWith(
        status: ProjectThreadsStatus.loading,
        searchTerm: event.searchTerm,
        threads: const <AgentThreadSummary>[],
        clearNextCursor: true,
        clearSessionFailure: true,
        clearProviderFailure: true,
      ),
    );
    await _loadInitial(emit);
  }

  Future<void> _onArchivedFilterChanged(
    ProjectThreadsArchivedFilterChanged event,
    Emitter<ProjectThreadsState> emit,
  ) async {
    if (state.projectPath == null) {
      return;
    }
    emit(
      state.copyWith(
        status: ProjectThreadsStatus.loading,
        archived: event.archived,
        threads: const <AgentThreadSummary>[],
        clearNextCursor: true,
        clearSessionFailure: true,
        clearProviderFailure: true,
      ),
    );
    await _loadInitial(emit);
  }

  Future<void> _onLoadMoreRequested(
    ProjectThreadsLoadMoreRequested event,
    Emitter<ProjectThreadsState> emit,
  ) async {
    final projectPath = state.projectPath;
    final cursor = state.nextCursor;
    if (projectPath == null || cursor == null || cursor.isEmpty) {
      return;
    }
    emit(
      state.copyWith(
        status: ProjectThreadsStatus.loadingMore,
        clearSessionFailure: true,
        clearProviderFailure: true,
      ),
    );
    try {
      final page = await _projectSessionRepository.threadPage(
        _query(projectPath: projectPath, cursor: cursor),
      );
      emit(
        state.copyWith(
          status: ProjectThreadsStatus.ready,
          threads: <AgentThreadSummary>[...state.threads, ...page.threads],
          nextCursor: page.nextCursor,
          catalogFailures: page.failures,
          clearNextCursor: page.nextCursor == null,
        ),
      );
    } on ProjectSessionRepositoryException catch (error) {
      emit(
        state.copyWith(
          status: ProjectThreadsStatus.failure,
          sessionFailure: error.failure,
        ),
      );
    }
  }

  Future<void> _onRefreshRequested(
    ProjectThreadsRefreshRequested event,
    Emitter<ProjectThreadsState> emit,
  ) async {
    if (state.projectPath == null) {
      return;
    }
    emit(
      state.copyWith(
        status: ProjectThreadsStatus.loading,
        clearSessionFailure: true,
        clearProviderFailure: true,
      ),
    );
    await _loadInitial(emit);
  }

  void _onThreadSelected(
    ProjectThreadsThreadSelected event,
    Emitter<ProjectThreadsState> emit,
  ) {
    emit(
      state.copyWith(
        selectedThreadId: event.threadId,
        clearProviderFailure: true,
      ),
    );
  }

  Future<void> _onRenameRequested(
    ProjectThreadsRenameRequested event,
    Emitter<ProjectThreadsState> emit,
  ) {
    return _mutateThread(
      emit,
      threadId: event.threadId,
      unsupportedCode: 'thread_naming_unavailable',
      failedCode: 'thread_rename_failed',
      port: (bundle) => bundle.threadNaming,
      action: (bundle, thread) {
        return bundle.threadNaming!.renameThread(
          threadId: thread.id,
          name: event.name,
        );
      },
    );
  }

  Future<void> _onArchiveRequested(
    ProjectThreadsArchiveRequested event,
    Emitter<ProjectThreadsState> emit,
  ) {
    return _mutateThread(
      emit,
      threadId: event.threadId,
      unsupportedCode: 'thread_archival_unavailable',
      failedCode: 'thread_archive_failed',
      port: (bundle) => bundle.threadArchival,
      action: (bundle, thread) {
        return bundle.threadArchival!.archiveThread(thread.id);
      },
    );
  }

  Future<void> _onUnarchiveRequested(
    ProjectThreadsUnarchiveRequested event,
    Emitter<ProjectThreadsState> emit,
  ) {
    return _mutateThread(
      emit,
      threadId: event.threadId,
      unsupportedCode: 'thread_archival_unavailable',
      failedCode: 'thread_unarchive_failed',
      port: (bundle) => bundle.threadArchival,
      action: (bundle, thread) {
        return bundle.threadArchival!.unarchiveThread(thread.id);
      },
    );
  }

  Future<void> _onDeleteRequested(
    ProjectThreadsDeleteRequested event,
    Emitter<ProjectThreadsState> emit,
  ) {
    return _mutateThread(
      emit,
      threadId: event.threadId,
      unsupportedCode: 'thread_deletion_unavailable',
      failedCode: 'thread_delete_failed',
      port: (bundle) => bundle.threadDeletion,
      action: (bundle, thread) {
        return bundle.threadDeletion!.deleteThread(thread.id);
      },
    );
  }

  void _onSnapshotUpdated(
    ProjectThreadsSnapshotUpdated event,
    Emitter<ProjectThreadsState> emit,
  ) {
    final projectPath = state.projectPath;
    final snapshot = event.snapshot;
    if (projectPath == null || snapshot == null) {
      return;
    }
    final selected = snapshot.selectedThreadIdsByProject[projectPath];
    if (selected == null || selected == state.selectedThreadId) {
      return;
    }
    emit(state.copyWith(selectedThreadId: selected));
  }

  Future<void> _loadInitial(Emitter<ProjectThreadsState> emit) async {
    final projectPath = state.projectPath;
    if (projectPath == null) {
      return;
    }
    try {
      final page = await _projectSessionRepository.threadPage(
        _query(projectPath: projectPath),
      );
      emit(
        state.copyWith(
          status: ProjectThreadsStatus.ready,
          threads: page.threads,
          nextCursor: page.nextCursor,
          catalogFailures: page.failures,
          clearNextCursor: page.nextCursor == null,
          clearSessionFailure: true,
        ),
      );
    } on ProjectSessionRepositoryException catch (error) {
      emit(
        state.copyWith(
          status: ProjectThreadsStatus.failure,
          sessionFailure: error.failure,
        ),
      );
    }
  }

  Future<void> _mutateThread(
    Emitter<ProjectThreadsState> emit, {
    required String threadId,
    required String unsupportedCode,
    required String failedCode,
    required Object? Function(AgentProviderBundle bundle) port,
    required Future<void> Function(
      AgentProviderBundle bundle,
      AgentThreadSummary thread,
    )
    action,
  }) async {
    final thread = _threadById(threadId);
    if (thread == null) {
      return;
    }
    try {
      final bundle = _agentProviderRepository.bundleFor(thread.providerId);
      if (port(bundle) == null) {
        emit(
          state.copyWith(
            status: ProjectThreadsStatus.failure,
            providerFailure: AgentProviderFailure(
              code: AgentProviderFailureCode.unavailable,
              diagnosticCode: unsupportedCode,
            ),
          ),
        );
        return;
      }
      await action(bundle, thread);
      emit(
        state.copyWith(
          status: ProjectThreadsStatus.loading,
          clearProviderFailure: true,
          clearSessionFailure: true,
        ),
      );
      await _loadInitial(emit);
    } on AgentProviderRepositoryException catch (error) {
      emit(
        state.copyWith(
          status: ProjectThreadsStatus.failure,
          providerFailure: error.failure,
        ),
      );
    } on Object {
      emit(
        state.copyWith(
          status: ProjectThreadsStatus.failure,
          providerFailure: AgentProviderFailure(
            code: AgentProviderFailureCode.unknown,
            diagnosticCode: failedCode,
          ),
        ),
      );
    }
  }

  AgentThreadSummary? _threadById(String threadId) {
    for (final thread in state.threads) {
      if (thread.id == threadId) {
        return thread;
      }
    }
    return null;
  }

  ProjectThreadQuery _query({
    required String projectPath,
    String? cursor,
  }) {
    final search = state.searchTerm.trim();
    return ProjectThreadQuery(
      projectPath: projectPath,
      cursor: cursor,
      archived: state.archived,
      searchTerm: search.isEmpty ? null : search,
    );
  }

  @override
  Future<void> close() async {
    await _snapshotSubscription?.cancel();
    return super.close();
  }
}

import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/project_threads/application/project_threads_slice/project_threads_slice_effect.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_slice/project_threads_slice_intent.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_slice/project_threads_slice_state.dart';
import 'package:zeta/src/features/project_threads/domain/project_thread_list_state.dart';

/// Project Threads 的纯同步 reducer（G3）。
///
/// 时间由 intent 显式携带；Provider 查询、Timer 和 Future 都只存在于 runner。
Transition<ProjectThreadsSliceState, ProjectThreadsSliceEffect>
projectThreadsSliceReduce(
  ProjectThreadsSliceState state,
  ProjectThreadsSliceIntent intent,
) {
  switch (intent) {
    case ProjectThreadsEffectRequested():
      return Transition(state, <ProjectThreadsSliceEffect>[intent.effect]);

    case ProjectThreadStatesReplaced():
      return Transition.stateOnly(
        ProjectThreadsSliceState(statesByProject: intent.states),
      );

    case ProjectThreadProjectsRetained():
      final allowed = intent.projectPaths.toSet();
      if (state.statesByProject.keys.every(allowed.contains)) {
        return Transition.none(state);
      }
      return Transition.stateOnly(
        ProjectThreadsSliceState(
          statesByProject: <String, ProjectThreadListState>{
            for (final entry in state.statesByProject.entries)
              if (allowed.contains(entry.key)) entry.key: entry.value,
          },
        ),
      );

    case ProjectThreadStateApplied():
      if (identical(state.statesByProject[intent.projectPath], intent.state)) {
        return Transition.none(state);
      }
      return Transition.stateOnly(
        _replaceProject(state, intent.projectPath, intent.state),
      );

    case ProjectThreadSelected():
      return _selectThread(state, intent.projectPath, intent.threadId);

    case ProjectThreadSelectionCleared():
      return _updateProject(state, intent.projectPath, (current) {
        if (current.selectedThreadId == null) {
          return current;
        }
        return current.copyWith(selectedThreadId: null);
      });

    case AllProjectThreadSelectionsCleared():
      var changed = false;
      final next = Map<String, ProjectThreadListState>.of(
        state.statesByProject,
      );
      for (final entry in state.statesByProject.entries) {
        if (entry.value.selectedThreadId == null) {
          continue;
        }
        next[entry.key] = entry.value.copyWith(selectedThreadId: null);
        changed = true;
      }
      return changed
          ? Transition.stateOnly(
              ProjectThreadsSliceState(statesByProject: next),
            )
          : Transition.none(state);

    case ProjectThreadRunningChanged():
      return _updateProject(state, intent.projectPath, (current) {
        final nextRunning = Set<String>.from(current.runningThreadIds);
        final nextCompleted = Set<String>.from(current.completedThreadIds);
        var next = current;
        if (intent.isRunning) {
          final added = nextRunning.add(intent.threadId);
          final clearedCompleted = nextCompleted.remove(intent.threadId);
          if (!added && !clearedCompleted) {
            return current;
          }
          if (added) {
            next = _promoteThread(
              current,
              threadId: intent.threadId,
              activityAt: intent.activityAt,
            );
          }
        } else {
          final removed = nextRunning.remove(intent.threadId);
          final clearedActive = _clearActiveStatus(
            next,
            threadId: intent.threadId,
          );
          if (!removed && identical(clearedActive, next)) {
            return current;
          }
          next = clearedActive;
          if (removed && current.selectedThreadId != intent.threadId) {
            nextCompleted.add(intent.threadId);
          }
        }
        return next.copyWith(
          runningThreadIds: nextRunning,
          completedThreadIds: nextCompleted,
        );
      });

    case CompletedProjectThreadDismissed():
      return _updateProject(state, intent.projectPath, (current) {
        if (!current.completedThreadIds.contains(intent.threadId)) {
          return current;
        }
        final nextCompleted = Set<String>.from(current.completedThreadIds)
          ..remove(intent.threadId);
        return current.copyWith(completedThreadIds: nextCompleted);
      });

    case ProjectThreadRuntimeStatusChanged():
      return _updateProject(state, intent.projectPath, (current) {
        final index = current.threads.indexWhere(
          (thread) => thread.id == intent.threadId,
        );
        if (index == -1) {
          return current;
        }
        final nextRunning = Set<String>.from(current.runningThreadIds);
        final nextCompleted = Set<String>.from(current.completedThreadIds);
        var base = current;
        if (intent.status == AgentThreadRuntimeStatus.active) {
          final added = nextRunning.add(intent.threadId);
          nextCompleted.remove(intent.threadId);
          if (added) {
            base = _promoteThread(
              current,
              threadId: intent.threadId,
              activityAt: intent.activityAt,
            );
          }
        } else {
          final wasRunning = nextRunning.remove(intent.threadId);
          if (wasRunning && current.selectedThreadId != intent.threadId) {
            nextCompleted.add(intent.threadId);
          }
        }
        final promotedIndex = base.threads.indexWhere(
          (thread) => thread.id == intent.threadId,
        );
        if (promotedIndex == -1) {
          return current;
        }
        final threads = List<AgentThreadSummary>.of(base.threads);
        final existing = threads[promotedIndex];
        final isActive = intent.status == AgentThreadRuntimeStatus.active;
        threads[promotedIndex] = existing.copyWith(
          status: intent.status,
          waitingOnApproval: isActive && intent.waitingOnApproval,
          waitingOnUserInput: isActive && intent.waitingOnUserInput,
        );
        return base.copyWith(
          threads: List<AgentThreadSummary>.unmodifiable(threads),
          runningThreadIds: nextRunning,
          completedThreadIds: nextCompleted,
        );
      });

    case ProjectThreadTitleChanged():
      return _updateThread(state, intent.projectPath, intent.threadId, (
        thread,
      ) {
        return thread.copyWith(title: intent.title);
      });

    case ProjectThreadPreviewChanged():
      return _updateThread(state, intent.projectPath, intent.threadId, (
        thread,
      ) {
        if (thread.preview == intent.preview) {
          return thread;
        }
        return thread.copyWith(preview: intent.preview);
      });

    case ProjectThreadRemoved():
      return _updateProject(state, intent.projectPath, (current) {
        final threads = current.threads
            .where((thread) => thread.id != intent.threadId)
            .toList(growable: false);
        if (threads.length == current.threads.length) {
          return current;
        }
        final nextRunning = Set<String>.from(current.runningThreadIds)
          ..remove(intent.threadId);
        final nextCompleted = Set<String>.from(current.completedThreadIds)
          ..remove(intent.threadId);
        final selectedCleared = current.selectedThreadId == intent.threadId;
        return current.copyWith(
          threads: List<AgentThreadSummary>.unmodifiable(threads),
          runningThreadIds: nextRunning,
          completedThreadIds: nextCompleted,
          selectedThreadId: selectedCleared ? null : current.selectedThreadId,
        );
      });

    case ProjectThreadPrepended():
      return _updateProject(state, intent.projectPath, (current) {
        if (current.threads.any((item) => item.id == intent.thread.id)) {
          return _promoteThread(
            current,
            threadId: intent.thread.id,
            activityAt: intent.thread.recencyAt ?? intent.thread.updatedAt,
          );
        }
        return current.copyWith(
          threads: List<AgentThreadSummary>.unmodifiable(<AgentThreadSummary>[
            intent.thread,
            ...current.threads,
          ]),
        );
      });

    case ProjectThreadsOperationSucceeded() ||
        ProjectThreadsForkSucceeded() ||
        ProjectThreadsOperationFailed():
      return Transition.none(state);
  }
}

Transition<ProjectThreadsSliceState, ProjectThreadsSliceEffect> _selectThread(
  ProjectThreadsSliceState state,
  String projectPath,
  String threadId,
) {
  var changed = false;
  final next = Map<String, ProjectThreadListState>.of(state.statesByProject);
  for (final entry in state.statesByProject.entries) {
    if (entry.key == projectPath || entry.value.selectedThreadId == null) {
      continue;
    }
    next[entry.key] = entry.value.copyWith(selectedThreadId: null);
    changed = true;
  }

  final current = state.stateFor(projectPath);
  final nextCompleted = Set<String>.from(current.completedThreadIds)
    ..remove(threadId);
  if (!state.statesByProject.containsKey(projectPath) ||
      current.selectedThreadId != threadId ||
      nextCompleted.length != current.completedThreadIds.length) {
    next[projectPath] = current.copyWith(
      selectedThreadId: threadId,
      completedThreadIds: nextCompleted,
    );
    changed = true;
  }
  return changed
      ? Transition.stateOnly(ProjectThreadsSliceState(statesByProject: next))
      : Transition.none(state);
}

Transition<ProjectThreadsSliceState, ProjectThreadsSliceEffect> _updateThread(
  ProjectThreadsSliceState state,
  String projectPath,
  String threadId,
  AgentThreadSummary Function(AgentThreadSummary thread) update,
) {
  return _updateProject(state, projectPath, (current) {
    final index = current.threads.indexWhere((thread) => thread.id == threadId);
    if (index == -1) {
      return current;
    }
    final existing = current.threads[index];
    final updated = update(existing);
    if (identical(existing, updated)) {
      return current;
    }
    final threads = List<AgentThreadSummary>.of(current.threads);
    threads[index] = updated;
    return current.copyWith(
      threads: List<AgentThreadSummary>.unmodifiable(threads),
    );
  });
}

Transition<ProjectThreadsSliceState, ProjectThreadsSliceEffect> _updateProject(
  ProjectThreadsSliceState state,
  String projectPath,
  ProjectThreadListState Function(ProjectThreadListState current) update,
) {
  final current = state.stateFor(projectPath);
  final next = update(current);
  if (identical(current, next)) {
    return Transition.none(state);
  }
  return Transition.stateOnly(_replaceProject(state, projectPath, next));
}

ProjectThreadsSliceState _replaceProject(
  ProjectThreadsSliceState state,
  String projectPath,
  ProjectThreadListState value,
) {
  return ProjectThreadsSliceState(
    statesByProject: <String, ProjectThreadListState>{
      ...state.statesByProject,
      projectPath: value,
    },
  );
}

ProjectThreadListState _clearActiveStatus(
  ProjectThreadListState current, {
  required String threadId,
}) {
  final index = current.threads.indexWhere((thread) => thread.id == threadId);
  if (index == -1) {
    return current;
  }
  final existing = current.threads[index];
  final needsClear =
      existing.status == AgentThreadRuntimeStatus.active ||
      existing.waitingOnApproval ||
      existing.waitingOnUserInput;
  if (!needsClear) {
    return current;
  }
  final threads = List<AgentThreadSummary>.of(current.threads);
  threads[index] = existing.copyWith(
    status: AgentThreadRuntimeStatus.idle,
    waitingOnApproval: false,
    waitingOnUserInput: false,
  );
  return current.copyWith(
    threads: List<AgentThreadSummary>.unmodifiable(threads),
  );
}

ProjectThreadListState _promoteThread(
  ProjectThreadListState current, {
  required String threadId,
  required DateTime activityAt,
}) {
  final index = current.threads.indexWhere((thread) => thread.id == threadId);
  if (index == -1) {
    return current;
  }
  final existing = current.threads[index];
  final previousRecency = existing.recencyAt ?? existing.updatedAt;
  if (index == 0 && !activityAt.isAfter(previousRecency)) {
    return current;
  }
  final promoted = existing.copyWith(
    updatedAt: activityAt,
    recencyAt: activityAt,
  );
  if (index == 0) {
    final threads = List<AgentThreadSummary>.of(current.threads);
    threads[0] = promoted;
    return current.copyWith(
      threads: List<AgentThreadSummary>.unmodifiable(threads),
    );
  }
  final rest = List<AgentThreadSummary>.of(current.threads)..removeAt(index);
  return current.copyWith(
    threads: List<AgentThreadSummary>.unmodifiable(<AgentThreadSummary>[
      promoted,
      ...rest,
    ]),
  );
}

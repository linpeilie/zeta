import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/project_threads/domain/project_thread_list_state.dart';

/// Project Threads 列表的纯状态容器。
///
/// 它只负责暴露和更新列表状态本身，不再直接处理会话恢复编排或分页请求策略。
class ProjectThreadsViewModel extends ChangeNotifier {
  final Map<String, ProjectThreadListState> _states =
      <String, ProjectThreadListState>{};
  bool _disposed = false;

  /// 所有项目的 thread 状态快照。
  Map<String, ProjectThreadListState> get states =>
      UnmodifiableMapView<String, ProjectThreadListState>(_states);

  ProjectThreadListState stateFor(String projectPath) {
    return _states[projectPath] ?? const ProjectThreadListState();
  }

  /// 用恢复结果整体替换当前项目 thread 状态。
  void replaceStates(Map<String, ProjectThreadListState> states) {
    _states
      ..clear()
      ..addAll(states);
    _notify();
  }

  /// 清理已经不在项目列表中的状态。
  void retainProjects(List<String> projectPaths) {
    final allowed = projectPaths.toSet();
    final removed = _states.keys.where((path) => !allowed.contains(path));
    if (removed.isEmpty) {
      return;
    }
    for (final path in removed.toList()) {
      _states.remove(path);
    }
    _notify();
  }

  /// 直接覆盖某个项目的列表状态。
  void setStateFor(String projectPath, ProjectThreadListState state) {
    _states[projectPath] = state;
    _notify();
  }

  /// 基于当前状态更新某个项目。
  void updateState(
    String projectPath,
    ProjectThreadListState Function(ProjectThreadListState current) updater,
  ) {
    final current = stateFor(projectPath);
    _states[projectPath] = updater(current);
    _notify();
  }

  /// 全局唯一选中：写入 [projectPath] 的 thread 高亮，并清除其他项目的选中态。
  ///
  /// 侧栏可能同时展开多个项目；选中样式必须跨项目互斥，避免多个 thread 同时高亮。
  /// 选中某 thread 时同步清除其「后台执行完毕」提示。
  void selectThreadId(String projectPath, String threadId) {
    var changed = false;

    for (final path in _states.keys.toList(growable: false)) {
      if (path == projectPath) {
        continue;
      }
      final other = _states[path]!;
      if (other.selectedThreadId != null) {
        _states[path] = other.copyWith(selectedThreadId: null);
        changed = true;
      }
    }

    final current = stateFor(projectPath);
    final nextCompleted = Set<String>.from(current.completedThreadIds)
      ..remove(threadId);
    final completedChanged =
        nextCompleted.length != current.completedThreadIds.length;
    if (!_states.containsKey(projectPath) ||
        current.selectedThreadId != threadId ||
        completedChanged) {
      _states[projectPath] = current.copyWith(
        selectedThreadId: threadId,
        completedThreadIds: nextCompleted,
      );
      changed = true;
    }

    if (changed) {
      _notify();
    }
  }

  void clearSelectedThreadId(String projectPath) {
    updateState(
      projectPath,
      (current) => current.copyWith(selectedThreadId: null),
    );
  }

  /// 只更新执行中的 thread 集合，避免影响其它项目列表状态。
  void setRunningThreadIds(String projectPath, Set<String> runningThreadIds) {
    updateState(
      projectPath,
      (current) => current.copyWith(runningThreadIds: runningThreadIds),
    );
  }

  /// 更新单条 thread 的执行中标记；结束后若非当前选中则记入完成提示集合。
  ///
  /// 首次进入执行中时会同步 [promoteThread]（刷新 recency 并置顶），
  /// 使已有 thread 发消息后与新建会话的列表行为一致。
  void setThreadRunning({
    required String projectPath,
    required String threadId,
    required bool isRunning,
  }) {
    updateState(projectPath, (current) {
      final nextRunning = Set<String>.from(current.runningThreadIds);
      final nextCompleted = Set<String>.from(current.completedThreadIds);
      var next = current;
      if (isRunning) {
        final added = nextRunning.add(threadId);
        final clearedCompleted = nextCompleted.remove(threadId);
        if (!added && !clearedCompleted) {
          return current;
        }
        // 仅在 idle→running 边沿置顶，避免 turn 期间重复 snapshot 重建列表。
        if (added) {
          next = _promoteThreadInState(
            current,
            threadId: threadId,
            activityAt: DateTime.now(),
          );
        }
      } else {
        final removed = nextRunning.remove(threadId);
        if (!removed) {
          return current;
        }
        // 后台完成：当前查看的不是该 thread 时，保留绿色完成提示。
        if (current.selectedThreadId != threadId) {
          nextCompleted.add(threadId);
        }
      }
      return next.copyWith(
        runningThreadIds: nextRunning,
        completedThreadIds: nextCompleted,
      );
    });
  }

  /// 用户点击完成提示后清除；不改变选中态。
  void dismissCompletedThread({
    required String projectPath,
    required String threadId,
  }) {
    updateState(projectPath, (current) {
      if (!current.completedThreadIds.contains(threadId)) {
        return current;
      }
      final nextCompleted = Set<String>.from(current.completedThreadIds)
        ..remove(threadId);
      return current.copyWith(completedThreadIds: nextCompleted);
    });
  }

  /// 用实时状态通知更新列表中某条 thread 的运行态与等待标志。
  ///
  /// 首次进入 active 时同样置顶，覆盖仅靠 status 事件、尚未发 TurnStarted 的路径。
  void updateThreadRuntimeStatus({
    required String projectPath,
    required String threadId,
    required AgentThreadRuntimeStatus status,
    required bool waitingOnApproval,
    required bool waitingOnUserInput,
  }) {
    updateState(projectPath, (current) {
      final index = current.threads.indexWhere(
        (thread) => thread.id == threadId,
      );
      if (index == -1) {
        return current;
      }
      final nextRunning = Set<String>.from(current.runningThreadIds);
      final nextCompleted = Set<String>.from(current.completedThreadIds);
      var base = current;
      if (status == AgentThreadRuntimeStatus.active) {
        final added = nextRunning.add(threadId);
        nextCompleted.remove(threadId);
        if (added) {
          base = _promoteThreadInState(
            current,
            threadId: threadId,
            activityAt: DateTime.now(),
          );
        }
      } else {
        final wasRunning = nextRunning.remove(threadId);
        // 与 setThreadRunning 一致：仅在从执行中退出且非当前选中时提示完成。
        if (wasRunning && current.selectedThreadId != threadId) {
          nextCompleted.add(threadId);
        }
      }
      // 置顶后 index 可能变为 0，需重新定位再写 status 字段。
      final promotedIndex = base.threads.indexWhere(
        (thread) => thread.id == threadId,
      );
      if (promotedIndex == -1) {
        return current;
      }
      final threads = List<AgentThreadSummary>.of(base.threads);
      threads[promotedIndex] = threads[promotedIndex].copyWith(
        status: status,
        waitingOnApproval: waitingOnApproval,
        waitingOnUserInput: waitingOnUserInput,
      );
      return base.copyWith(
        threads: List<AgentThreadSummary>.unmodifiable(threads),
        runningThreadIds: nextRunning,
        completedThreadIds: nextCompleted,
      );
    });
  }

  /// 更新列表中某条 thread 的标题。
  void updateThreadTitle({
    required String projectPath,
    required String threadId,
    required String? title,
  }) {
    updateState(projectPath, (current) {
      final index = current.threads.indexWhere(
        (thread) => thread.id == threadId,
      );
      if (index == -1) {
        return current;
      }
      final threads = List<AgentThreadSummary>.of(current.threads);
      threads[index] = threads[index].copyWith(title: title);
      return current.copyWith(
        threads: List<AgentThreadSummary>.unmodifiable(threads),
      );
    });
  }

  /// 从列表移除 thread；若正被选中则清空选中。
  ///
  /// 返回是否清除了选中态。
  bool removeThread({required String projectPath, required String threadId}) {
    var clearedSelection = false;
    updateState(projectPath, (current) {
      final threads = current.threads
          .where((thread) => thread.id != threadId)
          .toList(growable: false);
      if (threads.length == current.threads.length) {
        return current;
      }
      final nextRunning = Set<String>.from(current.runningThreadIds)
        ..remove(threadId);
      final nextCompleted = Set<String>.from(current.completedThreadIds)
        ..remove(threadId);
      final selectedCleared = current.selectedThreadId == threadId;
      clearedSelection = selectedCleared;
      return current.copyWith(
        threads: List<AgentThreadSummary>.unmodifiable(threads),
        runningThreadIds: nextRunning,
        completedThreadIds: nextCompleted,
        selectedThreadId: selectedCleared ? null : current.selectedThreadId,
      );
    });
    return clearedSelection;
  }

  /// 将 thread 插入列表头部（若尚不存在）。
  ///
  /// 若已存在，则只刷新 recency 并移到顶部，不覆盖运行态等字段，
  /// 避免重复 register 时把 active 状态冲成 idle。
  void prependThread({
    required String projectPath,
    required AgentThreadSummary thread,
  }) {
    updateState(projectPath, (current) {
      if (current.threads.any((item) => item.id == thread.id)) {
        return _promoteThreadInState(
          current,
          threadId: thread.id,
          activityAt: thread.recencyAt ?? thread.updatedAt,
        );
      }
      return current.copyWith(
        threads: List<AgentThreadSummary>.unmodifiable(<AgentThreadSummary>[
          thread,
          ...current.threads,
        ]),
      );
    });
  }

  /// 刷新已有 thread 的 recency，并将其移到列表顶部。
  ///
  /// 用于已有 thread 开始新 turn 时的侧栏置顶；thread 不在列表中时为 no-op。
  void promoteThread({
    required String projectPath,
    required String threadId,
    DateTime? activityAt,
  }) {
    updateState(projectPath, (current) {
      return _promoteThreadInState(
        current,
        threadId: threadId,
        activityAt: activityAt ?? DateTime.now(),
      );
    });
  }

  /// 在单次状态更新内完成 recency 刷新与置顶，避免多次 notify。
  static ProjectThreadListState _promoteThreadInState(
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
    // 已在顶部且时间戳未推进时跳过，减少无意义重建。
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

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }
}

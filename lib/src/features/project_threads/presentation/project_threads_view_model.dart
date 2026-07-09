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

  /// 只更新选中 id，用于当前 Agent 会话创建后同步高亮。
  void selectThreadId(String projectPath, String threadId) {
    updateState(
      projectPath,
      (current) => current.copyWith(selectedThreadId: threadId),
    );
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

  /// 用实时状态通知更新列表中某条 thread 的运行态与等待标志。
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
      final threads = List<AgentThreadSummary>.of(current.threads);
      threads[index] = threads[index].copyWith(
        status: status,
        waitingOnApproval: waitingOnApproval,
        waitingOnUserInput: waitingOnUserInput,
      );
      final nextRunning = Set<String>.from(current.runningThreadIds);
      if (status == AgentThreadRuntimeStatus.active) {
        nextRunning.add(threadId);
      } else {
        nextRunning.remove(threadId);
      }
      return current.copyWith(
        threads: List<AgentThreadSummary>.unmodifiable(threads),
        runningThreadIds: nextRunning,
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
      final selectedCleared = current.selectedThreadId == threadId;
      clearedSelection = selectedCleared;
      return current.copyWith(
        threads: List<AgentThreadSummary>.unmodifiable(threads),
        runningThreadIds: nextRunning,
        selectedThreadId: selectedCleared ? null : current.selectedThreadId,
      );
    });
    return clearedSelection;
  }

  /// 将 thread 插入列表头部（若尚不存在）。
  void prependThread({
    required String projectPath,
    required AgentThreadSummary thread,
  }) {
    updateState(projectPath, (current) {
      if (current.threads.any((item) => item.id == thread.id)) {
        return current;
      }
      return current.copyWith(
        threads: List<AgentThreadSummary>.unmodifiable(<AgentThreadSummary>[
          thread,
          ...current.threads,
        ]),
      );
    });
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

import 'dart:async';

import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/ui/features/ide/view_models/active_agent_provider_controller.dart';
import 'package:zeta/src/features/project_threads/domain/project_thread_list_state.dart';
import 'package:zeta/src/features/project_threads/domain/project_threads_session_snapshot.dart';
import 'package:zeta/src/features/project_threads/presentation/project_threads_view_model.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_session_snapshot_codec.dart';

final _log = loggerFor('zeta.project_threads.controller');

/// Project Threads 模块的应用层协调器。
///
/// 分页、恢复、缓存快照和 provider 交互都收敛到这里，页面层只触发动作并读取
/// [viewModel] 暴露的状态。
class ProjectThreadsController {
  ProjectThreadsController({
    required this.providerController,
    ProjectThreadsViewModel? viewModel,
  }) : viewModel = viewModel ?? ProjectThreadsViewModel();

  final ActiveAgentProviderController providerController;
  final ProjectThreadsViewModel viewModel;

  final Map<String, int> _loadTokens = <String, int>{};
  final Map<String, String> _projectPathByThreadId = <String, String>{};

  AgentProvider? _provider;
  StreamSubscription<AgentEvent>? _providerEventSubscription;
  bool _disposed = false;

  ProjectThreadListState stateFor(String projectPath) {
    return viewModel.stateFor(projectPath);
  }

  ProjectThreadsSessionSnapshot get sessionSnapshot {
    return buildProjectThreadsSessionSnapshot(viewModel.states);
  }

  /// 从 IDE 会话恢复项目 thread 状态。
  void restoreSession({
    required List<String> projectPaths,
    required String? activeProjectPath,
    required ProjectThreadsSessionSnapshot snapshot,
  }) {
    final plan = buildProjectThreadsRestorePlan(
      projectPaths: projectPaths,
      activeProjectPath: activeProjectPath,
      snapshot: snapshot,
    );
    viewModel.replaceStates(plan.states);
    for (final entry in plan.states.entries) {
      _registerStateThreadMappings(entry.key, entry.value);
    }
    if (plan.states.isNotEmpty) {
      unawaited(_ensureProviderEventSubscription());
    }
    for (final path in plan.projectsToLoad) {
      unawaited(loadInitial(path));
    }
  }

  /// 记录或激活一个项目；新项目默认展开并加载首屏。
  void activateProject(String projectPath) {
    final current = stateFor(projectPath);
    viewModel.setStateFor(projectPath, current.copyWith(isExpanded: true));
    unawaited(loadInitial(projectPath));
  }

  /// 清理已经不在项目列表中的状态。
  void retainProjects(List<String> projectPaths) {
    final allowed = projectPaths.toSet();
    final removed = viewModel.states.keys
        .where((path) => !allowed.contains(path))
        .toList();
    viewModel.retainProjects(projectPaths);
    for (final path in removed) {
      _loadTokens.remove(path);
    }
    _projectPathByThreadId.removeWhere(
      (_, projectPath) => removed.contains(projectPath),
    );
  }

  /// 点击项目时切换展开状态；展开时自动加载首屏。
  Future<void> toggleProject(String projectPath) async {
    final current = stateFor(projectPath);
    final next = current.copyWith(isExpanded: !current.isExpanded);
    viewModel.setStateFor(projectPath, next);
    if (next.isExpanded && !next.hasLoaded) {
      await loadInitial(projectPath);
    }
  }

  /// 重新加载首屏，保留旧缓存直到新数据返回。
  Future<void> loadInitial(String projectPath) {
    return _loadPage(
      projectPath: projectPath,
      limit: projectThreadInitialLimit,
      cursor: null,
      append: false,
    );
  }

  /// 追加加载下一页。
  Future<void> loadMore(String projectPath) async {
    final current = stateFor(projectPath);
    final cursor = current.nextCursor;
    if (cursor == null || current.isLoadingMore) {
      return;
    }
    await _loadPage(
      projectPath: projectPath,
      limit: projectThreadPageLimit,
      cursor: cursor,
      append: true,
    );
  }

  /// 选中某条 thread，并写入项目级选择状态。
  void selectThread(String projectPath, AgentThreadSummary thread) {
    _registerThreadMapping(projectPath, thread.id);
    selectThreadId(projectPath, thread.id);
  }

  /// 只更新选中 id，用于当前 Agent 会话创建后同步高亮。
  void selectThreadId(String projectPath, String threadId) {
    _registerThreadMapping(projectPath, threadId);
    viewModel.selectThreadId(projectPath, threadId);
  }

  /// 显式登记 thread 所属项目，供实时事件反查列表分组。
  void registerThreadMapping(String projectPath, String threadId) {
    _registerThreadMapping(projectPath, threadId);
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _provider = null;
    _loadTokens.clear();
    _projectPathByThreadId.clear();
    final subscription = _providerEventSubscription;
    _providerEventSubscription = null;
    unawaited(subscription?.cancel());
  }

  Future<void> _loadPage({
    required String projectPath,
    required int limit,
    required String? cursor,
    required bool append,
  }) async {
    final current = stateFor(projectPath);
    if (current.isLoadingInitial || current.isLoadingMore) {
      return;
    }

    final token = (_loadTokens[projectPath] ?? 0) + 1;
    _loadTokens[projectPath] = token;
    viewModel.setStateFor(
      projectPath,
      current.copyWith(
        isLoadingInitial: !append,
        isLoadingMore: append,
        errorMessage: null,
      ),
    );

    try {
      final provider = await _ensureProviderEventSubscription();
      if (provider == null) {
        return;
      }
      final page = await provider.listThreads(
        query: AgentThreadListQuery(
          projectPath: projectPath,
          limit: limit,
          cursor: cursor,
        ),
      );
      if (_loadTokens[projectPath] != token) {
        return;
      }

      final latest = stateFor(projectPath);
      _registerThreadSummaries(projectPath, page.threads);
      final threads = append
          ? _appendUnique(latest.threads, page.threads)
          : page.threads;
      viewModel.setStateFor(
        projectPath,
        latest.copyWith(
          hasLoaded: true,
          isLoadingInitial: false,
          isLoadingMore: false,
          threads: List<AgentThreadSummary>.unmodifiable(threads),
          nextCursor: page.nextCursor,
          errorMessage: null,
        ),
      );
    } catch (error, stackTrace) {
      _log.warning(
        'Could not load threads for $projectPath',
        error,
        stackTrace,
      );
      if (_loadTokens[projectPath] != token) {
        return;
      }
      final latest = stateFor(projectPath);
      viewModel.setStateFor(
        projectPath,
        latest.copyWith(
          isLoadingInitial: false,
          isLoadingMore: false,
          errorMessage: 'Could not load threads',
        ),
      );
    }
  }

  Future<AgentProvider?> _ensureProviderEventSubscription() async {
    if (_disposed) {
      return null;
    }
    final provider = await providerController.activeProvider();
    if (_disposed) {
      return null;
    }
    if (identical(provider, _provider)) {
      return provider;
    }

    final previousProvider = _provider;
    final previousSubscription = _providerEventSubscription;
    _provider = provider;
    _providerEventSubscription = provider.events.listen(_handleProviderEvent);
    await previousSubscription?.cancel();
    if (previousProvider != null) {
      _clearAllRunningThreadIds();
    }
    return provider;
  }

  void _handleProviderEvent(AgentEvent event) {
    switch (event) {
      case AgentTurnStartedEvent():
        _setThreadRunning(event.turn.sessionId, isRunning: true);
      case AgentTurnCompletedEvent():
        _setThreadRunning(event.sessionId, isRunning: false);
      default:
        return;
    }
  }

  void _setThreadRunning(String threadId, {required bool isRunning}) {
    final projectPath = _projectPathByThreadId[threadId];
    if (projectPath == null) {
      return;
    }

    final current = stateFor(projectPath);
    final nextRunningThreadIds = Set<String>.from(current.runningThreadIds);
    final changed = isRunning
        ? nextRunningThreadIds.add(threadId)
        : nextRunningThreadIds.remove(threadId);
    if (!changed) {
      return;
    }
    viewModel.setRunningThreadIds(projectPath, nextRunningThreadIds);
  }

  void _registerStateThreadMappings(
    String projectPath,
    ProjectThreadListState state,
  ) {
    _registerThreadSummaries(projectPath, state.threads);
    final selectedThreadId = state.selectedThreadId;
    if (selectedThreadId != null) {
      _registerThreadMapping(projectPath, selectedThreadId);
    }
  }

  void _registerThreadSummaries(
    String projectPath,
    Iterable<AgentThreadSummary> threads,
  ) {
    for (final thread in threads) {
      _registerThreadMapping(projectPath, thread.id);
    }
  }

  void _registerThreadMapping(String projectPath, String threadId) {
    _projectPathByThreadId[threadId] = projectPath;
  }

  void _clearAllRunningThreadIds() {
    for (final entry in viewModel.states.entries) {
      if (entry.value.runningThreadIds.isEmpty) {
        continue;
      }
      viewModel.setRunningThreadIds(entry.key, const <String>{});
    }
  }

  List<AgentThreadSummary> _appendUnique(
    List<AgentThreadSummary> existing,
    List<AgentThreadSummary> incoming,
  ) {
    final seen = existing.map((thread) => thread.id).toSet();
    return <AgentThreadSummary>[
      ...existing,
      for (final thread in incoming)
        if (seen.add(thread.id)) thread,
    ];
  }
}

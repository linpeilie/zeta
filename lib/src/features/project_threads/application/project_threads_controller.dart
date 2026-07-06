import 'dart:async';

import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
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
    selectThreadId(projectPath, thread.id);
  }

  /// 只更新选中 id，用于当前 Agent 会话创建后同步高亮。
  void selectThreadId(String projectPath, String threadId) {
    viewModel.selectThreadId(projectPath, threadId);
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
      final provider = await providerController.activeProvider();
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

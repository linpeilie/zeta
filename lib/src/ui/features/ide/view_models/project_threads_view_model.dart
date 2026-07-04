import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../../../core/logging/app_logging.dart';
import '../../../../domain/agent/agent_models.dart';
import 'active_agent_provider_controller.dart';

final _log = loggerFor('zeta.ui.project_threads');

const int projectThreadInitialLimit = 5;
const int projectThreadPageLimit = 10;

const Object _unset = Object();

/// 单个项目下 thread 列表的展示状态。
class ProjectThreadListState {
  const ProjectThreadListState({
    this.isExpanded = false,
    this.hasLoaded = false,
    this.isLoadingInitial = false,
    this.isLoadingMore = false,
    this.threads = const <AgentThreadSummary>[],
    this.nextCursor,
    this.errorMessage,
    this.selectedThreadId,
  });

  /// 项目下 thread 列表是否展开。
  final bool isExpanded;

  /// 是否至少完成过一次首屏加载。
  final bool hasLoaded;

  /// 是否正在刷新首屏。
  final bool isLoadingInitial;

  /// 是否正在追加下一页。
  final bool isLoadingMore;

  /// 已加载的 thread 摘要。
  final List<AgentThreadSummary> threads;

  /// 下一页游标，空表示没有更多。
  final String? nextCursor;

  /// 最近一次加载错误；保留已有 thread 缓存。
  final String? errorMessage;

  /// 当前项目选中的 thread id。
  final String? selectedThreadId;

  bool get hasMore => nextCursor != null;

  ProjectThreadListState copyWith({
    bool? isExpanded,
    bool? hasLoaded,
    bool? isLoadingInitial,
    bool? isLoadingMore,
    List<AgentThreadSummary>? threads,
    Object? nextCursor = _unset,
    Object? errorMessage = _unset,
    Object? selectedThreadId = _unset,
  }) {
    return ProjectThreadListState(
      isExpanded: isExpanded ?? this.isExpanded,
      hasLoaded: hasLoaded ?? this.hasLoaded,
      isLoadingInitial: isLoadingInitial ?? this.isLoadingInitial,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      threads: threads ?? this.threads,
      nextCursor: identical(nextCursor, _unset)
          ? this.nextCursor
          : nextCursor as String?,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      selectedThreadId: identical(selectedThreadId, _unset)
          ? this.selectedThreadId
          : selectedThreadId as String?,
    );
  }
}

/// 项目列表下 thread 分页状态的协调器。
class ProjectThreadsViewModel extends ChangeNotifier {
  ProjectThreadsViewModel({required this.providerController});

  final ActiveAgentProviderController providerController;

  final Map<String, ProjectThreadListState> _states =
      <String, ProjectThreadListState>{};
  final Map<String, int> _loadTokens = <String, int>{};
  bool _disposed = false;

  /// 所有项目的 thread 状态快照。
  Map<String, ProjectThreadListState> get states =>
      UnmodifiableMapView<String, ProjectThreadListState>(_states);

  /// 会话持久化使用的展开状态。
  Map<String, bool> get projectExpansionByProject {
    return <String, bool>{
      for (final entry in _states.entries) entry.key: entry.value.isExpanded,
    };
  }

  /// 会话持久化使用的 thread 摘要缓存。
  Map<String, List<AgentThreadSummary>> get cachedThreadsByProject {
    return <String, List<AgentThreadSummary>>{
      for (final entry in _states.entries)
        if (entry.value.threads.isNotEmpty)
          entry.key: List<AgentThreadSummary>.unmodifiable(entry.value.threads),
    };
  }

  /// 会话持久化使用的当前选中 thread。
  Map<String, String> get selectedThreadIdsByProject {
    return <String, String>{
      for (final entry in _states.entries)
        if (entry.value.selectedThreadId != null)
          entry.key: entry.value.selectedThreadId!,
    };
  }

  ProjectThreadListState stateFor(String projectPath) {
    return _states[projectPath] ?? const ProjectThreadListState();
  }

  /// 从 IDE 会话恢复项目 thread 状态。
  void restoreSession({
    required List<String> projectPaths,
    required String? activeProjectPath,
    required Map<String, bool> expansionByProject,
    required Map<String, List<AgentThreadSummary>> cachedThreadsByProject,
    required Map<String, String> selectedThreadIdsByProject,
  }) {
    _states.clear();
    for (final path in projectPaths) {
      final cachedThreads = cachedThreadsByProject[path] ?? const [];
      final isExpanded = expansionByProject[path] ?? path == activeProjectPath;
      _states[path] = ProjectThreadListState(
        isExpanded: isExpanded,
        hasLoaded: cachedThreads.isNotEmpty,
        threads: List<AgentThreadSummary>.unmodifiable(cachedThreads),
        selectedThreadId: selectedThreadIdsByProject[path],
      );
    }
    _notify();
    for (final path in projectPaths) {
      if (stateFor(path).isExpanded) {
        unawaited(loadInitial(path));
      }
    }
  }

  /// 记录或激活一个项目；新项目默认展开并加载首屏。
  void activateProject(String projectPath) {
    final current = stateFor(projectPath);
    _states[projectPath] = current.copyWith(isExpanded: true);
    _notify();
    unawaited(loadInitial(projectPath));
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
      _loadTokens.remove(path);
    }
    _notify();
  }

  /// 点击项目时切换展开状态；展开时自动加载首屏。
  Future<void> toggleProject(String projectPath) async {
    final current = stateFor(projectPath);
    final next = current.copyWith(isExpanded: !current.isExpanded);
    _states[projectPath] = next;
    _notify();
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
    final current = stateFor(projectPath);
    _states[projectPath] = current.copyWith(selectedThreadId: threadId);
    _notify();
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
    _states[projectPath] = current.copyWith(
      isLoadingInitial: !append,
      isLoadingMore: append,
      errorMessage: null,
    );
    _notify();

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
      _states[projectPath] = latest.copyWith(
        hasLoaded: true,
        isLoadingInitial: false,
        isLoadingMore: false,
        threads: List<AgentThreadSummary>.unmodifiable(threads),
        nextCursor: page.nextCursor,
        errorMessage: null,
      );
      _notify();
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
      _states[projectPath] = latest.copyWith(
        isLoadingInitial: false,
        isLoadingMore: false,
        errorMessage: 'Could not load threads',
      );
      _notify();
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

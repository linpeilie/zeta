import 'package:zeta_agent_core/zeta_agent_core.dart';

const Object projectThreadUnset = Object();

const int projectThreadInitialLimit = 5;
const int projectThreadPageLimit = 10;

/// 单个项目下 thread 列表的展示状态。
class ProjectThreadListState {
  const ProjectThreadListState({
    this.isExpanded = false,
    this.hasLoaded = false,
    this.isLoadingInitial = false,
    this.isLoadingMore = false,
    this.threads = const <AgentThreadSummary>[],
    this.runningThreadIds = const <String>{},
    this.completedThreadIds = const <String>{},
    this.nextCursor,
    this.errorMessage,
    this.selectedThreadId,
    this.archived = false,
    this.searchTerm = '',
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

  /// 当前项目内临时标记为执行中的 thread id。
  final Set<String> runningThreadIds;

  /// 后台执行结束后、尚未被用户确认的 thread id（仅内存态，不持久化）。
  ///
  /// 用于在列表原「执行中」位置展示绿色完成提示；点击或选中该 thread 后清除。
  final Set<String> completedThreadIds;

  /// 下一页游标，空表示没有更多。
  final String? nextCursor;

  /// 最近一次加载错误；保留已有 thread 缓存。
  final String? errorMessage;

  /// 当前项目下被全局选中的 thread id。
  ///
  /// 运行时全局至多一个项目持有非空值；其它项目必须为 null，以保证侧栏只有一条选中样式。
  final String? selectedThreadId;

  /// 是否显示已归档线程（对应 `thread/list` 的 `archived`）。
  final bool archived;

  /// 标题搜索词（对应协议 `searchTerm`）。
  final String searchTerm;

  bool get hasMore => nextCursor != null;

  /// Zeta 本进程是否将该 thread 视为 live 执行中（列表 busy 指示真源）。
  bool isThreadRunning(String threadId) => runningThreadIds.contains(threadId);

  ProjectThreadListState copyWith({
    bool? isExpanded,
    bool? hasLoaded,
    bool? isLoadingInitial,
    bool? isLoadingMore,
    List<AgentThreadSummary>? threads,
    Set<String>? runningThreadIds,
    Set<String>? completedThreadIds,
    Object? nextCursor = projectThreadUnset,
    Object? errorMessage = projectThreadUnset,
    Object? selectedThreadId = projectThreadUnset,
    bool? archived,
    String? searchTerm,
  }) {
    return ProjectThreadListState(
      isExpanded: isExpanded ?? this.isExpanded,
      hasLoaded: hasLoaded ?? this.hasLoaded,
      isLoadingInitial: isLoadingInitial ?? this.isLoadingInitial,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      threads: threads ?? this.threads,
      runningThreadIds: runningThreadIds == null
          ? this.runningThreadIds
          : Set<String>.unmodifiable(runningThreadIds),
      completedThreadIds: completedThreadIds == null
          ? this.completedThreadIds
          : Set<String>.unmodifiable(completedThreadIds),
      nextCursor: identical(nextCursor, projectThreadUnset)
          ? this.nextCursor
          : nextCursor as String?,
      errorMessage: identical(errorMessage, projectThreadUnset)
          ? this.errorMessage
          : errorMessage as String?,
      selectedThreadId: identical(selectedThreadId, projectThreadUnset)
          ? this.selectedThreadId
          : selectedThreadId as String?,
      archived: archived ?? this.archived,
      searchTerm: searchTerm ?? this.searchTerm,
    );
  }
}

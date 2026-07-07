import 'package:zeta/src/features/agent/domain/agent_models.dart';

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

  /// 当前项目内临时标记为执行中的 thread id。
  final Set<String> runningThreadIds;

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
    Set<String>? runningThreadIds,
    Object? nextCursor = projectThreadUnset,
    Object? errorMessage = projectThreadUnset,
    Object? selectedThreadId = projectThreadUnset,
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
      nextCursor: identical(nextCursor, projectThreadUnset)
          ? this.nextCursor
          : nextCursor as String?,
      errorMessage: identical(errorMessage, projectThreadUnset)
          ? this.errorMessage
          : errorMessage as String?,
      selectedThreadId: identical(selectedThreadId, projectThreadUnset)
          ? this.selectedThreadId
          : selectedThreadId as String?,
    );
  }
}

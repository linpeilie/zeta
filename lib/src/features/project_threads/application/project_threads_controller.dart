import 'dart:async';

import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/agent/application/agent_provider_event_listener_gate.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/ui/features/ide/view_models/active_agent_provider_controller.dart';
import 'package:zeta/src/features/project_threads/domain/project_thread_list_state.dart';
import 'package:zeta/src/features/project_threads/domain/project_threads_session_snapshot.dart';
import 'package:zeta/src/features/project_threads/presentation/project_threads_view_model.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_session_snapshot_codec.dart';

final _log = loggerFor('zeta.project_threads.controller');

/// 搜索输入防抖时长。
const Duration projectThreadSearchDebounce = Duration(milliseconds: 300);

/// 聚合列表时每个 provider 最多拉取的 thread 条数上限。
const int projectThreadPerProviderFetchCap = 50;

/// 聚合分页游标前缀（客户端 offset）。
const String _aggregateCursorPrefix = 'agg:';

/// Project Threads 模块的应用层协调器。
///
/// 分页、恢复、缓存快照和 provider 交互都收敛到这里，页面层只触发动作并读取
/// [viewModel] 暴露的状态。
class ProjectThreadsController {
  ProjectThreadsController({
    required this.providerController,
    ProjectThreadsViewModel? viewModel,
  }) : viewModel = viewModel ?? ProjectThreadsViewModel() {
    // active provider 切换后必须重绑事件流，否则列表收不到 TurnStarted，侧栏无执行动画。
    providerController.addListener(_handleProviderControllerChanged);
  }

  final ActiveAgentProviderController providerController;
  final ProjectThreadsViewModel viewModel;

  final Map<String, int> _loadTokens = <String, int>{};
  final Map<String, String> _projectPathByThreadId = <String, String>{};
  final Map<String, Timer> _searchDebounceTimers = <String, Timer>{};

  AgentProvider? _provider;
  StreamSubscription<AgentEvent>? _providerEventSubscription;
  final AgentProviderEventListenerGate _providerEventListenerGate =
      AgentProviderEventListenerGate();
  bool _disposed = false;

  /// 当前会话因删除/归档/关闭而被清空时回调（projectPath, threadId）。
  void Function(String projectPath, String threadId)? onActiveThreadCleared;

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
      _searchDebounceTimers.remove(path)?.cancel();
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

  /// 切换活动/已归档视图并重新加载。
  Future<void> setArchivedView({
    required String projectPath,
    required bool archived,
  }) async {
    final current = stateFor(projectPath);
    if (current.archived == archived) {
      return;
    }
    viewModel.setStateFor(
      projectPath,
      current.copyWith(
        archived: archived,
        hasLoaded: false,
        threads: const <AgentThreadSummary>[],
        nextCursor: null,
        selectedThreadId: null,
      ),
    );
    await loadInitial(projectPath);
  }

  /// 更新搜索词；防抖后重新加载首屏。
  void setSearchTerm({
    required String projectPath,
    required String searchTerm,
  }) {
    final current = stateFor(projectPath);
    if (current.searchTerm == searchTerm) {
      return;
    }
    viewModel.setStateFor(
      projectPath,
      current.copyWith(searchTerm: searchTerm),
    );
    _searchDebounceTimers.remove(projectPath)?.cancel();
    _searchDebounceTimers[projectPath] = Timer(projectThreadSearchDebounce, () {
      _searchDebounceTimers.remove(projectPath);
      if (_disposed) {
        return;
      }
      unawaited(loadInitial(projectPath));
    });
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

  /// 选中某条 thread，并写入全局唯一选择状态（跨项目互斥高亮）。
  void selectThread(String projectPath, AgentThreadSummary thread) {
    _registerThreadMapping(projectPath, thread.id);
    selectThreadId(projectPath, thread.id);
  }

  /// 更新选中 id 并同步高亮；会清除其他项目的选中态。
  void selectThreadId(String projectPath, String threadId) {
    _registerThreadMapping(projectPath, threadId);
    viewModel.selectThreadId(projectPath, threadId);
  }

  /// 清空指定项目的 thread 选中态，用于切换到全新的会话草稿。
  void clearSelectedThread(String projectPath) {
    viewModel.clearSelectedThreadId(projectPath);
  }

  /// 显式登记 thread 所属项目，供实时事件反查列表分组。
  void registerThreadMapping(String projectPath, String threadId) {
    _registerThreadMapping(projectPath, threadId);
  }

  /// 登记 provider 已创建或恢复成功的 session，并立即缓存其 provider 归属。
  ///
  /// 这样新 thread 无需等待下一次列表刷新，也能以完整摘要参与会话持久化和恢复。
  ///
  /// [preview] 可传入首条用户消息等临时摘要，避免列表在 generated_title
  /// 写入前只能显示短 id。
  ///
  /// [markRunning] 为 true 时乐观写入执行中指示（新建 thread 首条消息场景），
  /// 避免 active provider 事件订阅尚未跟上时侧栏无转圈动画。
  void registerSession(
    String projectPath,
    AgentSession session, {
    String? preview,
    bool markRunning = false,
  }) {
    _registerThreadMapping(projectPath, session.id);
    final resolvedPreview = (preview ?? session.title ?? '').trim();
    // title 只在 provider 已给出正式名时写入；首条用户消息只放 preview，
    // 避免把临时文案写进 title 后挡住后续 generated_title 覆盖观感。
    viewModel.prependThread(
      projectPath: projectPath,
      thread: AgentThreadSummary(
        id: session.id,
        providerId: session.providerId,
        projectPath: projectPath,
        title: session.title,
        preview: resolvedPreview,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        status: AgentThreadRuntimeStatus.idle,
        raw: session.raw,
      ),
    );
    if (session.title != null && session.title!.trim().isNotEmpty) {
      viewModel.updateThreadTitle(
        projectPath: projectPath,
        threadId: session.id,
        title: session.title,
      );
    }
    selectThreadId(projectPath, session.id);
    if (markRunning) {
      _setThreadRunning(session.id, isRunning: true);
    }
    // 新 session 往往伴随 active provider 刚切换；立刻挂上事件流接收 TurnStarted。
    unawaited(_ensureProviderEventSubscription());
  }

  /// 由详情侧 turn 状态同步列表执行中指示（不依赖 provider 事件是否已送达）。
  void setThreadRunning(String threadId, {required bool isRunning}) {
    _setThreadRunning(threadId, isRunning: isRunning);
  }

  /// 更新列表中某条 thread 的标题（供 shell 从详情侧回写）。
  void updateThreadTitle({
    required String projectPath,
    required String threadId,
    required String? title,
  }) {
    _registerThreadMapping(projectPath, threadId);
    viewModel.updateThreadTitle(
      projectPath: projectPath,
      threadId: threadId,
      title: title,
    );
  }

  /// 重命名 thread；乐观更新标题，以 `thread/name/updated` 为准。
  Future<void> renameThread({
    required String projectPath,
    required String threadId,
    required String name,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final provider = await _providerForThread(
      projectPath: projectPath,
      threadId: threadId,
    );
    if (provider == null) {
      return;
    }
    _requireCapability(
      provider: provider,
      supported: provider.capabilities.canRenameThread,
      operation: 'rename threads',
    );
    viewModel.updateThreadTitle(
      projectPath: projectPath,
      threadId: threadId,
      title: trimmed,
    );
    await provider.renameThread(threadId: threadId, name: trimmed);
  }

  /// 归档 thread。
  Future<void> archiveThread({
    required String projectPath,
    required String threadId,
  }) async {
    final provider = await _providerForThread(
      projectPath: projectPath,
      threadId: threadId,
    );
    if (provider == null) {
      return;
    }
    _requireCapability(
      provider: provider,
      supported: provider.capabilities.canArchiveThread,
      operation: 'archive threads',
    );
    await provider.archiveThread(threadId);
    _removeThreadFromList(
      projectPath: projectPath,
      threadId: threadId,
      notifyCleared: true,
    );
  }

  /// 取消归档 thread。
  Future<void> unarchiveThread({
    required String projectPath,
    required String threadId,
  }) async {
    final provider = await _providerForThread(
      projectPath: projectPath,
      threadId: threadId,
    );
    if (provider == null) {
      return;
    }
    _requireCapability(
      provider: provider,
      supported: provider.capabilities.canUnarchiveThread,
      operation: 'unarchive threads',
    );
    await provider.unarchiveThread(threadId);
    _removeThreadFromList(
      projectPath: projectPath,
      threadId: threadId,
      notifyCleared: true,
    );
  }

  /// 删除 provider 端 thread；若只支持本地索引，则仅从 Zeta 列表移除。
  Future<void> deleteThread({
    required String projectPath,
    required String threadId,
  }) async {
    final provider = await _providerForThread(
      projectPath: projectPath,
      threadId: threadId,
    );
    if (provider == null) {
      return;
    }
    if (provider.capabilities.canDeleteThread) {
      await provider.deleteThread(threadId);
    } else if (provider.capabilities.canRemoveThreadFromList &&
        provider is AgentLocalThreadListProvider) {
      await (provider as AgentLocalThreadListProvider).removeThreadFromList(
        threadId,
      );
    } else {
      _requireCapability(
        provider: provider,
        supported: false,
        operation: 'delete or remove threads',
      );
    }
    _removeThreadFromList(
      projectPath: projectPath,
      threadId: threadId,
      notifyCleared: true,
    );
  }

  /// 分叉 thread，返回新会话；调用方负责切换 Agent 面板。
  Future<AgentSession?> forkThread({
    required String projectPath,
    required String threadId,
  }) async {
    final provider = await _providerForThread(
      projectPath: projectPath,
      threadId: threadId,
    );
    if (provider == null) {
      return null;
    }
    _requireCapability(
      provider: provider,
      supported: provider.capabilities.canForkThread,
      operation: 'fork threads',
    );
    final session = await provider.forkThread(
      threadId: threadId,
      context: AgentContext(projectPath: projectPath),
    );
    _registerThreadMapping(projectPath, session.id);
    viewModel.prependThread(
      projectPath: projectPath,
      thread: AgentThreadSummary(
        id: session.id,
        providerId: session.providerId,
        projectPath: projectPath,
        title: session.title,
        preview: session.title ?? '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        status: AgentThreadRuntimeStatus.idle,
      ),
    );
    selectThreadId(projectPath, session.id);
    return session;
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _providerEventListenerGate.invalidate();
    providerController.removeListener(_handleProviderControllerChanged);
    _provider = null;
    _loadTokens.clear();
    _projectPathByThreadId.clear();
    for (final timer in _searchDebounceTimers.values) {
      timer.cancel();
    }
    _searchDebounceTimers.clear();
    final subscription = _providerEventSubscription;
    _providerEventSubscription = null;
    unawaited(subscription?.cancel());
  }

  void _handleProviderControllerChanged() {
    if (_disposed) {
      return;
    }
    unawaited(_ensureProviderEventSubscription());
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
      // 保证 active provider 事件订阅仍在（运行中指示等）。
      await _ensureProviderEventSubscription();
      if (_disposed) {
        return;
      }

      final searchTerm = current.searchTerm.trim();
      final page = await _listThreadsAcrossProviders(
        projectPath: projectPath,
        limit: limit,
        cursor: cursor,
        archived: current.archived,
        searchTerm: searchTerm.isEmpty ? null : searchTerm,
      );
      if (_loadTokens[projectPath] != token) {
        return;
      }

      final latest = stateFor(projectPath);
      // 全部 provider 失败时保留已有缓存，仅更新错误态。
      if (page.threads.isEmpty &&
          page.errorMessage != null &&
          latest.threads.isNotEmpty) {
        viewModel.setStateFor(
          projectPath,
          latest.copyWith(
            isLoadingInitial: false,
            isLoadingMore: false,
            errorMessage: page.errorMessage,
          ),
        );
        return;
      }

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
          errorMessage: page.errorMessage,
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

  /// 从所有已启用 provider 拉取 thread，保证首页可见后再按 recency 分页。
  Future<_AggregatedThreadPage> _listThreadsAcrossProviders({
    required String projectPath,
    required int limit,
    required String? cursor,
    required bool archived,
    required String? searchTerm,
  }) async {
    await providerController.loadSettings();
    final enabled = providerController.enabledProviders;
    if (enabled.isEmpty) {
      return const _AggregatedThreadPage(
        threads: <AgentThreadSummary>[],
        nextCursor: null,
        errorMessage: 'No enabled Agent providers',
      );
    }

    final threadsByProviderId = <String, List<AgentThreadSummary>>{};
    final failures = <String>[];

    await Future.wait(
      enabled.map((config) async {
        final staticCapabilities = providerController.capabilitiesForProviderId(
          config.id,
        );
        if (!staticCapabilities.canListThreads) {
          return;
        }
        AgentProvider? opened;
        var shouldDispose = false;
        try {
          opened = await providerController.openProvider(config);
          shouldDispose = !providerController.isSharedActiveProvider(opened);
          final collected = await _collectProviderThreads(
            provider: opened,
            projectPath: projectPath,
            archived: archived,
            searchTerm: searchTerm,
          );
          threadsByProviderId[config.id] = collected;
        } catch (error, stackTrace) {
          _log.warning(
            'Could not list threads from ${config.id}',
            error,
            stackTrace,
          );
          failures.add(config.displayName);
        } finally {
          if (shouldDispose) {
            await opened?.dispose();
          }
        }
      }),
    );

    final merged = _prioritizeProviderHeads(
      enabled: enabled,
      threadsByProviderId: threadsByProviderId,
    );

    final offset = appendOffsetFromCursor(cursor);
    // Provider 数量超过默认页大小时仍保证每个有结果的 provider 至少出现一条。
    final providerCount = threadsByProviderId.values
        .where((threads) => threads.isNotEmpty)
        .length;
    final pageLimit = offset == 0 && providerCount > limit
        ? providerCount
        : limit;
    final pageThreads = merged
        .skip(offset)
        .take(pageLimit)
        .toList(growable: false);
    final nextOffset = offset + pageThreads.length;
    final nextCursor = nextOffset < merged.length
        ? '$_aggregateCursorPrefix$nextOffset'
        : null;

    String? errorMessage;
    if (merged.isEmpty && failures.isNotEmpty) {
      errorMessage = 'Could not load threads';
    } else if (failures.isNotEmpty && pageThreads.isNotEmpty) {
      // 部分 provider 失败时仍展示成功部分。
      errorMessage = null;
    }

    final counts = <String>[
      for (final config in enabled)
        '${config.id}:${threadsByProviderId[config.id]?.length ?? 0}',
    ].join(',');
    _log.info(
      'Aggregated project threads for $projectPath '
      'providers=[$counts] total=${merged.length} offset=$offset '
      'page=${pageThreads.length} next=${nextCursor != null}',
    );

    return _AggregatedThreadPage(
      threads: pageThreads,
      nextCursor: nextCursor,
      errorMessage: errorMessage,
    );
  }

  /// 单个 provider 拉取至多 [projectThreadPerProviderFetchCap] 条。
  Future<List<AgentThreadSummary>> _collectProviderThreads({
    required AgentProvider provider,
    required String projectPath,
    required bool archived,
    required String? searchTerm,
  }) async {
    final collected = <AgentThreadSummary>[];
    String? pageCursor;
    final seenIds = <String>{};

    while (collected.length < projectThreadPerProviderFetchCap) {
      final remaining = projectThreadPerProviderFetchCap - collected.length;
      final pageLimit = remaining < projectThreadPageLimit
          ? remaining
          : projectThreadPageLimit;
      final page = await provider.listThreads(
        query: AgentThreadListQuery(
          projectPath: projectPath,
          limit: pageLimit,
          cursor: pageCursor,
          archived: archived,
          searchTerm: searchTerm,
        ),
      );
      if (page.threads.isEmpty) {
        break;
      }
      for (final thread in page.threads) {
        if (seenIds.add(thread.id)) {
          collected.add(thread);
        }
      }
      pageCursor = page.nextCursor;
      if (pageCursor == null) {
        break;
      }
    }
    return collected;
  }

  void _requireCapability({
    required AgentProvider provider,
    required bool supported,
    required String operation,
  }) {
    if (!supported) {
      throw UnsupportedError(
        '${provider.config.displayName} does not support $operation',
      );
    }
  }

  /// 解析聚合游标；非法或空时从 0 开始。
  static int appendOffsetFromCursor(String? cursor) {
    if (cursor == null || cursor.isEmpty) {
      return 0;
    }
    if (!cursor.startsWith(_aggregateCursorPrefix)) {
      // 兼容旧单 provider 游标：聚合模式下视为首页。
      return 0;
    }
    return int.tryParse(cursor.substring(_aggregateCursorPrefix.length)) ?? 0;
  }

  static int _compareThreadRecency(AgentThreadSummary a, AgentThreadSummary b) {
    final aTime = a.recencyAt ?? a.updatedAt;
    final bTime = b.recencyAt ?? b.updatedAt;
    final byTime = bTime.compareTo(aTime);
    if (byTime != 0) {
      return byTime;
    }
    // 稳定次序：providerId 再 id。
    final byProvider = a.providerId.compareTo(b.providerId);
    if (byProvider != 0) {
      return byProvider;
    }
    return a.id.compareTo(b.id);
  }

  /// 先放入每个 provider 最新的一条，再按全局时间排列其余条目。
  ///
  /// 这样既保留统一时间线，也避免历史较旧的 Cursor/Grok 会话一直被 Codex 首页
  /// 挤到后续分页。相同输入会得到稳定顺序，因此聚合游标仍可安全复用。
  static List<AgentThreadSummary> _prioritizeProviderHeads({
    required List<AgentProviderConfig> enabled,
    required Map<String, List<AgentThreadSummary>> threadsByProviderId,
  }) {
    final heads = <AgentThreadSummary>[];
    final remaining = <AgentThreadSummary>[];
    for (final config in enabled) {
      final threads = List<AgentThreadSummary>.from(
        threadsByProviderId[config.id] ?? const <AgentThreadSummary>[],
      )..sort(_compareThreadRecency);
      if (threads.isEmpty) {
        continue;
      }
      heads.add(threads.first);
      remaining.addAll(threads.skip(1));
    }
    heads.sort(_compareThreadRecency);
    remaining.sort(_compareThreadRecency);
    return <AgentThreadSummary>[...heads, ...remaining];
  }

  Future<AgentProvider?> _ensureProviderEventSubscription() async {
    if (_disposed) {
      return null;
    }
    final provider = await providerController.activeProvider();
    if (_disposed) {
      return null;
    }
    if (identical(provider, _provider) &&
        _hasCurrentProviderEventListener(provider)) {
      return provider;
    }

    final previousProvider = _provider;
    final previousSubscription = _providerEventSubscription;
    final scope = _providerEventListenerGate.activate(
      providerId: provider.config.id,
      threadId: null,
      runtimeScope: _runtimeScopeOf(provider),
    );
    _provider = provider;
    StreamSubscription<AgentEvent>? subscription;
    subscription = provider.events.listen(
      (event) {
        if (_disposed || !identical(_provider, provider)) {
          return;
        }
        if (!_providerEventListenerGate.accepts(
          scope,
          currentRuntimeScope: _runtimeScopeOf(provider),
          allowDetachedRuntime: _isProjectThreadTerminalEvent(event),
        )) {
          return;
        }
        _handleProviderEvent(event);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!_providerEventListenerGate.accepts(
          scope,
          currentRuntimeScope: _runtimeScopeOf(provider),
          allowDetachedRuntime: true,
        )) {
          return;
        }
        _log.warning(
          'Project thread provider event stream failed',
          error,
          stackTrace,
        );
      },
      onDone: () {
        if (!_providerEventListenerGate.release(scope)) {
          return;
        }
        if (identical(_providerEventSubscription, subscription)) {
          _providerEventSubscription = null;
        }
      },
    );
    _providerEventSubscription = subscription;
    await previousSubscription?.cancel();
    // 仅清理「旧 provider 名下」的执行中标记。同 id 重建实例时保留乐观 running，
    // 避免新建 thread 刚 markRunning 就被整表清空导致侧栏无转圈。
    if (previousProvider != null &&
        previousProvider.config.id != provider.config.id) {
      _clearRunningThreadIdsOwnedByProvider(previousProvider.config.id);
    }
    return provider;
  }

  AgentRuntimeScope? _runtimeScopeOf(AgentProvider provider) {
    if (provider case final AgentRuntimeScopeProvider scopedProvider) {
      return scopedProvider.runtimeScope;
    }
    return null;
  }

  bool _hasCurrentProviderEventListener(AgentProvider provider) {
    final scope = _providerEventListenerGate.current;
    if (scope == null || scope.providerId != provider.config.id) {
      return false;
    }
    final expectedRuntime = scope.runtimeScope;
    if (expectedRuntime == null) {
      return true;
    }
    return expectedRuntime == _runtimeScopeOf(provider);
  }

  bool _isProjectThreadTerminalEvent(AgentEvent event) {
    return event is AgentTurnStartedEvent ||
        event is AgentTurnCompletedEvent ||
        event is AgentThreadStatusChangedEvent ||
        event is AgentThreadNameUpdatedEvent ||
        event is AgentThreadArchivedEvent ||
        event is AgentThreadUnarchivedEvent ||
        event is AgentThreadDeletedEvent ||
        event is AgentThreadClosedEvent;
  }

  /// 解析 thread 所属 provider；必要时切换 active 以便后续写操作落到正确后端。
  Future<AgentProvider?> _providerForThread({
    required String projectPath,
    required String threadId,
  }) async {
    final ownerId = _providerIdForThread(projectPath, threadId);
    if (ownerId != null &&
        ownerId != providerController.activeProviderId &&
        providerController.isProviderEnabled(ownerId)) {
      try {
        await providerController.setActiveProvider(ownerId);
      } catch (error, stackTrace) {
        _log.warning(
          'Could not switch active provider to $ownerId for thread $threadId',
          error,
          stackTrace,
        );
      }
    }
    return _ensureProviderEventSubscription();
  }

  String? _providerIdForThread(String projectPath, String threadId) {
    for (final thread in stateFor(projectPath).threads) {
      if (thread.id == threadId) {
        return thread.providerId;
      }
    }
    return null;
  }

  void _handleProviderEvent(AgentEvent event) {
    switch (event) {
      case AgentTurnStartedEvent():
        _setThreadRunning(event.turn.sessionId, isRunning: true);
      case AgentTurnCompletedEvent():
        _setThreadRunning(event.sessionId, isRunning: false);
      case AgentThreadStatusChangedEvent():
        _applyThreadStatusChanged(event);
      case AgentThreadNameUpdatedEvent():
        _applyThreadNameUpdated(event);
      case AgentThreadArchivedEvent():
        _applyThreadRemoved(event.threadId, notifyCleared: true);
      case AgentThreadUnarchivedEvent():
        _applyThreadRemoved(event.threadId, notifyCleared: true);
      case AgentThreadDeletedEvent():
        _applyThreadRemoved(event.threadId, notifyCleared: true);
      case AgentThreadClosedEvent():
        _setThreadRunning(event.threadId, isRunning: false);
        _applyThreadClosed(event.threadId);
      default:
        return;
    }
  }

  void _applyThreadStatusChanged(AgentThreadStatusChangedEvent event) {
    final projectPath = _projectPathByThreadId[event.threadId];
    if (projectPath == null) {
      return;
    }
    viewModel.updateThreadRuntimeStatus(
      projectPath: projectPath,
      threadId: event.threadId,
      status: event.status,
      waitingOnApproval: event.waitingOnApproval,
      waitingOnUserInput: event.waitingOnUserInput,
    );
  }

  void _applyThreadNameUpdated(AgentThreadNameUpdatedEvent event) {
    final projectPath = _projectPathByThreadId[event.threadId];
    if (projectPath == null) {
      return;
    }
    viewModel.updateThreadTitle(
      projectPath: projectPath,
      threadId: event.threadId,
      title: event.threadName,
    );
  }

  void _applyThreadRemoved(String threadId, {required bool notifyCleared}) {
    final projectPath = _projectPathByThreadId[threadId];
    if (projectPath == null) {
      return;
    }
    _removeThreadFromList(
      projectPath: projectPath,
      threadId: threadId,
      notifyCleared: notifyCleared,
    );
  }

  void _applyThreadClosed(String threadId) {
    final projectPath = _projectPathByThreadId[threadId];
    if (projectPath == null) {
      return;
    }
    final current = stateFor(projectPath);
    final nextRunning = Set<String>.from(current.runningThreadIds)
      ..remove(threadId);
    if (nextRunning.length != current.runningThreadIds.length) {
      viewModel.setRunningThreadIds(projectPath, nextRunning);
    }
  }

  void _removeThreadFromList({
    required String projectPath,
    required String threadId,
    required bool notifyCleared,
  }) {
    final cleared = viewModel.removeThread(
      projectPath: projectPath,
      threadId: threadId,
    );
    _projectPathByThreadId.remove(threadId);
    if (cleared && notifyCleared) {
      onActiveThreadCleared?.call(projectPath, threadId);
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

  /// 去掉属于 [providerId] 的 thread 的执行中标记（切换 active provider 时用）。
  void _clearRunningThreadIdsOwnedByProvider(String providerId) {
    for (final entry in viewModel.states.entries) {
      final state = entry.value;
      if (state.runningThreadIds.isEmpty) {
        continue;
      }
      final ownedIds = <String>{
        for (final thread in state.threads)
          if (thread.providerId == providerId) thread.id,
      };
      if (ownedIds.isEmpty) {
        continue;
      }
      final nextRunning = state.runningThreadIds
          .where((threadId) => !ownedIds.contains(threadId))
          .toSet();
      if (nextRunning.length == state.runningThreadIds.length) {
        continue;
      }
      viewModel.setRunningThreadIds(entry.key, nextRunning);
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

/// 跨 provider 聚合后的一页 thread。
class _AggregatedThreadPage {
  const _AggregatedThreadPage({
    required this.threads,
    required this.nextCursor,
    this.errorMessage,
  });

  final List<AgentThreadSummary> threads;
  final String? nextCursor;
  final String? errorMessage;
}

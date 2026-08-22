import 'dart:async';

import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/agent/application/agent_provider_settings_port.dart';
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
    required this.globalRuntime,
    this.bindingManager,
    ProjectThreadsViewModel? viewModel,
    AgentUiTextCatalog? textCatalog,
  }) : viewModel = viewModel ?? ProjectThreadsViewModel(),
       _textCatalog = textCatalog ?? const FallbackAgentUiTextCatalog();

  final AgentProviderSettingsPort providerController;
  final AgentProviderGlobalRuntime globalRuntime;
  final AgentConversationBindingManager? bindingManager;
  final ProjectThreadsViewModel viewModel;
  final AgentUiTextCatalog _textCatalog;

  final Map<String, int> _loadTokens = <String, int>{};
  final Map<String, String> _projectPathByThreadId = <String, String>{};
  final Map<String, Timer> _searchDebounceTimers = <String, Timer>{};

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

  /// 进入项目首页时清除全局唯一的 thread 高亮。
  void clearAllSelectedThreads() {
    viewModel.clearAllSelectedThreadIds();
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
  AgentThreadSummary registerSession(
    String projectPath,
    AgentSession session, {
    String? preview,
    bool markRunning = false,
  }) {
    _registerThreadMapping(projectPath, session.id);
    // title 只在 provider 已给出正式名时写入；首条用户消息只放 preview，
    // 避免把临时文案/「New thread」占位写进 title 后挡住后续 generated_title。
    final formalTitle = isAgentThreadTitlePlaceholder(session.title)
        ? null
        : session.title?.trim();
    final resolvedPreview = (preview ?? session.title ?? '').trim();
    final now = DateTime.now();
    final thread = AgentThreadSummary(
      id: session.id,
      providerId: session.providerId,
      projectPath: projectPath,
      title: formalTitle,
      preview: resolvedPreview,
      createdAt: now,
      updatedAt: now,
      status: AgentThreadRuntimeStatus.idle,
      raw: session.raw,
    );
    viewModel.prependThread(projectPath: projectPath, thread: thread);
    if (formalTitle != null) {
      viewModel.updateThreadTitle(
        projectPath: projectPath,
        threadId: session.id,
        title: formalTitle,
      );
    }
    selectThreadId(projectPath, session.id);
    if (markRunning) {
      _setThreadRunning(session.id, isRunning: true);
    }
    return thread;
  }

  /// 由详情侧 turn 状态同步列表执行中指示（不依赖 provider 事件是否已送达）。
  void setThreadRunning(String threadId, {required bool isRunning}) {
    _setThreadRunning(threadId, isRunning: isRunning);
  }

  /// 清除列表上「后台执行完毕」绿色提示（用户点击完成 icon）。
  void dismissCompletedThread({
    required String projectPath,
    required String threadId,
  }) {
    viewModel.dismissCompletedThread(
      projectPath: projectPath,
      threadId: threadId,
    );
  }

  /// 用常驻 thread runtime 快照同步列表状态。
  ///
  /// 这里不依赖当前 active provider 的单路事件流；已打开 thread 的后台执行、
  /// 等待审批与等待输入都应由各自 runtime 常驻同步。
  ///
  /// 标题同步对 **全部 Provider** 生效：仅当 snapshot 携带非占位正式标题时
  /// 才 `updateThreadTitle`。新建会话的「New thread」/空串若写进列表 title，
  /// 会被当成正式名，后续首条消息临时标题与 generated_title 都可能被挡住。
  void syncRuntimeSnapshot({
    required String projectPath,
    required AgentConversationThreadSnapshot snapshot,
  }) {
    final sessionId = snapshot.sessionId;
    if (sessionId == null || sessionId.isEmpty) {
      return;
    }
    _registerThreadMapping(projectPath, sessionId);
    final threadTitle = snapshot.threadTitle.trim();
    final currentTitle = stateFor(projectPath).threads
        .where((thread) => thread.id == sessionId)
        .map((thread) => thread.title?.trim())
        .firstOrNull;
    if (!isAgentThreadTitlePlaceholder(threadTitle) &&
        currentTitle != threadTitle) {
      viewModel.updateThreadTitle(
        projectPath: projectPath,
        threadId: sessionId,
        title: threadTitle,
      );
    }
    final threadPreview = snapshot.threadPreview.trim();
    if (threadPreview.isNotEmpty) {
      final currentPreview = stateFor(projectPath).threads
          .where((thread) => thread.id == sessionId)
          .map((thread) => thread.preview)
          .firstOrNull;
      if (currentPreview != threadPreview) {
        viewModel.updateThreadPreview(
          projectPath: projectPath,
          threadId: sessionId,
          preview: threadPreview,
        );
      }
    }
    final runtimeStatus = _effectiveListRuntimeStatus(snapshot);
    if (runtimeStatus != null) {
      viewModel.updateThreadRuntimeStatus(
        projectPath: projectPath,
        threadId: sessionId,
        status: runtimeStatus,
        waitingOnApproval: snapshot.waitingOnApproval,
        waitingOnUserInput: snapshot.waitingOnUserInput,
      );
    }
    // 先写 status 再写 running：isTurnRunning=false 时 setThreadRunning 会
    // 收束残留 active，避免 status 事件迟到时侧栏一直转圈。
    _setThreadRunning(sessionId, isRunning: snapshot.isTurnRunning);
  }

  /// 将详情侧 snapshot 映射为列表可消费的 runtime status。
  ///
  /// turn 已结束但 `thread/status/changed` 仍停留在 active 时，若无 waiting
  /// 标志，视为 idle，避免列表 `isBusy` 假阳性。
  AgentThreadRuntimeStatus? _effectiveListRuntimeStatus(
    AgentConversationThreadSnapshot snapshot,
  ) {
    final status = snapshot.runtimeStatus;
    if (status == null) {
      return null;
    }
    if (!snapshot.isTurnRunning &&
        status == AgentThreadRuntimeStatus.active &&
        !snapshot.waitingOnApproval &&
        !snapshot.waitingOnUserInput) {
      return AgentThreadRuntimeStatus.idle;
    }
    return status;
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

  /// 更新列表中某条 thread 的旁文案（供 shell 从详情侧回写）。
  void updateThreadPreview({
    required String projectPath,
    required String threadId,
    required String preview,
  }) {
    _registerThreadMapping(projectPath, threadId);
    viewModel.updateThreadPreview(
      projectPath: projectPath,
      threadId: threadId,
      preview: preview,
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
    await _runForThread<void>(
      projectPath: projectPath,
      threadId: threadId,
      operation: (bundle) async {
        _requireCapability(
          bundle: bundle,
          supported: bundle.capabilities.canRenameThread,
          operation: 'rename threads',
        );
        final threadNaming = bundle.threadNaming;
        if (threadNaming == null) {
          throw StateError(
            '${bundle.runtime.config.displayName} '
            'missing thread naming port',
          );
        }
        viewModel.updateThreadTitle(
          projectPath: projectPath,
          threadId: threadId,
          title: trimmed,
        );
        await threadNaming.renameThread(threadId: threadId, name: trimmed);
      },
    );
  }

  /// 归档 thread。
  Future<void> archiveThread({
    required String projectPath,
    required String threadId,
  }) async {
    await _runForThread<void>(
      projectPath: projectPath,
      threadId: threadId,
      operation: (bundle) async {
        _requireCapability(
          bundle: bundle,
          supported: bundle.capabilities.canArchiveThread,
          operation: 'archive threads',
        );
        final threadArchival = bundle.threadArchival;
        if (threadArchival == null) {
          throw StateError(
            '${bundle.runtime.config.displayName} '
            'missing thread archival port',
          );
        }
        await threadArchival.archiveThread(threadId);
        _removeThreadFromList(
          projectPath: projectPath,
          threadId: threadId,
          notifyCleared: true,
        );
      },
    );
  }

  /// 取消归档 thread。
  Future<void> unarchiveThread({
    required String projectPath,
    required String threadId,
  }) async {
    await _runForThread<void>(
      projectPath: projectPath,
      threadId: threadId,
      operation: (bundle) async {
        _requireCapability(
          bundle: bundle,
          supported: bundle.capabilities.canUnarchiveThread,
          operation: 'unarchive threads',
        );
        final threadArchival = bundle.threadArchival;
        if (threadArchival == null) {
          throw StateError(
            '${bundle.runtime.config.displayName} '
            'missing thread archival port',
          );
        }
        await threadArchival.unarchiveThread(threadId);
        _removeThreadFromList(
          projectPath: projectPath,
          threadId: threadId,
          notifyCleared: true,
        );
      },
    );
  }

  /// 删除 provider 端 thread；若只支持本地索引，则仅从 Zeta 列表移除。
  Future<void> deleteThread({
    required String projectPath,
    required String threadId,
  }) async {
    await _runForThread<void>(
      projectPath: projectPath,
      threadId: threadId,
      operation: (bundle) async {
        if (bundle.capabilities.canDeleteThread) {
          final threadDeletion = bundle.threadDeletion;
          if (threadDeletion == null) {
            throw StateError(
              '${bundle.runtime.config.displayName} '
              'missing thread deletion port',
            );
          }
          await threadDeletion.deleteThread(threadId);
        } else if (bundle.capabilities.canRemoveThreadFromList) {
          final localThreadList = bundle.localThreadList;
          if (localThreadList != null) {
            await localThreadList.removeThreadFromList(threadId);
          } else {
            _requireCapability(
              bundle: bundle,
              supported: false,
              operation: 'delete or remove threads',
            );
          }
        } else {
          _requireCapability(
            bundle: bundle,
            supported: false,
            operation: 'delete or remove threads',
          );
        }
        _removeThreadFromList(
          projectPath: projectPath,
          threadId: threadId,
          notifyCleared: true,
        );
      },
    );
  }

  /// 分叉 thread，返回 Provider 创建的新会话；调用方负责登记并切换 Agent 面板。
  Future<AgentSession?> forkThread({
    required String projectPath,
    required String threadId,
    AgentPermissionRequestSnapshot? permissionSnapshot,
  }) async {
    final session = await _runForThread<AgentSession>(
      projectPath: projectPath,
      threadId: threadId,
      operation: (bundle) async {
        _requireCapability(
          bundle: bundle,
          supported: bundle.capabilities.canForkThread,
          operation: 'fork threads',
        );
        final threadBranching = bundle.threadBranching;
        if (threadBranching == null) {
          throw StateError(
            '${bundle.runtime.config.displayName} '
            'missing thread branching port',
          );
        }
        final requestPermissionSnapshot = await _resolveForkPermissionSnapshot(
          bundle: bundle,
          threadId: threadId,
          supplied: permissionSnapshot,
        );
        return threadBranching.forkThread(
          threadId: threadId,
          context: AgentContext(projectPath: projectPath),
          permissionSnapshot: requestPermissionSnapshot,
        );
      },
    );
    return session;
  }

  Future<AgentPermissionRequestSnapshot> _resolveForkPermissionSnapshot({
    required AgentProviderBundle bundle,
    required String threadId,
    required AgentPermissionRequestSnapshot? supplied,
  }) async {
    if (supplied != null &&
        supplied.source != AgentPermissionRequestSource.providerFallback) {
      return supplied;
    }
    final providerId = bundle.runtime.config.id;
    final binding = bindingManager?.bindingForThread(
      providerId: providerId,
      threadId: threadId,
    );
    if (binding != null) {
      return binding.permissions.snapshotForRequest(threadId: threadId);
    }
    final configuredId = providerController
        .providerConfigById(providerId)
        ?.resolvedPermissionOptionId
        ?.trim();
    AgentPermissionSelection? catalogDefault;
    final permissionPolicy = bundle.permissionPolicy;
    if (permissionPolicy != null) {
      try {
        final catalog = await permissionPolicy.listPermissionOptions();
        final catalogId = catalog.defaultOptionId.trim();
        if (catalogId.isNotEmpty) {
          catalogDefault = AgentPermissionSelection(optionId: catalogId);
        }
      } catch (_) {
        // 目录暂不可用时仍可使用持久化默认；两者都没有才走 adapter fallback。
      }
    }
    return AgentPermissionRequestResolver.resolve(
      providerDefault: configuredId == null || configuredId.isEmpty
          ? null
          : AgentPermissionSelection(optionId: configuredId),
      catalogDefault: catalogDefault,
    );
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _loadTokens.clear();
    _projectPathByThreadId.clear();
    for (final timer in _searchDebounceTimers.values) {
      timer.cancel();
    }
    _searchDebounceTimers.clear();
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
      final merged = append
          ? _appendUnique(latest.threads, page.threads)
          : _replaceWithPageKeepingRuntimeThreads(
              current: latest,
              incoming: page.threads,
              preserveRuntimeThreads: !current.archived && searchTerm.isEmpty,
            );
      // Grok 等异步写 generated_title：provider 列表页可能暂无 title，
      // 不得冲掉 Zeta 本地乐观/已同步的展示标题与 preview。
      final displayMerged = _preferLocalDisplayFields(
        current: latest.threads,
        next: merged,
      );
      // provider list 的 active/waiting 可能来自外部客户端；仅 Zeta live 可 busy。
      final threads = _projectThreadsForZetaOwnedRuntime(
        threads: displayMerged,
        runningThreadIds: latest.runningThreadIds,
      );
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
      _log.w(
        'Could not load threads for $projectPath',
        error: error,
        stackTrace: stackTrace,
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
          errorMessage: _textCatalog.couldNotLoadThreads,
        ),
      );
    }
  }

  /// 从所有已启用 provider 拉取 thread，合并后按 recency 统一分页。
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
      return _AggregatedThreadPage(
        threads: const <AgentThreadSummary>[],
        nextCursor: null,
        errorMessage: _textCatalog.noEnabledProviders,
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
        try {
          final collected = await globalRuntime.run(
            config,
            (runtime) => _collectProviderThreads(
              bundle: runtime.bundle,
              projectPath: projectPath,
              archived: archived,
              searchTerm: searchTerm,
            ),
          );
          threadsByProviderId[config.id] = collected;
        } catch (error, stackTrace) {
          _log.w(
            'Could not list threads from ${config.id}',
            error: error,
            stackTrace: stackTrace,
          );
          failures.add(config.displayName);
        }
      }),
    );

    final merged = _mergeThreadsByRecency(threadsByProviderId.values);

    final offset = appendOffsetFromCursor(cursor);
    final pageThreads = merged.skip(offset).take(limit).toList(growable: false);
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
    _log.i(
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
    required AgentProviderBundle bundle,
    required String projectPath,
    required bool archived,
    required String? searchTerm,
  }) async {
    final threadCatalog = bundle.threadCatalog;
    if (threadCatalog == null) {
      return const <AgentThreadSummary>[];
    }
    final collected = <AgentThreadSummary>[];
    String? pageCursor;
    final seenIds = <String>{};

    while (collected.length < projectThreadPerProviderFetchCap) {
      final remaining = projectThreadPerProviderFetchCap - collected.length;
      final pageLimit = remaining < projectThreadPageLimit
          ? remaining
          : projectThreadPageLimit;
      final page = await threadCatalog.listThreads(
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
    required AgentProviderBundle bundle,
    required bool supported,
    required String operation,
  }) {
    if (!supported) {
      throw UnsupportedError(
        '${bundle.runtime.config.displayName} does not support $operation',
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

  /// 将所有 Provider 会话合并为一条稳定的全局时间线。
  static List<AgentThreadSummary> _mergeThreadsByRecency(
    Iterable<List<AgentThreadSummary>> groups,
  ) {
    return <AgentThreadSummary>[for (final threads in groups) ...threads]
      ..sort(_compareThreadRecency);
  }

  /// 按 thread 的稳定 provider 归属执行 global 操作，不改变当前 active provider。
  Future<T?> _runForThread<T>({
    required String projectPath,
    required String threadId,
    required Future<T> Function(AgentProviderBundle bundle) operation,
  }) async {
    await providerController.loadSettings();
    final ownerId = _providerIdForThread(projectPath, threadId);
    if (ownerId == null || !providerController.isProviderEnabled(ownerId)) {
      return null;
    }
    final config = providerController.providerConfigById(ownerId);
    if (config == null) {
      return null;
    }
    return globalRuntime.run(config, (runtime) => operation(runtime.bundle));
  }

  String? _providerIdForThread(String projectPath, String threadId) {
    for (final thread in stateFor(projectPath).threads) {
      if (thread.id == threadId) {
        return thread.providerId;
      }
    }
    return null;
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
    viewModel.setThreadRunning(
      projectPath: projectPath,
      threadId: threadId,
      isRunning: isRunning,
    );
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

  /// 将 provider 报告的 busy 收敛为 Zeta live 语义。
  ///
  /// - 在 [runningThreadIds] 内：保证摘要 `active`，供列表指示器与 isBusy 使用
  /// - 其余：剥离 active/waiting，避免 Codex 等外部客户端 running 造成假转圈
  List<AgentThreadSummary> _projectThreadsForZetaOwnedRuntime({
    required List<AgentThreadSummary> threads,
    required Set<String> runningThreadIds,
  }) {
    if (threads.isEmpty) {
      return threads;
    }
    return <AgentThreadSummary>[
      for (final thread in threads)
        if (runningThreadIds.contains(thread.id))
          thread.status == AgentThreadRuntimeStatus.active
              ? thread
              : thread.copyWith(status: AgentThreadRuntimeStatus.active)
        else if (thread.status == AgentThreadRuntimeStatus.active ||
            thread.waitingOnApproval ||
            thread.waitingOnUserInput)
          thread.copyWith(
            status: thread.status == AgentThreadRuntimeStatus.active
                ? AgentThreadRuntimeStatus.idle
                : thread.status,
            waitingOnApproval: false,
            waitingOnUserInput: false,
          )
        else
          thread,
    ];
  }

  /// 首屏刷新时保留 Provider 尚未落盘的本地运行态 thread。
  ///
  /// 新 session 会先乐观插入列表，Grok 等 Provider 的本地索引可能稍后才可见。
  /// 若更早发起的首屏请求随后返回，不能用缺少该 session 的页面覆盖当前状态。
  List<AgentThreadSummary> _replaceWithPageKeepingRuntimeThreads({
    required ProjectThreadListState current,
    required List<AgentThreadSummary> incoming,
    required bool preserveRuntimeThreads,
  }) {
    if (!preserveRuntimeThreads || current.threads.isEmpty) {
      return incoming;
    }
    final retainedIds = <String>{
      ...current.runningThreadIds,
      ...current.completedThreadIds,
      ?current.selectedThreadId,
    };
    if (retainedIds.isEmpty) {
      return incoming;
    }
    final incomingIds = incoming.map((thread) => thread.id).toSet();
    return <AgentThreadSummary>[
      for (final thread in current.threads)
        if (retainedIds.contains(thread.id) && !incomingIds.contains(thread.id))
          thread,
      ...incoming,
    ];
  }

  /// 合并列表页时保留本地更丰富的 title/preview。
  ///
  /// Provider 本地索引（尤其 Grok `summary.json`）可能晚于 live 乐观标题；
  /// 若页数据 title 为空或 preview 退化为 session id，沿用当前缓存展示字段。
  List<AgentThreadSummary> _preferLocalDisplayFields({
    required List<AgentThreadSummary> current,
    required List<AgentThreadSummary> next,
  }) {
    if (current.isEmpty || next.isEmpty) {
      return next;
    }
    final localById = <String, AgentThreadSummary>{
      for (final thread in current) thread.id: thread,
    };
    return <AgentThreadSummary>[
      for (final incoming in next)
        _mergeThreadSummaryPreferLocalDisplay(
          local: localById[incoming.id],
          incoming: incoming,
        ),
    ];
  }

  /// 单条摘要：incoming 权威字段优先，空/弱展示字段回退 local。
  ///
  /// 标题的「弱」判定含 Zeta 占位 [agentDefaultThreadTitle]：provider 列表若
  /// 仍回传「New thread」，不得冲掉本地首条消息临时标题或已同步正式名。
  static AgentThreadSummary _mergeThreadSummaryPreferLocalDisplay({
    required AgentThreadSummary? local,
    required AgentThreadSummary incoming,
  }) {
    if (local == null || local.id != incoming.id) {
      return incoming;
    }

    final incomingTitleStrong = !isAgentThreadTitlePlaceholder(incoming.title);
    final localTitleStrong = !isAgentThreadTitlePlaceholder(local.title);
    final resolvedTitle = incomingTitleStrong
        ? incoming.title
        : (localTitleStrong ? local.title : incoming.title);

    final incomingPreview = incoming.preview.trim();
    final localPreview = local.preview.trim();
    final incomingPreviewWeak =
        incomingPreview.isEmpty || incomingPreview == incoming.id;
    final localPreviewStrong =
        localPreview.isNotEmpty && localPreview != local.id;
    final resolvedPreview = incomingPreviewWeak && localPreviewStrong
        ? local.preview
        : incoming.preview;

    if (resolvedTitle == incoming.title &&
        resolvedPreview == incoming.preview) {
      return incoming;
    }
    return incoming.copyWith(title: resolvedTitle, preview: resolvedPreview);
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

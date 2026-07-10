import 'dart:async';

import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/usage_statistics/data/usage_statistics_index_store.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_repository.dart';

typedef UsageAgentProviderLoader = Future<AgentProvider> Function();

/// 基于 Codex app-server thread 历史和本地 JSONL 的使用统计数据源。
class CodexUsageStatisticsRepository implements UsageStatisticsRepository {
  CodexUsageStatisticsRepository({
    required this.providerLoader,
    required this.indexStore,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const int _threadPageSize = 100;
  static const int _historyReadConcurrency = 4;
  static const List<String> _humanRootSourceKinds = <String>[
    'cli',
    'vscode',
    'exec',
    'appServer',
  ];

  final UsageAgentProviderLoader providerLoader;
  final UsageStatisticsIndexStore indexStore;
  final DateTime Function() _clock;

  @override
  Future<UsageStatisticsSourceSnapshot> load({
    required DateTime earliest,
    bool forceRefresh = false,
  }) async {
    final provider = await providerLoader();
    final warnings = <String>[];
    var index = await indexStore.load();
    final summaries = await _listRelevantThreads(provider, earliest);
    final nextThreads = <String, UsageStatisticsIndexedThread>{
      ...index.threads,
    };
    final seenThreadIds = summaries.map((thread) => thread.id).toSet();
    nextThreads.removeWhere(
      (threadId, cached) =>
          !cached.updatedAt.isBefore(earliest) &&
          !seenThreadIds.contains(threadId),
    );

    final pendingReads = <AgentThreadSummary>[];
    for (final summary in summaries) {
      final cached = nextThreads[summary.id];
      final unchanged =
          !forceRefresh &&
          cached != null &&
          cached.updatedAt.isAtSameMomentAs(summary.updatedAt);
      if (!unchanged) {
        pendingReads.add(summary);
      }
    }

    var failedThreadReads = 0;
    for (
      var offset = 0;
      offset < pendingReads.length;
      offset += _historyReadConcurrency
    ) {
      final end = (offset + _historyReadConcurrency).clamp(
        0,
        pendingReads.length,
      );
      final batch = pendingReads.sublist(offset, end);
      final results = await Future.wait(
        batch.map((summary) => _readThread(provider, summary)),
      );
      for (final result in results) {
        if (result.thread != null) {
          nextThreads[result.summary.id] = result.thread!;
        } else {
          failedThreadReads += 1;
        }
      }
    }
    if (failedThreadReads > 0) {
      warnings.add('$failedThreadReads 个 Codex 会话读取失败，已保留可用缓存。');
    }

    index = UsageStatisticsIndexSnapshot(
      threads: Map<String, UsageStatisticsIndexedThread>.unmodifiable(
        nextThreads,
      ),
    );
    try {
      await indexStore.save(index);
    } catch (_) {
      warnings.add('统计索引暂时无法保存，本次结果仍可正常查看。');
    }

    AgentUsageQuotaSnapshot? quota;
    if (provider case final AgentUsageQuotaProvider quotaProvider) {
      try {
        quota = await quotaProvider.readUsageQuota();
      } catch (_) {
        warnings.add('Codex 当前未返回套餐额度信息。');
      }
    }

    final records =
        nextThreads.values
            .expand((thread) => thread.records)
            .where((record) => !record.startedAt.isBefore(earliest))
            .toList()
          ..sort((left, right) => right.startedAt.compareTo(left.startedAt));
    return UsageStatisticsSourceSnapshot(
      records: List<AgentUsageRecord>.unmodifiable(records),
      refreshedAt: _clock(),
      quota: quota,
      warnings: List<String>.unmodifiable(warnings),
    );
  }

  Future<List<AgentThreadSummary>> _listRelevantThreads(
    AgentProvider provider,
    DateTime earliest,
  ) async {
    final byId = <String, AgentThreadSummary>{};
    for (final archived in <bool>[false, true]) {
      String? cursor;
      var pageCount = 0;
      do {
        final page = await provider.listThreads(
          query: AgentThreadListQuery(
            projectPath: null,
            limit: _threadPageSize,
            cursor: cursor,
            archived: archived,
            sourceKinds: _humanRootSourceKinds,
          ),
        );
        pageCount += 1;
        for (final thread in page.threads) {
          if (!thread.updatedAt.isBefore(earliest)) {
            final previous = byId[thread.id];
            if (previous == null ||
                thread.updatedAt.isAfter(previous.updatedAt)) {
              byId[thread.id] = thread;
            }
          }
        }
        final reachedOlderThreads =
            page.threads.isNotEmpty &&
            page.threads.last.updatedAt.isBefore(earliest);
        cursor = reachedOlderThreads ? null : page.nextCursor;
        // 防御异常 provider 重复返回游标导致无限循环。
        if (pageCount >= 1000) {
          cursor = null;
        }
      } while (cursor != null);
    }
    final result = byId.values.toList()
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return result;
  }

  Future<_ThreadReadResult> _readThread(
    AgentProvider provider,
    AgentThreadSummary summary,
  ) async {
    try {
      final history = await provider.readThreadHistory(
        threadId: summary.id,
        sessionPath: summary.sessionPath,
      );
      return _ThreadReadResult(
        summary: summary,
        thread: UsageStatisticsIndexedThread(
          threadId: summary.id,
          updatedAt: summary.updatedAt,
          records: _recordsFromHistory(provider, summary, history),
        ),
      );
    } catch (_) {
      return _ThreadReadResult(summary: summary);
    }
  }

  List<AgentUsageRecord> _recordsFromHistory(
    AgentProvider provider,
    AgentThreadSummary summary,
    AgentThreadHistorySnapshot history,
  ) {
    final records = <AgentUsageRecord>[];
    AgentTokenUsage? previousCumulative;
    for (final turn in history.turns) {
      final cumulative = turn.tokenUsage;
      final turnTokens = cumulative?.hasCumulativeBreakdown == true
          ? cumulative!.deltaFrom(previousCumulative)
          : cumulative;
      if (cumulative?.hasCumulativeBreakdown == true) {
        previousCumulative = cumulative;
      }
      final startedAt =
          turn.startedAt ??
          turn.completedAt ??
          (history.turns.length == 1 ? summary.createdAt : null);
      if (startedAt == null) {
        continue;
      }
      final status = _usageStatus(turn.status);
      final errorCategory = _errorCategory(
        status: status,
        code: turn.errorCode,
        message: turn.errorMessage,
      );
      records.add(
        AgentUsageRecord(
          threadId: summary.id,
          turnId: turn.id,
          providerId: provider.config.id,
          providerName: provider.config.displayName,
          projectPath: _nonEmpty(turn.cwd) ?? summary.projectPath,
          sourceKind: _sourceKind(summary.raw['source']),
          startedAt: startedAt,
          completedAt: turn.completedAt,
          duration:
              turn.duration ?? _durationBetween(startedAt, turn.completedAt),
          timeToFirstToken: turn.timeToFirstToken,
          model: _nonEmpty(turn.model),
          status: status,
          tokens: UsageTokenBreakdown(
            inputTokens: turnTokens?.inputTokens,
            cachedInputTokens: turnTokens?.cachedInputTokens,
            outputTokens: turnTokens?.outputTokens,
            totalTokens: turnTokens?.totalTokens,
          ),
          errorCategory: errorCategory,
          errorMessage: _nonEmpty(turn.errorMessage),
          errorCode: _nonEmpty(turn.errorCode),
        ),
      );
    }
    return List<AgentUsageRecord>.unmodifiable(records);
  }
}

class _ThreadReadResult {
  const _ThreadReadResult({required this.summary, this.thread});

  final AgentThreadSummary summary;
  final UsageStatisticsIndexedThread? thread;
}

UsageTaskStatus _usageStatus(AgentHistoryTurnStatus status) => switch (status) {
  AgentHistoryTurnStatus.running => UsageTaskStatus.running,
  AgentHistoryTurnStatus.completed => UsageTaskStatus.completed,
  AgentHistoryTurnStatus.interrupted => UsageTaskStatus.interrupted,
  AgentHistoryTurnStatus.failed => UsageTaskStatus.failed,
  AgentHistoryTurnStatus.unknown => UsageTaskStatus.unknown,
};

UsageErrorCategory? _errorCategory({
  required UsageTaskStatus status,
  required String? code,
  required String? message,
}) {
  if (!status.isFailure) {
    return null;
  }
  if (status == UsageTaskStatus.interrupted) {
    return UsageErrorCategory.cancelled;
  }
  final normalizedCode = code?.toLowerCase() ?? '';
  final normalizedMessage = message?.toLowerCase() ?? '';
  if (normalizedCode.contains('unauthorized') ||
      normalizedCode.contains('usagelimit') ||
      normalizedMessage.contains('account') ||
      normalizedMessage.contains('login')) {
    return UsageErrorCategory.account;
  }
  if (normalizedCode.contains('connection') ||
      normalizedCode.contains('stream') ||
      normalizedCode.contains('serveroverloaded') ||
      normalizedMessage.contains('network') ||
      normalizedMessage.contains('connection')) {
    return UsageErrorCategory.network;
  }
  if (normalizedCode.contains('timeout') ||
      normalizedMessage.contains('timeout') ||
      normalizedMessage.contains('timed out') ||
      normalizedMessage.contains('deadline')) {
    return UsageErrorCategory.timeout;
  }
  if (normalizedCode.contains('sandbox') ||
      normalizedCode.contains('threadrollback') ||
      normalizedMessage.contains('codex cli')) {
    return UsageErrorCategory.cli;
  }
  return UsageErrorCategory.other;
}

String _sourceKind(Object? source) {
  if (source is String && source.trim().isNotEmpty) {
    return source.trim();
  }
  if (source is Map) {
    final type = source['type'];
    if (type is String && type.trim().isNotEmpty) {
      return type.trim();
    }
    if (source.length == 1) {
      return source.keys.first.toString();
    }
  }
  return 'unknown';
}

String? _nonEmpty(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

Duration? _durationBetween(DateTime startedAt, DateTime? completedAt) {
  if (completedAt == null || completedAt.isBefore(startedAt)) {
    return null;
  }
  return completedAt.difference(startedAt);
}

import 'dart:async';
import 'dart:io';

import 'package:zeta/src/features/agent/data/datasources/local_history/codex_usage_log_scanner.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/usage_statistics/data/usage_statistics_index_store.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_repository.dart';

typedef UsageAgentProviderLoader = Future<AgentProvider> Function();

/// 基于 Codex 本地 rollout JSONL 的使用统计数据源。
///
/// 记录身份固定为 Codex（[defaultAgentProviderId]），不依赖当前激活 Provider。
/// [providerLoader] 仅用于解析 `CODEX_HOME` 与可选套餐额度；可为空，此时仅扫本机默认路径。
/// app-server 仅用于读取当前套餐额度；历史 token 不依赖 thread/list。
class CodexUsageStatisticsRepository implements UsageStatisticsRepository {
  CodexUsageStatisticsRepository({
    required this.indexStore,
    this.providerLoader,
    this.scanner = const FileSystemCodexUsageLogScanner(),
    Map<String, String>? environment,
    this.homeDirectory,
    this.includeQuota = true,
    this.providerId = defaultAgentProviderId,
    String? providerName,
    DateTime Function()? clock,
  }) : providerName =
           providerName ?? AgentProviderConfig.defaultCodex.displayName,
       _environment = environment ?? Platform.environment,
       _clock = clock ?? DateTime.now;

  /// 可选；仅用于配置环境中的 `CODEX_HOME` 与 [AgentUsageQuotaProvider]。
  final UsageAgentProviderLoader? providerLoader;
  final UsageStatisticsIndexStore indexStore;
  final CodexUsageLogScanner scanner;
  final Map<String, String> _environment;
  final String? homeDirectory;
  final bool includeQuota;

  /// 写入记录的稳定 Provider 身份，不随 active provider 变化。
  final String providerId;
  final String providerName;
  final DateTime Function() _clock;

  @override
  Future<UsageStatisticsSourceSnapshot> load({
    required DateTime earliest,
    bool forceRefresh = false,
  }) async {
    final warnings = <String>[];
    AgentProvider? provider;
    final loader = providerLoader;
    if (loader != null) {
      try {
        provider = await loader();
      } catch (_) {
        warnings.add('Codex 运行时暂时不可用，已仅根据本地历史统计。');
      }
    }

    final index = await indexStore.load();
    final scan = await scanner.scan(
      codexHome: _resolveCodexHome(provider),
      cachedSessions: index.codexSessions,
      forceRefresh: forceRefresh,
    );
    warnings.addAll(scan.warnings);
    try {
      // 按 sourceId 写入分区，与 Grok 并行 mergeSave 互不覆盖。
      final codexSessions = <String, CodexUsageSessionSnapshot>{
        for (final session in scan.sessions.values) session.sourceId: session,
      };
      await indexStore.mergeSave(codexSessions: codexSessions);
    } catch (_) {
      warnings.add('统计索引暂时无法保存，本次结果仍可正常查看。');
    }

    AgentUsageQuotaSnapshot? quota;
    if (includeQuota && provider is AgentUsageQuotaProvider) {
      try {
        quota = await (provider as AgentUsageQuotaProvider).readUsageQuota();
      } catch (_) {
        warnings.add('Codex 当前未返回套餐额度信息。');
      }
    }

    final records =
        _recordsFromSessions(
            scan.sessions.values,
          ).where((record) => !record.startedAt.isBefore(earliest)).toList()
          ..sort((left, right) => right.startedAt.compareTo(left.startedAt));
    return UsageStatisticsSourceSnapshot(
      records: List<AgentUsageRecord>.unmodifiable(records),
      refreshedAt: _clock(),
      quota: quota,
      warnings: List<String>.unmodifiable(warnings),
    );
  }

  String _resolveCodexHome(AgentProvider? provider) {
    final configured = _nonEmpty(provider?.config.environment['CODEX_HOME']);
    if (configured != null) {
      return configured;
    }
    final inherited = _nonEmpty(_environment['CODEX_HOME']);
    if (inherited != null) {
      return inherited;
    }
    final home =
        _nonEmpty(homeDirectory) ??
        _nonEmpty(_environment[Platform.isWindows ? 'USERPROFILE' : 'HOME']) ??
        Directory.current.path;
    return _joinPath(home, '.codex');
  }

  List<AgentUsageRecord> _recordsFromSessions(
    Iterable<CodexUsageSessionSnapshot> sessions,
  ) {
    final recordsById = <String, AgentUsageRecord>{};
    final seenSamples = <String>{};
    final orderedSessions = sessions.toList()
      ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
    for (final session in orderedSessions) {
      for (final turn in session.turns) {
        final acceptedSamples = turn.samples
            .where((sample) => seenSamples.add(sample.deduplicationKey))
            .toList();
        final startedAt =
            turn.startedAt ??
            (acceptedSamples.isEmpty
                ? null
                : acceptedSamples.first.timestamp) ??
            turn.completedAt ??
            session.createdAt;
        final status = _usageStatus(turn.status);
        final tokens = acceptedSamples.isEmpty
            ? const UsageTokenBreakdown()
            : UsageTokenBreakdown(
                inputTokens: _sum(
                  acceptedSamples,
                  (sample) => sample.inputTokens,
                ),
                cachedInputTokens: _sum(
                  acceptedSamples,
                  (sample) => sample.cachedInputTokens,
                ),
                outputTokens: _sum(
                  acceptedSamples,
                  (sample) => sample.outputTokens,
                ),
                reasoningTokens: _sum(
                  acceptedSamples,
                  (sample) => sample.reasoningTokens,
                ),
                totalTokens: _sum(
                  acceptedSamples,
                  (sample) => sample.totalTokens,
                ),
              );
        final record = AgentUsageRecord(
          threadId: session.threadId,
          turnId: turn.id,
          providerId: providerId,
          providerName: providerName,
          projectPath: _nonEmpty(turn.cwd) ?? session.projectPath,
          sourceKind: session.sourceKind,
          startedAt: startedAt,
          completedAt: turn.completedAt,
          duration: _durationBetween(startedAt, turn.completedAt),
          model: _nonEmpty(turn.model),
          status: status,
          tokens: tokens,
          errorCategory: _errorCategory(
            status: status,
            hint:
                turn.errorCategoryHint ??
                codexUsageErrorCategoryHint(
                  status: turn.status,
                  code: turn.errorCode,
                  message: turn.errorMessage,
                ),
          ),
          errorMessage: _nonEmpty(turn.errorMessage),
          errorCode: _nonEmpty(turn.errorCode),
        );
        recordsById.update(
          record.id,
          (existing) => _mergeUsageRecords(existing, record),
          ifAbsent: () => record,
        );
      }
    }
    return List<AgentUsageRecord>.unmodifiable(recordsById.values);
  }
}

/// 合并多个 rollout 文件中指向同一 thread/turn 的派生记录。
///
/// Token sample 已由调用方按原始事件键去重，这里只累加真正新增的 sample，
/// 并保留终态、完成时间、模型和错误等更完整的元数据。
AgentUsageRecord _mergeUsageRecords(
  AgentUsageRecord existing,
  AgentUsageRecord candidate,
) {
  final candidatePreferred =
      _usageStatusRank(candidate.status) >= _usageStatusRank(existing.status);
  final preferred = candidatePreferred ? candidate : existing;
  final fallback = candidatePreferred ? existing : candidate;
  final startedAt = existing.startedAt.isBefore(candidate.startedAt)
      ? existing.startedAt
      : candidate.startedAt;
  final completedAt = _latestDateTime(
    existing.completedAt,
    candidate.completedAt,
  );

  return AgentUsageRecord(
    threadId: existing.threadId,
    turnId: existing.turnId,
    providerId: existing.providerId,
    providerName: existing.providerName,
    projectPath: _nonEmpty(preferred.projectPath) ?? fallback.projectPath,
    sourceKind: _nonEmpty(preferred.sourceKind) ?? fallback.sourceKind,
    startedAt: startedAt,
    completedAt: completedAt,
    duration: _durationBetween(startedAt, completedAt),
    timeToFirstToken: _shorterDuration(
      existing.timeToFirstToken,
      candidate.timeToFirstToken,
    ),
    model: _nonEmpty(preferred.model) ?? _nonEmpty(fallback.model),
    status: preferred.status,
    tokens: _sumTokenBreakdown(existing.tokens, candidate.tokens),
    errorCategory: preferred.errorCategory ?? fallback.errorCategory,
    errorMessage:
        _nonEmpty(preferred.errorMessage) ?? _nonEmpty(fallback.errorMessage),
    errorCode: _nonEmpty(preferred.errorCode) ?? _nonEmpty(fallback.errorCode),
  );
}

UsageTokenBreakdown _sumTokenBreakdown(
  UsageTokenBreakdown left,
  UsageTokenBreakdown right,
) {
  return UsageTokenBreakdown(
    inputTokens: _sumNullable(left.inputTokens, right.inputTokens),
    cachedInputTokens: _sumNullable(
      left.cachedInputTokens,
      right.cachedInputTokens,
    ),
    outputTokens: _sumNullable(left.outputTokens, right.outputTokens),
    reasoningTokens: _sumNullable(left.reasoningTokens, right.reasoningTokens),
    totalTokens: _sumNullable(left.totalTokens, right.totalTokens),
  );
}

int? _sumNullable(int? left, int? right) {
  if (left == null && right == null) {
    return null;
  }
  return (left ?? 0) + (right ?? 0);
}

int _usageStatusRank(UsageTaskStatus status) => switch (status) {
  UsageTaskStatus.unknown => 0,
  UsageTaskStatus.running => 1,
  UsageTaskStatus.completed ||
  UsageTaskStatus.interrupted ||
  UsageTaskStatus.failed => 2,
};

DateTime? _latestDateTime(DateTime? left, DateTime? right) {
  if (left == null) {
    return right;
  }
  if (right == null) {
    return left;
  }
  return left.isAfter(right) ? left : right;
}

Duration? _shorterDuration(Duration? left, Duration? right) {
  if (left == null) {
    return right;
  }
  if (right == null) {
    return left;
  }
  return left <= right ? left : right;
}

int _sum(
  Iterable<CodexUsageSample> samples,
  int Function(CodexUsageSample sample) select,
) => samples.fold<int>(0, (total, sample) => total + select(sample));

UsageTaskStatus _usageStatus(AgentHistoryTurnStatus status) => switch (status) {
  AgentHistoryTurnStatus.running => UsageTaskStatus.running,
  AgentHistoryTurnStatus.completed => UsageTaskStatus.completed,
  AgentHistoryTurnStatus.interrupted => UsageTaskStatus.interrupted,
  AgentHistoryTurnStatus.failed => UsageTaskStatus.failed,
  AgentHistoryTurnStatus.unknown => UsageTaskStatus.unknown,
};

UsageErrorCategory? _errorCategory({
  required UsageTaskStatus status,
  required String? hint,
}) {
  if (!status.isFailure) {
    return null;
  }
  return switch (hint) {
    'account' => UsageErrorCategory.account,
    'cli' => UsageErrorCategory.cli,
    'network' => UsageErrorCategory.network,
    'timeout' => UsageErrorCategory.timeout,
    'cancelled' => UsageErrorCategory.cancelled,
    _ => UsageErrorCategory.other,
  };
}

String? _nonEmpty(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

String _joinPath(String parent, String child) {
  final separator = Platform.pathSeparator;
  final normalized = parent.endsWith('/') || parent.endsWith('\\')
      ? parent.substring(0, parent.length - 1)
      : parent;
  return '$normalized$separator$child';
}

Duration? _durationBetween(DateTime startedAt, DateTime? completedAt) {
  if (completedAt == null || completedAt.isBefore(startedAt)) {
    return null;
  }
  return completedAt.difference(startedAt);
}

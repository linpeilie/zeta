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
/// app-server 仅用于读取当前套餐额度；历史 token 不依赖 thread/list。
class CodexUsageStatisticsRepository implements UsageStatisticsRepository {
  CodexUsageStatisticsRepository({
    required this.providerLoader,
    required this.indexStore,
    this.scanner = const FileSystemCodexUsageLogScanner(),
    Map<String, String>? environment,
    this.homeDirectory,
    DateTime Function()? clock,
  }) : _environment = environment ?? Platform.environment,
       _clock = clock ?? DateTime.now;

  final UsageAgentProviderLoader providerLoader;
  final UsageStatisticsIndexStore indexStore;
  final CodexUsageLogScanner scanner;
  final Map<String, String> _environment;
  final String? homeDirectory;
  final DateTime Function() _clock;

  @override
  Future<UsageStatisticsSourceSnapshot> load({
    required DateTime earliest,
    bool forceRefresh = false,
  }) async {
    final provider = await providerLoader();
    final warnings = <String>[];
    final index = await indexStore.load();
    final scan = await scanner.scan(
      codexHome: _resolveCodexHome(provider),
      cachedSessions: index.sessions,
      forceRefresh: forceRefresh,
    );
    warnings.addAll(scan.warnings);
    try {
      await indexStore.save(
        UsageStatisticsIndexSnapshot(sessions: scan.sessions),
      );
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
        _recordsFromSessions(
            provider,
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

  String _resolveCodexHome(AgentProvider provider) {
    final configured = _nonEmpty(provider.config.environment['CODEX_HOME']);
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
    AgentProvider provider,
    Iterable<CodexUsageSessionSnapshot> sessions,
  ) {
    final records = <AgentUsageRecord>[];
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
        records.add(
          AgentUsageRecord(
            threadId: session.threadId,
            turnId: turn.id,
            providerId: provider.config.id,
            providerName: provider.config.displayName,
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
          ),
        );
      }
    }
    return List<AgentUsageRecord>.unmodifiable(records);
  }
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

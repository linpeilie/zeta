import 'dart:io';

import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/usage_statistics/data/providers/codex/codex_usage_log_scanner.dart';
import 'package:zeta/src/features/usage_statistics/data/providers/codex/codex_usage_partition_codec.dart';
import 'package:zeta/src/features/usage_statistics/data/usage_statistics_partition_store.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_token_usage_source.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_query_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/fallback_usage_statistics_text_catalog.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_text_catalog.dart';

/// 直接从 Codex rollout 与自有 v4 分区读取 Token 历史。
///
/// 本 source 与实际 Provider 配置实例绑定；配置环境、CLI home 和 session 路径始终留在
/// data 层，不进入 query service 或中立快照。
final class CodexTokenUsageSource implements AgentTokenUsageSource {
  factory CodexTokenUsageSource({
    required AgentProviderConfig config,
    required UsageStatisticsPartitionStore partitionStore,
    CodexUsageLogScanner scanner = const FileSystemCodexUsageLogScanner(),
    CodexUsagePartitionCodec codec = const CodexUsagePartitionCodec(),
    Map<String, String>? environment,
    String? homeDirectory,
    DateTime Function()? clock,
    UsageStatisticsTextCatalog? textCatalog,
  }) {
    return CodexTokenUsageSource._(
      providerId: config.id,
      providerName: config.displayName,
      configuredEnvironment: config.environment,
      partitionStore: partitionStore,
      scanner: scanner,
      codec: codec,
      environment: environment ?? Platform.environment,
      homeDirectory: homeDirectory,
      clock: clock ?? DateTime.now,
      textCatalog: textCatalog ?? const FallbackUsageStatisticsTextCatalog(),
    );
  }

  CodexTokenUsageSource._({
    required this.providerId,
    required this.providerName,
    required Map<String, String> configuredEnvironment,
    required this._partitionStore,
    required this._scanner,
    required this._codec,
    required Map<String, String> environment,
    required this._homeDirectory,
    required this._clock,
    required this._textCatalog,
  }) : _configuredEnvironment = Map<String, String>.unmodifiable(
         configuredEnvironment,
       ),
       _environment = Map<String, String>.unmodifiable(environment);

  @override
  final String providerId;

  final String providerName;
  final Map<String, String> _configuredEnvironment;
  final UsageStatisticsPartitionStore _partitionStore;
  final CodexUsageLogScanner _scanner;
  final CodexUsagePartitionCodec _codec;
  final Map<String, String> _environment;
  final String? _homeDirectory;
  final DateTime Function() _clock;
  final UsageStatisticsTextCatalog _textCatalog;

  @override
  Future<AgentTokenUsageSourceSnapshot> load(AgentUsageQuery query) async {
    final warnings = <AgentUsageWarning>[];
    Map<String, CodexUsageSessionSnapshot> cachedSessions;
    try {
      cachedSessions = _codec.decode(
        await _partitionStore.readPartition(providerId),
      );
    } catch (_) {
      cachedSessions = const <String, CodexUsageSessionSnapshot>{};
      warnings.add(
        AgentUsageWarning(
          code: 'codex-index-read',
          message: _textCatalog.indexReadRescanned(providerName),
        ),
      );
    }

    final scan = await _scanner.scan(
      codexHome: _resolveCodexHome(),
      cachedSessions: cachedSessions,
      forceRefresh: query.forceRefresh,
    );
    warnings.addAll(
      scan.warnings.map(
        (message) =>
            AgentUsageWarning(code: 'codex-source-warning', message: message),
      ),
    );

    try {
      await _partitionStore.writePartition(
        providerId,
        _codec.encode(scan.sessions.values),
      );
    } catch (_) {
      warnings.add(
        AgentUsageWarning(
          code: 'codex-index-write',
          message: _textCatalog.indexWriteFailed,
        ),
      );
    }

    final records =
        _recordsFromSessions(scan.sessions.values)
            .where((record) => !record.startedAt.isBefore(query.earliest))
            .toList()
          ..sort((left, right) => right.startedAt.compareTo(left.startedAt));
    return AgentTokenUsageSourceSnapshot(
      providerId: providerId,
      providerName: providerName,
      historyPresence: scan.sessions.isEmpty
          ? AgentTokenHistoryPresence.absent
          : AgentTokenHistoryPresence.present,
      records: records,
      refreshedAt: _clock(),
      warnings: warnings,
    );
  }

  String _resolveCodexHome() {
    final configured = _nonEmpty(_configuredEnvironment['CODEX_HOME']);
    if (configured != null) {
      return configured;
    }
    final inherited = _nonEmpty(_environment['CODEX_HOME']);
    if (inherited != null) {
      return inherited;
    }
    final home =
        _nonEmpty(_homeDirectory) ??
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

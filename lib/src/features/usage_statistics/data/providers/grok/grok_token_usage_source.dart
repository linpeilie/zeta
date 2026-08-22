import 'dart:io';

import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/usage_statistics/data/providers/grok/grok_usage_log_scanner.dart';
import 'package:zeta/src/features/usage_statistics/data/providers/grok/grok_usage_partition_codec.dart';
import 'package:zeta/src/features/usage_statistics/data/usage_statistics_partition_store.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_token_usage_source.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_query_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/fallback_usage_statistics_text_catalog.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_text_catalog.dart';

/// 直接从 Grok updates 历史与自有 v4 分区读取 Token 用量。
final class GrokTokenUsageSource implements AgentTokenUsageSource {
  factory GrokTokenUsageSource({
    required AgentProviderConfig config,
    required UsageStatisticsPartitionStore partitionStore,
    GrokUsageLogScanner scanner = const FileSystemGrokUsageLogScanner(),
    GrokUsagePartitionCodec codec = const GrokUsagePartitionCodec(),
    Map<String, String>? environment,
    String? homeDirectory,
    DateTime Function()? clock,
    UsageStatisticsTextCatalog? textCatalog,
  }) {
    return GrokTokenUsageSource._(
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

  GrokTokenUsageSource._({
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
  final GrokUsageLogScanner _scanner;
  final GrokUsagePartitionCodec _codec;
  final Map<String, String> _environment;
  final String? _homeDirectory;
  final DateTime Function() _clock;
  final UsageStatisticsTextCatalog _textCatalog;

  @override
  Future<AgentTokenUsageSourceSnapshot> load(AgentUsageQuery query) async {
    final warnings = <AgentUsageWarning>[];
    Map<String, GrokUsageIndexedSession> cachedSessions;
    try {
      cachedSessions = _codec.decode(
        await _partitionStore.readPartition(providerId),
      );
    } catch (_) {
      cachedSessions = const <String, GrokUsageIndexedSession>{};
      warnings.add(
        AgentUsageWarning(
          code: 'grok-index-read',
          message: _textCatalog.indexReadRescanned(providerName),
        ),
      );
    }

    final scan = await _scanner.scan(
      grokHome: _resolveGrokHome(),
      cachedSessions: cachedSessions,
      forceRefresh: query.forceRefresh,
      textCatalog: _textCatalog,
    );
    warnings.addAll(
      scan.warnings.map(
        (message) =>
            AgentUsageWarning(code: 'grok-source-warning', message: message),
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
          code: 'grok-index-write',
          message: _textCatalog.indexWriteFailed,
        ),
      );
    }

    final records = <AgentUsageRecord>[];
    for (final session in scan.sessions.values) {
      for (final turn in session.turns) {
        final startedAt =
            turn.startedAt ?? turn.completedAt ?? session.modifiedAt;
        if (startedAt.isBefore(query.earliest)) {
          continue;
        }
        final status = _usageStatus(turn.status);
        records.add(
          AgentUsageRecord(
            threadId: session.threadId,
            turnId: turn.id,
            providerId: providerId,
            providerName: providerName,
            projectPath: _nonEmpty(turn.cwd) ?? session.projectPath,
            sourceKind: session.sourceKind,
            startedAt: startedAt,
            completedAt: turn.completedAt,
            duration:
                turn.duration ?? _durationBetween(startedAt, turn.completedAt),
            timeToFirstToken: turn.timeToFirstToken,
            model: _nonEmpty(turn.model),
            status: status,
            tokens: UsageTokenBreakdown(
              inputTokens: turn.inputTokens,
              cachedInputTokens: turn.cachedInputTokens,
              outputTokens: turn.outputTokens,
              reasoningTokens: turn.reasoningTokens,
              totalTokens: turn.totalTokens,
            ),
            errorCategory: _errorCategory(
              status: status,
              hint: turn.errorCategoryHint,
            ),
            errorMessage: _nonEmpty(turn.errorMessage),
            errorCode: _nonEmpty(turn.errorCode),
          ),
        );
      }
    }
    records.sort((left, right) => right.startedAt.compareTo(left.startedAt));

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

  String _resolveGrokHome() {
    final configured = _nonEmpty(_configuredEnvironment['GROK_HOME']);
    if (configured != null) {
      return configured;
    }
    final inherited = _nonEmpty(_environment['GROK_HOME']);
    if (inherited != null) {
      return inherited;
    }
    final home =
        _nonEmpty(_homeDirectory) ??
        _nonEmpty(_environment[Platform.isWindows ? 'USERPROFILE' : 'HOME']) ??
        Directory.current.path;
    return _joinPath(home, '.grok');
  }
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

Duration? _durationBetween(DateTime startedAt, DateTime? completedAt) {
  if (completedAt == null) {
    return null;
  }
  final duration = completedAt.difference(startedAt);
  return duration.isNegative ? Duration.zero : duration;
}

String? _nonEmpty(String? value) {
  final cleaned = value?.trim();
  return cleaned == null || cleaned.isEmpty ? null : cleaned;
}

String _joinPath(String left, String right) {
  if (left.endsWith('/') || left.endsWith(r'\')) {
    return '$left$right';
  }
  return '$left${Platform.pathSeparator}$right';
}

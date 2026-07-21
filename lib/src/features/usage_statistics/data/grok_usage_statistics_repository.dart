import 'dart:io';

import 'package:zeta/src/features/agent/data/datasources/local_history/grok_usage_log_scanner.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_repository.dart';

typedef GrokUsageAgentProviderLoader = Future<AgentProvider> Function();

/// 基于 Grok 本地 `updates.jsonl` 的跨项目使用统计数据源。
class GrokUsageStatisticsRepository implements UsageStatisticsRepository {
  GrokUsageStatisticsRepository({
    required this.providerLoader,
    this.scanner = const FileSystemGrokUsageLogScanner(),
    Map<String, String>? environment,
    this.homeDirectory,
    this.includeQuota = true,
    DateTime Function()? clock,
  }) : _environment = environment ?? Platform.environment,
       _clock = clock ?? DateTime.now;

  final GrokUsageAgentProviderLoader providerLoader;
  final GrokUsageLogScanner scanner;
  final Map<String, String> _environment;
  final String? homeDirectory;
  final bool includeQuota;
  final DateTime Function() _clock;

  @override
  Future<UsageStatisticsSourceSnapshot> load({
    required DateTime earliest,
    bool forceRefresh = false,
  }) async {
    final provider = await providerLoader();
    final scan = await scanner.scan(
      grokHome: _resolveGrokHome(provider),
      forceRefresh: forceRefresh,
    );
    final warnings = scan.warnings.toList();

    AgentUsageQuotaSnapshot? quota;
    if (includeQuota && provider is AgentUsageQuotaProvider) {
      try {
        quota = await (provider as AgentUsageQuotaProvider).readUsageQuota();
      } catch (_) {
        warnings.add('Grok 当前未返回套餐额度信息。');
      }
    }

    final records = <AgentUsageRecord>[];
    for (final session in scan.sessions) {
      for (final turn in session.history.turns) {
        final startedAt =
            turn.startedAt ?? turn.completedAt ?? session.modifiedAt;
        if (startedAt.isBefore(earliest)) {
          continue;
        }
        records.add(
          AgentUsageRecord(
            threadId: session.threadId,
            turnId: turn.id,
            providerId: provider.config.id,
            providerName: provider.config.displayName,
            projectPath: _nonEmpty(turn.cwd) ?? session.projectPath,
            sourceKind: 'grok_acp',
            startedAt: startedAt,
            completedAt: turn.completedAt,
            duration:
                turn.duration ?? _durationBetween(startedAt, turn.completedAt),
            timeToFirstToken: turn.timeToFirstToken,
            model: _nonEmpty(turn.model),
            status: _usageStatus(turn.status),
            tokens: _tokenBreakdown(turn.tokenUsage),
            errorCategory: switch (turn.status) {
              AgentHistoryTurnStatus.interrupted =>
                UsageErrorCategory.cancelled,
              AgentHistoryTurnStatus.failed => UsageErrorCategory.other,
              _ => null,
            },
            errorMessage: _nonEmpty(turn.errorMessage),
            errorCode: _nonEmpty(turn.errorCode),
          ),
        );
      }
    }
    records.sort((left, right) => right.startedAt.compareTo(left.startedAt));

    return UsageStatisticsSourceSnapshot(
      records: List<AgentUsageRecord>.unmodifiable(records),
      refreshedAt: _clock(),
      quota: quota,
      warnings: List<String>.unmodifiable(warnings),
    );
  }

  String _resolveGrokHome(AgentProvider provider) {
    final configured = _nonEmpty(provider.config.environment['GROK_HOME']);
    if (configured != null) {
      return configured;
    }
    final inherited = _nonEmpty(_environment['GROK_HOME']);
    if (inherited != null) {
      return inherited;
    }
    final home =
        _nonEmpty(homeDirectory) ??
        _nonEmpty(_environment[Platform.isWindows ? 'USERPROFILE' : 'HOME']) ??
        Directory.current.path;
    return _joinPath(home, '.grok');
  }
}

UsageTokenBreakdown _tokenBreakdown(AgentTokenUsage? usage) {
  if (usage == null) {
    return const UsageTokenBreakdown();
  }
  final cached = usage.cachedInputTokens;
  final reasoning = usage.reasoningOutputTokens;
  return UsageTokenBreakdown(
    inputTokens: _exclusiveTokens(usage.inputTokens, cached),
    cachedInputTokens: cached,
    outputTokens: _exclusiveTokens(usage.outputTokens, reasoning),
    reasoningTokens: reasoning,
    totalTokens: usage.totalTokens,
  );
}

int? _exclusiveTokens(int? inclusive, int? nested) {
  if (inclusive == null) {
    return null;
  }
  final exclusive = inclusive - (nested ?? 0);
  return exclusive < 0 ? 0 : exclusive;
}

UsageTaskStatus _usageStatus(AgentHistoryTurnStatus status) => switch (status) {
  AgentHistoryTurnStatus.running => UsageTaskStatus.running,
  AgentHistoryTurnStatus.completed => UsageTaskStatus.completed,
  AgentHistoryTurnStatus.interrupted => UsageTaskStatus.interrupted,
  AgentHistoryTurnStatus.failed => UsageTaskStatus.failed,
  AgentHistoryTurnStatus.unknown => UsageTaskStatus.unknown,
};

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

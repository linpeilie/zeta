import 'dart:io';

import 'package:zeta/src/features/agent/data/datasources/local_history/grok_usage_log_scanner.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/usage_statistics/data/usage_statistics_index_store.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_repository.dart';

typedef GrokUsageAgentProviderLoader = Future<AgentProvider> Function();

/// 基于 Grok 本地 `updates.jsonl` 的跨项目使用统计数据源。
///
/// 记录身份固定为 Grok（[grokAgentProviderId]），不依赖当前激活 Provider。
/// [providerLoader] 仅用于解析 `GROK_HOME` 与可选套餐额度；可为空。
/// 派生索引经 [indexStore] 与 Codex 分区共存，按文件 fingerprint 增量扫描。
class GrokUsageStatisticsRepository implements UsageStatisticsRepository {
  GrokUsageStatisticsRepository({
    required this.indexStore,
    this.providerLoader,
    this.scanner = const FileSystemGrokUsageLogScanner(),
    Map<String, String>? environment,
    this.homeDirectory,
    this.includeQuota = true,
    this.providerId = grokAgentProviderId,
    String? providerName,
    DateTime Function()? clock,
  }) : providerName =
           providerName ?? AgentProviderConfig.defaultGrok.displayName,
       _environment = environment ?? Platform.environment,
       _clock = clock ?? DateTime.now;

  /// 可选；仅用于配置环境中的 `GROK_HOME` 与 [AgentUsageQuotaProvider]。
  final GrokUsageAgentProviderLoader? providerLoader;
  final UsageStatisticsIndexStore indexStore;
  final GrokUsageLogScanner scanner;
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
        warnings.add('Grok 运行时暂时不可用，已仅根据本地历史统计。');
      }
    }

    final index = await indexStore.load();
    final scan = await scanner.scan(
      grokHome: _resolveGrokHome(provider),
      cachedSessions: index.grokSessions,
      forceRefresh: forceRefresh,
    );
    warnings.addAll(scan.warnings);
    try {
      final grokSessions = <String, GrokUsageIndexedSession>{
        for (final session in scan.sessions.values) session.sourceId: session,
      };
      await indexStore.mergeSave(grokSessions: grokSessions);
    } catch (_) {
      warnings.add('统计索引暂时无法保存，本次结果仍可正常查看。');
    }

    AgentUsageQuotaSnapshot? quota;
    if (includeQuota && provider is AgentUsageQuotaProvider) {
      try {
        quota = await (provider as AgentUsageQuotaProvider).readUsageQuota();
      } catch (_) {
        warnings.add('Grok 当前未返回套餐额度信息。');
      }
    }

    final records = <AgentUsageRecord>[];
    for (final session in scan.sessions.values) {
      for (final turn in session.turns) {
        final startedAt =
            turn.startedAt ?? turn.completedAt ?? session.modifiedAt;
        if (startedAt.isBefore(earliest)) {
          continue;
        }
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
            status: _usageStatus(turn.status),
            tokens: UsageTokenBreakdown(
              inputTokens: turn.inputTokens,
              cachedInputTokens: turn.cachedInputTokens,
              outputTokens: turn.outputTokens,
              reasoningTokens: turn.reasoningTokens,
              totalTokens: turn.totalTokens,
            ),
            errorCategory: _errorCategory(
              status: _usageStatus(turn.status),
              hint: turn.errorCategoryHint,
            ),
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

  String _resolveGrokHome(AgentProvider? provider) {
    final configured = _nonEmpty(provider?.config.environment['GROK_HOME']);
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

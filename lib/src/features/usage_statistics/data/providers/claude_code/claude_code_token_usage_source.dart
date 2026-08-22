import 'dart:io';

import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_session_history_reader.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/usage_statistics/data/providers/claude_code/claude_code_usage_partition_codec.dart';
import 'package:zeta/src/features/usage_statistics/data/providers/usage_scan_cache.dart';
import 'package:zeta/src/features/usage_statistics/data/usage_statistics_partition_store.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_token_usage_source.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_query_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/fallback_usage_statistics_text_catalog.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_text_catalog.dart';

/// 直接从 Claude Code 本地历史与自有 v4 分区读取 Token 用量。
///
/// 历史解析复用 Claude Code Provider 自己的独立 identity/mapper/reducer，统计层
/// 只投影已规范化 turn，不接触消息或工具正文。
final class ClaudeCodeTokenUsageSource implements AgentTokenUsageSource {
  factory ClaudeCodeTokenUsageSource({
    required AgentProviderConfig config,
    required UsageStatisticsPartitionStore partitionStore,
    ClaudeCodeSessionHistoryReader? historyReader,
    ClaudeCodeUsagePartitionCodec codec = const ClaudeCodeUsagePartitionCodec(),
    Map<String, String>? environment,
    String? homeDirectory,
    DateTime Function()? clock,
    UsageStatisticsTextCatalog? textCatalog,
  }) {
    return ClaudeCodeTokenUsageSource._(
      providerId: config.id,
      providerName: config.displayName,
      configuredEnvironment: config.environment,
      partitionStore: partitionStore,
      historyReader:
          historyReader ??
          ClaudeCodeSessionHistoryReader(
            homeResolver: homeDirectory == null ? null : () => homeDirectory,
          ),
      codec: codec,
      environment: environment ?? Platform.environment,
      clock: clock ?? DateTime.now,
      textCatalog: textCatalog ?? const FallbackUsageStatisticsTextCatalog(),
    );
  }

  ClaudeCodeTokenUsageSource._({
    required this.providerId,
    required this.providerName,
    required Map<String, String> configuredEnvironment,
    required this._partitionStore,
    required this._historyReader,
    required this._codec,
    required Map<String, String> environment,
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
  final ClaudeCodeSessionHistoryReader _historyReader;
  final ClaudeCodeUsagePartitionCodec _codec;
  final Map<String, String> _environment;
  final DateTime Function() _clock;
  final UsageStatisticsTextCatalog _textCatalog;

  @override
  Future<AgentTokenUsageSourceSnapshot> load(AgentUsageQuery query) async {
    final warnings = <AgentUsageWarning>[];
    Map<String, ClaudeCodeUsageIndexedSession> cachedSessions;
    try {
      cachedSessions = _codec.decode(
        await _partitionStore.readPartition(providerId),
      );
    } catch (_) {
      cachedSessions = const <String, ClaudeCodeUsageIndexedSession>{};
      warnings.add(
        AgentUsageWarning(
          code: 'claude-code-index-read',
          message: _textCatalog.indexReadRescanned(providerName),
        ),
      );
    }

    final scan = await _scan(
      cachedSessions: cachedSessions,
      forceRefresh: query.forceRefresh,
    );
    warnings.addAll(
      scan.warnings.map(
        (message) => AgentUsageWarning(
          code: 'claude-code-source-warning',
          message: message,
        ),
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
          code: 'claude-code-index-write',
          message: _textCatalog.indexWriteFailed,
        ),
      );
    }

    final recordsById = <String, AgentUsageRecord>{};
    for (final session in scan.sessions.values) {
      for (final turn in session.turns) {
        final startedAt =
            turn.startedAt ?? turn.completedAt ?? session.modifiedAt;
        if (startedAt.isBefore(query.earliest)) {
          continue;
        }
        final status = _usageStatus(turn.status);
        final record = AgentUsageRecord(
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
        );
        final existing = recordsById[record.id];
        if (existing == null || _isMoreComplete(record, existing)) {
          recordsById[record.id] = record;
        }
      }
    }

    final records = recordsById.values.toList(growable: false)
      ..sort((left, right) {
        final byTime = right.startedAt.compareTo(left.startedAt);
        return byTime != 0 ? byTime : left.id.compareTo(right.id);
      });
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

  Future<_ClaudeCodeUsageScanResult> _scan({
    required Map<String, ClaudeCodeUsageIndexedSession> cachedSessions,
    required bool forceRefresh,
  }) async {
    final effectiveEnvironment = <String, String>{
      ..._environment,
      ..._configuredEnvironment,
    };
    final claudeHome = _historyReader.resolveClaudeHome(
      environment: effectiveEnvironment,
    );
    final projectsDirectory = Directory(_joinPath(claudeHome, 'projects'));
    if (!await projectsDirectory.exists()) {
      return const _ClaudeCodeUsageScanResult(
        sessions: <String, ClaudeCodeUsageIndexedSession>{},
        warnings: <String>[],
      );
    }

    final files = <File>[];
    var discoveryFailures = 0;
    try {
      await for (final entity in projectsDirectory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File && entity.path.toLowerCase().endsWith('.jsonl')) {
          files.add(entity);
        }
      }
    } on FileSystemException {
      discoveryFailures += 1;
    }
    files.sort((left, right) => left.path.compareTo(right.path));

    final malformedBefore = _historyReader.malformedLineCount;
    final sessions = <String, ClaudeCodeUsageIndexedSession>{};
    var unreadableFiles = 0;
    for (final file in files) {
      try {
        final stat = await file.stat();
        final fingerprint = usageFileFingerprint(stat);
        final cached = findUsageCachedSession(cachedSessions, file.path);
        if (usageCacheHit(
          cachedFingerprint: cached?.fingerprint,
          currentFingerprint: fingerprint,
          forceRefresh: forceRefresh,
        )) {
          sessions[file.path] = cached!.sourcePath == file.path
              ? cached
              : cached.withSourcePath(file.path);
          continue;
        }

        final read = await _historyReader.readLocalHistoryFile(
          file: file,
          providerId: providerId,
          environment: effectiveEnvironment,
        );
        if (read == null) {
          unreadableFiles += 1;
          continue;
        }
        sessions[file.path] = ClaudeCodeUsageIndexedSession(
          sourcePath: file.path,
          fingerprint: fingerprint,
          threadId: read.threadId,
          projectPath: read.projectPath,
          sourceKind: 'claude_code_stream_json',
          modifiedAt: stat.modified,
          turns: read.history.snapshot.turns.map(_projectTurn).toList(),
        );
      } on FileSystemException {
        unreadableFiles += 1;
      } catch (_) {
        // 单个历史文件包含未知结构时继续统计其它会话。
        unreadableFiles += 1;
      }
    }

    final malformedLines = _historyReader.malformedLineCount - malformedBefore;
    return _ClaudeCodeUsageScanResult(
      sessions: Map<String, ClaudeCodeUsageIndexedSession>.unmodifiable(
        sessions,
      ),
      warnings: List<String>.unmodifiable(<String>[
        if (discoveryFailures > 0)
          _textCatalog.sessionDirIncomplete('Claude Code'),
        if (unreadableFiles > 0)
          _textCatalog.sessionFilesUnreadable(
            '$unreadableFiles',
            'Claude Code',
          ),
        if (malformedLines > 0)
          _textCatalog.historyRowsCorrupt('$malformedLines', 'Claude Code'),
      ]),
    );
  }
}

final class _ClaudeCodeUsageScanResult {
  const _ClaudeCodeUsageScanResult({
    required this.sessions,
    required this.warnings,
  });

  final Map<String, ClaudeCodeUsageIndexedSession> sessions;
  final List<String> warnings;
}

ClaudeCodeUsageIndexedTurn _projectTurn(AgentHistoryTurn turn) {
  final usage = turn.tokenUsage;
  return ClaudeCodeUsageIndexedTurn(
    id: turn.id,
    status: turn.status,
    startedAt: turn.startedAt,
    completedAt: turn.completedAt,
    duration: turn.duration,
    timeToFirstToken: turn.timeToFirstToken,
    cwd: turn.cwd,
    model: turn.modelId,
    inputTokens: _nonNegative(usage?.inputTokens),
    cachedInputTokens: _nonNegative(usage?.cachedInputTokens),
    outputTokens: _nonNegative(usage?.outputTokens),
    reasoningTokens: _nonNegative(usage?.reasoningOutputTokens),
    totalTokens: _nonNegative(usage?.totalTokens),
    errorCategoryHint: switch (turn.status) {
      AgentHistoryTurnStatus.interrupted => 'cancelled',
      AgentHistoryTurnStatus.failed => 'other',
      _ => null,
    },
    errorMessage: turn.errorMessage,
    errorCode: turn.errorCode,
  );
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

bool _isMoreComplete(AgentUsageRecord candidate, AgentUsageRecord existing) {
  final candidateScore = _recordCompleteness(candidate);
  final existingScore = _recordCompleteness(existing);
  if (candidateScore != existingScore) {
    return candidateScore > existingScore;
  }
  final candidateTotal = candidate.tokens.effectiveTotal ?? -1;
  final existingTotal = existing.tokens.effectiveTotal ?? -1;
  if (candidateTotal != existingTotal) {
    return candidateTotal > existingTotal;
  }
  final candidateCompleted = candidate.completedAt;
  final existingCompleted = existing.completedAt;
  return candidateCompleted != null &&
      (existingCompleted == null ||
          candidateCompleted.isAfter(existingCompleted));
}

int _recordCompleteness(AgentUsageRecord record) {
  var score = record.status.isTerminal ? 8 : 0;
  score += record.completedAt == null ? 0 : 2;
  score += record.duration == null ? 0 : 1;
  score += record.timeToFirstToken == null ? 0 : 1;
  score += record.model == null ? 0 : 1;
  score += record.errorCategory == null ? 0 : 1;
  score += record.tokens.inputTokens == null ? 0 : 1;
  score += record.tokens.cachedInputTokens == null ? 0 : 1;
  score += record.tokens.outputTokens == null ? 0 : 1;
  score += record.tokens.reasoningTokens == null ? 0 : 1;
  score += record.tokens.totalTokens == null ? 0 : 1;
  return score;
}

int? _nonNegative(int? value) => value == null || value < 0 ? null : value;

Duration? _durationBetween(DateTime startedAt, DateTime? completedAt) {
  if (completedAt == null) {
    return null;
  }
  final duration = completedAt.difference(startedAt);
  return duration.isNegative ? Duration.zero : duration;
}

String? _nonEmpty(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

String _joinPath(String left, String right) {
  if (left.endsWith('/') || left.endsWith(r'\')) {
    return '$left$right';
  }
  return '$left${Platform.pathSeparator}$right';
}

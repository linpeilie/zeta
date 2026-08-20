// Named public dependency parameters intentionally initialize private fields.
// ignore_for_file: prefer_initializing_formals

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:claude_code_client/claude_code_client.dart';
import 'package:codex_app_server_client/codex_app_server_client.dart';
import 'package:grok_acp_client/grok_acp_client.dart';
import 'package:usage_statistics_repository/src/usage_statistics_models.dart';
import 'package:usage_statistics_storage_client/usage_statistics_storage_client.dart';

/// Cooperative report cancellation callback.
typedef UsageStatisticsCancellationCheck = bool Function();

/// A report scan was cancelled by its caller.
final class UsageStatisticsCancelledException implements Exception {
  /// Creates a cancellation failure.
  const UsageStatisticsCancelledException();

  @override
  String toString() => 'UsageStatisticsCancelledException()';
}

/// Identifies one configured vendor input.
final class UsageProviderIdentity {
  /// Creates a provider identity.
  const UsageProviderIdentity({required this.id, required this.name});

  /// Stable configured provider identifier.
  final String id;

  /// Provider display name.
  final String name;
}

/// Aggregates vendor-owned usage readers and rebuildable storage projections.
final class UsageStatisticsRepository {
  /// Creates the repository.
  UsageStatisticsRepository({
    required CodexUsageReader codex,
    required ClaudeCodeUsageReader claude,
    required GrokUsageReader grok,
    required UsagePartitionStore cacheStore,
    required UsageProviderIdentity codexProvider,
    required UsageProviderIdentity claudeProvider,
    required UsageProviderIdentity grokProvider,
    Map<String, AgentUsageQuotaProvider> quotaProviders =
        const <String, AgentUsageQuotaProvider>{},
    DateTime Function()? clock,
  }) : _codex = codex,
       _claude = claude,
       _grok = grok,
       _codexProvider = codexProvider,
       _claudeProvider = claudeProvider,
       _grokProvider = grokProvider,
       _quotaProviders = Map.unmodifiable(quotaProviders),
       _clock = clock ?? DateTime.now,
       _codexCache = UsageScanCache(
         store: cacheStore,
         sourceKey: 'repository.codex',
       ),
       _claudeCache = UsageScanCache(
         store: cacheStore,
         sourceKey: 'repository.claude',
       ),
       _grokCache = UsageScanCache(
         store: cacheStore,
         sourceKey: 'repository.grok',
       );

  final CodexUsageReader _codex;
  final ClaudeCodeUsageReader _claude;
  final GrokUsageReader _grok;
  final UsageProviderIdentity _codexProvider;
  final UsageProviderIdentity _claudeProvider;
  final UsageProviderIdentity _grokProvider;
  final Map<String, AgentUsageQuotaProvider> _quotaProviders;
  final DateTime Function() _clock;
  final UsageScanCache _codexCache;
  final UsageScanCache _claudeCache;
  final UsageScanCache _grokCache;

  /// Builds a report for [query]. Filter selection remains Bloc state.
  Future<UsageStatisticsReport> report(
    UsageStatisticsQuery query, {
    UsageStatisticsCancellationCheck? isCancelled,
  }) async {
    if (!query.endExclusive.isAfter(query.startInclusive)) {
      throw ArgumentError.value(query.endExclusive, 'query.endExclusive');
    }
    _throwIfCancelled(isCancelled);
    final results = await Future.wait([
      _scanCodex(query, isCancelled),
      _scanClaude(query, isCancelled),
      _scanGrok(query, isCancelled),
    ]);
    _throwIfCancelled(isCancelled);
    final records =
        <UsageRecord>[
          for (final result in results) ...result.records,
        ]..sort((left, right) {
          final time = right.startedAt.compareTo(left.startedAt);
          return time != 0 ? time : left.id.compareTo(right.id);
        });
    final warnings = <UsageWarning>[
      for (final result in results) ...result.warnings,
    ];
    return UsageStatisticsReport(
      query: query,
      records: records,
      totals: _totals(records),
      warnings: warnings,
      refreshedAt: _clock(),
    );
  }

  /// Reads each configured quota capability independently.
  Future<List<UsageQuotaResult>> quotaSnapshots() async {
    final ids = _quotaProviders.keys.toList()..sort();
    return Future.wait([
      for (final id in ids) _readQuota(id, _quotaProviders[id]!),
    ]);
  }

  Future<UsageQuotaResult> _readQuota(
    String id,
    AgentUsageQuotaProvider provider,
  ) async {
    try {
      return UsageQuotaResult(
        providerId: id,
        snapshot: await provider.readUsageQuota(),
      );
    } on Object {
      return UsageQuotaResult(providerId: id, failed: true);
    }
  }

  Future<_ProviderReport> _scanCodex(
    UsageStatisticsQuery query,
    UsageStatisticsCancellationCheck? isCancelled,
  ) async {
    try {
      final scan = await _codex.scan(
        startInclusive: query.startInclusive,
        endExclusive: query.endExclusive,
        isCancelled: isCancelled,
      );
      final warnings = <UsageWarning>[
        if (scan.unreadableSourceCount > 0)
          UsageWarning(
            providerId: _codexProvider.id,
            code: UsageWarningCode.unreadableSources,
            count: scan.unreadableSourceCount,
          ),
        if (scan.discoveryFailureCount > 0)
          UsageWarning(
            providerId: _codexProvider.id,
            code: UsageWarningCode.discoveryFailure,
            count: scan.discoveryFailureCount,
          ),
      ];
      final records = <UsageRecord>[];
      final seenSamples = <String>{};
      for (final source in scan.sources) {
        final sourceRecords = await _cacheRecords(
          cache: _codexCache,
          query: query,
          sourcePath: source.sourcePath,
          fingerprint: source.fingerprint,
          build: () => _codexRecords(source, _codexProvider),
          providerId: _codexProvider.id,
          warnings: warnings,
        );
        records.addAll(
          sourceRecords.where((record) {
            final key = record.deduplicationKey;
            return key == null || seenSamples.add(key);
          }),
        );
      }
      return _ProviderReport(records: records, warnings: warnings);
    } on CodexUsageScanCancelledException {
      throw const UsageStatisticsCancelledException();
    } on Object {
      return _failed(_codexProvider.id);
    }
  }

  Future<_ProviderReport> _scanClaude(
    UsageStatisticsQuery query,
    UsageStatisticsCancellationCheck? isCancelled,
  ) async {
    try {
      final scan = await _claude.scan(
        startInclusive: query.startInclusive,
        endExclusive: query.endExclusive,
        isCancelled: isCancelled,
      );
      final warnings = <UsageWarning>[];
      final records = <UsageRecord>[];
      for (final source in scan.sources) {
        records.addAll(
          await _cacheRecords(
            cache: _claudeCache,
            query: query,
            sourcePath: source.sourcePath,
            fingerprint: source.fingerprint,
            build: () => _claudeRecords(source, _claudeProvider),
            providerId: _claudeProvider.id,
            warnings: warnings,
          ),
        );
      }
      return _ProviderReport(records: records, warnings: warnings);
    } on ClaudeCodeUsageScanCancelledException {
      throw const UsageStatisticsCancelledException();
    } on Object {
      return _failed(_claudeProvider.id);
    }
  }

  Future<_ProviderReport> _scanGrok(
    UsageStatisticsQuery query,
    UsageStatisticsCancellationCheck? isCancelled,
  ) async {
    try {
      final scan = await _grok.scan(
        startInclusive: query.startInclusive,
        endExclusive: query.endExclusive,
        isCancelled: isCancelled,
      );
      final warnings = <UsageWarning>[
        if (scan.unreadableSourceCount > 0)
          UsageWarning(
            providerId: _grokProvider.id,
            code: UsageWarningCode.unreadableSources,
            count: scan.unreadableSourceCount,
          ),
      ];
      final records = <UsageRecord>[];
      for (final source in scan.sources) {
        records.addAll(
          await _cacheRecords(
            cache: _grokCache,
            query: query,
            sourcePath: source.sourcePath,
            fingerprint: source.fingerprint,
            build: () => _grokRecords(source, _grokProvider),
            providerId: _grokProvider.id,
            warnings: warnings,
          ),
        );
      }
      return _ProviderReport(records: records, warnings: warnings);
    } on GrokUsageScanCancelledException {
      throw const UsageStatisticsCancelledException();
    } on Object {
      return _failed(_grokProvider.id);
    }
  }

  Future<List<UsageRecord>> _cacheRecords({
    required UsageScanCache cache,
    required UsageStatisticsQuery query,
    required String sourcePath,
    required String fingerprint,
    required List<UsageRecord> Function() build,
    required String providerId,
    required List<UsageWarning> warnings,
  }) async {
    final sourceId = usageSourceId(sourcePath);
    try {
      final hit = await cache.read(
        sourceId: sourceId,
        fingerprint: fingerprint,
        forceRefresh: query.forceRefresh,
      );
      if (hit != null && _matchesQuery(hit.payload, query)) {
        return _decodeRecords(hit.payload);
      }
    } on Object {
      warnings.add(
        UsageWarning(
          providerId: providerId,
          code: UsageWarningCode.cacheReadFailure,
        ),
      );
    }
    final records = build();
    try {
      await cache.write(
        UsageScanCacheEntry(
          sourceId: sourceId,
          fingerprint: fingerprint,
          payload: _encodeRecords(query, records),
        ),
      );
    } on Object {
      warnings.add(
        UsageWarning(
          providerId: providerId,
          code: UsageWarningCode.cacheWriteFailure,
        ),
      );
    }
    return records;
  }
}

final class _ProviderReport {
  const _ProviderReport({required this.records, required this.warnings});

  final List<UsageRecord> records;
  final List<UsageWarning> warnings;
}

_ProviderReport _failed(String providerId) => _ProviderReport(
  records: const [],
  warnings: [
    UsageWarning(
      providerId: providerId,
      code: UsageWarningCode.providerFailure,
    ),
  ],
);

List<UsageRecord> _codexRecords(
  CodexUsageSourceResponse source,
  UsageProviderIdentity provider,
) {
  final records = <UsageRecord>[];
  final seen = <String>{};
  for (final turn in source.turns) {
    final samples = turn.samples.where(
      (sample) => seen.add(sample.deduplicationKey),
    );
    for (final sample in samples) {
      records.add(
        UsageRecord(
          threadId: source.threadId,
          turnId: '${turn.id}:${sample.deduplicationKey}',
          providerId: provider.id,
          providerName: provider.name,
          projectPath: _nonEmpty(turn.cwd) ?? source.projectPath,
          sourceKind: source.sourceKind,
          startedAt: sample.timestamp,
          completedAt: turn.completedAt,
          duration: _duration(sample.timestamp, turn.completedAt),
          model: _nonEmpty(turn.model),
          deduplicationKey: sample.deduplicationKey,
          status: _status(turn.status),
          tokens: UsageTokenBreakdown(
            inputTokens: sample.inputTokens,
            cachedInputTokens: sample.cachedInputTokens,
            outputTokens: sample.outputTokens,
            reasoningTokens: sample.reasoningTokens,
            totalTokens: sample.totalTokens,
          ),
        ),
      );
    }
  }
  return records;
}

List<UsageRecord> _claudeRecords(
  ClaudeCodeUsageSourceResponse source,
  UsageProviderIdentity provider,
) => [
  for (final turn in source.turns)
    _turnRecord(
      providerId: provider.id,
      providerName: provider.name,
      sourceKind: 'claude_code_stream_json',
      threadId: source.threadId,
      projectPath: source.projectPath,
      modifiedAt: source.modifiedAt,
      id: turn.id,
      status: turn.status,
      startedAt: turn.startedAt,
      completedAt: turn.completedAt,
      duration: turn.duration,
      timeToFirstToken: turn.timeToFirstToken,
      cwd: turn.cwd,
      model: turn.model,
      inputTokens: turn.inputTokens,
      cachedInputTokens: turn.cachedInputTokens,
      outputTokens: turn.outputTokens,
      reasoningTokens: turn.reasoningTokens,
      totalTokens: turn.totalTokens,
    ),
];

List<UsageRecord> _grokRecords(
  GrokUsageSourceResponse source,
  UsageProviderIdentity provider,
) => [
  for (final turn in source.turns)
    _turnRecord(
      providerId: provider.id,
      providerName: provider.name,
      sourceKind: 'grok_acp_updates_jsonl',
      threadId: source.threadId,
      projectPath: source.projectPath,
      modifiedAt: source.modifiedAt,
      id: turn.id,
      status: turn.status,
      startedAt: turn.startedAt,
      completedAt: turn.completedAt,
      duration: turn.duration,
      timeToFirstToken: turn.timeToFirstToken,
      cwd: turn.cwd,
      model: turn.model,
      inputTokens: turn.inputTokens,
      cachedInputTokens: turn.cachedInputTokens,
      outputTokens: turn.outputTokens,
      reasoningTokens: turn.reasoningTokens,
      totalTokens: turn.totalTokens,
    ),
];

UsageRecord _turnRecord({
  required String providerId,
  required String providerName,
  required String sourceKind,
  required String threadId,
  required String projectPath,
  required DateTime modifiedAt,
  required String id,
  required String status,
  required DateTime? startedAt,
  required DateTime? completedAt,
  required Duration? duration,
  required Duration? timeToFirstToken,
  required String? cwd,
  required String? model,
  required int? inputTokens,
  required int? cachedInputTokens,
  required int? outputTokens,
  required int? reasoningTokens,
  required int? totalTokens,
}) {
  final start = startedAt ?? completedAt ?? modifiedAt;
  return UsageRecord(
    threadId: threadId,
    turnId: id,
    providerId: providerId,
    providerName: providerName,
    projectPath: _nonEmpty(cwd) ?? projectPath,
    sourceKind: sourceKind,
    startedAt: start,
    completedAt: completedAt,
    duration: duration ?? _duration(start, completedAt),
    timeToFirstToken: timeToFirstToken,
    model: _nonEmpty(model),
    status: _status(status),
    tokens: UsageTokenBreakdown(
      inputTokens: _nonNegative(inputTokens),
      cachedInputTokens: _nonNegative(cachedInputTokens),
      outputTokens: _nonNegative(outputTokens),
      reasoningTokens: _nonNegative(reasoningTokens),
      totalTokens: _nonNegative(totalTokens),
    ),
  );
}

UsageTaskStatus _status(String status) => switch (status.toLowerCase()) {
  'running' || 'in_progress' => UsageTaskStatus.running,
  'completed' || 'success' || 'succeeded' => UsageTaskStatus.completed,
  'interrupted' || 'cancelled' || 'canceled' => UsageTaskStatus.interrupted,
  'failed' || 'error' => UsageTaskStatus.failed,
  _ => UsageTaskStatus.unknown,
};

UsageTotals _totals(Iterable<UsageRecord> records) {
  var calls = 0;
  var failures = 0;
  var input = 0;
  var cached = 0;
  var output = 0;
  var reasoning = 0;
  var total = 0;
  for (final record in records) {
    calls += 1;
    if (record.status.isFailure) failures += 1;
    input += record.tokens.inputTokens ?? 0;
    cached += record.tokens.cachedInputTokens ?? 0;
    output += record.tokens.outputTokens ?? 0;
    reasoning += record.tokens.reasoningTokens ?? 0;
    total += record.tokens.effectiveTotal ?? 0;
  }
  return UsageTotals(
    calls: calls,
    failures: failures,
    inputTokens: input,
    cachedInputTokens: cached,
    outputTokens: output,
    reasoningTokens: reasoning,
    totalTokens: total,
  );
}

Map<String, Object?> _encodeRecords(
  UsageStatisticsQuery query,
  Iterable<UsageRecord> records,
) => {
  'start': query.startInclusive.toUtc().toIso8601String(),
  'end': query.endExclusive.toUtc().toIso8601String(),
  'records': [for (final record in records) _encodeRecord(record)],
};

Map<String, Object?> _encodeRecord(UsageRecord record) => {
  'threadId': record.threadId,
  'turnId': record.turnId,
  'providerId': record.providerId,
  'providerName': record.providerName,
  'projectPath': record.projectPath,
  'sourceKind': record.sourceKind,
  'startedAt': record.startedAt.toUtc().toIso8601String(),
  'completedAt': record.completedAt?.toUtc().toIso8601String(),
  'durationUs': record.duration?.inMicroseconds,
  'ttftUs': record.timeToFirstToken?.inMicroseconds,
  'model': record.model,
  'deduplicationKey': record.deduplicationKey,
  'status': record.status.name,
  'input': record.tokens.inputTokens,
  'cached': record.tokens.cachedInputTokens,
  'output': record.tokens.outputTokens,
  'reasoning': record.tokens.reasoningTokens,
  'total': record.tokens.totalTokens,
};

bool _matchesQuery(
  Map<String, Object?> payload,
  UsageStatisticsQuery query,
) =>
    payload['start'] == query.startInclusive.toUtc().toIso8601String() &&
    payload['end'] == query.endExclusive.toUtc().toIso8601String();

List<UsageRecord> _decodeRecords(Map<String, Object?> payload) {
  final rawRecords = payload['records'];
  if (rawRecords is! List<Object?>) throw const FormatException();
  return [for (final raw in rawRecords) _decodeRecord(raw)];
}

UsageRecord _decodeRecord(Object? raw) {
  if (raw is! Map<String, Object?>) throw const FormatException();
  final statusName = raw['status'];
  if (statusName is! String) throw const FormatException();
  return UsageRecord(
    threadId: _requiredString(raw, 'threadId'),
    turnId: _requiredString(raw, 'turnId'),
    providerId: _requiredString(raw, 'providerId'),
    providerName: _requiredString(raw, 'providerName'),
    projectPath: _requiredString(raw, 'projectPath'),
    sourceKind: _requiredString(raw, 'sourceKind'),
    startedAt: DateTime.parse(_requiredString(raw, 'startedAt')),
    completedAt: _optionalDate(raw['completedAt']),
    duration: _optionalDuration(raw['durationUs']),
    timeToFirstToken: _optionalDuration(raw['ttftUs']),
    model: raw['model'] as String?,
    deduplicationKey: raw['deduplicationKey'] as String?,
    status: UsageTaskStatus.values.byName(statusName),
    tokens: UsageTokenBreakdown(
      inputTokens: raw['input'] as int?,
      cachedInputTokens: raw['cached'] as int?,
      outputTokens: raw['output'] as int?,
      reasoningTokens: raw['reasoning'] as int?,
      totalTokens: raw['total'] as int?,
    ),
  );
}

String _requiredString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! String) throw const FormatException();
  return value;
}

DateTime? _optionalDate(Object? value) =>
    value == null ? null : DateTime.parse(value as String);

Duration? _optionalDuration(Object? value) =>
    value == null ? null : Duration(microseconds: value as int);

Duration? _duration(DateTime startedAt, DateTime? completedAt) {
  if (completedAt == null) return null;
  final value = completedAt.difference(startedAt);
  return value.isNegative ? Duration.zero : value;
}

int? _nonNegative(int? value) => value == null || value < 0 ? null : value;

String? _nonEmpty(String? value) {
  final result = value?.trim();
  return result == null || result.isEmpty ? null : result;
}

void _throwIfCancelled(UsageStatisticsCancellationCheck? isCancelled) {
  if (isCancelled?.call() ?? false) {
    throw const UsageStatisticsCancelledException();
  }
}

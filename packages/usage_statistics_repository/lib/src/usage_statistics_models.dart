import 'dart:collection';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:equatable/equatable.dart';

/// One half-open reporting interval.
final class UsageStatisticsQuery extends Equatable {
  /// Creates a query for `[startInclusive, endExclusive)`.
  const UsageStatisticsQuery({
    required this.startInclusive,
    required this.endExclusive,
    this.forceRefresh = false,
  });

  /// Inclusive lower time boundary.
  final DateTime startInclusive;

  /// Exclusive upper time boundary.
  final DateTime endExclusive;

  /// Whether rebuildable cached projections must be ignored.
  final bool forceRefresh;

  @override
  List<Object?> get props => [startInclusive, endExclusive, forceRefresh];
}

/// Stable task status projected from vendor history.
enum UsageTaskStatus {
  /// The task is still executing.
  running,

  /// The task completed normally.
  completed,

  /// The task was interrupted or cancelled.
  interrupted,

  /// The task failed.
  failed,

  /// The vendor returned an unrecognized state.
  unknown;

  /// Whether this status is terminal.
  bool get isTerminal => this != running && this != unknown;

  /// Whether this status represents an unsuccessful terminal state.
  bool get isFailure => this == interrupted || this == failed;
}

/// Token counts for one usage record.
final class UsageTokenBreakdown extends Equatable {
  /// Creates token counts. Missing vendor fields remain `null`.
  const UsageTokenBreakdown({
    this.inputTokens,
    this.cachedInputTokens,
    this.outputTokens,
    this.reasoningTokens,
    this.totalTokens,
  });

  /// Non-cached input tokens.
  final int? inputTokens;

  /// Cached input tokens.
  final int? cachedInputTokens;

  /// Visible output tokens.
  final int? outputTokens;

  /// Reasoning tokens.
  final int? reasoningTokens;

  /// Provider-reported total tokens.
  final int? totalTokens;

  /// Reported total, or the sum of available component counts.
  int? get effectiveTotal {
    if (totalTokens case final total?) {
      return total;
    }
    final components = [
      inputTokens,
      cachedInputTokens,
      outputTokens,
      reasoningTokens,
    ];
    return components.every((value) => value == null)
        ? null
        : components.fold<int>(0, (sum, value) => sum + (value ?? 0));
  }

  @override
  List<Object?> get props => [
    inputTokens,
    cachedInputTokens,
    outputTokens,
    reasoningTokens,
    totalTokens,
  ];
}

/// One content-free provider usage record.
final class UsageRecord extends Equatable {
  /// Creates a record.
  const UsageRecord({
    required this.threadId,
    required this.turnId,
    required this.providerId,
    required this.providerName,
    required this.projectPath,
    required this.sourceKind,
    required this.startedAt,
    required this.status,
    required this.tokens,
    this.completedAt,
    this.duration,
    this.timeToFirstToken,
    this.model,
    this.deduplicationKey,
  });

  /// Provider-scoped stable record identifier.
  String get id => '$providerId:$threadId:$turnId';

  /// Provider thread identifier.
  final String threadId;

  /// Provider turn or usage-sample identifier.
  final String turnId;

  /// Stable configured provider identifier.
  final String providerId;

  /// Display name supplied at composition.
  final String providerName;

  /// Project path supplied by provider history.
  final String projectPath;

  /// Vendor-owned source kind.
  final String sourceKind;

  /// Start or occurrence timestamp.
  final DateTime startedAt;

  /// Completion timestamp.
  final DateTime? completedAt;

  /// Total task duration.
  final Duration? duration;

  /// Time to first token.
  final Duration? timeToFirstToken;

  /// Vendor model identifier.
  final String? model;

  /// Optional content-free key shared by replayed provider samples.
  final String? deduplicationKey;

  /// Stable task status.
  final UsageTaskStatus status;

  /// Token usage.
  final UsageTokenBreakdown tokens;

  @override
  List<Object?> get props => [
    threadId,
    turnId,
    providerId,
    providerName,
    projectPath,
    sourceKind,
    startedAt,
    completedAt,
    duration,
    timeToFirstToken,
    model,
    deduplicationKey,
    status,
    tokens,
  ];
}

/// Non-localized warning code emitted while building a provider report.
enum UsageWarningCode {
  /// One or more provider files could not be read or decoded.
  unreadableSources,

  /// Provider history discovery was incomplete.
  discoveryFailure,

  /// A rebuildable cache entry could not be read.
  cacheReadFailure,

  /// A rebuildable cache entry could not be persisted.
  cacheWriteFailure,

  /// The provider reader failed before returning a partial result.
  providerFailure,
}

/// One content-free report warning.
final class UsageWarning extends Equatable {
  /// Creates a warning.
  const UsageWarning({
    required this.providerId,
    required this.code,
    this.count = 1,
  });

  /// Provider that produced the warning.
  final String providerId;

  /// Stable warning code mapped to localized copy by the app.
  final UsageWarningCode code;

  /// Number of affected sources or operations.
  final int count;

  @override
  List<Object?> get props => [providerId, code, count];
}

/// Aggregated token totals.
final class UsageTotals extends Equatable {
  /// Creates totals.
  const UsageTotals({
    required this.calls,
    required this.failures,
    required this.inputTokens,
    required this.cachedInputTokens,
    required this.outputTokens,
    required this.reasoningTokens,
    required this.totalTokens,
  });

  /// Number of usage records.
  final int calls;

  /// Number of failed or interrupted records.
  final int failures;

  /// Non-cached input tokens.
  final int inputTokens;

  /// Cached input tokens.
  final int cachedInputTokens;

  /// Visible output tokens.
  final int outputTokens;

  /// Reasoning tokens.
  final int reasoningTokens;

  /// Effective total tokens.
  final int totalTokens;

  @override
  List<Object?> get props => [
    calls,
    failures,
    inputTokens,
    cachedInputTokens,
    outputTokens,
    reasoningTokens,
    totalTokens,
  ];
}

/// Domain report returned to the usage statistics Bloc.
final class UsageStatisticsReport extends Equatable {
  /// Creates an immutable report.
  UsageStatisticsReport({
    required this.query,
    required Iterable<UsageRecord> records,
    required this.totals,
    required Iterable<UsageWarning> warnings,
    required this.refreshedAt,
  }) : records = UnmodifiableListView<UsageRecord>(List.of(records)),
       warnings = UnmodifiableListView<UsageWarning>(List.of(warnings));

  /// Time interval used to build this report.
  final UsageStatisticsQuery query;

  /// Usage records sorted newest first.
  final List<UsageRecord> records;

  /// Totals across [records].
  final UsageTotals totals;

  /// Non-localized partial-failure warnings.
  final List<UsageWarning> warnings;

  /// Time at which aggregation completed.
  final DateTime refreshedAt;

  @override
  List<Object?> get props => [query, records, totals, warnings, refreshedAt];
}

/// Result of one provider quota capability.
final class UsageQuotaResult extends Equatable {
  /// Creates an available or unsupported result.
  const UsageQuotaResult({
    required this.providerId,
    this.snapshot,
    this.failed = false,
  });

  /// Configured provider identifier.
  final String providerId;

  /// Available snapshot, or `null` when unsupported or failed.
  final AgentUsageQuotaSnapshot? snapshot;

  /// Whether the port threw while reading quota.
  final bool failed;

  @override
  List<Object?> get props => [providerId, snapshot, failed];
}

import 'dart:math' as math;

import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';

/// 将中立调用记录聚合为页面直接消费的统计报告。
UsageStatisticsReport buildUsageStatisticsReport({
  required UsageStatisticsSourceSnapshot source,
  required UsageDateWindow window,
  required UsageStatisticsFilter filter,
  required UsageTrendMetric trendMetric,
  required UsageRankSort rankSort,
}) {
  final recordsInWindow = source.records
      .where((record) => window.contains(record.startedAt))
      .toList();
  final previousRecords = source.records
      .where((record) => window.previous.contains(record.startedAt))
      .where((record) => _matchesFilter(record, filter))
      .toList();
  final filtered =
      recordsInWindow.where((record) => _matchesFilter(record, filter)).toList()
        ..sort((left, right) => right.startedAt.compareTo(left.startedAt));

  final projectOptions =
      recordsInWindow
          .map((record) => record.projectPath)
          .where((path) => path.isNotEmpty)
          .toSet()
          .toList()
        ..sort(
          (left, right) =>
              usageProjectName(left).compareTo(usageProjectName(right)),
        );
  final agentOptions =
      recordsInWindow.map((record) => record.providerId).toSet().toList()
        ..sort();
  final modelOptions =
      recordsInWindow
          .map((record) => record.model)
          .whereType<String>()
          .where((model) => model.trim().isNotEmpty)
          .toSet()
          .toList()
        ..sort();

  return UsageStatisticsReport(
    window: window,
    records: List<AgentUsageRecord>.unmodifiable(filtered),
    overview: _buildOverview(filtered, previousRecords),
    trend: _buildTrend(filtered, window, trendMetric),
    agentRanking: _buildAgentRanking(filtered, rankSort),
    projectRanking: _buildProjectRanking(filtered),
    modelShares: _buildModelShares(filtered),
    tokenTrend: _buildTrend(filtered, window, UsageTrendMetric.totalTokens),
    errors: _buildErrors(filtered),
    projectOptions: List<String>.unmodifiable(projectOptions),
    agentOptions: List<String>.unmodifiable(agentOptions),
    modelOptions: List<String>.unmodifiable(modelOptions),
  );
}

bool _matchesFilter(AgentUsageRecord record, UsageStatisticsFilter filter) {
  if (filter.projectPath != null && record.projectPath != filter.projectPath) {
    return false;
  }
  if (filter.providerId != null && record.providerId != filter.providerId) {
    return false;
  }
  if (filter.model != null && record.model != filter.model) {
    return false;
  }
  return true;
}

UsageOverview _buildOverview(
  List<AgentUsageRecord> records,
  List<AgentUsageRecord> previousRecords,
) {
  final terminal = records.where((record) => record.status.isTerminal).toList();
  final succeeded = terminal
      .where((record) => record.status == UsageTaskStatus.completed)
      .length;
  final failed = terminal.where((record) => record.status.isFailure).length;
  final responseSamples = records
      .where((record) => record.timeToFirstToken != null)
      .toList();
  final recentProjectPath = records.isEmpty ? null : records.first.projectPath;
  final currentCalls = records.length.toDouble();
  final previousCalls = previousRecords.length.toDouble();
  return UsageOverview(
    totalCalls: records.length,
    failedCalls: failed,
    successRate: terminal.isEmpty ? null : succeeded / terminal.length,
    averageResponse: averageUsageDuration(
      responseSamples.map((record) => record.timeToFirstToken),
    ),
    responseSampleCount: responseSamples.length,
    averageDuration: averageUsageDuration(
      terminal.map((record) => record.duration),
    ),
    tokens: _sumTokens(records),
    callComparison: UsageMetricComparison(
      current: currentCalls,
      previous: previousCalls,
      changePercent: previousCalls == 0
          ? null
          : ((currentCalls - previousCalls) / previousCalls) * 100,
    ),
    recentProjectPath: recentProjectPath,
  );
}

UsageTokenBreakdown _sumTokens(Iterable<AgentUsageRecord> records) {
  var hasInput = false;
  var hasCached = false;
  var hasOutput = false;
  var hasReasoning = false;
  var hasTotal = false;
  var input = 0;
  var cached = 0;
  var output = 0;
  var reasoning = 0;
  var total = 0;
  for (final record in records) {
    final tokens = record.tokens;
    if (tokens.inputTokens != null) {
      hasInput = true;
      input += tokens.inputTokens!;
    }
    if (tokens.cachedInputTokens != null) {
      hasCached = true;
      cached += tokens.cachedInputTokens!;
    }
    if (tokens.outputTokens != null) {
      hasOutput = true;
      output += tokens.outputTokens!;
    }
    if (tokens.reasoningTokens != null) {
      hasReasoning = true;
      reasoning += tokens.reasoningTokens!;
    }
    final effectiveTotal = tokens.effectiveTotal;
    if (effectiveTotal != null) {
      hasTotal = true;
      total += effectiveTotal;
    }
  }
  return UsageTokenBreakdown(
    inputTokens: hasInput ? input : null,
    cachedInputTokens: hasCached ? cached : null,
    outputTokens: hasOutput ? output : null,
    reasoningTokens: hasReasoning ? reasoning : null,
    totalTokens: hasTotal ? total : null,
  );
}

List<UsageTrendPoint> _buildTrend(
  List<AgentUsageRecord> records,
  UsageDateWindow window,
  UsageTrendMetric metric,
) {
  final bucketDuration = _trendBucketDuration(window);
  final points = <UsageTrendPoint>[];
  var bucketStart = window.start;
  while (bucketStart.isBefore(window.endExclusive)) {
    final candidateEnd = bucketStart.add(bucketDuration);
    final bucketEnd = candidateEnd.isAfter(window.endExclusive)
        ? window.endExclusive
        : candidateEnd;
    final bucketRecords = records
        .where(
          (record) =>
              !record.startedAt.isBefore(bucketStart) &&
              record.startedAt.isBefore(bucketEnd),
        )
        .toList();
    points.add(
      UsageTrendPoint(
        start: bucketStart,
        endExclusive: bucketEnd,
        label: _trendLabel(bucketStart, bucketDuration),
        value: _trendValue(bucketRecords, metric),
      ),
    );
    bucketStart = bucketEnd;
  }
  return List<UsageTrendPoint>.unmodifiable(points);
}

Duration _trendBucketDuration(UsageDateWindow window) {
  if (window.duration <= const Duration(days: 2)) {
    return const Duration(hours: 1);
  }
  if (window.duration <= const Duration(days: 45)) {
    return const Duration(days: 1);
  }
  return const Duration(days: 7);
}

String _trendLabel(DateTime value, Duration bucketDuration) {
  if (bucketDuration <= const Duration(hours: 1)) {
    return '${value.hour.toString().padLeft(2, '0')}:00';
  }
  return '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

double? _trendValue(List<AgentUsageRecord> records, UsageTrendMetric metric) {
  return switch (metric) {
    UsageTrendMetric.calls => records.length.toDouble(),
    UsageTrendMetric.successRate => _successRate(records),
    UsageTrendMetric.totalTokens => _tokenTrendValue(records),
    UsageTrendMetric.averageResponse => _durationTrendValue(
      records.map((record) => record.timeToFirstToken),
    ),
    UsageTrendMetric.averageDuration => _durationTrendValue(
      records
          .where((record) => record.status.isTerminal)
          .map((record) => record.duration),
    ),
  };
}

double? _successRate(List<AgentUsageRecord> records) {
  final terminal = records.where((record) => record.status.isTerminal).toList();
  if (terminal.isEmpty) {
    return null;
  }
  final completed = terminal
      .where((record) => record.status == UsageTaskStatus.completed)
      .length;
  return completed / terminal.length;
}

double? _tokenTrendValue(List<AgentUsageRecord> records) {
  final total = _sumTokens(records).totalTokens;
  return total?.toDouble();
}

double? _durationTrendValue(Iterable<Duration?> values) {
  return averageUsageDuration(values)?.inMilliseconds.toDouble();
}

List<UsageAgentRankEntry> _buildAgentRanking(
  List<AgentUsageRecord> records,
  UsageRankSort rankSort,
) {
  final groups = <String, List<AgentUsageRecord>>{};
  for (final record in records) {
    groups
        .putIfAbsent(record.providerId, () => <AgentUsageRecord>[])
        .add(record);
  }
  final result = <UsageAgentRankEntry>[];
  for (final entry in groups.entries) {
    final values = entry.value;
    final terminal = values
        .where((record) => record.status.isTerminal)
        .toList();
    final completed = terminal
        .where((record) => record.status == UsageTaskStatus.completed)
        .length;
    result.add(
      UsageAgentRankEntry(
        providerId: entry.key,
        providerName: values.first.providerName,
        calls: values.length,
        failures: terminal.where((record) => record.status.isFailure).length,
        successRate: terminal.isEmpty ? null : completed / terminal.length,
        totalTokens: _sumTokens(values).totalTokens,
        averageDuration: averageUsageDuration(
          terminal.map((record) => record.duration),
        ),
      ),
    );
  }
  result.sort((left, right) {
    final comparison = switch (rankSort) {
      UsageRankSort.calls => right.calls.compareTo(left.calls),
      UsageRankSort.totalTokens => (right.totalTokens ?? -1).compareTo(
        left.totalTokens ?? -1,
      ),
      UsageRankSort.failures => right.failures.compareTo(left.failures),
      UsageRankSort.averageDuration =>
        (right.averageDuration?.inMilliseconds ?? -1).compareTo(
          left.averageDuration?.inMilliseconds ?? -1,
        ),
    };
    return comparison != 0
        ? comparison
        : left.providerName.compareTo(right.providerName);
  });
  return List<UsageAgentRankEntry>.unmodifiable(result);
}

List<UsageProjectRankEntry> _buildProjectRanking(
  List<AgentUsageRecord> records,
) {
  final groups = <String, List<AgentUsageRecord>>{};
  for (final record in records) {
    groups
        .putIfAbsent(record.projectPath, () => <AgentUsageRecord>[])
        .add(record);
  }
  final result = <UsageProjectRankEntry>[];
  for (final entry in groups.entries) {
    final values = entry.value;
    result.add(
      UsageProjectRankEntry(
        projectPath: entry.key,
        calls: values.length,
        totalTokens: _sumTokens(values).totalTokens,
        averageDuration: averageUsageDuration(
          values
              .where((record) => record.status.isTerminal)
              .map((record) => record.duration),
        ),
        lastUsedAt: values
            .map((record) => record.startedAt)
            .reduce((left, right) => left.isAfter(right) ? left : right),
      ),
    );
  }
  result.sort((left, right) => right.calls.compareTo(left.calls));
  return List<UsageProjectRankEntry>.unmodifiable(result);
}

List<UsageModelShare> _buildModelShares(List<AgentUsageRecord> records) {
  final totals = <String, int>{};
  for (final record in records) {
    final model = record.model;
    final total = record.tokens.effectiveTotal;
    if (model == null || model.trim().isEmpty || total == null) {
      continue;
    }
    totals.update(model, (value) => value + total, ifAbsent: () => total);
  }
  final grandTotal = totals.values.fold<int>(0, (sum, value) => sum + value);
  if (grandTotal == 0) {
    return const <UsageModelShare>[];
  }
  final result =
      totals.entries
          .map(
            (entry) => UsageModelShare(
              model: entry.key,
              totalTokens: entry.value,
              ratio: entry.value / grandTotal,
            ),
          )
          .toList()
        ..sort((left, right) => right.totalTokens.compareTo(left.totalTokens));
  return List<UsageModelShare>.unmodifiable(result);
}

List<UsageErrorBreakdown> _buildErrors(List<AgentUsageRecord> records) {
  final counts = <UsageErrorCategory, int>{};
  for (final record in records.where((record) => record.status.isFailure)) {
    final category = record.errorCategory ?? UsageErrorCategory.other;
    counts.update(category, (value) => value + 1, ifAbsent: () => 1);
  }
  final result =
      counts.entries
          .map(
            (entry) =>
                UsageErrorBreakdown(category: entry.key, count: entry.value),
          )
          .toList()
        ..sort((left, right) => right.count.compareTo(left.count));
  return List<UsageErrorBreakdown>.unmodifiable(result);
}

double safeUsageChartMaximum(Iterable<UsageTrendPoint> points) {
  var maximum = 0.0;
  for (final point in points) {
    maximum = math.max(maximum, point.value ?? 0);
  }
  return maximum <= 0 ? 1 : maximum;
}

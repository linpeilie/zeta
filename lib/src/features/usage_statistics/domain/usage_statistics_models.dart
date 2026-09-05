import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'dart:math' as math;

import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 使用统计支持的时间范围。
enum UsageTimeRangePreset {
  today,
  last7Days,
  last30Days,
  last90Days,
  thisMonth,
  previousMonth,
  custom,
}

/// 时间范围弹层左侧快捷选项（不含自定义；日历选择即自定义）。
const List<UsageTimeRangePreset> kUsageTimeRangeQuickOptions =
    <UsageTimeRangePreset>[
      UsageTimeRangePreset.today,
      UsageTimeRangePreset.last7Days,
      UsageTimeRangePreset.last30Days,
    ];

/// 左闭右开的统计时间窗口。
class UsageDateWindow {
  const UsageDateWindow({required this.start, required this.endExclusive});

  final DateTime start;
  final DateTime endExclusive;

  Duration get duration => endExclusive.difference(start);

  bool contains(DateTime value) =>
      !value.isBefore(start) && value.isBefore(endExclusive);

  UsageDateWindow get previous {
    final windowDuration = duration;
    return UsageDateWindow(
      start: start.subtract(windowDuration),
      endExclusive: start,
    );
  }

  static UsageDateWindow resolve({
    required UsageTimeRangePreset preset,
    required DateTime now,
    DateTime? customStart,
    DateTime? customEndInclusive,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    return switch (preset) {
      UsageTimeRangePreset.today => UsageDateWindow(
        start: today,
        endExclusive: now,
      ),
      UsageTimeRangePreset.last7Days => UsageDateWindow(
        start: today.subtract(const Duration(days: 6)),
        endExclusive: now,
      ),
      UsageTimeRangePreset.last30Days => UsageDateWindow(
        start: today.subtract(const Duration(days: 29)),
        endExclusive: now,
      ),
      UsageTimeRangePreset.last90Days => UsageDateWindow(
        start: today.subtract(const Duration(days: 89)),
        endExclusive: now,
      ),
      UsageTimeRangePreset.thisMonth => UsageDateWindow(
        start: DateTime(now.year, now.month),
        endExclusive: now,
      ),
      UsageTimeRangePreset.previousMonth => UsageDateWindow(
        start: DateTime(now.year, now.month - 1),
        endExclusive: DateTime(now.year, now.month),
      ),
      UsageTimeRangePreset.custom => _customWindow(
        customStart: customStart,
        customEndInclusive: customEndInclusive,
        today: today,
      ),
    };
  }

  static UsageDateWindow _customWindow({
    required DateTime? customStart,
    required DateTime? customEndInclusive,
    required DateTime today,
  }) {
    final rawStart = customStart ?? today.subtract(const Duration(days: 6));
    final rawEnd = customEndInclusive ?? today;
    final start = DateTime(rawStart.year, rawStart.month, rawStart.day);
    final end = DateTime(rawEnd.year, rawEnd.month, rawEnd.day);
    final normalizedStart = start.isAfter(end) ? end : start;
    final normalizedEnd = start.isAfter(end) ? start : end;
    return UsageDateWindow(
      start: normalizedStart,
      endExclusive: normalizedEnd.add(const Duration(days: 1)),
    );
  }
}

class UsageStatisticsSourceSnapshot {
  const UsageStatisticsSourceSnapshot({
    required this.records,
    required this.refreshedAt,
    this.quota,
    this.warnings = const <String>[],
  });

  final List<AgentUsageRecord> records;
  final DateTime refreshedAt;
  final AgentUsageQuotaSnapshot? quota;
  final List<String> warnings;
}

class UsageStatisticsFilter {
  const UsageStatisticsFilter({this.projectPath, this.providerId, this.model});

  final String? projectPath;
  final String? providerId;
  final String? model;
}

enum UsageTrendMetric {
  calls,
  successRate,
  totalTokens,
  averageResponse,
  averageDuration,
}

enum UsageRankSort { calls, totalTokens, failures, averageDuration }

class UsageMetricComparison {
  const UsageMetricComparison({
    required this.current,
    required this.previous,
    required this.changePercent,
  });

  final double current;
  final double previous;
  final double? changePercent;

  bool get hasPreviousBaseline => previous != 0;
}

class UsageOverview {
  const UsageOverview({
    required this.totalCalls,
    required this.failedCalls,
    required this.successRate,
    required this.averageResponse,
    required this.responseSampleCount,
    required this.averageDuration,
    required this.tokens,
    required this.callComparison,
    this.recentProjectPath,
  });

  final int totalCalls;
  final int failedCalls;
  final double? successRate;
  final Duration? averageResponse;
  final int responseSampleCount;
  final Duration? averageDuration;
  final UsageTokenBreakdown tokens;
  final UsageMetricComparison callComparison;
  final String? recentProjectPath;
}

class UsageTrendPoint {
  const UsageTrendPoint({
    required this.start,
    required this.endExclusive,
    required this.label,
    required this.value,
  });

  final DateTime start;
  final DateTime endExclusive;
  final String label;
  final double? value;
}

class UsageAgentRankEntry {
  const UsageAgentRankEntry({
    required this.providerId,
    required this.providerName,
    required this.calls,
    required this.failures,
    required this.successRate,
    required this.totalTokens,
    required this.averageDuration,
  });

  final String providerId;
  final String providerName;
  final int calls;
  final int failures;
  final double? successRate;
  final int? totalTokens;
  final Duration? averageDuration;
}

class UsageProjectRankEntry {
  const UsageProjectRankEntry({
    required this.projectPath,
    required this.calls,
    required this.totalTokens,
    required this.averageDuration,
    required this.lastUsedAt,
  });

  final String projectPath;
  final int calls;
  final int? totalTokens;
  final Duration? averageDuration;
  final DateTime lastUsedAt;

  String get projectName => usageProjectName(projectPath);
}

class UsageModelShare {
  const UsageModelShare({
    required this.model,
    required this.totalTokens,
    required this.ratio,
  });

  final String model;
  final int totalTokens;
  final double ratio;
}

class UsageErrorBreakdown {
  const UsageErrorBreakdown({required this.category, required this.count});

  final UsageErrorCategory category;
  final int count;
}

class UsageStatisticsReport {
  const UsageStatisticsReport({
    required this.window,
    required this.records,
    required this.overview,
    required this.trend,
    required this.agentRanking,
    required this.projectRanking,
    required this.modelShares,
    required this.tokenTrend,
    required this.errors,
    required this.projectOptions,
    required this.agentOptions,
    required this.modelOptions,
  });

  final UsageDateWindow window;
  final List<AgentUsageRecord> records;
  final UsageOverview overview;
  final List<UsageTrendPoint> trend;
  final List<UsageAgentRankEntry> agentRanking;
  final List<UsageProjectRankEntry> projectRanking;
  final List<UsageModelShare> modelShares;
  final List<UsageTrendPoint> tokenTrend;
  final List<UsageErrorBreakdown> errors;
  final List<String> projectOptions;
  final List<String> agentOptions;
  final List<String> modelOptions;
}

Duration? averageUsageDuration(Iterable<Duration?> values) {
  var count = 0;
  var totalMicroseconds = 0;
  for (final value in values) {
    if (value == null) {
      continue;
    }
    count += 1;
    totalMicroseconds += value.inMicroseconds;
  }
  return count == 0
      ? null
      : Duration(microseconds: totalMicroseconds ~/ math.max(1, count));
}

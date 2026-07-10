import 'dart:math' as math;

import 'package:zeta/src/features/agent/domain/agent_usage_models.dart';

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

extension UsageTimeRangePresetLabel on UsageTimeRangePreset {
  String get label => switch (this) {
    UsageTimeRangePreset.today => '今天',
    UsageTimeRangePreset.last7Days => '最近 7 天',
    UsageTimeRangePreset.last30Days => '最近 30 天',
    UsageTimeRangePreset.last90Days => '最近 90 天',
    UsageTimeRangePreset.thisMonth => '本月',
    UsageTimeRangePreset.previousMonth => '上个月',
    UsageTimeRangePreset.custom => '自定义时间',
  };
}

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

enum UsageTaskStatus { running, completed, interrupted, failed, unknown }

extension UsageTaskStatusX on UsageTaskStatus {
  bool get isTerminal => switch (this) {
    UsageTaskStatus.completed ||
    UsageTaskStatus.interrupted ||
    UsageTaskStatus.failed => true,
    UsageTaskStatus.running || UsageTaskStatus.unknown => false,
  };

  bool get isFailure =>
      this == UsageTaskStatus.interrupted || this == UsageTaskStatus.failed;

  String get label => switch (this) {
    UsageTaskStatus.running => '运行中',
    UsageTaskStatus.completed => '成功',
    UsageTaskStatus.interrupted => '已取消',
    UsageTaskStatus.failed => '失败',
    UsageTaskStatus.unknown => '未知',
  };
}

enum UsageErrorCategory { account, cli, network, timeout, cancelled, other }

extension UsageErrorCategoryLabel on UsageErrorCategory {
  String get label => switch (this) {
    UsageErrorCategory.account => '账号异常',
    UsageErrorCategory.cli => 'CLI 异常',
    UsageErrorCategory.network => '网络错误',
    UsageErrorCategory.timeout => '超时',
    UsageErrorCategory.cancelled => '用户取消',
    UsageErrorCategory.other => '其他异常',
  };

  String get nextAction => switch (this) {
    UsageErrorCategory.account => '检查 Codex 登录状态与当前套餐额度。',
    UsageErrorCategory.cli => '检查 Codex CLI 版本、配置和运行日志。',
    UsageErrorCategory.network => '检查网络、代理设置后重试。',
    UsageErrorCategory.timeout => '缩小任务范围或提高 Agent 超时时间。',
    UsageErrorCategory.cancelled => '如需继续，请重新发起该任务。',
    UsageErrorCategory.other => '打开任务详情或 Agent 日志查看原始原因。',
  };
}

/// 单次调用的 Token 明细。
class UsageTokenBreakdown {
  const UsageTokenBreakdown({
    this.inputTokens,
    this.cachedInputTokens,
    this.outputTokens,
    this.totalTokens,
  });

  final int? inputTokens;
  final int? cachedInputTokens;
  final int? outputTokens;
  final int? totalTokens;

  bool get hasData =>
      inputTokens != null ||
      cachedInputTokens != null ||
      outputTokens != null ||
      totalTokens != null;

  int? get effectiveTotal {
    if (totalTokens != null) {
      return totalTokens;
    }
    if (inputTokens == null && outputTokens == null) {
      return null;
    }
    return (inputTokens ?? 0) + (outputTokens ?? 0);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'inputTokens': inputTokens,
    'cachedInputTokens': cachedInputTokens,
    'outputTokens': outputTokens,
    'totalTokens': totalTokens,
  };

  static UsageTokenBreakdown tryDecode(Object? value) {
    final map = value is Map<String, Object?>
        ? value
        : value is Map
        ? value.map((key, value) => MapEntry(key.toString(), value))
        : const <String, Object?>{};
    return UsageTokenBreakdown(
      inputTokens: _int(map['inputTokens']),
      cachedInputTokens: _int(map['cachedInputTokens']),
      outputTokens: _int(map['outputTokens']),
      totalTokens: _int(map['totalTokens']),
    );
  }
}

/// 可落盘的单次 Agent 调用统计记录。
///
/// 该模型刻意不包含 Prompt、回复正文、文件路径列表或工具输出。
class AgentUsageRecord {
  const AgentUsageRecord({
    required this.threadId,
    required this.turnId,
    required this.providerId,
    required this.providerName,
    required this.projectPath,
    required this.sourceKind,
    required this.startedAt,
    required this.status,
    this.completedAt,
    this.duration,
    this.timeToFirstToken,
    this.model,
    this.tokens = const UsageTokenBreakdown(),
    this.errorCategory,
    this.errorMessage,
    this.errorCode,
  });

  final String threadId;
  final String turnId;
  final String providerId;
  final String providerName;
  final String projectPath;
  final String sourceKind;
  final DateTime startedAt;
  final DateTime? completedAt;
  final Duration? duration;
  final Duration? timeToFirstToken;
  final String? model;
  final UsageTaskStatus status;
  final UsageTokenBreakdown tokens;
  final UsageErrorCategory? errorCategory;
  final String? errorMessage;
  final String? errorCode;

  String get id => '$threadId/$turnId';
  String get projectName => usageProjectName(projectPath);

  Map<String, Object?> toJson() => <String, Object?>{
    'threadId': threadId,
    'turnId': turnId,
    'providerId': providerId,
    'providerName': providerName,
    'projectPath': projectPath,
    'sourceKind': sourceKind,
    'startedAt': startedAt.millisecondsSinceEpoch,
    'completedAt': completedAt?.millisecondsSinceEpoch,
    'durationMs': duration?.inMilliseconds,
    'timeToFirstTokenMs': timeToFirstToken?.inMilliseconds,
    'model': model,
    'status': status.name,
    'tokens': tokens.toJson(),
    'errorCategory': errorCategory?.name,
  };

  static AgentUsageRecord? tryDecode(Object? value) {
    final map = value is Map<String, Object?>
        ? value
        : value is Map
        ? value.map((key, value) => MapEntry(key.toString(), value))
        : const <String, Object?>{};
    final threadId = _text(map['threadId']);
    final turnId = _text(map['turnId']);
    final providerId = _text(map['providerId']);
    final providerName = _text(map['providerName']);
    final projectPath = _text(map['projectPath']);
    final sourceKind = _text(map['sourceKind']);
    final startedAtMs = _int(map['startedAt']);
    if (threadId == null ||
        turnId == null ||
        providerId == null ||
        providerName == null ||
        projectPath == null ||
        sourceKind == null ||
        startedAtMs == null) {
      return null;
    }
    return AgentUsageRecord(
      threadId: threadId,
      turnId: turnId,
      providerId: providerId,
      providerName: providerName,
      projectPath: projectPath,
      sourceKind: sourceKind,
      startedAt: DateTime.fromMillisecondsSinceEpoch(startedAtMs),
      completedAt: _dateTime(map['completedAt']),
      duration: _duration(map['durationMs']),
      timeToFirstToken: _duration(map['timeToFirstTokenMs']),
      model: _text(map['model']),
      status: _enumByName(
        UsageTaskStatus.values,
        map['status'],
        UsageTaskStatus.unknown,
      ),
      tokens: UsageTokenBreakdown.tryDecode(map['tokens']),
      errorCategory: _nullableEnumByName(
        UsageErrorCategory.values,
        map['errorCategory'],
      ),
    );
  }
}

String usageProjectName(String projectPath) {
  final normalized = projectPath.replaceAll('\\', '/');
  final segments = normalized
      .split('/')
      .where((segment) => segment.trim().isNotEmpty)
      .toList();
  return segments.isEmpty ? '未知项目' : segments.last;
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

extension UsageTrendMetricLabel on UsageTrendMetric {
  String get label => switch (this) {
    UsageTrendMetric.calls => '调用次数',
    UsageTrendMetric.successRate => '成功率',
    UsageTrendMetric.totalTokens => 'Token 消耗',
    UsageTrendMetric.averageResponse => '平均响应时间',
    UsageTrendMetric.averageDuration => '任务耗时',
  };
}

enum UsageRankSort { calls, totalTokens, failures, averageDuration }

extension UsageRankSortLabel on UsageRankSort {
  String get label => switch (this) {
    UsageRankSort.calls => '调用次数',
    UsageRankSort.totalTokens => 'Token 消耗',
    UsageRankSort.failures => '失败次数',
    UsageRankSort.averageDuration => '任务耗时',
  };
}

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

int? _int(Object? value) => switch (value) {
  int() => value,
  num() => value.toInt(),
  String() => int.tryParse(value),
  _ => null,
};

String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

DateTime? _dateTime(Object? value) {
  final milliseconds = _int(value);
  return milliseconds == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(milliseconds);
}

Duration? _duration(Object? value) {
  final milliseconds = _int(value);
  return milliseconds == null ? null : Duration(milliseconds: milliseconds);
}

T _enumByName<T extends Enum>(List<T> values, Object? value, T fallback) {
  return _nullableEnumByName(values, value) ?? fallback;
}

T? _nullableEnumByName<T extends Enum>(List<T> values, Object? value) {
  if (value is! String) {
    return null;
  }
  for (final candidate in values) {
    if (candidate.name == value) {
      return candidate;
    }
  }
  return null;
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

import 'dart:collection';

/// Provider 中立的 Token 历史查询。
final class AgentUsageQuery {
  const AgentUsageQuery({required this.earliest, this.forceRefresh = false});

  /// 只返回该时间点及之后开始的回合。
  final DateTime earliest;

  /// 绕过 Provider source 的可重用缓存并重新读取权威来源。
  final bool forceRefresh;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentUsageQuery &&
          earliest == other.earliest &&
          forceRefresh == other.forceRefresh;

  @override
  int get hashCode => Object.hash(earliest, forceRefresh);
}

/// Token 历史权威来源中是否发现过可读取的会话。
///
/// 它与查询时间窗内是否有记录是两件事：历史存在但当前时间窗无记录时应展示 0；
/// 完全没有历史时保持“暂无历史”，不能伪造 0。
enum AgentTokenHistoryPresence { absent, present }

/// 可安全展示的非阻断诊断，不包含 Provider raw、路径或原始异常正文。
final class AgentUsageWarning {
  const AgentUsageWarning({required this.code, required this.message});

  final String code;
  final String message;
}

/// 单个 Provider Token 历史 source 的中立快照。
final class AgentTokenUsageSourceSnapshot {
  AgentTokenUsageSourceSnapshot({
    required this.providerId,
    required this.providerName,
    required this.historyPresence,
    required List<AgentUsageRecord> records,
    required this.refreshedAt,
    List<AgentUsageWarning> warnings = const <AgentUsageWarning>[],
  }) : records = UnmodifiableListView<AgentUsageRecord>(
         List<AgentUsageRecord>.of(records),
       ),
       warnings = UnmodifiableListView<AgentUsageWarning>(
         List<AgentUsageWarning>.of(warnings),
       );

  final String providerId;
  final String providerName;
  final AgentTokenHistoryPresence historyPresence;
  final List<AgentUsageRecord> records;
  final DateTime refreshedAt;
  final List<AgentUsageWarning> warnings;
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
}

enum UsageErrorCategory { account, cli, network, timeout, cancelled, other }

/// 单次调用的 Token 明细。
class UsageTokenBreakdown {
  const UsageTokenBreakdown({
    this.inputTokens,
    this.cachedInputTokens,
    this.outputTokens,
    this.reasoningTokens,
    this.totalTokens,
  });

  final int? inputTokens;
  final int? cachedInputTokens;
  final int? outputTokens;
  final int? reasoningTokens;
  final int? totalTokens;

  bool get hasData =>
      inputTokens != null ||
      cachedInputTokens != null ||
      outputTokens != null ||
      reasoningTokens != null ||
      totalTokens != null;

  int? get effectiveTotal {
    if (totalTokens != null) {
      return totalTokens;
    }
    if (inputTokens == null &&
        cachedInputTokens == null &&
        outputTokens == null &&
        reasoningTokens == null) {
      return null;
    }
    return (inputTokens ?? 0) +
        (cachedInputTokens ?? 0) +
        (outputTokens ?? 0) +
        (reasoningTokens ?? 0);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'inputTokens': inputTokens,
    'cachedInputTokens': cachedInputTokens,
    'outputTokens': outputTokens,
    'reasoningTokens': reasoningTokens,
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
      reasoningTokens: _int(map['reasoningTokens']),
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

  /// 跨 Provider 唯一的规范记录 identity，供去重和稳定 UI key 使用。
  String get id => '$providerId/$threadId/$turnId';
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
    final startedAt = _dateTime(map['startedAt']);
    if (threadId == null ||
        turnId == null ||
        providerId == null ||
        providerName == null ||
        projectPath == null ||
        sourceKind == null ||
        startedAt == null) {
      return null;
    }
    return AgentUsageRecord(
      threadId: threadId,
      turnId: turnId,
      providerId: providerId,
      providerName: providerName,
      projectPath: projectPath,
      sourceKind: sourceKind,
      startedAt: startedAt,
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

String usageProjectName(String projectPath, {String? unknownName}) {
  final normalized = projectPath.replaceAll('\\', '/');
  final segments = normalized
      .split('/')
      .where((segment) => segment.trim().isNotEmpty)
      .toList();
  return segments.isEmpty ? (unknownName ?? '未知项目') : segments.last;
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
  final timestamp = _int(value);
  if (timestamp == null) {
    return null;
  }
  return DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true);
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

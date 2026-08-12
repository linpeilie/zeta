import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/usage_statistics/data/providers/usage_scan_cache.dart';
import 'package:zeta/src/features/usage_statistics/data/usage_statistics_partition_store.dart';

/// Claude Code 派生索引中的单 turn 白名单快照。
///
/// Prompt、回复、工具内容、Provider raw 和原始错误正文都不会进入该对象的 JSON。
final class ClaudeCodeUsageIndexedTurn {
  const ClaudeCodeUsageIndexedTurn({
    required this.id,
    required this.status,
    this.startedAt,
    this.completedAt,
    this.duration,
    this.timeToFirstToken,
    this.cwd,
    this.model,
    this.inputTokens,
    this.cachedInputTokens,
    this.outputTokens,
    this.reasoningTokens,
    this.totalTokens,
    this.errorCategoryHint,
    this.errorMessage,
    this.errorCode,
  });

  final String id;
  final AgentHistoryTurnStatus status;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final Duration? duration;
  final Duration? timeToFirstToken;
  final String? cwd;
  final String? model;
  final int? inputTokens;
  final int? cachedInputTokens;
  final int? outputTokens;
  final int? reasoningTokens;
  final int? totalTokens;
  final String? errorCategoryHint;

  /// 仅当前内存扫描可用；不会由 [toJson] 持久化。
  final String? errorMessage;

  /// 仅当前内存扫描可用；不会由 [toJson] 持久化。
  final String? errorCode;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'status': status.name,
    'startedAt': startedAt?.millisecondsSinceEpoch,
    'completedAt': completedAt?.millisecondsSinceEpoch,
    'durationMs': duration?.inMilliseconds,
    'timeToFirstTokenMs': timeToFirstToken?.inMilliseconds,
    'cwd': cwd,
    'model': model,
    'inputTokens': inputTokens,
    'cachedInputTokens': cachedInputTokens,
    'outputTokens': outputTokens,
    'reasoningTokens': reasoningTokens,
    'totalTokens': totalTokens,
    'errorCategoryHint': errorCategoryHint,
  };

  static ClaudeCodeUsageIndexedTurn? tryDecode(Object? value) {
    final map = _map(value);
    final id = _string(map['id']);
    if (id == null) {
      return null;
    }
    return ClaudeCodeUsageIndexedTurn(
      id: id,
      status: _historyStatus(map['status']),
      startedAt: _dateTime(map['startedAt']),
      completedAt: _dateTime(map['completedAt']),
      duration: _duration(map['durationMs']),
      timeToFirstToken: _duration(map['timeToFirstTokenMs']),
      cwd: _string(map['cwd']),
      model: _string(map['model']),
      inputTokens: _nonNegativeInt(map['inputTokens']),
      cachedInputTokens: _nonNegativeInt(map['cachedInputTokens']),
      outputTokens: _nonNegativeInt(map['outputTokens']),
      reasoningTokens: _nonNegativeInt(map['reasoningTokens']),
      totalTokens: _nonNegativeInt(map['totalTokens']),
      errorCategoryHint: _string(map['errorCategoryHint']),
    );
  }
}

/// 单个 Claude Code JSONL 文件的可缓存用量快照。
final class ClaudeCodeUsageIndexedSession {
  ClaudeCodeUsageIndexedSession({
    required this.sourcePath,
    String? sourceId,
    required this.fingerprint,
    required this.threadId,
    required this.projectPath,
    required this.sourceKind,
    required this.modifiedAt,
    required List<ClaudeCodeUsageIndexedTurn> turns,
  }) : sourceId = sourceId ?? usageSourceId(sourcePath),
       turns = List<ClaudeCodeUsageIndexedTurn>.unmodifiable(turns);

  /// 当前扫描进程内的真实源路径；不会由 [toJson] 持久化。
  final String sourcePath;
  final String sourceId;
  final String fingerprint;
  final String threadId;
  final String projectPath;
  final String sourceKind;
  final DateTime modifiedAt;
  final List<ClaudeCodeUsageIndexedTurn> turns;

  Map<String, Object?> toJson() => <String, Object?>{
    'sourceId': sourceId,
    'fingerprint': fingerprint,
    'threadId': threadId,
    'projectPath': projectPath,
    'sourceKind': sourceKind,
    'modifiedAt': modifiedAt.millisecondsSinceEpoch,
    'turns': turns.map((turn) => turn.toJson()).toList(),
  };

  static ClaudeCodeUsageIndexedSession? tryDecode(Object? value) {
    final map = _map(value);
    final sourceId = _string(map['sourceId']);
    final fingerprint = _string(map['fingerprint']);
    final threadId = _string(map['threadId']);
    final projectPath = _string(map['projectPath']);
    final sourceKind = _string(map['sourceKind']);
    final modifiedAt = _dateTime(map['modifiedAt']);
    if (sourceId == null ||
        fingerprint == null ||
        threadId == null ||
        projectPath == null ||
        sourceKind == null ||
        modifiedAt == null) {
      return null;
    }
    final turns = <ClaudeCodeUsageIndexedTurn>[];
    if (map['turns'] case final List<Object?> values) {
      for (final value in values) {
        final turn = ClaudeCodeUsageIndexedTurn.tryDecode(value);
        if (turn != null) {
          turns.add(turn);
        }
      }
    }
    return ClaudeCodeUsageIndexedSession(
      sourcePath: '',
      sourceId: sourceId,
      fingerprint: fingerprint,
      threadId: threadId,
      projectPath: projectPath,
      sourceKind: sourceKind,
      modifiedAt: modifiedAt,
      turns: turns,
    );
  }

  /// 给缓存恢复的安全快照补回本轮只读扫描发现的路径。
  ClaudeCodeUsageIndexedSession withSourcePath(String value) {
    return ClaudeCodeUsageIndexedSession(
      sourcePath: value,
      sourceId: sourceId,
      fingerprint: fingerprint,
      threadId: threadId,
      projectPath: projectPath,
      sourceKind: sourceKind,
      modifiedAt: modifiedAt,
      turns: turns,
    );
  }
}

/// Claude Code 自有 v1 分区 codec；通用 Store 不解析 sessions 结构。
final class ClaudeCodeUsagePartitionCodec {
  const ClaudeCodeUsagePartitionCodec();

  static const int schemaVersion = 1;

  Map<String, ClaudeCodeUsageIndexedSession> decode(
    UsageStatisticsIndexPartition? partition,
  ) {
    if (partition == null || partition.schemaVersion != schemaVersion) {
      return const <String, ClaudeCodeUsageIndexedSession>{};
    }
    final sessions = <String, ClaudeCodeUsageIndexedSession>{};
    final rawSessions = partition.payload['sessions'];
    if (rawSessions is List) {
      for (final value in rawSessions) {
        final session = ClaudeCodeUsageIndexedSession.tryDecode(value);
        if (session != null) {
          sessions[session.sourceId] = session;
        }
      }
    }
    return Map<String, ClaudeCodeUsageIndexedSession>.unmodifiable(sessions);
  }

  UsageStatisticsIndexPartition encode(
    Iterable<ClaudeCodeUsageIndexedSession> sessions,
  ) {
    return UsageStatisticsIndexPartition(
      schemaVersion: schemaVersion,
      payload: <String, Object?>{
        'sessions': sessions.map((session) => session.toJson()).toList(),
      },
    );
  }
}

Map<String, Object?> _map(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const <String, Object?>{};
}

String? _string(Object? value) {
  if (value is! String) {
    return null;
  }
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

int? _int(Object? value) => switch (value) {
  int() => value,
  num() when value.isFinite => value.toInt(),
  String() => int.tryParse(value.trim()),
  _ => null,
};

int? _nonNegativeInt(Object? value) {
  final parsed = _int(value);
  return parsed == null || parsed < 0 ? null : parsed;
}

DateTime? _dateTime(Object? value) {
  final timestamp = _int(value);
  if (timestamp == null) {
    return null;
  }
  final milliseconds = timestamp.abs() < 1000000000000
      ? timestamp * Duration.millisecondsPerSecond
      : timestamp;
  return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
}

Duration? _duration(Object? value) {
  final milliseconds = _nonNegativeInt(value);
  return milliseconds == null ? null : Duration(milliseconds: milliseconds);
}

AgentHistoryTurnStatus _historyStatus(Object? value) {
  if (value is String) {
    for (final status in AgentHistoryTurnStatus.values) {
      if (status.name == value) {
        return status;
      }
    }
  }
  return AgentHistoryTurnStatus.unknown;
}

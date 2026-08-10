import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:zeta/src/features/agent/data/datasources/local_history/grok_updates_history_parser.dart';
import 'package:zeta/src/features/agent/data/datasources/local_history/usage_scan_cache.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// Grok 派生索引中的单 turn 白名单快照。
///
/// 不含消息体、工具输出、原始错误文本或 raw payload。
class GrokUsageIndexedTurn {
  const GrokUsageIndexedTurn({
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

  /// 不含原始错误内容的稳定分类，用于派生索引跨启动恢复。
  final String? errorCategoryHint;

  /// 仅内存持有；[toJson] 不落盘。
  final String? errorMessage;

  /// 仅内存持有；[toJson] 不落盘。
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

  static GrokUsageIndexedTurn? tryDecode(Object? value) {
    final map = _map(value);
    final id = _string(map['id']);
    if (id == null) {
      return null;
    }
    return GrokUsageIndexedTurn(
      id: id,
      status: _historyStatus(map['status']),
      startedAt: _dateTime(map['startedAt']),
      completedAt: _dateTime(map['completedAt']),
      duration: _duration(map['durationMs']),
      timeToFirstToken: _duration(map['timeToFirstTokenMs']),
      cwd: _string(map['cwd']),
      model: _string(map['model']),
      inputTokens: _int(map['inputTokens']),
      cachedInputTokens: _int(map['cachedInputTokens']),
      outputTokens: _int(map['outputTokens']),
      reasoningTokens: _int(map['reasoningTokens']),
      totalTokens: _int(map['totalTokens']),
      errorCategoryHint: _string(map['errorCategoryHint']),
    );
  }
}

/// 单个 Grok `updates.jsonl` 的可缓存用量会话快照。
class GrokUsageIndexedSession {
  GrokUsageIndexedSession({
    required this.sourcePath,
    String? sourceId,
    required this.fingerprint,
    required this.threadId,
    required this.projectPath,
    required this.sourceKind,
    required this.modifiedAt,
    required this.turns,
  }) : sourceId = sourceId ?? usageSourceId(sourcePath);

  /// 当前进程发现的源路径，只用于只读扫描，不进入派生索引。
  final String sourcePath;

  /// 源路径的稳定不可逆标识，用于跨启动命中派生缓存。
  final String sourceId;
  final String fingerprint;
  final String threadId;
  final String projectPath;
  final String sourceKind;
  final DateTime modifiedAt;
  final List<GrokUsageIndexedTurn> turns;

  Map<String, Object?> toJson() => <String, Object?>{
    'sourceId': sourceId,
    'fingerprint': fingerprint,
    'threadId': threadId,
    'projectPath': projectPath,
    'sourceKind': sourceKind,
    'modifiedAt': modifiedAt.millisecondsSinceEpoch,
    'turns': turns.map((turn) => turn.toJson()).toList(),
  };

  static GrokUsageIndexedSession? tryDecode(Object? value) {
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
    final turns = <GrokUsageIndexedTurn>[];
    if (map['turns'] case final List<Object?> values) {
      for (final item in values) {
        final turn = GrokUsageIndexedTurn.tryDecode(item);
        if (turn != null) {
          turns.add(turn);
        }
      }
    }
    return GrokUsageIndexedSession(
      sourcePath: '',
      sourceId: sourceId,
      fingerprint: fingerprint,
      threadId: threadId,
      projectPath: projectPath,
      sourceKind: sourceKind,
      modifiedAt: modifiedAt,
      turns: List<GrokUsageIndexedTurn>.unmodifiable(turns),
    );
  }

  /// 为从索引恢复的快照补回本次扫描发现的真实路径，路径不会再次持久化。
  GrokUsageIndexedSession withSourcePath(String value) {
    return GrokUsageIndexedSession(
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

/// Grok 本地用量扫描结果。
class GrokUsageScanResult {
  const GrokUsageScanResult({required this.sessions, required this.warnings});

  /// key 为本次扫描发现的源路径（内存）；持久化时改按 sourceId。
  final Map<String, GrokUsageIndexedSession> sessions;
  final List<String> warnings;
}

/// 可注入的 Grok 本地 usage 扫描接口。
abstract interface class GrokUsageLogScanner {
  Future<GrokUsageScanResult> scan({
    required String grokHome,
    required Map<String, GrokUsageIndexedSession> cachedSessions,
    bool forceRefresh = false,
  });
}

/// 扫描 `$GROK_HOME/sessions/**/updates.jsonl` 中的跨项目用量。
class FileSystemGrokUsageLogScanner implements GrokUsageLogScanner {
  const FileSystemGrokUsageLogScanner({
    this.parser = const GrokUpdatesHistoryParser(),
  });

  final GrokUpdatesHistoryParser parser;

  @override
  Future<GrokUsageScanResult> scan({
    required String grokHome,
    required Map<String, GrokUsageIndexedSession> cachedSessions,
    bool forceRefresh = false,
  }) {
    if (forceRefresh) {
      // Grok parser 会同步归并完整历史，强制刷新时放到后台 isolate 执行。
      return Isolate.run(
        () => _scan(
          grokHome: grokHome,
          cachedSessions: cachedSessions,
          forceRefresh: true,
        ),
        debugName: 'zeta-grok-usage-scan',
      );
    }
    return _scan(
      grokHome: grokHome,
      cachedSessions: cachedSessions,
      forceRefresh: false,
    );
  }

  Future<GrokUsageScanResult> _scan({
    required String grokHome,
    required Map<String, GrokUsageIndexedSession> cachedSessions,
    required bool forceRefresh,
  }) async {
    final sessionsDirectory = Directory(_joinPath(grokHome, 'sessions'));
    if (!await sessionsDirectory.exists()) {
      return const GrokUsageScanResult(
        sessions: <String, GrokUsageIndexedSession>{},
        warnings: <String>[],
      );
    }

    final files = <File>[];
    var discoveryFailures = 0;
    try {
      await for (final entity in sessionsDirectory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File &&
            _basename(entity.path).toLowerCase() == 'updates.jsonl') {
          files.add(entity);
        }
      }
    } on FileSystemException {
      discoveryFailures += 1;
    }
    files.sort((left, right) => left.path.compareTo(right.path));

    final sessions = <String, GrokUsageIndexedSession>{};
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

        final sessionDirectory = file.parent;
        final threadId = _basename(sessionDirectory.path);
        final projectPath = await _readProjectPath(sessionDirectory);
        final history = parser.parse(
          threadId: threadId,
          content: await file.readAsString(),
          raw: <String, Object?>{
            'source': 'updates.jsonl',
            'sourcePath': file.path,
            'projectPath': projectPath,
          },
        );
        sessions[file.path] = GrokUsageIndexedSession(
          sourcePath: file.path,
          fingerprint: fingerprint,
          threadId: threadId,
          projectPath: projectPath,
          sourceKind: 'grok_acp',
          modifiedAt: stat.modified,
          turns: List<GrokUsageIndexedTurn>.unmodifiable(
            history.turns.map(_projectTurn),
          ),
        );
      } on FileSystemException {
        unreadableFiles += 1;
      } on FormatException {
        unreadableFiles += 1;
      } catch (_) {
        // 单个会话包含未知结构时继续统计其他会话。
        unreadableFiles += 1;
      }
    }

    return GrokUsageScanResult(
      sessions: Map<String, GrokUsageIndexedSession>.unmodifiable(sessions),
      warnings: List<String>.unmodifiable(<String>[
        if (discoveryFailures > 0) 'Grok 会话目录未能完整枚举，已展示可读取的数据。',
        if (unreadableFiles > 0) '$unreadableFiles 个 Grok 会话文件读取失败，已展示其余数据。',
      ]),
    );
  }

  Future<String> _readProjectPath(Directory sessionDirectory) async {
    final summary = File(_joinPath(sessionDirectory.path, 'summary.json'));
    if (await summary.exists()) {
      try {
        final decoded = jsonDecode(await summary.readAsString());
        if (decoded is Map) {
          final info = decoded['info'];
          if (info is Map) {
            final cwd = info['cwd']?.toString().trim();
            if (cwd != null && cwd.isNotEmpty) {
              return cwd;
            }
          }
        }
      } on FileSystemException {
        // summary 仅用于补全项目路径，失败时仍可从目录名恢复。
      } on FormatException {
        // 损坏的 summary 不影响 updates.jsonl 用量读取。
      }
    }

    final encoded = _basename(sessionDirectory.parent.path);
    try {
      final decoded = Uri.decodeComponent(encoded).trim();
      return decoded.isEmpty ? 'unknown' : decoded;
    } on FormatException {
      return encoded.isEmpty ? 'unknown' : encoded;
    }
  }
}

GrokUsageIndexedTurn _projectTurn(AgentHistoryTurn turn) {
  final usage = turn.tokenUsage;
  final cached = usage?.cachedInputTokens;
  final reasoning = usage?.reasoningOutputTokens;
  return GrokUsageIndexedTurn(
    id: turn.id,
    status: turn.status,
    startedAt: turn.startedAt,
    completedAt: turn.completedAt,
    duration: turn.duration,
    timeToFirstToken: turn.timeToFirstToken,
    cwd: turn.cwd,
    model: turn.model,
    inputTokens: _exclusiveTokens(usage?.inputTokens, cached),
    cachedInputTokens: cached,
    outputTokens: _exclusiveTokens(usage?.outputTokens, reasoning),
    reasoningTokens: reasoning,
    totalTokens: usage?.totalTokens,
    errorCategoryHint: switch (turn.status) {
      AgentHistoryTurnStatus.interrupted => 'cancelled',
      AgentHistoryTurnStatus.failed => 'other',
      _ => null,
    },
    errorMessage: turn.errorMessage,
    errorCode: turn.errorCode,
  );
}

int? _exclusiveTokens(int? inclusive, int? nested) {
  if (inclusive == null) {
    return null;
  }
  final exclusive = inclusive - (nested ?? 0);
  return exclusive < 0 ? 0 : exclusive;
}

String _joinPath(String left, String right) {
  if (left.endsWith('/') || left.endsWith(r'\')) {
    return '$left$right';
  }
  return '$left${Platform.pathSeparator}$right';
}

String _basename(String path) {
  final parts = path
      .split(RegExp(r'[\\/]+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  return parts.isEmpty ? path : parts.last;
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
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _int(Object? value) => switch (value) {
  int() => value,
  num() => value.toInt(),
  String() => int.tryParse(value),
  _ => null,
};

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
  final milliseconds = _int(value);
  return milliseconds == null ? null : Duration(milliseconds: milliseconds);
}

AgentHistoryTurnStatus _historyStatus(Object? value) {
  if (value is! String) {
    return AgentHistoryTurnStatus.unknown;
  }
  for (final status in AgentHistoryTurnStatus.values) {
    if (status.name == value) {
      return status;
    }
  }
  return AgentHistoryTurnStatus.unknown;
}

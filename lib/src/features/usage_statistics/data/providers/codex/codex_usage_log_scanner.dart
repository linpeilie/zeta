import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/usage_statistics/data/providers/usage_scan_cache.dart';
import 'package:zeta/src/features/usage_statistics/domain/fallback_usage_statistics_text_catalog.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_text_catalog.dart';

/// 一条 Codex 模型请求的精确 Token 用量。
class CodexUsageSample {
  const CodexUsageSample({
    required this.deduplicationKey,
    required this.timestamp,
    required this.inputTokens,
    required this.cachedInputTokens,
    required this.outputTokens,
    required this.reasoningTokens,
    required this.totalTokens,
  });

  final String deduplicationKey;
  final DateTime timestamp;
  final int inputTokens;
  final int cachedInputTokens;
  final int outputTokens;
  final int reasoningTokens;
  final int totalTokens;

  Map<String, Object?> toJson() => <String, Object?>{
    'deduplicationKey': deduplicationKey,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'inputTokens': inputTokens,
    'cachedInputTokens': cachedInputTokens,
    'outputTokens': outputTokens,
    'reasoningTokens': reasoningTokens,
    'totalTokens': totalTokens,
  };

  static CodexUsageSample? tryDecode(Object? value) {
    final map = _map(value);
    final key = _string(map['deduplicationKey']);
    final timestamp = _dateTime(map['timestamp']);
    if (key == null || timestamp == null) {
      return null;
    }
    return CodexUsageSample(
      deduplicationKey: key,
      timestamp: timestamp,
      inputTokens: _int(map['inputTokens']) ?? 0,
      cachedInputTokens: _int(map['cachedInputTokens']) ?? 0,
      outputTokens: _int(map['outputTokens']) ?? 0,
      reasoningTokens: _int(map['reasoningTokens']) ?? 0,
      totalTokens: _int(map['totalTokens']) ?? 0,
    );
  }
}

/// 从单个 rollout 文件恢复的 Agent turn。
class CodexUsageTurnSnapshot {
  const CodexUsageTurnSnapshot({
    required this.id,
    required this.status,
    required this.samples,
    this.startedAt,
    this.completedAt,
    this.cwd,
    this.model,
    this.errorMessage,
    this.errorCode,
    this.errorCategoryHint,
  });

  final String id;
  final AgentHistoryTurnStatus status;
  final List<CodexUsageSample> samples;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? cwd;
  final String? model;
  final String? errorMessage;
  final String? errorCode;

  /// 不含原始错误内容的稳定分类，用于派生索引跨启动恢复统计。
  final String? errorCategoryHint;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'status': status.name,
    'startedAt': startedAt?.millisecondsSinceEpoch,
    'completedAt': completedAt?.millisecondsSinceEpoch,
    'cwd': cwd,
    'model': model,
    // 原始错误文本与 provider code 可能携带 payload 或凭据，只保留在当前内存扫描。
    'errorCategoryHint':
        errorCategoryHint ??
        codexUsageErrorCategoryHint(
          status: status,
          code: errorCode,
          message: errorMessage,
        ),
    'samples': samples.map((sample) => sample.toJson()).toList(),
  };

  static CodexUsageTurnSnapshot? tryDecode(Object? value) {
    final map = _map(value);
    final id = _string(map['id']);
    if (id == null) {
      return null;
    }
    final samples = <CodexUsageSample>[];
    if (map['samples'] case final List<Object?> values) {
      for (final value in values) {
        final sample = CodexUsageSample.tryDecode(value);
        if (sample != null) {
          samples.add(sample);
        }
      }
    }
    final status = _historyStatus(map['status']);
    final errorMessage = _string(map['errorMessage']);
    final errorCode = _string(map['errorCode']);
    return CodexUsageTurnSnapshot(
      id: id,
      status: status,
      startedAt: _dateTime(map['startedAt']),
      completedAt: _dateTime(map['completedAt']),
      cwd: _string(map['cwd']),
      model: _string(map['model']),
      errorMessage: errorMessage,
      errorCode: errorCode,
      errorCategoryHint:
          _string(map['errorCategoryHint']) ??
          codexUsageErrorCategoryHint(
            status: status,
            code: errorCode,
            message: errorMessage,
          ),
      samples: List<CodexUsageSample>.unmodifiable(samples),
    );
  }
}

/// 单个 Codex rollout 文件的可缓存扫描结果。
class CodexUsageSessionSnapshot {
  CodexUsageSessionSnapshot({
    required this.sourcePath,
    String? sourceId,
    required this.fingerprint,
    required this.threadId,
    required this.projectPath,
    required this.sourceKind,
    required this.createdAt,
    required this.turns,
  }) : sourceId = sourceId ?? usageSourceId(sourcePath);

  /// 当前进程发现的 rollout 文件路径，只用于只读扫描，不进入派生索引。
  final String sourcePath;

  /// rollout 路径的稳定不可逆标识，用于跨启动命中派生缓存。
  final String sourceId;
  final String fingerprint;
  final String threadId;
  final String projectPath;
  final String sourceKind;
  final DateTime createdAt;
  final List<CodexUsageTurnSnapshot> turns;

  Map<String, Object?> toJson() => <String, Object?>{
    'sourceId': sourceId,
    'fingerprint': fingerprint,
    'threadId': threadId,
    'projectPath': projectPath,
    'sourceKind': sourceKind,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'turns': turns.map((turn) => turn.toJson()).toList(),
  };

  static CodexUsageSessionSnapshot? tryDecode(Object? value) {
    final map = _map(value);
    final legacySourcePath = _string(map['sourcePath']);
    final sourceId =
        _string(map['sourceId']) ??
        (legacySourcePath == null ? null : usageSourceId(legacySourcePath));
    final fingerprint = _string(map['fingerprint']);
    final threadId = _string(map['threadId']);
    final projectPath = _string(map['projectPath']);
    final sourceKind = _string(map['sourceKind']);
    final createdAt = _dateTime(map['createdAt']);
    if (sourceId == null ||
        fingerprint == null ||
        threadId == null ||
        projectPath == null ||
        sourceKind == null ||
        createdAt == null) {
      return null;
    }
    final turns = <CodexUsageTurnSnapshot>[];
    if (map['turns'] case final List<Object?> values) {
      for (final value in values) {
        final turn = CodexUsageTurnSnapshot.tryDecode(value);
        if (turn != null) {
          turns.add(turn);
        }
      }
    }
    return CodexUsageSessionSnapshot(
      sourcePath: legacySourcePath ?? '',
      sourceId: sourceId,
      fingerprint: fingerprint,
      threadId: threadId,
      projectPath: projectPath,
      sourceKind: sourceKind,
      createdAt: createdAt,
      turns: List<CodexUsageTurnSnapshot>.unmodifiable(turns),
    );
  }

  /// 为从索引恢复的快照补回本次扫描发现的真实路径，路径不会再次持久化。
  CodexUsageSessionSnapshot withSourcePath(String value) {
    return CodexUsageSessionSnapshot(
      sourcePath: value,
      sourceId: sourceId,
      fingerprint: fingerprint,
      threadId: threadId,
      projectPath: projectPath,
      sourceKind: sourceKind,
      createdAt: createdAt,
      turns: turns,
    );
  }
}

/// 为 Codex rollout 路径生成稳定的 64-bit FNV-1a 标识。
///
/// 兼容旧调用点；新代码请直接使用 [usageSourceId]。
String codexUsageSourceId(String sourcePath) => usageSourceId(sourcePath);

/// 将 Codex turn 错误归一为不含原始内容的稳定分类标识。
String? codexUsageErrorCategoryHint({
  required AgentHistoryTurnStatus status,
  required String? code,
  required String? message,
}) {
  if (status == AgentHistoryTurnStatus.interrupted) {
    return 'cancelled';
  }
  if (status != AgentHistoryTurnStatus.failed) {
    return null;
  }
  final normalizedCode = code?.toLowerCase() ?? '';
  final normalizedMessage = message?.toLowerCase() ?? '';
  if (normalizedCode.contains('unauthorized') ||
      normalizedCode.contains('usagelimit') ||
      normalizedCode.contains('sessionbudget') ||
      normalizedMessage.contains('account') ||
      normalizedMessage.contains('login')) {
    return 'account';
  }
  if (normalizedCode.contains('connection') ||
      normalizedCode.contains('stream') ||
      normalizedCode.contains('serveroverloaded') ||
      normalizedMessage.contains('network') ||
      normalizedMessage.contains('connection')) {
    return 'network';
  }
  if (normalizedCode.contains('timeout') ||
      normalizedMessage.contains('timeout') ||
      normalizedMessage.contains('timed out') ||
      normalizedMessage.contains('deadline')) {
    return 'timeout';
  }
  if (normalizedCode.contains('sandbox') ||
      normalizedCode.contains('threadrollback') ||
      normalizedMessage.contains('codex cli')) {
    return 'cli';
  }
  return 'other';
}

class CodexUsageScanResult {
  const CodexUsageScanResult({
    required this.sessions,
    required this.warnings,
    this.discoveryFailures = 0,
    this.unreadableFiles = 0,
  });

  final Map<String, CodexUsageSessionSnapshot> sessions;
  final List<String> warnings;
  final int discoveryFailures;
  final int unreadableFiles;
}

/// 可注入的 Codex 本地 usage 扫描接口。
abstract interface class CodexUsageLogScanner {
  Future<CodexUsageScanResult> scan({
    required String codexHome,
    required Map<String, CodexUsageSessionSnapshot> cachedSessions,
    bool forceRefresh = false,
    UsageStatisticsTextCatalog textCatalog =
        const FallbackUsageStatisticsTextCatalog(),
  });
}

/// 直接扫描 `$CODEX_HOME/sessions/**/rollout-*.jsonl`。
class FileSystemCodexUsageLogScanner implements CodexUsageLogScanner {
  const FileSystemCodexUsageLogScanner();

  @override
  Future<CodexUsageScanResult> scan({
    required String codexHome,
    required Map<String, CodexUsageSessionSnapshot> cachedSessions,
    bool forceRefresh = false,
    UsageStatisticsTextCatalog textCatalog =
        const FallbackUsageStatisticsTextCatalog(),
  }) async {
    final scanned = forceRefresh
        ? await Isolate.run(
            () => _scan(
              codexHome: codexHome,
              cachedSessions: cachedSessions,
              forceRefresh: true,
            ),
            debugName: 'zeta-codex-usage-scan',
          )
        : await _scan(
            codexHome: codexHome,
            cachedSessions: cachedSessions,
            forceRefresh: false,
          );
    return CodexUsageScanResult(
      sessions: scanned.sessions,
      warnings: <String>[
        if (scanned.discoveryFailures > 0)
          textCatalog.sessionDirIncomplete('Codex'),
        if (scanned.unreadableFiles > 0)
          textCatalog.sessionFilesUnreadable(
            '${scanned.unreadableFiles}',
            'Codex',
          ),
      ],
    );
  }

  Future<CodexUsageScanResult> _scan({
    required String codexHome,
    required Map<String, CodexUsageSessionSnapshot> cachedSessions,
    required bool forceRefresh,
  }) async {
    final sessionsDirectory = Directory(_joinPath(codexHome, 'sessions'));
    if (!await sessionsDirectory.exists()) {
      return const CodexUsageScanResult(
        sessions: <String, CodexUsageSessionSnapshot>{},
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
        if (entity is File && _isRolloutFile(entity.path)) {
          files.add(entity);
        }
      }
    } on FileSystemException {
      discoveryFailures += 1;
    }
    files.sort((left, right) => left.path.compareTo(right.path));

    final sessions = <String, CodexUsageSessionSnapshot>{};
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
        final parsed = await _CodexUsageFileParser(
          file: file,
          fingerprint: fingerprint,
        ).parse();
        if (parsed != null) {
          sessions[file.path] = parsed;
        }
      } on FileSystemException {
        unreadableFiles += 1;
      } on FormatException {
        // 损坏的 UTF-8 不能阻断其余会话的统计。
        unreadableFiles += 1;
      }
    }

    return CodexUsageScanResult(
      sessions: Map<String, CodexUsageSessionSnapshot>.unmodifiable(sessions),
      warnings: const <String>[],
      discoveryFailures: discoveryFailures,
      unreadableFiles: unreadableFiles,
    );
  }
}

class _CodexUsageFileParser {
  _CodexUsageFileParser({required this.file, required this.fingerprint});

  final File file;
  final String fingerprint;
  final Map<String, _TurnBuilder> _turns = <String, _TurnBuilder>{};

  String? _sessionId;
  String? _forkedFromId;
  String? _projectPath;
  String? _sourceKind;
  String? _sessionModel;
  DateTime? _createdAt;
  DateTime? _forkCutoff;
  String? _currentTurnId;
  int _turnCounter = 0;
  int? _previousCumulativeTotal;
  String? _previousCumulativeSignature;
  int _previousInput = 0;
  int _previousCached = 0;
  int _previousOutput = 0;
  int _previousReasoning = 0;

  Future<CodexUsageSessionSnapshot?> parse() async {
    var lineNumber = 0;
    await for (final line
        in file
            .openRead()
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      lineNumber += 1;
      final record = _decodeLine(line);
      if (lineNumber == 1) {
        if (!_consumeSessionMeta(record)) {
          return null;
        }
        continue;
      }
      if (record.isEmpty) {
        continue;
      }
      _consumeRecord(record);
    }

    final sessionId = _sessionId;
    final createdAt = _createdAt;
    if (sessionId == null || createdAt == null) {
      return null;
    }
    final turns =
        _turns.values
            .map((turn) => turn.build())
            .where(
              (turn) =>
                  turn.startedAt != null ||
                  turn.completedAt != null ||
                  turn.samples.isNotEmpty,
            )
            .toList()
          ..sort((left, right) {
            final leftTime = left.startedAt ?? left.completedAt ?? createdAt;
            final rightTime = right.startedAt ?? right.completedAt ?? createdAt;
            return leftTime.compareTo(rightTime);
          });
    return CodexUsageSessionSnapshot(
      sourcePath: file.path,
      fingerprint: fingerprint,
      threadId: sessionId,
      projectPath: _projectPath ?? 'unknown',
      sourceKind: _sourceKind ?? 'codex',
      createdAt: createdAt,
      turns: List<CodexUsageTurnSnapshot>.unmodifiable(turns),
    );
  }

  bool _consumeSessionMeta(Map<String, Object?> record) {
    // 只校验合法 rollout 结构：首行必须是 session_meta 且能解析时间戳。
    // originator 可能是 codex_cli_rs / Codex Desktop / zeta 等客户端名，
    // 不得用前缀白名单过滤，否则 Zeta 等客户端会话的 Token 会整份丢失。
    if (_string(record['type']) != 'session_meta') {
      return false;
    }
    final payload = _map(record['payload']);
    final createdAt =
        _dateTime(record['timestamp']) ?? _dateTime(payload['timestamp']);
    if (createdAt == null) {
      return false;
    }
    _sessionId =
        _string(payload['session_id']) ?? _basenameWithoutExtension(file.path);
    _forkedFromId = _string(payload['forked_from_id']);
    _projectPath = _string(payload['cwd']);
    _sourceKind = _string(payload['originator']) ?? 'codex';
    _sessionModel = _string(payload['model']);
    _createdAt = createdAt;
    if (_forkedFromId != null) {
      _forkCutoff = createdAt.add(const Duration(seconds: 5));
    }
    return true;
  }

  void _consumeRecord(Map<String, Object?> record) {
    final payload = _map(record['payload']);
    if (payload.isEmpty) {
      return;
    }
    final timestamp = _dateTime(record['timestamp']);
    final explicitTurnId = _turnIdFrom(record, payload);
    if (explicitTurnId != null) {
      _currentTurnId = explicitTurnId;
    }

    final recordType = _string(record['type']);
    if (recordType == 'turn_context') {
      final turn = _currentTurn(timestamp);
      turn.cwd = _string(payload['cwd']) ?? turn.cwd;
      turn.model = _string(payload['model']) ?? turn.model;
      _sessionModel = turn.model ?? _sessionModel;
      return;
    }
    if (recordType == 'response_item' &&
        _string(payload['type']) == 'message' &&
        _string(payload['role']) == 'user') {
      final current = _currentTurnId == null ? null : _turns[_currentTurnId];
      if (explicitTurnId == null &&
          (current == null ||
              _isTerminal(current.status) ||
              current.samples.isNotEmpty)) {
        _currentTurnId = '${_sessionId ?? 'session'}:t${++_turnCounter}';
      }
      _currentTurn(timestamp).startedAt ??= timestamp;
      return;
    }
    if (recordType != 'event_msg') {
      return;
    }

    switch (_string(payload['type'])) {
      case 'task_started':
        final turn = _currentTurn(timestamp);
        turn.status = AgentHistoryTurnStatus.running;
        turn.startedAt ??= timestamp;
        return;
      case 'task_complete':
        final turn = _currentTurn(timestamp);
        turn.status = AgentHistoryTurnStatus.completed;
        turn.completedAt = timestamp ?? turn.completedAt;
        return;
      case 'turn_aborted':
        final turn = _currentTurn(timestamp);
        turn.status = AgentHistoryTurnStatus.interrupted;
        turn.completedAt = timestamp ?? turn.completedAt;
        turn.errorMessage = _string(payload['reason']) ?? 'user_cancelled';
        return;
      case 'error':
        final turn = _currentTurn(timestamp);
        turn.status = AgentHistoryTurnStatus.failed;
        turn.completedAt = timestamp ?? turn.completedAt;
        turn.errorMessage = _string(payload['message']);
        turn.errorCode = _string(payload['code']);
        return;
      case 'token_count':
        _consumeTokenCount(payload, timestamp: timestamp);
        return;
      default:
        return;
    }
  }

  void _consumeTokenCount(
    Map<String, Object?> payload, {
    required DateTime? timestamp,
  }) {
    final eventTime = timestamp ?? _createdAt;
    if (eventTime == null ||
        (_forkCutoff != null && eventTime.isBefore(_forkCutoff!))) {
      return;
    }
    final info = _map(payload['info']);
    if (info.isEmpty) {
      return;
    }
    final total = _map(info['total_token_usage']);
    final last = _map(info['last_token_usage']);
    final cumulativeTotal = _int(total['total_tokens']) ?? 0;
    final totalInput = _int(total['input_tokens']) ?? 0;
    final totalCached = _int(total['cached_input_tokens']) ?? 0;
    final totalOutput = _int(total['output_tokens']) ?? 0;
    final totalReasoning = _int(total['reasoning_output_tokens']) ?? 0;
    final cumulativeSignature =
        '$cumulativeTotal:$totalInput:$totalCached:'
        '$totalOutput:$totalReasoning';
    final previousCumulativeTotal = _previousCumulativeTotal;
    if (_previousCumulativeSignature == cumulativeSignature) {
      return;
    }
    _previousCumulativeTotal = cumulativeTotal;
    _previousCumulativeSignature = cumulativeSignature;

    final rawInput = last.isNotEmpty
        ? _int(last['input_tokens']) ?? 0
        : _nonNegativeDelta(totalInput, _previousInput);
    final cached = last.isNotEmpty
        ? _int(last['cached_input_tokens']) ?? 0
        : _nonNegativeDelta(totalCached, _previousCached);
    final rawOutput = last.isNotEmpty
        ? _int(last['output_tokens']) ?? 0
        : _nonNegativeDelta(totalOutput, _previousOutput);
    final reasoning = last.isNotEmpty
        ? _int(last['reasoning_output_tokens']) ?? 0
        : _nonNegativeDelta(totalReasoning, _previousReasoning);
    final reportedTotal = last.isNotEmpty
        ? _int(last['total_tokens'])
        : _nonNegativeDelta(cumulativeTotal, previousCumulativeTotal ?? 0);

    _previousInput = totalInput;
    _previousCached = totalCached;
    _previousOutput = totalOutput;
    _previousReasoning = totalReasoning;

    final input = (rawInput - cached).clamp(0, rawInput);
    final output = (rawOutput - reasoning).clamp(0, rawOutput);
    final sampleTotal = reportedTotal ?? input + cached + output + reasoning;
    if (sampleTotal == 0 &&
        input == 0 &&
        cached == 0 &&
        output == 0 &&
        reasoning == 0) {
      return;
    }
    final namespace = _forkedFromId ?? _sessionId ?? 'unknown';
    final key =
        'codex:$namespace:$cumulativeTotal:$totalInput:'
        '$totalCached:$totalOutput:$totalReasoning';
    final turn = _currentTurn(eventTime);
    turn.startedAt ??= eventTime;
    turn.model ??= _sessionModel;
    turn.samples.add(
      CodexUsageSample(
        deduplicationKey: key,
        timestamp: eventTime,
        inputTokens: input,
        cachedInputTokens: cached,
        outputTokens: output,
        reasoningTokens: reasoning,
        totalTokens: sampleTotal,
      ),
    );
  }

  _TurnBuilder _currentTurn(DateTime? timestamp) {
    final id = _currentTurnId ??= '${_sessionId ?? 'session'}:t0';
    return _turns.putIfAbsent(
      id,
      () => _TurnBuilder(id: id, startedAt: timestamp, model: _sessionModel),
    );
  }
}

class _TurnBuilder {
  _TurnBuilder({required this.id, this.startedAt, this.model});

  final String id;
  AgentHistoryTurnStatus status = AgentHistoryTurnStatus.unknown;
  DateTime? startedAt;
  DateTime? completedAt;
  String? cwd;
  String? model;
  String? errorMessage;
  String? errorCode;
  final List<CodexUsageSample> samples = <CodexUsageSample>[];

  CodexUsageTurnSnapshot build() => CodexUsageTurnSnapshot(
    id: id,
    status: status == AgentHistoryTurnStatus.unknown && completedAt != null
        ? AgentHistoryTurnStatus.completed
        : status,
    startedAt: startedAt,
    completedAt: completedAt,
    cwd: cwd,
    model: model,
    errorMessage: errorMessage,
    errorCode: errorCode,
    samples: List<CodexUsageSample>.unmodifiable(samples),
  );
}

Map<String, Object?> _decodeLine(String line) {
  try {
    return _map(jsonDecode(line));
  } catch (_) {
    return const <String, Object?>{};
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

String? _turnIdFrom(
  Map<String, Object?> record,
  Map<String, Object?> payload,
) =>
    _string(payload['turn_id']) ??
    _string(
      _map(payload['internal_chat_message_metadata_passthrough'])['turn_id'],
    ) ??
    _string(
      _map(record['internal_chat_message_metadata_passthrough'])['turn_id'],
    );

String? _string(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

int? _int(Object? value) => switch (value) {
  int() => value,
  num() => value.toInt(),
  String() => int.tryParse(value),
  _ => null,
};

DateTime? _dateTime(Object? value) {
  if (value is String) {
    return DateTime.tryParse(value)?.toLocal();
  }
  final milliseconds = _int(value);
  if (milliseconds == null) {
    return null;
  }
  final normalized = milliseconds.abs() < 1000000000000
      ? milliseconds * Duration.millisecondsPerSecond
      : milliseconds;
  return DateTime.fromMillisecondsSinceEpoch(normalized);
}

int _nonNegativeDelta(int current, int baseline) {
  final delta = current - baseline;
  return delta < 0 ? 0 : delta;
}

AgentHistoryTurnStatus _historyStatus(Object? value) {
  final name = _string(value);
  for (final status in AgentHistoryTurnStatus.values) {
    if (status.name == name) {
      return status;
    }
  }
  return AgentHistoryTurnStatus.unknown;
}

bool _isTerminal(AgentHistoryTurnStatus status) => switch (status) {
  AgentHistoryTurnStatus.completed ||
  AgentHistoryTurnStatus.interrupted ||
  AgentHistoryTurnStatus.failed => true,
  AgentHistoryTurnStatus.unknown || AgentHistoryTurnStatus.running => false,
};

bool _isRolloutFile(String path) {
  final name = path.replaceAll('\\', '/').split('/').last;
  return name.startsWith('rollout-') && name.endsWith('.jsonl');
}

String _basenameWithoutExtension(String path) {
  final name = path.replaceAll('\\', '/').split('/').last;
  return name.endsWith('.jsonl')
      ? name.substring(0, name.length - '.jsonl'.length)
      : name;
}

String _joinPath(String parent, String child) {
  final separator = Platform.pathSeparator;
  final normalized = parent.endsWith('/') || parent.endsWith('\\')
      ? parent.substring(0, parent.length - 1)
      : parent;
  return '$normalized$separator$child';
}

// Asynchronous filesystem traversal is intentional at the vendor IO boundary.
// ignore_for_file: avoid_slow_async_io

import 'dart:convert';
import 'dart:io';

/// Discovers Codex rollout files below a configured home.
typedef CodexUsageFileDiscovery = Stream<File> Function(String codexHome);

/// Loads one rollout into a content-free usage projection.
typedef CodexUsageSourceLoader = Future<CodexUsageLoadedSource?> Function(
  File file, {
  CodexUsageCancellationCheck? isCancelled,
});

/// Reads filesystem metadata for one rollout.
typedef CodexUsageFileStatReader = Future<FileStat> Function(File file);

/// Reads decoded lines from one rollout.
typedef CodexUsageLineReader = Stream<String> Function(File file);

/// Cooperative scan cancellation callback.
typedef CodexUsageCancellationCheck = bool Function();

/// A Codex usage scan was cancelled by its caller.
final class CodexUsageScanCancelledException implements Exception {
  /// Creates a cancellation failure.
  const CodexUsageScanCancelledException();

  @override
  String toString() => 'CodexUsageScanCancelledException()';
}

/// One exact, de-duplicated Codex token-count sample.
final class CodexUsageSampleResponse {
  /// Creates a usage sample.
  const CodexUsageSampleResponse({
    required this.deduplicationKey,
    required this.timestamp,
    required this.inputTokens,
    required this.cachedInputTokens,
    required this.outputTokens,
    required this.reasoningTokens,
    required this.totalTokens,
  });

  /// Stable key shared by parent and fork replay records.
  final String deduplicationKey;

  /// Provider event timestamp.
  final DateTime timestamp;

  /// Non-cached input tokens.
  final int inputTokens;

  /// Cached input tokens.
  final int cachedInputTokens;

  /// Visible output tokens.
  final int outputTokens;

  /// Reasoning output tokens.
  final int reasoningTokens;

  /// Provider-reported total tokens.
  final int totalTokens;
}

/// Whitelisted usage fields for one Codex turn.
final class CodexUsageTurnResponse {
  /// Creates a turn response and freezes [samples].
  CodexUsageTurnResponse({
    required this.id,
    required this.status,
    required List<CodexUsageSampleResponse> samples,
    this.startedAt,
    this.completedAt,
    this.cwd,
    this.model,
  }) : samples = List<CodexUsageSampleResponse>.unmodifiable(samples);

  /// Provider turn identifier.
  final String id;

  /// Stable provider-neutral status name.
  final String status;

  /// Turn start timestamp.
  final DateTime? startedAt;

  /// Turn completion timestamp.
  final DateTime? completedAt;

  /// Working directory supplied by Codex.
  final String? cwd;

  /// Model identifier supplied by Codex.
  final String? model;

  /// Exact token-count samples for this turn.
  final List<CodexUsageSampleResponse> samples;

  CodexUsageTurnResponse _withSamples(
    List<CodexUsageSampleResponse> value,
  ) {
    return CodexUsageTurnResponse(
      id: id,
      status: status,
      startedAt: startedAt,
      completedAt: completedAt,
      cwd: cwd,
      model: model,
      samples: value,
    );
  }
}

/// Parser result before filesystem metadata and range filtering are applied.
final class CodexUsageLoadedSource {
  /// Creates a loaded source and freezes [turns].
  CodexUsageLoadedSource({
    required this.threadId,
    required this.projectPath,
    required this.sourceKind,
    required this.createdAt,
    required List<CodexUsageTurnResponse> turns,
  }) : turns = List<CodexUsageTurnResponse>.unmodifiable(turns);

  /// Provider session identifier.
  final String threadId;

  /// Provider project path.
  final String projectPath;

  /// Session originator, such as `codex_cli_rs` or `zeta`.
  final String sourceKind;

  /// Session creation timestamp.
  final DateTime createdAt;

  /// Content-free usage turns.
  final List<CodexUsageTurnResponse> turns;
}

/// One scanned Codex rollout. [sourcePath] remains memory-only.
final class CodexUsageSourceResponse {
  /// Creates a source response and freezes [turns].
  CodexUsageSourceResponse({
    required this.sourcePath,
    required this.fingerprint,
    required this.threadId,
    required this.projectPath,
    required this.sourceKind,
    required this.createdAt,
    required this.modifiedAt,
    required List<CodexUsageTurnResponse> turns,
  }) : turns = List<CodexUsageTurnResponse>.unmodifiable(turns);

  /// Memory-only source path. Storage must hash rather than persist it.
  final String sourcePath;

  /// Size/mtime fingerprint.
  final String fingerprint;

  /// Provider session identifier.
  final String threadId;

  /// Provider project path.
  final String projectPath;

  /// Session originator.
  final String sourceKind;

  /// Session creation timestamp.
  final DateTime createdAt;

  /// Source modification timestamp.
  final DateTime modifiedAt;

  /// Turns containing samples in the requested half-open range.
  final List<CodexUsageTurnResponse> turns;
}

/// Cross-project Codex scan result.
final class CodexUsageScanResult {
  /// Creates a result and freezes [sources].
  CodexUsageScanResult({
    required List<CodexUsageSourceResponse> sources,
    required this.localSourceCount,
    required this.unreadableSourceCount,
    required this.discoveryFailureCount,
  }) : sources = List<CodexUsageSourceResponse>.unmodifiable(sources);

  /// Sources containing at least one in-range usage sample.
  final List<CodexUsageSourceResponse> sources;

  /// Successfully parsed local rollouts before range filtering.
  final int localSourceCount;

  /// Rollouts skipped after a content-free IO, format, or shape failure.
  final int unreadableSourceCount;

  /// Filesystem traversal failures.
  final int discoveryFailureCount;
}

/// Reads Codex rollouts into exact, content-free token usage samples.
final class CodexUsageReader {
  /// Creates a Codex usage reader.
  CodexUsageReader({
    required this.codexHome,
    CodexUsageFileDiscovery? discoverFiles,
    CodexUsageSourceLoader? loadSource,
    CodexUsageFileStatReader? statFile,
    CodexUsageLineReader? readLines,
  }) : _discoverFiles = discoverFiles ?? _discoverCodexUsageFiles,
       _loadSource =
           loadSource ??
           _DefaultCodexUsageLoader(
             readLines: readLines ?? _readCodexUsageLines,
           ).load,
       _statFile = statFile ?? _statCodexUsageFile;

  /// Codex home directory.
  final String codexHome;

  final CodexUsageFileDiscovery _discoverFiles;
  final CodexUsageSourceLoader _loadSource;
  final CodexUsageFileStatReader _statFile;

  /// Scans exact samples in `[startInclusive, endExclusive)`.
  Future<CodexUsageScanResult> scan({
    required DateTime startInclusive,
    required DateTime endExclusive,
    CodexUsageCancellationCheck? isCancelled,
  }) async {
    if (!endExclusive.isAfter(startInclusive)) {
      throw ArgumentError.value(endExclusive, 'endExclusive');
    }
    final files = <File>[];
    var discoveryFailureCount = 0;
    try {
      await for (final file in _discoverFiles(codexHome)) {
        _throwIfCancelled(isCancelled);
        files.add(file);
      }
    } on FileSystemException {
      discoveryFailureCount += 1;
    }
    files.sort((left, right) => left.path.compareTo(right.path));

    final sources = <CodexUsageSourceResponse>[];
    var localSourceCount = 0;
    var unreadableSourceCount = 0;
    for (final file in files) {
      _throwIfCancelled(isCancelled);
      try {
        final loaded = await _loadSource(
          file,
          isCancelled: isCancelled,
        );
        _throwIfCancelled(isCancelled);
        if (loaded == null) {
          unreadableSourceCount += 1;
          continue;
        }
        localSourceCount += 1;
        final turns = <CodexUsageTurnResponse>[];
        for (final turn in loaded.turns) {
          final samples = <CodexUsageSampleResponse>[
            for (final sample in turn.samples)
              if (_insideRange(
                sample.timestamp,
                startInclusive,
                endExclusive,
              ))
                sample,
          ];
          if (samples.isNotEmpty) {
            turns.add(turn._withSamples(samples));
          }
        }
        if (turns.isEmpty) {
          continue;
        }
        final stat = await _statFile(file);
        _throwIfCancelled(isCancelled);
        sources.add(
          CodexUsageSourceResponse(
            sourcePath: file.path,
            fingerprint: '${stat.size}:${stat.modified.microsecondsSinceEpoch}',
            threadId: loaded.threadId,
            projectPath: loaded.projectPath,
            sourceKind: loaded.sourceKind,
            createdAt: loaded.createdAt,
            modifiedAt: stat.modified,
            turns: turns,
          ),
        );
      } on FileSystemException {
        unreadableSourceCount += 1;
      } on FormatException {
        unreadableSourceCount += 1;
      }
    }
    return CodexUsageScanResult(
      sources: sources,
      localSourceCount: localSourceCount,
      unreadableSourceCount: unreadableSourceCount,
      discoveryFailureCount: discoveryFailureCount,
    );
  }
}

final class _DefaultCodexUsageLoader {
  const _DefaultCodexUsageLoader({required this.readLines});

  final CodexUsageLineReader readLines;

  Future<CodexUsageLoadedSource?> load(
    File file, {
    CodexUsageCancellationCheck? isCancelled,
  }) {
    return _CodexUsageFileParser(
      file: file,
      lines: readLines(file),
      isCancelled: isCancelled,
    ).parse();
  }
}

final class _CodexUsageFileParser {
  _CodexUsageFileParser({
    required this.file,
    required this.lines,
    required this.isCancelled,
  });

  final File file;
  final Stream<String> lines;
  final CodexUsageCancellationCheck? isCancelled;
  final Map<String, _CodexUsageTurnBuilder> _turns =
      <String, _CodexUsageTurnBuilder>{};

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

  Future<CodexUsageLoadedSource?> parse() async {
    var lineNumber = 0;
    await for (final line in lines) {
      _throwIfCancelled(isCancelled);
      lineNumber += 1;
      final record = _decodeLine(line);
      if (lineNumber == 1) {
        if (!_consumeSessionMeta(record)) {
          return null;
        }
        continue;
      }
      if (record.isNotEmpty) {
        _consumeRecord(record);
      }
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
              (turn) => turn.startedAt != null || turn.samples.isNotEmpty,
            )
            .toList()
          ..sort((left, right) {
            final leftTime = left.startedAt ?? left.completedAt ?? createdAt;
            final rightTime = right.startedAt ?? right.completedAt ?? createdAt;
            return leftTime.compareTo(rightTime);
          });
    return CodexUsageLoadedSource(
      threadId: sessionId,
      projectPath: _projectPath ?? 'unknown',
      sourceKind: _sourceKind ?? 'codex',
      createdAt: createdAt,
      turns: turns,
    );
  }

  bool _consumeSessionMeta(Map<String, Object?> record) {
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
        _currentTurn(timestamp)
          ..status = 'running'
          ..startedAt ??= timestamp;
      case 'task_complete':
        final turn = _currentTurn(timestamp)..status = 'completed';
        turn.completedAt = timestamp ?? turn.completedAt;
      case 'turn_aborted':
        final turn = _currentTurn(timestamp)..status = 'interrupted';
        turn.completedAt = timestamp ?? turn.completedAt;
      case 'error':
        final turn = _currentTurn(timestamp)..status = 'failed';
        turn.completedAt = timestamp ?? turn.completedAt;
      case 'token_count':
        _consumeTokenCount(payload, timestamp: timestamp);
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
    final signature =
        '$cumulativeTotal:$totalInput:$totalCached:'
        '$totalOutput:$totalReasoning';
    final previousCumulativeTotal = _previousCumulativeTotal;
    if (_previousCumulativeSignature == signature) {
      return;
    }
    _previousCumulativeTotal = cumulativeTotal;
    _previousCumulativeSignature = signature;

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
        : _nonNegativeDelta(
            cumulativeTotal,
            previousCumulativeTotal ?? 0,
          );

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
    final turn = _currentTurn(eventTime)
      ..startedAt ??= eventTime
      ..model ??= _sessionModel;
    turn.samples.add(
      CodexUsageSampleResponse(
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

  _CodexUsageTurnBuilder _currentTurn(DateTime? timestamp) {
    final id = _currentTurnId ??= '${_sessionId ?? 'session'}:t0';
    return _turns.putIfAbsent(
      id,
      () => _CodexUsageTurnBuilder(
        id: id,
        startedAt: timestamp,
        model: _sessionModel,
      ),
    );
  }
}

final class _CodexUsageTurnBuilder {
  _CodexUsageTurnBuilder({
    required this.id,
    this.startedAt,
    this.model,
  });

  final String id;
  String status = 'unknown';
  DateTime? startedAt;
  DateTime? completedAt;
  String? cwd;
  String? model;
  final List<CodexUsageSampleResponse> samples = <CodexUsageSampleResponse>[];

  CodexUsageTurnResponse build() {
    return CodexUsageTurnResponse(
      id: id,
      status: status == 'unknown' && completedAt != null ? 'completed' : status,
      startedAt: startedAt,
      completedAt: completedAt,
      cwd: cwd,
      model: model,
      samples: samples,
    );
  }
}

Stream<File> _discoverCodexUsageFiles(String codexHome) async* {
  final root = Directory('$codexHome${Platform.pathSeparator}sessions');
  if (!await root.exists()) {
    return;
  }
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is File && _isRolloutFile(entity.path)) {
      yield entity;
    }
  }
}

Stream<String> _readCodexUsageLines(File file) {
  return file
      .openRead()
      .transform(utf8.decoder)
      .transform(const LineSplitter());
}

Future<FileStat> _statCodexUsageFile(File file) => file.stat();

Map<String, Object?> _decodeLine(String line) {
  try {
    return _map(jsonDecode(line));
  } on FormatException {
    return const <String, Object?>{};
  }
}

Map<String, Object?> _map(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  return const <String, Object?>{};
}

String? _turnIdFrom(
  Map<String, Object?> record,
  Map<String, Object?> payload,
) {
  return _string(payload['turn_id']) ??
      _string(
        _map(payload['internal_chat_message_metadata_passthrough'])['turn_id'],
      ) ??
      _string(
        _map(record['internal_chat_message_metadata_passthrough'])['turn_id'],
      );
}

String? _string(Object? value) {
  return value is String && value.trim().isNotEmpty ? value.trim() : null;
}

int? _int(Object? value) => switch (value) {
  int() => value,
  num() => value.toInt(),
  String() => int.tryParse(value),
  _ => null,
};

DateTime? _dateTime(Object? value) {
  if (value is String) {
    return DateTime.tryParse(value);
  }
  final milliseconds = _int(value);
  if (milliseconds == null) {
    return null;
  }
  final normalized = milliseconds.abs() < 1000000000000
      ? milliseconds * Duration.millisecondsPerSecond
      : milliseconds;
  return DateTime.fromMillisecondsSinceEpoch(normalized, isUtc: true);
}

int _nonNegativeDelta(int current, int baseline) {
  final delta = current - baseline;
  return delta < 0 ? 0 : delta;
}

bool _isTerminal(String status) {
  return status == 'completed' || status == 'interrupted' || status == 'failed';
}

bool _insideRange(
  DateTime value,
  DateTime startInclusive,
  DateTime endExclusive,
) {
  return !value.isBefore(startInclusive) && value.isBefore(endExclusive);
}

bool _isRolloutFile(String path) {
  final name = path.replaceAll(r'\', '/').split('/').last;
  return name.startsWith('rollout-') && name.endsWith('.jsonl');
}

String _basenameWithoutExtension(String path) {
  final name = path.replaceAll(r'\', '/').split('/').last;
  return name.endsWith('.jsonl')
      ? name.substring(0, name.length - '.jsonl'.length)
      : name;
}

void _throwIfCancelled(CodexUsageCancellationCheck? isCancelled) {
  if (isCancelled?.call() ?? false) {
    throw const CodexUsageScanCancelledException();
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:grok_acp_client/src/history/grok_updates_history_parser.dart';

/// Discovers Grok `updates.jsonl` sources.
typedef GrokUsageFileDiscovery = Stream<File> Function(String grokHome);

/// Loads one Grok source into whitelisted usage values.
typedef GrokUsageSourceLoader = Future<GrokUsageLoadedSource?> Function(
  File file,
);

/// Reads source metadata.
typedef GrokUsageFileStatReader = Future<FileStat> Function(File file);

/// Reads one vendor-owned text file.
typedef GrokUsageFileTextReader = Future<String> Function(File file);

/// Cooperative cancellation callback.
typedef GrokUsageCancellationCheck = bool Function();

/// A Grok usage scan was cancelled.
final class GrokUsageScanCancelledException implements Exception {
  /// Creates a cancellation failure.
  const GrokUsageScanCancelledException();

  @override
  String toString() => 'GrokUsageScanCancelledException()';
}

/// Whitelisted usage values for one Grok turn.
final class GrokUsageTurnResponse {
  /// Creates a turn response.
  const GrokUsageTurnResponse({
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
  });

  /// Provider turn identifier.
  final String id;

  /// Provider-neutral history status name.
  final String status;

  /// Start timestamp.
  final DateTime? startedAt;

  /// Completion timestamp.
  final DateTime? completedAt;

  /// Turn duration.
  final Duration? duration;

  /// Time to first token.
  final Duration? timeToFirstToken;

  /// Working directory.
  final String? cwd;

  /// Model identifier.
  final String? model;

  /// Non-cached input tokens.
  final int? inputTokens;

  /// Cached input tokens.
  final int? cachedInputTokens;

  /// Visible output tokens.
  final int? outputTokens;

  /// Reasoning tokens.
  final int? reasoningTokens;

  /// Total tokens.
  final int? totalTokens;

  DateTime? get _occurredAt => completedAt ?? startedAt;
}

/// Parser result before metadata and range filtering.
final class GrokUsageLoadedSource {
  /// Creates a loaded source.
  const GrokUsageLoadedSource({
    required this.threadId,
    required this.projectPath,
    required this.turns,
  });

  /// Provider session identifier.
  final String threadId;

  /// Provider project path.
  final String projectPath;

  /// Content-free usage turns.
  final List<GrokUsageTurnResponse> turns;
}

/// One scanned Grok source. [sourcePath] remains memory-only.
final class GrokUsageSourceResponse {
  /// Creates a source response.
  const GrokUsageSourceResponse({
    required this.sourcePath,
    required this.fingerprint,
    required this.threadId,
    required this.projectPath,
    required this.modifiedAt,
    required this.turns,
  });

  /// Memory-only source path.
  final String sourcePath;

  /// Size/mtime fingerprint.
  final String fingerprint;

  /// Provider session identifier.
  final String threadId;

  /// Provider project path.
  final String projectPath;

  /// Source modification time.
  final DateTime modifiedAt;

  /// In-range usage turns.
  final List<GrokUsageTurnResponse> turns;
}

/// Cross-project Grok scan result.
final class GrokUsageScanResult {
  /// Creates a scan result.
  const GrokUsageScanResult({
    required this.sources,
    required this.localSourceCount,
    required this.unreadableSourceCount,
  });

  /// Sources with in-range usage.
  final List<GrokUsageSourceResponse> sources;

  /// Parsed local sources before range filtering.
  final int localSourceCount;

  /// Sources skipped after a content-free IO/format failure.
  final int unreadableSourceCount;
}

/// Reads Grok session updates into content-free usage responses.
final class GrokUsageReader {
  /// Creates a Grok usage reader.
  GrokUsageReader({
    required this.grokHome,
    GrokUsageFileDiscovery? discoverFiles,
    GrokUsageSourceLoader? loadSource,
    GrokUsageFileStatReader? statFile,
    GrokUsageFileTextReader? readFile,
  }) : _discoverFiles = discoverFiles ?? _discoverGrokUsageFiles,
       _loadSource =
           loadSource ??
           _DefaultGrokUsageLoader(
             readFile ?? _readGrokUsageFile,
           ).load,
       _statFile = statFile ?? _statGrokUsageFile;

  /// Grok home directory.
  final String grokHome;

  final GrokUsageFileDiscovery _discoverFiles;
  final GrokUsageSourceLoader _loadSource;
  final GrokUsageFileStatReader _statFile;

  /// Scans the half-open interval `[startInclusive, endExclusive)`.
  Future<GrokUsageScanResult> scan({
    required DateTime startInclusive,
    required DateTime endExclusive,
    GrokUsageCancellationCheck? isCancelled,
  }) async {
    if (!endExclusive.isAfter(startInclusive)) {
      throw ArgumentError.value(endExclusive, 'endExclusive');
    }
    final files = await _discoverFiles(grokHome).toList();
    files.sort((left, right) => left.path.compareTo(right.path));
    final sources = <GrokUsageSourceResponse>[];
    var localSourceCount = 0;
    var unreadableSourceCount = 0;
    for (final file in files) {
      _throwIfCancelled(isCancelled);
      try {
        final loaded = await _loadSource(file);
        _throwIfCancelled(isCancelled);
        if (loaded == null) {
          unreadableSourceCount += 1;
          continue;
        }
        localSourceCount += 1;
        final turns = <GrokUsageTurnResponse>[
          for (final turn in loaded.turns)
            if (_insideRange(turn._occurredAt, startInclusive, endExclusive))
              turn,
        ];
        if (turns.isEmpty) {
          continue;
        }
        final stat = await _statFile(file);
        _throwIfCancelled(isCancelled);
        sources.add(
          GrokUsageSourceResponse(
            sourcePath: file.path,
            fingerprint: '${stat.size}:${stat.modified.microsecondsSinceEpoch}',
            threadId: loaded.threadId,
            projectPath: loaded.projectPath,
            modifiedAt: stat.modified,
            turns: List<GrokUsageTurnResponse>.unmodifiable(turns),
          ),
        );
      } on FileSystemException {
        unreadableSourceCount += 1;
      } on FormatException {
        unreadableSourceCount += 1;
      }
    }
    return GrokUsageScanResult(
      sources: List<GrokUsageSourceResponse>.unmodifiable(sources),
      localSourceCount: localSourceCount,
      unreadableSourceCount: unreadableSourceCount,
    );
  }
}

final class _DefaultGrokUsageLoader {
  const _DefaultGrokUsageLoader(this._readFile);

  final GrokUsageFileTextReader _readFile;

  Future<GrokUsageLoadedSource?> load(File file) async {
    final threadId = _basename(file.parent.path);
    if (threadId.isEmpty) {
      return null;
    }
    final projectPath = await _readGrokProjectPath(file.parent, _readFile);
    final history = const GrokUpdatesHistoryParser().parse(
      threadId: threadId,
      content: await _readFile(file),
    );
    return GrokUsageLoadedSource(
      threadId: threadId,
      projectPath: projectPath,
      turns: List<GrokUsageTurnResponse>.unmodifiable(
        history.turns.map(_projectGrokUsageTurn),
      ),
    );
  }
}

GrokUsageTurnResponse _projectGrokUsageTurn(AgentHistoryTurn turn) {
  final usage = turn.tokenUsage;
  final cached = usage?.cachedInputTokens;
  final input = usage?.inputTokens;
  return GrokUsageTurnResponse(
    id: turn.id,
    status: turn.status.name,
    startedAt: turn.startedAt,
    completedAt: turn.completedAt,
    duration: turn.duration,
    timeToFirstToken: turn.timeToFirstToken,
    cwd: turn.cwd,
    model: turn.modelId,
    inputTokens: input == null ? null : (input - (cached ?? 0)).clamp(0, input),
    cachedInputTokens: cached,
    outputTokens: usage?.outputTokens,
    reasoningTokens: usage?.reasoningOutputTokens,
    totalTokens: usage?.totalTokens,
  );
}

Stream<File> _discoverGrokUsageFiles(String grokHome) async* {
  final root = Directory('$grokHome${Platform.pathSeparator}sessions');
  if (!await root.exists()) {
    return;
  }
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is File &&
        _basename(entity.path).toLowerCase() == 'updates.jsonl') {
      yield entity;
    }
  }
}

Future<FileStat> _statGrokUsageFile(File file) => file.stat();

Future<String> _readGrokUsageFile(File file) => file.readAsString();

Future<String> _readGrokProjectPath(
  Directory sessionDirectory,
  GrokUsageFileTextReader readFile,
) async {
  final summary = File(
    '${sessionDirectory.path}${Platform.pathSeparator}summary.json',
  );
  if (await summary.exists()) {
    try {
      final decoded = jsonDecode(await readFile(summary));
      if (decoded case <String, Object?>{
        'info': final Map<String, Object?> info,
      }) {
        final cwd = info['cwd'];
        if (cwd is String && cwd.trim().isNotEmpty) {
          return cwd.trim();
        }
      }
    } on FormatException {
      // The encoded project directory remains a safe fallback.
    } on FileSystemException {
      // The encoded project directory remains a safe fallback.
    }
  }
  final encoded = _basename(sessionDirectory.parent.path);
  try {
    final decoded = Uri.decodeComponent(encoded).trim();
    return decoded.isEmpty ? 'unknown' : decoded;
    // `Uri.decodeComponent` reports malformed percent escapes as ArgumentError.
    // A directory name is untrusted input, so retain it instead of aborting a
    // scan.
    // ignore: avoid_catching_errors
  } on ArgumentError {
    return encoded.isEmpty ? 'unknown' : encoded;
  }
}

String _basename(String path) {
  final parts = path
      .split(RegExp(r'[/\\]'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  return parts.isEmpty ? '' : parts.last;
}

bool _insideRange(
  DateTime? value,
  DateTime startInclusive,
  DateTime endExclusive,
) {
  return value != null &&
      !value.isBefore(startInclusive) &&
      value.isBefore(endExclusive);
}

void _throwIfCancelled(GrokUsageCancellationCheck? isCancelled) {
  if (isCancelled?.call() ?? false) {
    throw const GrokUsageScanCancelledException();
  }
}

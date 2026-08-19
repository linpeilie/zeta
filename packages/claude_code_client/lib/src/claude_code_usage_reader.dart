// Asynchronous filesystem traversal is intentional at the vendor IO boundary.
// ignore_for_file: avoid_slow_async_io

import 'dart:io';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:claude_code_client/src/datasources/claude_code/claude_code_session_history_reader.dart';

/// Discovers Claude Code history files below a configured home.
typedef ClaudeCodeUsageFileDiscovery = Stream<File> Function(String rootPath);

/// Loads one source into a content-free usage projection.
typedef ClaudeCodeUsageSourceLoader =
    Future<ClaudeCodeUsageLoadedSource?> Function(File file);

/// Reads metadata for one Claude Code history source.
typedef ClaudeCodeUsageFileStatReader = Future<FileStat> Function(File file);

/// Cooperative scan cancellation callback.
typedef ClaudeCodeUsageCancellationCheck = bool Function();

/// A Claude Code usage scan was cancelled by its caller.
final class ClaudeCodeUsageScanCancelledException implements Exception {
  /// Creates a cancellation failure.
  const ClaudeCodeUsageScanCancelledException();

  @override
  String toString() => 'ClaudeCodeUsageScanCancelledException()';
}

/// Whitelisted usage fields for one Claude Code turn.
final class ClaudeCodeUsageTurnResponse {
  /// Creates a turn response.
  const ClaudeCodeUsageTurnResponse({
    required this.id,
    required this.status,
    required this.tokenUsageIsSessionCumulative,
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

  /// Start time, when present in history.
  final DateTime? startedAt;

  /// Completion time, when present in history.
  final DateTime? completedAt;

  /// Turn duration.
  final Duration? duration;

  /// Time to first token.
  final Duration? timeToFirstToken;

  /// Working directory supplied by the provider.
  final String? cwd;

  /// Model identifier supplied by the provider.
  final String? model;

  /// Input tokens.
  final int? inputTokens;

  /// Cached input tokens.
  final int? cachedInputTokens;

  /// Visible output tokens.
  final int? outputTokens;

  /// Reasoning output tokens.
  final int? reasoningTokens;

  /// Total tokens.
  final int? totalTokens;

  /// Whether the provider values are session-cumulative.
  final bool tokenUsageIsSessionCumulative;

  DateTime? get _occurredAt => completedAt ?? startedAt;
}

/// Parser result before filesystem metadata and range filtering are applied.
final class ClaudeCodeUsageLoadedSource {
  /// Creates a loaded source.
  const ClaudeCodeUsageLoadedSource({
    required this.threadId,
    required this.projectPath,
    required this.turns,
  });

  /// Provider session identifier.
  final String threadId;

  /// Provider project path.
  final String projectPath;

  /// Content-free usage turns.
  final List<ClaudeCodeUsageTurnResponse> turns;
}

/// One scanned Claude Code file. [sourcePath] is memory-only cache input.
final class ClaudeCodeUsageSourceResponse {
  /// Creates a scanned source response.
  const ClaudeCodeUsageSourceResponse({
    required this.sourcePath,
    required this.fingerprint,
    required this.threadId,
    required this.projectPath,
    required this.modifiedAt,
    required this.turns,
  });

  /// Memory-only source path. Storage must hash rather than persist it.
  final String sourcePath;

  /// Size/mtime fingerprint.
  final String fingerprint;

  /// Provider session identifier.
  final String threadId;

  /// Provider project path.
  final String projectPath;

  /// Source modification time.
  final DateTime modifiedAt;

  /// Turns inside the requested half-open time range.
  final List<ClaudeCodeUsageTurnResponse> turns;
}

/// Cross-project scan result that distinguishes no history from an empty range.
final class ClaudeCodeUsageScanResult {
  /// Creates a scan result.
  const ClaudeCodeUsageScanResult({
    required this.sources,
    required this.localSourceCount,
  });

  /// Sources that contain at least one in-range usage turn.
  final List<ClaudeCodeUsageSourceResponse> sources;

  /// Successfully parsed local sources before time filtering.
  final int localSourceCount;
}

/// Reads raw Claude Code JSONL history into a content-free usage projection.
final class ClaudeCodeUsageReader {
  /// Creates a usage reader.
  ClaudeCodeUsageReader({
    required this.claudeHome,
    this.providerId = 'claude-code',
    ClaudeCodeUsageFileDiscovery? discoverFiles,
    ClaudeCodeUsageSourceLoader? loadSource,
    ClaudeCodeUsageFileStatReader? statFile,
  }) : _discoverFiles = discoverFiles ?? _discoverClaudeHistoryFiles,
       _loadSource =
           loadSource ??
           _DefaultClaudeCodeUsageLoader(
             claudeHome: claudeHome,
             providerId: providerId,
           ).load,
       _statFile = statFile ?? _statClaudeUsageFile;

  /// Claude Code home directory.
  final String claudeHome;

  /// Provider configuration identifier used by the history mapper.
  final String providerId;

  final ClaudeCodeUsageFileDiscovery _discoverFiles;
  final ClaudeCodeUsageSourceLoader _loadSource;
  final ClaudeCodeUsageFileStatReader _statFile;

  /// Scans the half-open interval `[startInclusive, endExclusive)`.
  Future<ClaudeCodeUsageScanResult> scan({
    required DateTime startInclusive,
    required DateTime endExclusive,
    ClaudeCodeUsageCancellationCheck? isCancelled,
  }) async {
    if (!endExclusive.isAfter(startInclusive)) {
      throw ArgumentError.value(endExclusive, 'endExclusive');
    }
    final sources = <ClaudeCodeUsageSourceResponse>[];
    var localSourceCount = 0;
    await for (final file in _discoverFiles(claudeHome)) {
      _throwIfCancelled(isCancelled);
      final loaded = await _loadSource(file);
      _throwIfCancelled(isCancelled);
      if (loaded == null) {
        continue;
      }
      localSourceCount += 1;
      final turns = <ClaudeCodeUsageTurnResponse>[
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
        ClaudeCodeUsageSourceResponse(
          sourcePath: file.path,
          fingerprint: '${stat.size}:${stat.modified.microsecondsSinceEpoch}',
          threadId: loaded.threadId,
          projectPath: loaded.projectPath,
          modifiedAt: stat.modified,
          turns: List<ClaudeCodeUsageTurnResponse>.unmodifiable(turns),
        ),
      );
    }
    return ClaudeCodeUsageScanResult(
      sources: List<ClaudeCodeUsageSourceResponse>.unmodifiable(sources),
      localSourceCount: localSourceCount,
    );
  }
}

final class _DefaultClaudeCodeUsageLoader {
  _DefaultClaudeCodeUsageLoader({
    required String claudeHome,
    required this.providerId,
  }) : _historyReader = ClaudeCodeSessionHistoryReader(claudeHome: claudeHome);

  final String providerId;
  final ClaudeCodeSessionHistoryReader _historyReader;

  Future<ClaudeCodeUsageLoadedSource?> load(File file) async {
    final result = await _historyReader.readLocalHistoryFile(
      file: file,
      providerId: providerId,
    );
    if (result == null) {
      return null;
    }
    return ClaudeCodeUsageLoadedSource(
      threadId: result.threadId,
      projectPath: result.projectPath,
      turns: List<ClaudeCodeUsageTurnResponse>.unmodifiable(
        result.history.snapshot.turns.map(_projectClaudeUsageTurn),
      ),
    );
  }
}

ClaudeCodeUsageTurnResponse _projectClaudeUsageTurn(AgentHistoryTurn turn) {
  final usage = turn.tokenUsage;
  return ClaudeCodeUsageTurnResponse(
    id: turn.id,
    status: turn.status.name,
    startedAt: turn.startedAt,
    completedAt: turn.completedAt,
    duration: turn.duration,
    timeToFirstToken: turn.timeToFirstToken,
    cwd: turn.cwd,
    model: turn.modelId,
    inputTokens: usage?.inputTokens,
    cachedInputTokens: usage?.cachedInputTokens,
    outputTokens: usage?.outputTokens,
    reasoningTokens: usage?.reasoningOutputTokens,
    totalTokens: usage?.totalTokens,
    tokenUsageIsSessionCumulative: turn.tokenUsageIsSessionCumulative,
  );
}

Stream<File> _discoverClaudeHistoryFiles(String claudeHome) async* {
  final root = Directory(
    '$claudeHome${Platform.pathSeparator}projects',
  );
  if (!await root.exists()) {
    return;
  }
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is File && entity.path.toLowerCase().endsWith('.jsonl')) {
      yield entity;
    }
  }
}

Future<FileStat> _statClaudeUsageFile(File file) => file.stat();

bool _insideRange(
  DateTime? value,
  DateTime startInclusive,
  DateTime endExclusive,
) {
  return value != null &&
      !value.isBefore(startInclusive) &&
      value.isBefore(endExclusive);
}

void _throwIfCancelled(ClaudeCodeUsageCancellationCheck? isCancelled) {
  if (isCancelled?.call() ?? false) {
    throw const ClaudeCodeUsageScanCancelledException();
  }
}

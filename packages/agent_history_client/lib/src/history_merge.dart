import 'dart:convert';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';

/// Reads one complete provider-owned history input.
///
/// File and transport failures intentionally escape the merge boundary.
typedef HistoryInputReader = Future<String> Function();

/// Converts one valid JSON object into a provider-neutral history turn.
///
/// Return `null` for an intentionally irrelevant record. Throw
/// [HistoryRecordDecodeException] when a corrupt record should be skipped with
/// a typed warning. Any other exception is treated as a programming or
/// infrastructure failure and escapes the merge boundary.
typedef HistoryRecordDecoder = AgentHistoryTurn? Function(
  Map<String, Object?> record,
);

/// One provider-owned JSON Lines input consumed by [mergeHistoryInputs].
final class HistoryReplayInput {
  /// Creates a replay input with an injected reader and vendor decoder.
  const HistoryReplayInput({
    required this.sourceId,
    required this.read,
    required this.decode,
  });

  /// Stable, non-secret identifier used in diagnostics.
  final String sourceId;

  /// Reads the complete JSON Lines payload.
  final HistoryInputReader read;

  /// Decodes vendor records after generic JSON validation.
  final HistoryRecordDecoder decode;
}

/// Generic categories for a skipped history record.
enum HistoryDecodeWarningKind {
  /// The line was not valid JSON.
  malformedJson,

  /// The JSON value was not an object.
  nonObjectRecord,

  /// The vendor decoder rejected a corrupt record explicitly.
  rejectedRecord,
}

/// A safe, typed description of one skipped history record.
final class HistoryDecodeWarning {
  /// Creates a warning without retaining the raw record or exception.
  const HistoryDecodeWarning({
    required this.sourceId,
    required this.lineNumber,
    required this.kind,
    this.decoderCode,
  });

  /// Stable input identifier supplied by [HistoryReplayInput.sourceId].
  final String sourceId;

  /// One-based line number in the input.
  final int lineNumber;

  /// Generic warning category.
  final HistoryDecodeWarningKind kind;

  /// Optional non-secret vendor code for an explicitly rejected record.
  final String? decoderCode;
}

/// Typed signal that a vendor decoder considers one record corrupt.
final class HistoryRecordDecodeException implements Exception {
  /// Creates a rejection with a stable, non-secret [code].
  const HistoryRecordDecodeException(this.code);

  /// Vendor-defined diagnostic code; raw payloads must not be included.
  final String code;

  @override
  String toString() => 'HistoryRecordDecodeException($code)';
}

/// Provider-neutral output from reading and merging history inputs.
final class HistoryMergeResult {
  /// Creates an immutable merge result.
  HistoryMergeResult({
    required List<AgentHistoryTurn> turns,
    required List<HistoryDecodeWarning> warnings,
  }) : turns = List<AgentHistoryTurn>.unmodifiable(turns),
       warnings = List<HistoryDecodeWarning>.unmodifiable(warnings);

  /// Turns in first-seen order, with later duplicate ids replacing content.
  final List<AgentHistoryTurn> turns;

  /// Corrupt individual records skipped during decoding.
  final List<HistoryDecodeWarning> warnings;
}

/// Reads JSON Lines [inputs] and merges their provider-neutral turns.
///
/// Inputs and records are processed in caller order. The first occurrence of a
/// turn id fixes its position; later occurrences replace that turn in place so
/// a higher-fidelity later input can overlay an earlier replay source.
///
/// Malformed individual records are skipped with typed warnings. Reader
/// failures and unexpected decoder failures are never caught.
Future<HistoryMergeResult> mergeHistoryInputs(
  Iterable<HistoryReplayInput> inputs,
) async {
  final turns = <AgentHistoryTurn>[];
  final turnIndexes = <String, int>{};
  final warnings = <HistoryDecodeWarning>[];

  for (final input in inputs) {
    final contents = await input.read();
    final lines = const LineSplitter().convert(contents);
    for (var index = 0; index < lines.length; index += 1) {
      final line = lines[index].trim();
      if (line.isEmpty) {
        continue;
      }
      final lineNumber = index + 1;
      Object? value;
      try {
        value = jsonDecode(line);
      } on FormatException {
        warnings.add(
          HistoryDecodeWarning(
            sourceId: input.sourceId,
            lineNumber: lineNumber,
            kind: HistoryDecodeWarningKind.malformedJson,
          ),
        );
        continue;
      }
      if (value is! Map) {
        warnings.add(
          HistoryDecodeWarning(
            sourceId: input.sourceId,
            lineNumber: lineNumber,
            kind: HistoryDecodeWarningKind.nonObjectRecord,
          ),
        );
        continue;
      }

      final record = value.map<String, Object?>(
        (key, item) => MapEntry(key.toString(), item as Object?),
      );
      AgentHistoryTurn? turn;
      try {
        turn = input.decode(record);
      } on HistoryRecordDecodeException catch (error) {
        warnings.add(
          HistoryDecodeWarning(
            sourceId: input.sourceId,
            lineNumber: lineNumber,
            kind: HistoryDecodeWarningKind.rejectedRecord,
            decoderCode: error.code,
          ),
        );
        continue;
      }
      if (turn == null) {
        continue;
      }

      final existingIndex = turnIndexes[turn.id];
      if (existingIndex == null) {
        turnIndexes[turn.id] = turns.length;
        turns.add(turn);
      } else {
        turns[existingIndex] = turn;
      }
    }
  }

  return HistoryMergeResult(turns: turns, warnings: warnings);
}

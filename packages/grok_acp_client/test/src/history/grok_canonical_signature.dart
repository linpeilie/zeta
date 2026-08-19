import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:meta/meta.dart';

/// Grok live/history 对比使用的稳定条目签名。
///
/// ordinal 均从 1 开始；runtime id、connection epoch 与规范化 entryId 不参与
/// 对比，只比较用户可见语义和 source metadata。
@immutable
final class GrokCanonicalEntrySignature {
  const GrokCanonicalEntrySignature({
    required this.turnOrdinal,
    required this.entryOrdinal,
    required this.entryType,
    required this.normalizedText,
    this.phaseOrdinal,
    this.sourceId,
    this.toolKind,
    this.toolStatus,
  });

  factory GrokCanonicalEntrySignature.fromJson(Map<String, Object?> json) {
    return GrokCanonicalEntrySignature(
      turnOrdinal: json['turnOrdinal']! as int,
      entryOrdinal: json['entryOrdinal']! as int,
      entryType: json['entryType']! as String,
      phaseOrdinal: json['phaseOrdinal'] as int?,
      sourceId: json['sourceId'] as String?,
      normalizedText: json['normalizedText']! as String,
      toolKind: json['toolKind'] as String?,
      toolStatus: json['toolStatus'] as String?,
    );
  }

  final int turnOrdinal;
  final int entryOrdinal;
  final String entryType;
  final int? phaseOrdinal;
  final String? sourceId;
  final String normalizedText;
  final String? toolKind;
  final String? toolStatus;

  @override
  bool operator ==(Object other) {
    return other is GrokCanonicalEntrySignature &&
        other.turnOrdinal == turnOrdinal &&
        other.entryOrdinal == entryOrdinal &&
        other.entryType == entryType &&
        other.phaseOrdinal == phaseOrdinal &&
        other.sourceId == sourceId &&
        other.normalizedText == normalizedText &&
        other.toolKind == toolKind &&
        other.toolStatus == toolStatus;
  }

  @override
  int get hashCode => Object.hash(
    turnOrdinal,
    entryOrdinal,
    entryType,
    phaseOrdinal,
    sourceId,
    normalizedText,
    toolKind,
    toolStatus,
  );

  @override
  String toString() {
    return 'GrokCanonicalEntrySignature('
        'turn=$turnOrdinal, entry=$entryOrdinal, type=$entryType, '
        'phase=$phaseOrdinal, source=$sourceId, text=$normalizedText, '
        'toolKind=$toolKind, toolStatus=$toolStatus)';
  }
}

/// 将 live AgentEvent 与 history snapshot 投影到相同 canonical contract。
abstract final class GrokCanonicalComparator {
  static List<GrokCanonicalEntrySignature> fromLiveTurns(
    List<List<AgentEvent>> turns,
  ) {
    final result = <GrokCanonicalEntrySignature>[];
    for (var turnIndex = 0; turnIndex < turns.length; turnIndex += 1) {
      final accumulator = _CanonicalTurnAccumulator();
      turns[turnIndex].forEach(accumulator.apply);
      result.addAll(accumulator.build(turnOrdinal: turnIndex + 1));
    }
    return List<GrokCanonicalEntrySignature>.unmodifiable(result);
  }

  static List<GrokCanonicalEntrySignature> fromHistory(
    AgentThreadHistorySnapshot snapshot,
  ) {
    final result = <GrokCanonicalEntrySignature>[];
    for (var turnIndex = 0; turnIndex < snapshot.turns.length; turnIndex += 1) {
      var messageOrdinal = 0;
      var reasoningOrdinal = 0;
      var entryOrdinal = 0;
      for (final entry in snapshot.turns[turnIndex].entries) {
        switch (entry) {
          case AgentHistoryMessageEntry()
              when entry.role == AgentMessageRole.user:
            // live mapper 会抑制 user chunk；live 用户消息由 ViewModel 乐观插入。
            continue;
          case AgentHistoryMessageEntry():
            entryOrdinal += 1;
            final isPlan = entry.kind == AgentMessageKind.plan;
            if (!isPlan) {
              messageOrdinal += 1;
            }
            result.add(
              GrokCanonicalEntrySignature(
                turnOrdinal: turnIndex + 1,
                entryOrdinal: entryOrdinal,
                entryType: isPlan ? 'plan' : 'message',
                phaseOrdinal: isPlan ? null : messageOrdinal,
                sourceId: entry.sourceMessageId,
                normalizedText: _normalizeText(entry.text),
              ),
            );
          case AgentHistoryToolEntry():
            entryOrdinal += 1;
            final tool = entry.toolCall;
            if (tool.kind == AgentToolKind.think) {
              reasoningOrdinal += 1;
              result.add(
                GrokCanonicalEntrySignature(
                  turnOrdinal: turnIndex + 1,
                  entryOrdinal: entryOrdinal,
                  entryType: 'reasoning',
                  phaseOrdinal: reasoningOrdinal,
                  sourceId: _reasoningSourceId(tool.raw),
                  normalizedText: _normalizeText(tool.content ?? ''),
                ),
              );
            } else {
              result.add(
                GrokCanonicalEntrySignature(
                  turnOrdinal: turnIndex + 1,
                  entryOrdinal: entryOrdinal,
                  entryType: 'tool',
                  sourceId: tool.id,
                  normalizedText: _normalizeText(tool.content ?? ''),
                  toolKind: tool.kind.name,
                  toolStatus: tool.status.name,
                ),
              );
            }
          case AgentHistoryEventEntry():
            entryOrdinal += 1;
            result.add(
              GrokCanonicalEntrySignature(
                turnOrdinal: turnIndex + 1,
                entryOrdinal: entryOrdinal,
                entryType: 'event',
                normalizedText: _normalizeText(
                  <String?>[
                    entry.title,
                    entry.description,
                    entry.content,
                  ].whereType<String>().join('\n'),
                ),
              ),
            );
        }
      }
    }
    return List<GrokCanonicalEntrySignature>.unmodifiable(result);
  }

  /// 返回逐位置差异；空列表表示完整相对顺序及所有字段一致。
  static List<String> compare(
    List<GrokCanonicalEntrySignature> live,
    List<GrokCanonicalEntrySignature> history,
  ) {
    final differences = <String>[];
    if (live.length != history.length) {
      differences.add('length: live=${live.length}, history=${history.length}');
    }
    final sharedLength = live.length < history.length
        ? live.length
        : history.length;
    for (var index = 0; index < sharedLength; index += 1) {
      if (live[index] != history[index]) {
        differences.add(
          'entry ${index + 1}: live=${live[index]}, history=${history[index]}',
        );
      }
    }
    return List<String>.unmodifiable(differences);
  }
}

final class _CanonicalTurnAccumulator {
  final List<_MutableCanonicalEntry> _entries = <_MutableCanonicalEntry>[];
  final Map<String, int> _indexByKey = <String, int>{};
  int _messageOrdinal = 0;
  int _reasoningOrdinal = 0;

  void apply(AgentEvent event) {
    switch (event) {
      case AgentMessageDeltaEvent():
        final key = 'message:${event.messageId}';
        final existingIndex = _indexByKey[key];
        if (existingIndex == null) {
          _messageOrdinal += 1;
          _indexByKey[key] = _entries.length;
          _entries.add(
            _MutableCanonicalEntry(
              entryType: event.kind == AgentMessageKind.plan
                  ? 'plan'
                  : 'message',
              phaseOrdinal: event.kind == AgentMessageKind.plan
                  ? null
                  : _messageOrdinal,
              sourceId: event.sourceMessageId,
              text: event.delta,
            ),
          );
        } else {
          final existing = _entries[existingIndex];
          existing
            ..sourceId = event.sourceMessageId ?? existing.sourceId
            ..text = '${existing.text}${event.delta}';
        }
      case AgentMessageUpdatedEvent():
        final existingIndex = _indexByKey['message:${event.messageId}'];
        if (existingIndex != null) {
          final existing = _entries[existingIndex];
          existing
            ..sourceId = event.sourceMessageId ?? existing.sourceId
            ..text = event.text ?? existing.text;
        }
      case AgentReasoningDeltaEvent():
        final key = 'reasoning:${event.itemId}';
        final existingIndex = _indexByKey[key];
        if (existingIndex == null) {
          _reasoningOrdinal += 1;
          _indexByKey[key] = _entries.length;
          _entries.add(
            _MutableCanonicalEntry(
              entryType: 'reasoning',
              phaseOrdinal: _reasoningOrdinal,
              sourceId: event.sourceItemId,
              text: event.delta,
            ),
          );
        } else {
          final existing = _entries[existingIndex];
          existing
            ..sourceId = event.sourceItemId ?? existing.sourceId
            ..text = '${existing.text}${event.delta}';
        }
      case AgentToolCallEvent():
        final tool = event.toolCall;
        final key = 'tool:${tool.id}';
        final existingIndex = _indexByKey[key];
        if (existingIndex == null) {
          _indexByKey[key] = _entries.length;
          _entries.add(
            _MutableCanonicalEntry(
              entryType: 'tool',
              sourceId: tool.id,
              text: tool.content ?? '',
              toolKind: tool.kind,
              toolStatus: tool.status,
            ),
          );
        } else {
          final existing = _entries[existingIndex];
          existing
            ..text = tool.content == null || tool.content!.isEmpty
                ? existing.text
                : tool.content!
            ..toolKind = tool.kind == AgentToolKind.other
                ? existing.toolKind
                : tool.kind
            ..toolStatus = tool.status;
        }
      case AgentPlanUpdatedEvent():
        final key = 'plan:${event.turnId ?? 'current'}';
        final text = event.entries
            .where((entry) => entry.content.trim().isNotEmpty)
            .map(
              (entry) => entry.status == null || entry.status!.isEmpty
                  ? '- ${entry.content.trim()}'
                  : '- [${entry.status}] ${entry.content.trim()}',
            )
            .join('\n');
        final existingIndex = _indexByKey[key];
        if (existingIndex == null) {
          _indexByKey[key] = _entries.length;
          _entries.add(_MutableCanonicalEntry(entryType: 'plan', text: text));
        } else {
          _entries[existingIndex].text = text;
        }
      default:
        break;
    }
  }

  List<GrokCanonicalEntrySignature> build({required int turnOrdinal}) {
    return <GrokCanonicalEntrySignature>[
      for (var index = 0; index < _entries.length; index += 1)
        GrokCanonicalEntrySignature(
          turnOrdinal: turnOrdinal,
          entryOrdinal: index + 1,
          entryType: _entries[index].entryType,
          phaseOrdinal: _entries[index].phaseOrdinal,
          sourceId: _entries[index].sourceId,
          normalizedText: _normalizeText(_entries[index].text),
          toolKind: _entries[index].toolKind?.name,
          toolStatus: _entries[index].toolStatus?.name,
        ),
    ];
  }
}

final class _MutableCanonicalEntry {
  _MutableCanonicalEntry({
    required this.entryType,
    required this.text,
    this.phaseOrdinal,
    this.sourceId,
    this.toolKind,
    this.toolStatus,
  });

  final String entryType;
  final int? phaseOrdinal;
  String? sourceId;
  String text;
  AgentToolKind? toolKind;
  AgentToolStatus? toolStatus;
}

String _normalizeText(String value) {
  return value
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String? _reasoningSourceId(Map<String, Object?> raw) {
  return _nonEmptyString(raw['sourceItemId']) ??
      _nonEmptyString(raw['itemId']) ??
      _nonEmptyString(raw['messageId']);
}

String? _nonEmptyString(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

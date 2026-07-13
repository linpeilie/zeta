import 'dart:convert';

import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// 从 Grok `updates.jsonl` 重建多回合历史快照。
///
/// 每行形如：
/// `{"timestamp":...,"method":"session/update","params":{sessionId,update,_meta}}`
///
/// 回合边界：
/// - 新的 `user_message_chunk` 开启新 turn
/// - `turn_completed`（含 `_x.ai/session/update`）结束当前 turn
/// - 无 user 时按 `promptId` 切换也可开启 turn
class GrokUpdatesHistoryParser {
  const GrokUpdatesHistoryParser();

  /// 解析完整 JSONL 文本。
  AgentThreadHistorySnapshot parse({
    required String threadId,
    required String content,
    Map<String, Object?> raw = const <String, Object?>{},
  }) {
    final turns = <_TurnBuilder>[];
    _TurnBuilder? current;
    final toolById = <String, AgentToolCall>{};

    void ensureTurn({String? promptId, String? fallbackId}) {
      if (current != null) {
        return;
      }
      final id =
          promptId ??
          fallbackId ??
          'grok-turn-${turns.length + 1}-$threadId'.hashCode
              .toUnsigned(32)
              .toRadixString(16);
      current = _TurnBuilder(id: id);
      turns.add(current!);
    }

    void closeTurn({
      AgentHistoryTurnStatus status = AgentHistoryTurnStatus.completed,
      AgentTokenUsage? usage,
      String? errorMessage,
    }) {
      final turn = current;
      if (turn == null) {
        return;
      }
      turn.status = status;
      if (usage != null) {
        turn.tokenUsage = usage;
      }
      if (errorMessage != null) {
        turn.errorMessage = errorMessage;
      }
      // 将仍挂起的工具写入当前 turn（若尚未写入）。
      current = null;
    }

    for (final line in const LineSplitter().convert(content)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      Map<String, Object?> root;
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is! Map) {
          continue;
        }
        root = decoded.map(
          (key, value) => MapEntry(key.toString(), value as Object?),
        );
      } catch (_) {
        continue;
      }

      final method = root['method']?.toString() ?? '';
      final params = _asMap(root['params']) ?? const <String, Object?>{};
      final update = _asMap(params['update']) ?? const <String, Object?>{};
      final paramsMeta = _asMap(params['_meta']) ?? const <String, Object?>{};
      final updateMeta = _asMap(update['_meta']) ?? const <String, Object?>{};
      final kind =
          update['sessionUpdate']?.toString() ??
          (method.contains('turn_completed') ? 'turn_completed' : '');

      final promptId =
          updateMeta['promptId']?.toString() ??
          paramsMeta['promptId']?.toString() ??
          update['prompt_id']?.toString() ??
          update['promptId']?.toString();
      final eventId =
          paramsMeta['eventId']?.toString() ??
          updateMeta['eventId']?.toString();

      switch (kind) {
        case 'user_message_chunk':
          // 新用户消息开启新 turn；先收尾上一个。
          if (current != null && current!.hasContent) {
            closeTurn();
          }
          ensureTurn(
            promptId: promptId,
            fallbackId: eventId ?? 'user-${turns.length}',
          );
          final text = _contentText(update['content']);
          if (text != null && text.trim().isNotEmpty) {
            final messageId =
                update['messageId']?.toString() ??
                eventId ??
                'user-${current!.id}-${current!.entries.length}';
            current!.addMessage(
              AgentHistoryMessageEntry(
                id: messageId,
                role: AgentMessageRole.user,
                text: text,
                status: AgentMessageStatus.completed,
                raw: update,
              ),
            );
          }

        case 'agent_message_chunk':
          ensureTurn(promptId: promptId, fallbackId: eventId);
          // 回合边界只认 user_message / turn_completed；promptId 仅用于对齐 id。
          if (promptId != null && current != null) {
            current!.preferId(promptId);
          }
          final text = _contentText(update['content']);
          if (text == null || text.trim().isEmpty) {
            break;
          }
          final messageId =
              update['messageId']?.toString() ??
              eventId ??
              'agent-${current!.id}-${current!.entries.length}';
          current!.addOrMergeAgentMessage(
            id: messageId,
            text: text,
            raw: update,
          );

        case 'agent_thought_chunk':
          ensureTurn(promptId: promptId, fallbackId: eventId);
          if (promptId != null && current != null) {
            current!.preferId(promptId);
          }
          final text = _contentText(update['content']) ?? '';
          if (text.trim().isEmpty) {
            break;
          }
          final itemId =
              update['messageId']?.toString() ??
              eventId ??
              'thought-${current!.id}-${current!.entries.length}';
          current!.addOrMergeThought(id: itemId, text: text, raw: update);

        case 'tool_call':
        case 'tool_call_update':
          ensureTurn(promptId: promptId, fallbackId: eventId);
          if (promptId != null && current != null) {
            current!.preferId(promptId);
          }
          final tool = _mapToolCall(update: update, sessionId: threadId);
          if (tool == null) {
            break;
          }
          final merged = _mergeTool(toolById[tool.id], tool);
          toolById[tool.id] = merged;
          current!.upsertTool(merged);

        case 'plan':
          ensureTurn(promptId: promptId, fallbackId: eventId);
          final planText = _planText(update['entries']);
          if (planText.isEmpty) {
            break;
          }
          final planId =
              eventId ?? 'plan-${current!.id}-${current!.entries.length}';
          current!.addMessage(
            AgentHistoryMessageEntry(
              id: planId,
              role: AgentMessageRole.agent,
              text: planText,
              status: AgentMessageStatus.completed,
              raw: <String, Object?>{'type': 'plan', ...update},
            ),
          );

        case 'turn_completed':
          final stop =
              update['stop_reason']?.toString() ??
              update['stopReason']?.toString() ??
              'end_turn';
          final usageMap = _asMap(update['usage']);
          AgentTokenUsage? usage;
          if (usageMap != null) {
            usage = AgentTokenUsage(
              inputTokens: _asInt(usageMap['inputTokens']),
              outputTokens: _asInt(usageMap['outputTokens']),
              totalTokens: _asInt(usageMap['totalTokens']),
              cachedInputTokens: _asInt(usageMap['cachedReadTokens']),
              reasoningOutputTokens: _asInt(usageMap['reasoningTokens']),
            );
          }
          if (current == null) {
            ensureTurn(
              promptId: update['prompt_id']?.toString() ?? promptId,
              fallbackId: eventId,
            );
          }
          closeTurn(
            status: _stopReasonToStatus(stop),
            usage: usage,
            errorMessage: _isFailedStop(stop) ? stop : null,
          );

        default:
          break;
      }
    }

    // 文件末尾未 close 的 turn 视为 completed。
    if (current != null) {
      closeTurn();
    }

    final built = turns
        .where((turn) => turn.hasContent)
        .map((turn) => turn.build())
        .toList(growable: false);

    return AgentThreadHistorySnapshot(
      threadId: threadId,
      turns: List<AgentHistoryTurn>.unmodifiable(built),
      currentTurn: built.isEmpty ? null : built.last,
      raw: raw,
    );
  }

  AgentToolCall? _mapToolCall({
    required Map<String, Object?> update,
    required String sessionId,
  }) {
    final id = update['toolCallId']?.toString();
    if (id == null || id.isEmpty) {
      return null;
    }
    final title = update['title']?.toString() ?? id;
    final kind = switch (update['kind']?.toString()) {
      'read' => AgentToolKind.read,
      'edit' => AgentToolKind.edit,
      'delete' => AgentToolKind.delete,
      'move' => AgentToolKind.move,
      'search' => AgentToolKind.search,
      'execute' => AgentToolKind.execute,
      'think' => AgentToolKind.think,
      'fetch' => AgentToolKind.fetch,
      _ => AgentToolKind.other,
    };
    final status = switch (update['status']?.toString()) {
      'pending' => AgentToolStatus.pending,
      'in_progress' => AgentToolStatus.inProgress,
      'completed' => AgentToolStatus.completed,
      'failed' => AgentToolStatus.failed,
      'cancelled' => AgentToolStatus.cancelled,
      _ => AgentToolStatus.completed,
    };
    final locations = <String>[];
    final rawLocations = update['locations'];
    if (rawLocations is List) {
      for (final item in rawLocations) {
        if (item is Map && item['path'] != null) {
          locations.add(item['path'].toString());
        } else if (item is String && item.isNotEmpty) {
          locations.add(item);
        }
      }
    }
    final rawInput = _asMap(update['rawInput']) ?? const <String, Object?>{};
    final rawOutput = _asMap(update['rawOutput']) ?? const <String, Object?>{};
    return AgentToolCall(
      id: id,
      title: title,
      kind: kind,
      status: status,
      content: _toolContentText(update['content']),
      locations: List<String>.unmodifiable(locations),
      sessionId: sessionId,
      rawInput: rawInput,
      rawOutput: rawOutput,
      raw: update,
    );
  }

  AgentToolCall _mergeTool(AgentToolCall? previous, AgentToolCall next) {
    if (previous == null) {
      return next;
    }
    return AgentToolCall(
      id: next.id,
      title: next.title.isNotEmpty ? next.title : previous.title,
      kind: next.kind == AgentToolKind.other ? previous.kind : next.kind,
      status: next.status,
      content: (next.content != null && next.content!.isNotEmpty)
          ? next.content
          : previous.content,
      locations: next.locations.isNotEmpty
          ? next.locations
          : previous.locations,
      sessionId: next.sessionId ?? previous.sessionId,
      turnId: next.turnId ?? previous.turnId,
      rawInput: next.rawInput.isNotEmpty ? next.rawInput : previous.rawInput,
      rawOutput: next.rawOutput.isNotEmpty
          ? next.rawOutput
          : previous.rawOutput,
      raw: next.raw.isNotEmpty ? next.raw : previous.raw,
    );
  }

  String _planText(Object? entries) {
    if (entries is! List) {
      return '';
    }
    final lines = <String>[];
    for (final item in entries) {
      if (item is! Map) {
        continue;
      }
      final content = (item['content']?.toString() ?? '').trim();
      if (content.isEmpty) {
        continue;
      }
      final status = item['status']?.toString();
      lines.add(
        status == null || status.isEmpty
            ? '- $content'
            : '- [$status] $content',
      );
    }
    return lines.join('\n');
  }

  AgentHistoryTurnStatus _stopReasonToStatus(String stopReason) {
    final normalized = stopReason.toLowerCase();
    if (normalized.contains('cancel')) {
      return AgentHistoryTurnStatus.interrupted;
    }
    if (_isFailedStop(normalized)) {
      return AgentHistoryTurnStatus.failed;
    }
    return AgentHistoryTurnStatus.completed;
  }

  bool _isFailedStop(String stopReason) {
    final normalized = stopReason.toLowerCase();
    return normalized.contains('refus') ||
        normalized.contains('error') ||
        normalized.contains('fail') ||
        normalized.contains('max_token') ||
        normalized.contains('max_turn');
  }
}

class _TurnBuilder {
  _TurnBuilder({required this.id});

  String id;
  final List<AgentHistoryEntry> entries = <AgentHistoryEntry>[];
  final Map<String, int> _messageIndexById = <String, int>{};
  final Map<String, int> _toolIndexById = <String, int>{};
  AgentHistoryTurnStatus status = AgentHistoryTurnStatus.completed;
  AgentTokenUsage? tokenUsage;
  String? errorMessage;

  bool get hasContent => entries.isNotEmpty;

  void preferId(String preferred) {
    if (preferred.isNotEmpty) {
      id = preferred;
    }
  }

  void addMessage(AgentHistoryMessageEntry entry) {
    final existing = _messageIndexById[entry.id];
    if (existing != null) {
      entries[existing] = entry;
      return;
    }
    _messageIndexById[entry.id] = entries.length;
    entries.add(entry);
  }

  /// agent_message_chunk 可能是完整段落；同 id 合并文本。
  void addOrMergeAgentMessage({
    required String id,
    required String text,
    required Map<String, Object?> raw,
  }) {
    final existingIndex = _messageIndexById[id];
    if (existingIndex != null) {
      final existing = entries[existingIndex] as AgentHistoryMessageEntry;
      // 完整段落重复到达时去重；否则拼接流式增量。
      final mergedText = existing.text == text
          ? existing.text
          : existing.text.endsWith(text)
          ? existing.text
          : text.startsWith(existing.text)
          ? text
          : '${existing.text}$text';
      entries[existingIndex] = AgentHistoryMessageEntry(
        id: id,
        role: AgentMessageRole.agent,
        text: mergedText,
        status: AgentMessageStatus.completed,
        raw: raw,
      );
      return;
    }
    addMessage(
      AgentHistoryMessageEntry(
        id: id,
        role: AgentMessageRole.agent,
        text: text,
        status: AgentMessageStatus.completed,
        raw: raw,
      ),
    );
  }

  void addOrMergeThought({
    required String id,
    required String text,
    required Map<String, Object?> raw,
  }) {
    final existingIndex = _toolIndexById[id];
    if (existingIndex != null) {
      final existing = entries[existingIndex] as AgentHistoryToolEntry;
      final prev = existing.toolCall.content ?? '';
      final merged = prev == text
          ? prev
          : prev.endsWith(text)
          ? prev
          : text.startsWith(prev)
          ? text
          : '$prev$text';
      entries[existingIndex] = AgentHistoryToolEntry(
        toolCall: AgentToolCall(
          id: id,
          title: existing.toolCall.title,
          kind: AgentToolKind.think,
          status: AgentToolStatus.completed,
          content: merged,
          raw: raw,
        ),
      );
      return;
    }
    _toolIndexById[id] = entries.length;
    entries.add(
      AgentHistoryToolEntry(
        toolCall: AgentToolCall(
          id: id,
          title: 'Thinking',
          kind: AgentToolKind.think,
          status: AgentToolStatus.completed,
          content: text,
          raw: raw,
        ),
      ),
    );
  }

  void upsertTool(AgentToolCall tool) {
    final existingIndex = _toolIndexById[tool.id];
    if (existingIndex != null) {
      entries[existingIndex] = AgentHistoryToolEntry(toolCall: tool);
      return;
    }
    _toolIndexById[tool.id] = entries.length;
    entries.add(AgentHistoryToolEntry(toolCall: tool));
  }

  AgentHistoryTurn build() {
    return AgentHistoryTurn(
      id: id,
      entries: List<AgentHistoryEntry>.unmodifiable(entries),
      status: status,
      tokenUsage: tokenUsage,
      errorMessage: errorMessage,
    );
  }
}

Map<String, Object?>? _asMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  return value.map((key, item) => MapEntry(key.toString(), item as Object?));
}

String? _contentText(Object? content) {
  if (content is String) {
    return content;
  }
  if (content is Map) {
    final map = content.map(
      (key, value) => MapEntry(key.toString(), value as Object?),
    );
    return map['text']?.toString();
  }
  return null;
}

String? _toolContentText(Object? content) {
  if (content == null) {
    return null;
  }
  if (content is String) {
    return content;
  }
  if (content is List) {
    final buffer = StringBuffer();
    for (final item in content) {
      if (item is! Map) {
        continue;
      }
      final map = item.map(
        (key, value) => MapEntry(key.toString(), value as Object?),
      );
      final type = map['type']?.toString();
      if (type == 'content') {
        final nested = _contentText(map['content']);
        if (nested != null) {
          if (buffer.isNotEmpty) {
            buffer.writeln();
          }
          buffer.write(nested);
        }
      } else if (type == 'diff') {
        final path = map['path']?.toString() ?? 'file';
        if (buffer.isNotEmpty) {
          buffer.writeln();
        }
        buffer.write('diff: $path');
      }
    }
    final text = buffer.toString();
    return text.isEmpty ? null : text;
  }
  return content.toString();
}

int? _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

import 'dart:convert';

import 'package:zeta/src/features/agent/data/datasources/local_history/grok_user_content_parser.dart';
import 'package:zeta/src/features/agent/data/mappers/context_window_codec.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// 从 Grok `updates.jsonl` 重建多回合历史快照。
///
/// 每行形如：
/// `{"timestamp":...,"method":"session/update","params":{sessionId,update,_meta}}`
///
/// 回合边界：
/// - 新的逻辑用户消息开启新 turn；同 `promptId` / `promptIndex` 的 chunk 合并
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
    String? currentModelId;

    void ensureTurn({String? promptId, String? fallbackId, DateTime? at}) {
      if (current != null) {
        current!.noteTime(at);
        return;
      }
      final id =
          promptId ??
          fallbackId ??
          'grok-turn-${turns.length + 1}-$threadId'.hashCode
              .toUnsigned(32)
              .toRadixString(16);
      current = _TurnBuilder(id: id, model: currentModelId)..noteTime(at);
      turns.add(current!);
    }

    void closeTurn({
      AgentHistoryTurnStatus status = AgentHistoryTurnStatus.completed,
      AgentTokenUsage? usage,
      Duration? duration,
      DateTime? at,
      String? errorMessage,
    }) {
      final turn = current;
      if (turn == null) {
        return;
      }
      turn.status = status;
      turn.noteTime(at);
      turn.completedAt ??= at;
      if (usage != null) {
        turn.tokenUsage = usage;
      }
      if (duration != null) {
        turn.duration = duration;
      } else if (turn.duration == null &&
          turn.startedAt != null &&
          turn.completedAt != null) {
        final inferred = turn.completedAt!.difference(turn.startedAt!);
        turn.duration = inferred.isNegative ? Duration.zero : inferred;
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
      final userPromptKey = _userPromptKey(
        promptId: promptId,
        promptIndex:
            updateMeta['promptIndex'] ??
            paramsMeta['promptIndex'] ??
            update['prompt_index'] ??
            update['promptIndex'],
        messageId: update['messageId']?.toString(),
      );
      // 事件时刻：优先 agentTimestampMs（毫秒），否则行级 timestamp（多为秒）。
      // turnStartMs 只用于校准 startedAt，不当作 completedAt。
      final eventAt =
          _dateTimeFromMs(updateMeta['agentTimestampMs']) ??
          _dateTimeFromMs(paramsMeta['agentTimestampMs']) ??
          _dateTimeFromTimestamp(root['timestamp']);

      final reportedModelId = _firstNonEmpty(<Object?>[
        update['modelId'],
        update['model_id'],
        updateMeta['modelId'],
        paramsMeta['modelId'],
        params['modelId'],
      ]);
      if (reportedModelId != null) {
        currentModelId = reportedModelId;
        current?.model ??= reportedModelId;
      }

      switch (kind) {
        case 'user_message_chunk':
          // Grok 会把同一次 prompt 的文字和本地图片拆成多个 chunk。
          // 只有逻辑 prompt 变化时才关闭上一 turn。
          if (current != null &&
              current!.hasContent &&
              !current!.acceptsUserPrompt(userPromptKey)) {
            closeTurn(at: eventAt);
          }
          ensureTurn(
            promptId: promptId,
            fallbackId: eventId ?? 'user-${turns.length}',
            at: eventAt,
          );
          current!.noteUserPrompt(userPromptKey);
          final parsed = parseGrokUserContent(
            _contentText(update['content']) ?? '',
          );
          if (parsed.text.isNotEmpty || parsed.localImagePaths.isNotEmpty) {
            final messageId =
                update['messageId']?.toString() ??
                eventId ??
                'user-${current!.id}-${current!.entries.length}';
            current!.addOrMergeUserMessage(
              id: messageId,
              text: parsed.text,
              localImagePaths: parsed.localImagePaths,
              raw: update,
            );
          }

        case 'agent_message_chunk':
          ensureTurn(promptId: promptId, fallbackId: eventId, at: eventAt);
          // 回合边界只认 user_message / turn_completed；promptId 仅用于对齐 id。
          if (promptId != null && current != null) {
            current!.preferId(promptId);
          }
          // 流式 chunk 的 turnStartMs 是整轮开始时刻，优先作 startedAt。
          current?.noteTurnStartMs(updateMeta['turnStartMs']);
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
          ensureTurn(promptId: promptId, fallbackId: eventId, at: eventAt);
          if (promptId != null && current != null) {
            current!.preferId(promptId);
          }
          current?.noteTurnStartMs(updateMeta['turnStartMs']);
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
          ensureTurn(promptId: promptId, fallbackId: eventId, at: eventAt);
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
          ensureTurn(promptId: promptId, fallbackId: eventId, at: eventAt);
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
          Duration? duration;
          if (usageMap != null) {
            usage = AgentTokenUsage(
              inputTokens: _asInt(usageMap['inputTokens']),
              outputTokens: _asInt(usageMap['outputTokens']),
              totalTokens: _asInt(usageMap['totalTokens']),
              cachedInputTokens: _asInt(usageMap['cachedReadTokens']),
              reasoningOutputTokens: _asInt(usageMap['reasoningTokens']),
              modelContextWindow: ContextWindowCodec.positiveWindow(usageMap),
            );
            final apiDurationMs = _asInt(usageMap['apiDurationMs']);
            if (apiDurationMs != null && apiDurationMs >= 0) {
              duration = Duration(milliseconds: apiDurationMs);
            }
          }
          if (current == null) {
            ensureTurn(
              promptId: update['prompt_id']?.toString() ?? promptId,
              fallbackId: eventId,
              at: eventAt,
            );
          }
          closeTurn(
            status: _stopReasonToStatus(stop),
            usage: usage,
            duration: duration,
            at: eventAt,
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
    final kind = parseAgentToolKind(update['kind']?.toString());
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
    final title = buildAgentToolCallDisplayTitle(
      toolCallId: id,
      title: update['title']?.toString(),
      kind: kind,
      kindRaw: update['kind']?.toString(),
      locations: locations,
      rawInput: rawInput,
    );
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
    final nextTitleNonInformative = isNonInformativeAgentToolCallTitle(
      next.title,
      toolCallId: next.id,
    );
    final previousTitleNonInformative = isNonInformativeAgentToolCallTitle(
      previous.title,
      toolCallId: previous.id,
    );
    return AgentToolCall(
      id: next.id,
      title: nextTitleNonInformative && !previousTitleNonInformative
          ? previous.title
          : (next.title.isNotEmpty ? next.title : previous.title),
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
  _TurnBuilder({required this.id, this.model});

  String id;
  final List<AgentHistoryEntry> entries = <AgentHistoryEntry>[];
  final Map<String, int> _messageIndexById = <String, int>{};
  final Map<String, int> _toolIndexById = <String, int>{};
  String? _userPromptKey;
  int? _userMessageIndex;
  AgentHistoryTurnStatus status = AgentHistoryTurnStatus.completed;
  AgentTokenUsage? tokenUsage;
  String? errorMessage;
  DateTime? startedAt;
  DateTime? completedAt;
  Duration? duration;
  String? model;

  bool get hasContent => entries.isNotEmpty;

  bool acceptsUserPrompt(String? promptKey) {
    return promptKey != null && promptKey == _userPromptKey;
  }

  void noteUserPrompt(String? promptKey) {
    if (promptKey != null) {
      _userPromptKey ??= promptKey;
    }
  }

  void preferId(String preferred) {
    if (preferred.isNotEmpty) {
      id = preferred;
    }
  }

  /// 记录事件时间；首次出现作为 [startedAt]。
  void noteTime(DateTime? at) {
    if (at == null) {
      return;
    }
    startedAt ??= at;
  }

  /// 用流式 `_meta.turnStartMs` 校正回合真实开始时间（可早于首条 user chunk）。
  void noteTurnStartMs(Object? value) {
    final at = _dateTimeFromMs(value);
    if (at == null) {
      return;
    }
    if (startedAt == null || at.isBefore(startedAt!)) {
      startedAt = at;
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

  /// 合并同一次 Grok prompt 拆分出的文字块和本地图片块。
  void addOrMergeUserMessage({
    required String id,
    required String text,
    required List<String> localImagePaths,
    required Map<String, Object?> raw,
  }) {
    final existingIndex = _userMessageIndex;
    if (existingIndex != null) {
      final existing = entries[existingIndex] as AgentHistoryMessageEntry;
      final mergedPaths = <String>{
        ...existing.localImagePaths,
        ...localImagePaths,
      };
      entries[existingIndex] = AgentHistoryMessageEntry(
        id: existing.id,
        role: AgentMessageRole.user,
        text: _mergeUserText(existing.text, text),
        status: AgentMessageStatus.completed,
        localImagePaths: List<String>.unmodifiable(mergedPaths),
        raw: raw,
      );
      return;
    }

    _userMessageIndex = entries.length;
    addMessage(
      AgentHistoryMessageEntry(
        id: id,
        role: AgentMessageRole.user,
        text: text,
        status: AgentMessageStatus.completed,
        localImagePaths: List<String>.unmodifiable(localImagePaths),
        raw: raw,
      ),
    );
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
      startedAt: startedAt,
      completedAt: completedAt,
      duration: duration,
      model: model,
      tokenUsage: tokenUsage,
      // Grok turn_completed.usage 是本回合绝对用量，不是会话累计。
      tokenUsageIsSessionCumulative: false,
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

String? _firstNonEmpty(List<Object?> values) {
  for (final value in values) {
    final text = value?.toString().trim();
    if (text != null && text.isNotEmpty) {
      return text;
    }
  }
  return null;
}

String? _userPromptKey({
  required String? promptId,
  required Object? promptIndex,
  required String? messageId,
}) {
  if (promptId != null && promptId.isNotEmpty) {
    return 'id:$promptId';
  }
  if (promptIndex != null && promptIndex.toString().isNotEmpty) {
    return 'index:$promptIndex';
  }
  if (messageId != null && messageId.isNotEmpty) {
    return 'message:$messageId';
  }
  return null;
}

String _mergeUserText(String previous, String next) {
  if (next.isEmpty || previous == next || previous.endsWith(next)) {
    return previous;
  }
  if (previous.isEmpty || next.startsWith(previous)) {
    return next;
  }
  return '$previous\n$next';
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

/// 毫秒时间戳 → UTC DateTime。
DateTime? _dateTimeFromMs(Object? value) {
  final ms = _asInt(value);
  if (ms == null || ms <= 0) {
    return null;
  }
  return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
}

/// Grok updates.jsonl 行级 `timestamp`：常见为 Unix 秒，偶发毫秒。
DateTime? _dateTimeFromTimestamp(Object? value) {
  final raw = _asInt(value);
  if (raw == null || raw <= 0) {
    return null;
  }
  // 10 位量级按秒，13 位按毫秒。
  final ms = raw.abs() < 1000000000000
      ? raw * Duration.millisecondsPerSecond
      : raw;
  return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
}

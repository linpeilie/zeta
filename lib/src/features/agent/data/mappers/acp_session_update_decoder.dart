import 'package:zeta/src/features/agent/data/mappers/context_window_codec.dart';

/// 无状态解析标准 ACP `session/update` payload。
///
/// decoder 只识别协议字段，不保存 turn、segment 或去重状态，也不会生成
/// message/reasoning entryId。Provider adapter 负责后续身份与叙事边界决策。
final class AcpSessionUpdateDecoder {
  const AcpSessionUpdateDecoder();

  /// 将通知 envelope 或 `params` 对象解码为 typed update。
  ///
  /// 未知 kind、损坏对象或缺少必需字段时返回 [AcpUnknownUpdate]，不会抛出
  /// 未处理异常。未知字段保留在 [AcpSessionUpdate.raw] 中供适配层诊断。
  AcpSessionUpdate decode(Object? value) {
    final envelope = _stringKeyedMap(value);
    if (envelope == null) {
      return const AcpUnknownUpdate(
        kind: 'session/update:invalid',
        diagnostic: 'params_not_object',
      );
    }

    // 同时接受完整 JSON-RPC notification 和 provider 已拆出的 params。
    final params = _stringKeyedMap(envelope['params']) ?? envelope;
    final update = _stringKeyedMap(params['update']);
    final sessionId = _nonEmptyString(params['sessionId']);
    if (update == null) {
      return AcpUnknownUpdate(
        sessionId: sessionId,
        kind: 'session/update:missing',
        raw: _frozenMap(params),
        diagnostic: 'update_not_object',
      );
    }

    final raw = _frozenMap(update);
    final kind = update['sessionUpdate']?.toString() ?? '';
    final updateMeta = _stringKeyedMap(update['_meta']);
    final paramsMeta = _stringKeyedMap(params['_meta']);
    final promptId =
        _nonEmptyString(updateMeta?['promptId']) ??
        _nonEmptyString(paramsMeta?['promptId']) ??
        _nonEmptyString(update['promptId']) ??
        _nonEmptyString(update['prompt_id']);
    final eventId =
        _nonEmptyString(updateMeta?['eventId']) ??
        _nonEmptyString(paramsMeta?['eventId']);

    AcpUnknownUpdate invalid(String diagnostic) {
      return AcpUnknownUpdate(
        sessionId: sessionId,
        kind: kind,
        promptId: promptId,
        eventId: eventId,
        raw: raw,
        diagnostic: diagnostic,
      );
    }

    if (sessionId == null) {
      return invalid('missing_session_id');
    }

    switch (kind) {
      case 'user_message_chunk':
        if (!update.containsKey('content') || update['content'] == null) {
          return invalid('missing_content');
        }
        return AcpUserMessageChunk(
          sessionId: sessionId,
          content: update['content'],
          sourceMessageId: _nonEmptyString(update['messageId']),
          hideFromScrollback: updateMeta?['hideFromScrollback'] == true,
          promptId: promptId,
          eventId: eventId,
          raw: raw,
        );
      case 'agent_message_chunk':
        if (!update.containsKey('content') || update['content'] == null) {
          return invalid('missing_content');
        }
        return AcpAgentMessageChunk(
          sessionId: sessionId,
          content: update['content'],
          sourceMessageId: _nonEmptyString(update['messageId']),
          promptId: promptId,
          eventId: eventId,
          raw: raw,
        );
      case 'agent_thought_chunk':
        if (!update.containsKey('content') || update['content'] == null) {
          return invalid('missing_content');
        }
        return AcpAgentThoughtChunk(
          sessionId: sessionId,
          content: update['content'],
          sourceItemId:
              _nonEmptyString(update['itemId']) ??
              _nonEmptyString(update['messageId']),
          promptId: promptId,
          eventId: eventId,
          raw: raw,
        );
      case 'tool_call':
      case 'tool_call_update':
        final toolCallId = _nonEmptyString(update['toolCallId']);
        if (toolCallId == null) {
          return invalid('missing_tool_call_id');
        }
        return AcpToolCallUpdate(
          sessionId: sessionId,
          kind: kind,
          toolCallId: toolCallId,
          title: _optionalString(update['title']),
          toolKind: _optionalString(update['kind']),
          status: _optionalString(update['status']),
          content: update['content'],
          locations: _locations(update['locations']),
          rawInput: _frozenMap(_stringKeyedMap(update['rawInput'])),
          rawOutput: _frozenMap(_stringKeyedMap(update['rawOutput'])),
          promptId: promptId,
          eventId: eventId,
          raw: raw,
        );
      case 'plan':
        return AcpPlanUpdate(
          sessionId: sessionId,
          entries: _planEntries(update['entries']),
          promptId: promptId,
          eventId: eventId,
          raw: raw,
        );
      case 'usage_update':
        final used = _intValue(update['used']);
        if (used == null) {
          return invalid('missing_usage');
        }
        return AcpUsageUpdate(
          sessionId: sessionId,
          used: used,
          modelContextWindow: ContextWindowCodec.positiveWindow(update),
          promptId: promptId,
          eventId: eventId,
          raw: raw,
        );
      case 'turn_completed':
        return AcpTurnCompletedUpdate(
          sessionId: sessionId,
          stopReason:
              _optionalString(update['stop_reason']) ??
              _optionalString(update['stopReason']) ??
              'end_turn',
          usage: _turnUsage(update['usage']),
          promptId: promptId,
          eventId: eventId,
          raw: raw,
        );
      default:
        return invalid(kind.isEmpty ? 'missing_update_kind' : 'unknown_kind');
    }
  }

  static List<String> _locations(Object? value) {
    if (value is! List) {
      return const <String>[];
    }
    final locations = <String>[];
    for (final item in value) {
      final map = _stringKeyedMap(item);
      final path = map == null
          ? _nonEmptyString(item)
          : _nonEmptyString(map['path']);
      if (path != null) {
        locations.add(path);
      }
    }
    return List<String>.unmodifiable(locations);
  }

  static List<AcpPlanEntry> _planEntries(Object? value) {
    if (value is! List) {
      return const <AcpPlanEntry>[];
    }
    final entries = <AcpPlanEntry>[];
    for (final item in value) {
      final map = _stringKeyedMap(item);
      if (map == null) {
        continue;
      }
      final content = _optionalString(map['content']);
      if (content == null || content.isEmpty) {
        continue;
      }
      entries.add(
        AcpPlanEntry(
          content: content,
          status: _optionalString(map['status']),
          priority: _optionalString(map['priority']),
          raw: _frozenMap(map),
        ),
      );
    }
    return List<AcpPlanEntry>.unmodifiable(entries);
  }

  static AcpTurnUsage? _turnUsage(Object? value) {
    final map = _stringKeyedMap(value);
    if (map == null) {
      return null;
    }
    return AcpTurnUsage(
      inputTokens: _intValue(map['inputTokens'] ?? map['input_tokens']),
      outputTokens: _intValue(map['outputTokens'] ?? map['output_tokens']),
      totalTokens: _intValue(map['totalTokens'] ?? map['total_tokens']),
      cachedReadTokens: _intValue(
        map['cachedReadTokens'] ?? map['cached_read_tokens'],
      ),
      reasoningTokens: _intValue(
        map['reasoningTokens'] ?? map['reasoning_tokens'],
      ),
      modelContextWindow: ContextWindowCodec.positiveWindow(map),
      apiDurationMs: _intValue(map['apiDurationMs'] ?? map['api_duration_ms']),
      raw: _frozenMap(map),
    );
  }
}

/// decoder 输出的标准 ACP session update。
sealed class AcpSessionUpdate {
  const AcpSessionUpdate({
    required this.sessionId,
    required this.kind,
    this.promptId,
    this.eventId,
    this.raw = const <String, Object?>{},
  });

  /// Provider 会话身份；损坏或未知输入中可能为空。
  final String? sessionId;

  /// 原始 `sessionUpdate` kind。
  final String kind;

  /// Provider prompt/turn 关联身份；不等同于规范化 entryId。
  final String? promptId;

  /// Provider 原始事件身份；只用于关联、去重或诊断。
  final String? eventId;

  /// 原始 update 字段；未知字段会保留。
  final Map<String, Object?> raw;
}

/// 用户消息 content chunk。
final class AcpUserMessageChunk extends AcpSessionUpdate {
  const AcpUserMessageChunk({
    required String sessionId,
    required this.content,
    this.sourceMessageId,
    this.hideFromScrollback = false,
    super.promptId,
    super.eventId,
    super.raw,
  }) : super(sessionId: sessionId, kind: 'user_message_chunk');

  final Object? content;
  final String? sourceMessageId;

  /// Provider 标记为仅供模型消费、不应进入客户端滚动区的用户回显。
  final bool hideFromScrollback;
}

/// Agent 正文 content chunk。
final class AcpAgentMessageChunk extends AcpSessionUpdate {
  const AcpAgentMessageChunk({
    required String sessionId,
    required this.content,
    this.sourceMessageId,
    super.promptId,
    super.eventId,
    super.raw,
  }) : super(sessionId: sessionId, kind: 'agent_message_chunk');

  final Object? content;
  final String? sourceMessageId;
}

/// Agent reasoning/thought content chunk。
final class AcpAgentThoughtChunk extends AcpSessionUpdate {
  const AcpAgentThoughtChunk({
    required String sessionId,
    required this.content,
    this.sourceItemId,
    super.promptId,
    super.eventId,
    super.raw,
  }) : super(sessionId: sessionId, kind: 'agent_thought_chunk');

  final Object? content;
  final String? sourceItemId;
}

/// Tool start 或 update；[kind] 保留两者的原始差异。
final class AcpToolCallUpdate extends AcpSessionUpdate {
  const AcpToolCallUpdate({
    required String sessionId,
    required super.kind,
    required this.toolCallId,
    this.title,
    this.toolKind,
    this.status,
    this.content,
    this.locations = const <String>[],
    this.rawInput = const <String, Object?>{},
    this.rawOutput = const <String, Object?>{},
    super.promptId,
    super.eventId,
    super.raw,
  }) : assert(kind == 'tool_call' || kind == 'tool_call_update'),
       super(sessionId: sessionId);

  final String toolCallId;
  final String? title;
  final String? toolKind;
  final String? status;
  final Object? content;
  final List<String> locations;
  final Map<String, Object?> rawInput;
  final Map<String, Object?> rawOutput;

  bool get isUpdate => kind == 'tool_call_update';
}

/// ACP plan 条目。
final class AcpPlanEntry {
  const AcpPlanEntry({
    required this.content,
    this.status,
    this.priority,
    this.raw = const <String, Object?>{},
  });

  final String content;
  final String? status;
  final String? priority;
  final Map<String, Object?> raw;
}

/// ACP plan update。
final class AcpPlanUpdate extends AcpSessionUpdate {
  const AcpPlanUpdate({
    required String sessionId,
    required this.entries,
    super.promptId,
    super.eventId,
    super.raw,
  }) : super(sessionId: sessionId, kind: 'plan');

  final List<AcpPlanEntry> entries;
}

/// 会话级上下文用量快照。
final class AcpUsageUpdate extends AcpSessionUpdate {
  const AcpUsageUpdate({
    required String sessionId,
    required this.used,
    this.modelContextWindow,
    super.promptId,
    super.eventId,
    super.raw,
  }) : super(sessionId: sessionId, kind: 'usage_update');

  final int used;
  final int? modelContextWindow;
}

/// ACP turn terminal usage。
final class AcpTurnUsage {
  const AcpTurnUsage({
    this.inputTokens,
    this.outputTokens,
    this.totalTokens,
    this.cachedReadTokens,
    this.reasoningTokens,
    this.modelContextWindow,
    this.apiDurationMs,
    this.raw = const <String, Object?>{},
  });

  final int? inputTokens;
  final int? outputTokens;
  final int? totalTokens;
  final int? cachedReadTokens;
  final int? reasoningTokens;
  final int? modelContextWindow;
  final int? apiDurationMs;
  final Map<String, Object?> raw;
}

/// ACP turn completed 扩展。
final class AcpTurnCompletedUpdate extends AcpSessionUpdate {
  const AcpTurnCompletedUpdate({
    required String sessionId,
    required this.stopReason,
    this.usage,
    super.promptId,
    super.eventId,
    super.raw,
  }) : super(sessionId: sessionId, kind: 'turn_completed');

  final String stopReason;
  final AcpTurnUsage? usage;
}

/// 未知、暂不投影或损坏的 ACP update。
final class AcpUnknownUpdate extends AcpSessionUpdate {
  const AcpUnknownUpdate({
    super.sessionId,
    required super.kind,
    super.promptId,
    super.eventId,
    super.raw,
    this.diagnostic,
  });

  /// 不包含正文的稳定诊断原因。
  final String? diagnostic;
}

Map<String, Object?>? _stringKeyedMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  return <String, Object?>{
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}

Map<String, Object?> _frozenMap(Map<String, Object?>? value) {
  if (value == null || value.isEmpty) {
    return const <String, Object?>{};
  }
  return Map<String, Object?>.unmodifiable(value);
}

String? _nonEmptyString(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

String? _optionalString(Object? value) => value?.toString();

int? _intValue(Object? value) {
  return switch (value) {
    int number => number,
    num number => number.toInt(),
    String text => int.tryParse(text.trim()),
    _ => null,
  };
}

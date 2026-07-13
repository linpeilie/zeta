import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// Grok ACP `session/update` 到领域事件的映射结果。
class GrokAcpMappedUpdate {
  const GrokAcpMappedUpdate({
    this.events = const <AgentEvent>[],
    this.unmatchedKind,
  });

  final List<AgentEvent> events;
  final String? unmatchedKind;
}

/// 将 ACP `session/update` 与部分 `_x.ai/*` 通知映射为 [AgentEvent]。
class GrokAcpNotificationMapper {
  const GrokAcpNotificationMapper();

  /// 映射标准 `session/update` 通知。
  GrokAcpMappedUpdate mapSessionUpdate({
    required Map<String, Object?> params,
    required String? runningTurnId,
  }) {
    final sessionId = params['sessionId']?.toString();
    final updateRaw = params['update'];
    if (updateRaw is! Map) {
      return const GrokAcpMappedUpdate(unmatchedKind: 'session/update:missing');
    }
    final update = updateRaw.map(
      (key, value) => MapEntry(key.toString(), value as Object?),
    );
    final kind = update['sessionUpdate']?.toString() ?? '';
    final turnId = runningTurnId;

    switch (kind) {
      case 'agent_message_chunk':
      case 'user_message_chunk':
        final text = _contentText(update['content']);
        if (text == null || text.isEmpty) {
          return GrokAcpMappedUpdate(unmatchedKind: kind);
        }
        final role = kind == 'user_message_chunk'
            ? AgentMessageRole.user
            : AgentMessageRole.agent;
        final messageId =
            update['messageId']?.toString() ??
            'acp-$kind-${sessionId ?? 'unknown'}';
        // Grok ACP 无 Codex final_answer 语义；不设 response phase，
        // 避免 UI 走「完成汇总」卡片样式。
        return GrokAcpMappedUpdate(
          events: <AgentEvent>[
            AgentMessageDeltaEvent(
              messageId: messageId,
              delta: text,
              role: role,
              status: AgentMessageStatus.streaming,
              sessionId: sessionId,
              turnId: turnId,
              raw: update,
            ),
          ],
        );

      case 'agent_thought_chunk':
        final text = _contentText(update['content']) ?? '';
        final itemId =
            update['messageId']?.toString() ??
            'acp-thought-${sessionId ?? 'unknown'}';
        return GrokAcpMappedUpdate(
          events: <AgentEvent>[
            AgentReasoningDeltaEvent(
              itemId: itemId,
              kind: AgentReasoningDeltaKind.text,
              delta: text,
              sessionId: sessionId,
              turnId: turnId,
              raw: update,
            ),
          ],
        );

      case 'tool_call':
      case 'tool_call_update':
        final toolCall = _mapToolCall(
          update: update,
          sessionId: sessionId,
          turnId: turnId,
        );
        if (toolCall == null) {
          return GrokAcpMappedUpdate(unmatchedKind: kind);
        }
        return GrokAcpMappedUpdate(
          events: <AgentEvent>[AgentToolCallEvent(toolCall)],
        );

      case 'plan':
        final entries = _mapPlanEntries(update['entries']);
        return GrokAcpMappedUpdate(
          events: <AgentEvent>[
            AgentPlanUpdatedEvent(
              entries: entries,
              sessionId: sessionId,
              turnId: turnId,
            ),
          ],
        );

      case 'usage_update':
        final used = _asInt(update['used']);
        if (used == null) {
          return GrokAcpMappedUpdate(unmatchedKind: kind);
        }
        return GrokAcpMappedUpdate(
          events: <AgentEvent>[
            AgentTokenUsageEvent(
              sessionId: sessionId,
              turnId: turnId,
              tokenUsage: AgentTokenUsage(
                totalTokens: used,
                inputTokens: used,
                outputTokens: 0,
              ),
              raw: update,
            ),
          ],
        );

      // 命令列表、模式切换等暂不驱动主时间线。
      case 'available_commands_update':
      case 'current_mode_update':
      case 'config_option_update':
      case 'session_info_update':
        return GrokAcpMappedUpdate(unmatchedKind: kind);

      default:
        return GrokAcpMappedUpdate(unmatchedKind: kind);
    }
  }

  /// 映射 `_x.ai/session/update` 中与回合完成相关的扩展。
  GrokAcpMappedUpdate mapXaiSessionUpdate({
    required Map<String, Object?> params,
    required String? runningTurnId,
  }) {
    final sessionId = params['sessionId']?.toString();
    final updateRaw = params['update'];
    if (updateRaw is! Map) {
      return const GrokAcpMappedUpdate(
        unmatchedKind: '_x.ai/session/update:missing',
      );
    }
    final update = updateRaw.map(
      (key, value) => MapEntry(key.toString(), value as Object?),
    );
    final kind = update['sessionUpdate']?.toString() ?? '';
    if (kind != 'turn_completed') {
      return GrokAcpMappedUpdate(unmatchedKind: kind);
    }

    final turnId =
        runningTurnId ??
        update['prompt_id']?.toString() ??
        update['promptId']?.toString();
    if (sessionId == null || turnId == null) {
      return GrokAcpMappedUpdate(unmatchedKind: kind);
    }

    final stopReason =
        update['stop_reason']?.toString() ??
        update['stopReason']?.toString() ??
        'end_turn';
    final status = _stopReasonToStatus(stopReason);
    final events = <AgentEvent>[
      AgentTurnCompletedEvent(
        sessionId: sessionId,
        turnId: turnId,
        status: status,
        errorMessage: status == AgentHistoryTurnStatus.failed
            ? stopReason
            : null,
        raw: update,
      ),
    ];

    final usage = update['usage'];
    if (usage is Map) {
      final usageMap = usage.map(
        (key, value) => MapEntry(key.toString(), value as Object?),
      );
      final tokenUsage = AgentTokenUsage(
        inputTokens: _asInt(usageMap['inputTokens']) ?? 0,
        outputTokens: _asInt(usageMap['outputTokens']) ?? 0,
        totalTokens: _asInt(usageMap['totalTokens']),
        cachedInputTokens: _asInt(usageMap['cachedReadTokens']),
        reasoningOutputTokens: _asInt(usageMap['reasoningTokens']),
      );
      events.add(
        AgentTokenUsageEvent(
          sessionId: sessionId,
          turnId: turnId,
          tokenUsage: tokenUsage,
          raw: usageMap,
        ),
      );
    }

    return GrokAcpMappedUpdate(events: events);
  }

  AgentToolCall? _mapToolCall({
    required Map<String, Object?> update,
    required String? sessionId,
    required String? turnId,
  }) {
    final id = update['toolCallId']?.toString();
    if (id == null || id.isEmpty) {
      return null;
    }
    final title = update['title']?.toString() ?? id;
    final kind = _mapToolKind(update['kind']?.toString());
    final status = _mapToolStatus(update['status']?.toString());
    final content = _toolContentText(update['content']);
    final locations = <String>[];
    final rawLocations = update['locations'];
    if (rawLocations is List) {
      for (final item in rawLocations) {
        if (item is Map) {
          final path = item['path']?.toString();
          if (path != null && path.isNotEmpty) {
            locations.add(path);
          }
        } else if (item is String && item.isNotEmpty) {
          locations.add(item);
        }
      }
    }

    final rawInput = update['rawInput'] is Map
        ? (update['rawInput'] as Map).map(
            (key, value) => MapEntry(key.toString(), value as Object?),
          )
        : const <String, Object?>{};
    final rawOutput = update['rawOutput'] is Map
        ? (update['rawOutput'] as Map).map(
            (key, value) => MapEntry(key.toString(), value as Object?),
          )
        : const <String, Object?>{};

    return AgentToolCall(
      id: id,
      title: title,
      kind: kind,
      status: status,
      content: content,
      locations: List<String>.unmodifiable(locations),
      sessionId: sessionId,
      turnId: turnId,
      rawInput: rawInput,
      rawOutput: rawOutput,
      raw: update,
    );
  }

  List<AgentPlanEntry> _mapPlanEntries(Object? value) {
    if (value is! List) {
      return const <AgentPlanEntry>[];
    }
    final entries = <AgentPlanEntry>[];
    for (final item in value) {
      if (item is! Map) {
        continue;
      }
      final map = item.map(
        (key, value) => MapEntry(key.toString(), value as Object?),
      );
      final content = map['content']?.toString() ?? '';
      if (content.isEmpty) {
        continue;
      }
      entries.add(
        AgentPlanEntry(
          content: content,
          status: map['status']?.toString(),
          priority: map['priority']?.toString(),
        ),
      );
    }
    return List<AgentPlanEntry>.unmodifiable(entries);
  }

  AgentToolKind _mapToolKind(String? kind) {
    return switch (kind) {
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
  }

  AgentToolStatus _mapToolStatus(String? status) {
    return switch (status) {
      'pending' => AgentToolStatus.pending,
      'in_progress' => AgentToolStatus.inProgress,
      'completed' => AgentToolStatus.completed,
      'failed' => AgentToolStatus.failed,
      'cancelled' => AgentToolStatus.cancelled,
      _ => AgentToolStatus.pending,
    };
  }

  AgentHistoryTurnStatus _stopReasonToStatus(String stopReason) {
    final normalized = stopReason.toLowerCase();
    if (normalized.contains('cancel')) {
      return AgentHistoryTurnStatus.interrupted;
    }
    if (normalized.contains('refus') ||
        normalized.contains('error') ||
        normalized.contains('fail') ||
        normalized.contains('max_token') ||
        normalized.contains('max_turn')) {
      return AgentHistoryTurnStatus.failed;
    }
    return AgentHistoryTurnStatus.completed;
  }

  String? _contentText(Object? content) {
    if (content is String) {
      return content;
    }
    if (content is Map) {
      final map = content.map(
        (key, value) => MapEntry(key.toString(), value as Object?),
      );
      if (map['type']?.toString() == 'text') {
        return map['text']?.toString();
      }
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
}

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
      case 'user_message_chunk':
        // 直播时间线已由 ViewModel 乐观插入用户消息；再映射会重复一条。
        // 历史回放走本地 updates.jsonl 解析，不经过此 live mapper。
        return const GrokAcpMappedUpdate(unmatchedKind: 'user_message_chunk');

      case 'agent_message_chunk':
        final text = _contentText(update['content']);
        if (text == null || text.isEmpty) {
          return GrokAcpMappedUpdate(unmatchedKind: kind);
        }
        // Grok 流式 chunk 常无 messageId；按 turn/prompt 聚合，避免整会话共用
        // 一个 id 导致后续 turn 文本追加到历史气泡。
        final messageId = _stableStreamMessageId(
          update: update,
          params: params,
          kind: kind,
          sessionId: sessionId,
          turnId: turnId,
        );
        // Grok ACP 无 Codex final_answer 语义；不设 response phase，
        // 避免 UI 走「完成汇总」卡片样式。
        return GrokAcpMappedUpdate(
          events: <AgentEvent>[
            AgentMessageDeltaEvent(
              messageId: messageId,
              delta: text,
              role: AgentMessageRole.agent,
              status: AgentMessageStatus.streaming,
              sessionId: sessionId,
              turnId: turnId,
              raw: update,
            ),
          ],
        );

      case 'agent_thought_chunk':
        final text = _contentText(update['content']) ?? '';
        final itemId = _stableStreamMessageId(
          update: update,
          params: params,
          kind: 'agent_thought_chunk',
          sessionId: sessionId,
          turnId: turnId,
        );
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
        // ACP 上下文占用进度：按会话级累计处理，供 header/composer 使用。
        final used = _asInt(update['used']);
        if (used == null) {
          return GrokAcpMappedUpdate(unmatchedKind: kind);
        }
        return GrokAcpMappedUpdate(
          events: <AgentEvent>[
            AgentTokenUsageEvent(
              sessionId: sessionId,
              turnId: turnId,
              isSessionCumulative: true,
              tokenUsage: AgentTokenUsage(
                totalTokens: used,
                inputTokens: used,
                outputTokens: 0,
              ),
              raw: update,
            ),
          ],
        );

      case 'turn_completed':
        // 标准 session/update 也会带 turn_completed（不仅 _x.ai 扩展）。
        return _mapTurnCompleted(
          params: params,
          update: update,
          runningTurnId: turnId,
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
    return _mapTurnCompleted(
      params: params,
      update: update,
      runningTurnId: runningTurnId,
    );
  }

  GrokAcpMappedUpdate _mapTurnCompleted({
    required Map<String, Object?> params,
    required Map<String, Object?> update,
    required String? runningTurnId,
  }) {
    final sessionId = params['sessionId']?.toString();
    final updateMeta = _asStringKeyedMap(update['_meta']);
    final paramsMeta = _asStringKeyedMap(params['_meta']);
    // 优先本地 running turn id（与 pending/live 分组一致）；否则用 Grok prompt_id。
    final turnId =
        runningTurnId ??
        updateMeta?['promptId']?.toString() ??
        paramsMeta?['promptId']?.toString() ??
        update['prompt_id']?.toString() ??
        update['promptId']?.toString();
    if (sessionId == null || turnId == null) {
      return const GrokAcpMappedUpdate(unmatchedKind: 'turn_completed');
    }

    final stopReason =
        update['stop_reason']?.toString() ??
        update['stopReason']?.toString() ??
        'end_turn';
    final status = _stopReasonToStatus(stopReason);

    // Grok usage 是本回合绝对用量（非会话累计），并常带 apiDurationMs。
    Duration? duration;
    AgentTokenUsage? tokenUsage;
    Map<String, Object?>? usageMap;
    final usage = update['usage'];
    if (usage is Map) {
      usageMap = usage.map(
        (key, value) => MapEntry(key.toString(), value as Object?),
      );
      final apiDurationMs = _asInt(usageMap['apiDurationMs']);
      if (apiDurationMs != null && apiDurationMs >= 0) {
        duration = Duration(milliseconds: apiDurationMs);
      }
      tokenUsage = AgentTokenUsage(
        inputTokens: _asInt(usageMap['inputTokens']) ?? 0,
        outputTokens: _asInt(usageMap['outputTokens']) ?? 0,
        totalTokens: _asInt(usageMap['totalTokens']),
        cachedInputTokens: _asInt(usageMap['cachedReadTokens']),
        reasoningOutputTokens: _asInt(usageMap['reasoningTokens']),
      );
    }

    // 先发 usage 再 complete，确保 complete 收尾时 turn 上已有 token（若 UI 只 flush 一次）。
    final events = <AgentEvent>[
      if (tokenUsage != null)
        AgentTokenUsageEvent(
          sessionId: sessionId,
          turnId: turnId,
          isSessionCumulative: false,
          tokenUsage: tokenUsage,
          raw: usageMap ?? const <String, Object?>{},
        ),
      AgentTurnCompletedEvent(
        sessionId: sessionId,
        turnId: turnId,
        status: status,
        duration: duration,
        errorMessage: status == AgentHistoryTurnStatus.failed
            ? stopReason
            : null,
        raw: update,
      ),
    ];

    return GrokAcpMappedUpdate(events: events);
  }

  /// 为无官方 messageId 的流式 chunk 生成按 turn 稳定的聚合 id。
  ///
  /// 优先 `messageId` → `promptId` → `runningTurnId` → session 级回退。
  /// 同 turn 内的 chunk 共用 id 以便 delta 拼接；跨 turn 必须不同。
  String _stableStreamMessageId({
    required Map<String, Object?> update,
    required Map<String, Object?> params,
    required String kind,
    required String? sessionId,
    required String? turnId,
  }) {
    final explicit = update['messageId']?.toString();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }
    final updateMeta = _asStringKeyedMap(update['_meta']);
    final paramsMeta = _asStringKeyedMap(params['_meta']);
    final promptId =
        updateMeta?['promptId']?.toString() ??
        paramsMeta?['promptId']?.toString() ??
        update['promptId']?.toString() ??
        update['prompt_id']?.toString();
    final scope = promptId ?? turnId ?? sessionId ?? 'unknown';
    return 'acp-$kind-$scope';
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
    // Grok 偶发 PascalCase（Read/Execute）；统一小写再匹配。
    final normalized = kind?.trim().toLowerCase();
    return switch (normalized) {
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
    // Grok 工具状态常为 Completed/Pending/InProgress 等 PascalCase。
    final normalized = status
        ?.trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
    return switch (normalized) {
      null || '' || 'pending' => AgentToolStatus.pending,
      'inprogress' ||
      'in_progress' ||
      'running' ||
      'started' => AgentToolStatus.inProgress,
      'completed' ||
      'complete' ||
      'success' ||
      'succeeded' => AgentToolStatus.completed,
      'failed' || 'error' || 'errored' => AgentToolStatus.failed,
      'cancelled' || 'canceled' => AgentToolStatus.cancelled,
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

  Map<String, Object?>? _asStringKeyedMap(Object? value) {
    if (value is! Map) {
      return null;
    }
    return value.map((key, item) => MapEntry(key.toString(), item as Object?));
  }
}

import 'dart:convert';

import 'package:zeta_agent_providers/src/datasources/local_history/grok_user_content_parser.dart';
import 'package:zeta_agent_providers/src/mappers/acp_session_update_decoder.dart';
import 'package:zeta_agent_providers/src/mappers/grok_error_normalizer.dart';
import 'package:zeta_agent_providers/src/mappers/grok_session_update_mapper.dart';
import 'package:zeta_agent_providers/src/mappers/grok_stream_identity.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 从 Grok `updates.jsonl` 重建多回合历史快照。
///
/// 每次 [parse] 都创建独立的 Grok mapper/reducer。History 与 live 只复用相同
/// boundary 算法，不共享 current segment、seen event/tool 或 terminal 状态。
class GrokUpdatesHistoryParser {
  const GrokUpdatesHistoryParser({
    this.textCatalog = const FallbackAgentUiTextCatalog(),
  });

  final AgentUiTextCatalog textCatalog;

  /// 解析完整 JSONL 文本，不修改或重写来源文件。
  AgentThreadHistorySnapshot parse({
    required String threadId,
    required String content,
    String? sourceLabel,
    String? sessionPath,
  }) {
    final turns = <_TurnBuilder>[];
    _TurnBuilder? current;
    String? currentModelId;

    // History reducer 必须是本次 parse 私有实例；epoch 只用于状态隔离，
    // canonical 对比不要求它与 live 相同。
    final mapper = GrokSessionUpdateMapper(textCatalog: textCatalog);
    const runtimeScope = AgentRuntimeScope(
      runtimeId: 'grok-history-parser',
      connectionEpoch: 0,
    );

    void closeTurn({
      AgentHistoryTurnStatus? status,
      Duration? duration,
      DateTime? at,
      String? errorMessage,
    }) {
      final turn = current;
      if (turn == null) {
        return;
      }
      if (status != null) {
        turn.status = status;
      }
      turn.noteTime(at);
      turn.completedAt ??= at;
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
      if (!turn.identityTerminal) {
        mapper.invalidateTurn(
          runtimeScope: runtimeScope,
          sessionId: turn.sessionId,
          runningTurnId: turn.id,
          promptId: turn.stablePromptId,
          reason: GrokIdentityInvalidationReason.newTurn,
        );
      }
      current = null;
    }

    void ensureTurn({
      required String sessionId,
      String? promptId,
      DateTime? at,
    }) {
      final active = current;
      if (active != null &&
          (active.sessionId != sessionId ||
              active.hasDifferentStablePrompt(promptId))) {
        closeTurn(at: at);
      }
      if (current != null) {
        current!
          ..noteTime(at)
          ..notePromptId(promptId);
        return;
      }

      final ordinal = turns.length + 1;
      final turnId = promptId ?? _historyTurnId(threadId, ordinal);
      final next = _TurnBuilder(
        id: turnId,
        sessionId: sessionId,
        stablePromptId: promptId,
        modelId: currentModelId,
      )..noteTime(at);
      turns.add(next);
      current = next;
      mapper.beginTurn(
        runtimeScope: runtimeScope,
        sessionId: sessionId,
        turnId: turnId,
      );
    }

    try {
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
        final sourceUpdate =
            _asMap(params['update']) ?? const <String, Object?>{};
        final update =
            sourceUpdate['sessionUpdate'] == null &&
                method.contains('turn_completed')
            ? <String, Object?>{
                ...sourceUpdate,
                'sessionUpdate': 'turn_completed',
              }
            : sourceUpdate;
        final normalizedParams = identical(update, sourceUpdate)
            ? params
            : <String, Object?>{...params, 'update': update};
        final updateMeta = _asMap(update['_meta']) ?? const <String, Object?>{};
        final paramsMeta = _asMap(params['_meta']) ?? const <String, Object?>{};

        // 事件时刻优先 agentTimestampMs；行级 timestamp 通常为 Unix 秒。
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
          current?.modelId ??= reportedModelId;
        }

        final decoded = mapper.decoder.decode(normalizedParams);
        final sessionId = decoded.sessionId ?? threadId;
        final promptId = decoded.promptId;

        if (decoded case final AcpUserMessageChunk user) {
          final userPromptKey = _userPromptKey(
            promptId: promptId,
            promptIndex:
                updateMeta['promptIndex'] ??
                paramsMeta['promptIndex'] ??
                update['prompt_index'] ??
                update['promptIndex'],
            messageId: user.sourceMessageId,
          );
          if (current != null &&
              current!.hasContent &&
              !current!.acceptsUserPrompt(userPromptKey)) {
            closeTurn(at: eventAt);
          }
          ensureTurn(sessionId: sessionId, promptId: promptId, at: eventAt);
          current!.noteUserPrompt(userPromptKey);
          if (user.hideFromScrollback) {
            // Grok 自动唤醒会把内部 system-reminder 回显写入历史；保留该
            // turn 的后续 Agent 内容，但不要把内部上下文冒充真实用户输入。
            continue;
          }
          final parsed = parseGrokUserContent(_contentText(user.content) ?? '');
          if (parsed.text.isNotEmpty || parsed.localImagePaths.isNotEmpty) {
            current!.addOrMergeUserMessage(
              sourceMessageId: user.sourceMessageId,
              text: parsed.text,
              localImagePaths: parsed.localImagePaths,
              raw: AgentProviderRawPayload.wrap(user.raw),
            );
          }
          continue;
        }

        if (update['sessionUpdate'] == 'retry_state') {
          ensureTurn(sessionId: sessionId, promptId: promptId, at: eventAt);
          current!.noteRetryState(update);
          continue;
        }

        if (decoded is AcpUnknownUpdate) {
          continue;
        }

        ensureTurn(sessionId: sessionId, promptId: promptId, at: eventAt);
        current?.noteTurnStartMs(updateMeta['turnStartMs']);
        final mapped = mapper.mapSessionUpdate(
          params: normalizedParams,
          runningTurnId: current!.id,
          runtimeScope: runtimeScope,
          terminalSource: method.startsWith('_x.ai/')
              ? GrokTerminalSource.xaiNotification
              : GrokTerminalSource.standardNotification,
        );

        AgentTurnCompletedEvent? terminal;
        for (final event in mapped.events) {
          switch (event) {
            case AgentMessageDeltaEvent():
              current!.addOrMergeAgentMessage(
                id: event.messageId,
                sourceMessageId: event.sourceMessageId,
                text: event.delta,
                raw: event.raw,
              );
            case AgentReasoningDeltaEvent():
              current!.addOrMergeThought(
                id: event.itemId,
                sourceItemId: event.sourceItemId,
                text: event.delta,
                raw: event.raw,
              );
            case AgentToolCallEvent():
              current!.upsertTool(event.toolCall);
            case AgentPlanUpdatedEvent():
              current!.addPlan(
                event.entries,
                raw: AgentProviderRawPayload.wrap(update),
              );
            case AgentTokenUsageEvent():
              // Grok turn_completed usage 是本回合绝对用量；usage_update 则是
              // session 累计进度，不能冒充当前 turn 用量。
              if (!event.isSessionCumulative) {
                current!.tokenUsage = event.tokenUsage;
              }
            case AgentTurnCompletedEvent():
              terminal = event;
            default:
              break;
          }
        }

        if (terminal != null) {
          current!.identityTerminal = true;
          closeTurn(
            status: terminal.status,
            duration: terminal.duration,
            at: eventAt,
            errorMessage: terminal.errorMessage,
          );
        }
      }

      if (current != null) {
        closeTurn();
      }

      final built = turns
          .where((turn) => turn.hasContent)
          .map((turn) => turn.build())
          .toList(growable: false);
      return AgentThreadHistorySnapshot(
        threadId: threadId,
        sourceLabel: sourceLabel,
        sessionPath: sessionPath,
        turns: List<AgentHistoryTurn>.unmodifiable(built),
        currentTurn: built.isEmpty ? null : built.last,
      );
    } finally {
      mapper.dispose();
    }
  }
}

class _TurnBuilder {
  _TurnBuilder({
    required this.id,
    required this.sessionId,
    this.stablePromptId,
    this.modelId,
  });

  final String id;
  final String sessionId;
  String? stablePromptId;
  final List<AgentHistoryEntry> entries = <AgentHistoryEntry>[];
  final Map<String, int> _messageIndexById = <String, int>{};
  final Map<String, int> _toolIndexById = <String, int>{};
  String? _userPromptKey;
  int? _userMessageIndex;
  int? _planMessageIndex;
  AgentHistoryTurnStatus status = AgentHistoryTurnStatus.completed;
  AgentTokenUsage? tokenUsage;
  String? errorMessage;
  Map<String, Object?>? retryStateRaw;
  DateTime? startedAt;
  DateTime? completedAt;
  Duration? duration;
  String? modelId;
  bool identityTerminal = false;

  bool get hasContent => entries.isNotEmpty;

  bool acceptsUserPrompt(String? promptKey) {
    return promptKey != null && promptKey == _userPromptKey;
  }

  bool hasDifferentStablePrompt(String? promptId) {
    final stable = stablePromptId;
    return stable != null && promptId != null && stable != promptId;
  }

  void notePromptId(String? promptId) {
    if (promptId != null && promptId.isNotEmpty) {
      stablePromptId ??= promptId;
    }
  }

  void noteUserPrompt(String? promptKey) {
    if (promptKey != null) {
      _userPromptKey ??= promptKey;
    }
  }

  /// 保存 Grok 重试诊断；耗尽状态可在缺少 turn_completed 时作为失败兜底。
  void noteRetryState(Map<String, Object?> raw) {
    retryStateRaw = Map<String, Object?>.unmodifiable(raw);
    final type = raw['type']?.toString().toLowerCase();
    final isRateLimited = raw['is_rate_limited'] == true;
    if (type != 'exhausted' && !isRateLimited) {
      return;
    }
    status = AgentHistoryTurnStatus.failed;
    errorMessage = grokRetryFailureMessage(
      reason: raw['reason']?.toString(),
      isRateLimited: isRateLimited,
    );
  }

  /// 记录事件时间；首次出现作为 [startedAt]。
  void noteTime(DateTime? at) {
    if (at != null) {
      startedAt ??= at;
    }
  }

  /// 用流式 `_meta.turnStartMs` 校正回合真实开始时间。
  void noteTurnStartMs(Object? value) {
    final at = _dateTimeFromMs(value);
    if (at != null && (startedAt == null || at.isBefore(startedAt!))) {
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
    required String? sourceMessageId,
    required String text,
    required List<String> localImagePaths,
    required AgentProviderRawPayload raw,
  }) {
    final existingIndex = _userMessageIndex;
    if (existingIndex != null) {
      final existing = entries[existingIndex] as AgentHistoryMessageEntry;
      entries[existingIndex] = AgentHistoryMessageEntry(
        id: existing.id,
        sourceMessageId: sourceMessageId ?? existing.sourceMessageId,
        role: AgentMessageRole.user,
        text: _mergeUserText(existing.text, text),
        status: AgentMessageStatus.completed,
        localImagePaths: List<String>.unmodifiable(<String>{
          ...existing.localImagePaths,
          ...localImagePaths,
        }),
        raw: raw,
      );
      return;
    }

    final entryId = '$id:user:1';
    _userMessageIndex = entries.length;
    addMessage(
      AgentHistoryMessageEntry(
        id: entryId,
        sourceMessageId: sourceMessageId,
        role: AgentMessageRole.user,
        text: text,
        status: AgentMessageStatus.completed,
        localImagePaths: List<String>.unmodifiable(localImagePaths),
        raw: raw,
      ),
    );
  }

  /// 按 reducer 已规范化的 entryId 聚合同一正文 segment。
  void addOrMergeAgentMessage({
    required String id,
    required String? sourceMessageId,
    required String text,
    required AgentProviderRawPayload raw,
  }) {
    final existingIndex = _messageIndexById[id];
    if (existingIndex != null) {
      final existing = entries[existingIndex] as AgentHistoryMessageEntry;
      entries[existingIndex] = AgentHistoryMessageEntry(
        id: id,
        sourceMessageId: sourceMessageId ?? existing.sourceMessageId,
        role: AgentMessageRole.agent,
        text: _mergeStreamText(existing.text, text),
        status: AgentMessageStatus.completed,
        raw: raw,
      );
      return;
    }
    addMessage(
      AgentHistoryMessageEntry(
        id: id,
        sourceMessageId: sourceMessageId,
        role: AgentMessageRole.agent,
        text: text,
        status: AgentMessageStatus.completed,
        raw: raw,
      ),
    );
  }

  /// 按 reducer 已规范化的 entryId 聚合连续 reasoning phase。
  void addOrMergeThought({
    required String id,
    required String? sourceItemId,
    required String text,
    required AgentProviderRawPayload raw,
  }) {
    final existingIndex = _toolIndexById[id];
    if (existingIndex != null) {
      final existing = entries[existingIndex] as AgentHistoryToolEntry;
      entries[existingIndex] = AgentHistoryToolEntry(
        toolCall: existing.toolCall.copyWith(
          content: _mergeStreamText(existing.toolCall.content ?? '', text),
          raw: raw,
          sourceItemId: sourceItemId,
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
          sessionId: sessionId,
          turnId: this.id,
          raw: raw,
          sourceItemId: sourceItemId,
        ),
      ),
    );
  }

  void upsertTool(AgentToolCall tool) {
    final existingIndex = _toolIndexById[tool.id];
    if (existingIndex != null) {
      final existing = entries[existingIndex] as AgentHistoryToolEntry;
      entries[existingIndex] = AgentHistoryToolEntry(
        toolCall: _mergeTool(existing.toolCall, tool),
      );
      return;
    }
    _toolIndexById[tool.id] = entries.length;
    entries.add(AgentHistoryToolEntry(toolCall: tool));
  }

  void addPlan(
    List<AgentPlanEntry> planEntries, {
    required AgentProviderRawPayload raw,
  }) {
    final text = _planText(planEntries);
    if (text.isEmpty) {
      return;
    }
    final entry = AgentHistoryMessageEntry(
      id: '$id:plan',
      role: AgentMessageRole.agent,
      text: text,
      kind: AgentMessageKind.plan,
      status: AgentMessageStatus.completed,
      raw: AgentProviderRawPayload.wrap(const <String, Object?>{
        'type': 'plan',
      }).mergedWith(raw),
    );
    final existingIndex = _planMessageIndex;
    if (existingIndex != null) {
      entries[existingIndex] = entry;
      return;
    }
    _planMessageIndex = entries.length;
    addMessage(entry);
  }

  AgentHistoryTurn build() {
    return AgentHistoryTurn(
      id: id,
      entries: List<AgentHistoryEntry>.unmodifiable(entries),
      status: status,
      startedAt: startedAt,
      completedAt: completedAt,
      duration: duration,
      modelId: modelId,
      tokenUsage: tokenUsage,
      // Grok turn_completed.usage 是本回合绝对用量，不是会话累计。
      tokenUsageIsSessionCumulative: false,
      errorMessage: errorMessage,
    );
  }
}

AgentToolCall _mergeTool(AgentToolCall previous, AgentToolCall next) {
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
    locations: next.locations.isNotEmpty ? next.locations : previous.locations,
    sessionId: next.sessionId ?? previous.sessionId,
    turnId: next.turnId ?? previous.turnId,
    rawInput: next.rawInput.isNotEmpty ? next.rawInput : previous.rawInput,
    rawOutput: next.rawOutput.isNotEmpty ? next.rawOutput : previous.rawOutput,
    raw: next.raw.isNotEmpty ? next.raw : previous.raw,
    fileChanges: next.fileChanges,
  );
}

String _historyTurnId(String threadId, int ordinal) {
  return 'grok-history:${Uri.encodeComponent(threadId)}:turn:$ordinal';
}

String _planText(List<AgentPlanEntry> entries) {
  return entries
      .where((entry) => entry.content.trim().isNotEmpty)
      .map(
        (entry) => entry.status == null || entry.status!.isEmpty
            ? '- ${entry.content.trim()}'
            : '- [${entry.status}] ${entry.content.trim()}',
      )
      .join('\n');
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

String _mergeStreamText(String previous, String next) {
  if (previous == next || previous.endsWith(next)) {
    return previous;
  }
  if (next.startsWith(previous)) {
    return next;
  }
  return '$previous$next';
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

DateTime? _dateTimeFromMs(Object? value) {
  final ms = _asInt(value);
  if (ms == null || ms <= 0) {
    return null;
  }
  return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
}

DateTime? _dateTimeFromTimestamp(Object? value) {
  final raw = _asInt(value);
  if (raw == null || raw <= 0) {
    return null;
  }
  final ms = raw.abs() < 1000000000000
      ? raw * Duration.millisecondsPerSecond
      : raw;
  return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
}

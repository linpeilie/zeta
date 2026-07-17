import 'package:zeta/src/features/agent/data/mappers/acp_content_codec.dart';
import 'package:zeta/src/features/agent/data/mappers/acp_session_update_decoder.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// 标准 ACP `session/update` 到领域事件的映射结果。
class AcpMappedUpdate {
  const AcpMappedUpdate({
    this.events = const <AgentEvent>[],
    this.unmatchedKind,
  });

  final List<AgentEvent> events;
  final String? unmatchedKind;
}

/// 兼容现有调用方的映射结果别名。
typedef GrokAcpMappedUpdate = AcpMappedUpdate;

/// 迁移期标准 ACP `session/update` 兼容 mapper。
///
/// 原始字段先由无状态 [AcpSessionUpdateDecoder] 解码。本类暂时保留旧 entryId
/// 合成规则，直到 Grok/Cursor 各自的 identity adapter 完成迁移；不得在此新增
/// Provider 叙事策略。
class AcpSessionUpdateMapper {
  const AcpSessionUpdateMapper({
    this.decoder = const AcpSessionUpdateDecoder(),
  });

  final AcpSessionUpdateDecoder decoder;

  /// 映射标准 `session/update` 通知。
  AcpMappedUpdate mapSessionUpdate({
    required Map<String, Object?> params,
    required String? runningTurnId,
  }) {
    final decoded = decoder.decode(params);
    final turnId = runningTurnId;

    switch (decoded) {
      case AcpUserMessageChunk():
        // 直播时间线已由 ViewModel 乐观插入用户消息；再映射会重复一条。
        // 历史回放走本地 updates.jsonl 解析，不经过此 live mapper。
        return const AcpMappedUpdate(unmatchedKind: 'user_message_chunk');
      case AcpAgentMessageChunk():
        final text = AcpContentCodec.textFromContent(decoded.content);
        if (text == null || text.isEmpty) {
          return AcpMappedUpdate(unmatchedKind: decoded.kind);
        }
        // 迁移期保留旧 identity 优先级，避免尚未迁移的 Grok/Cursor 行为变化。
        final messageId = _stableStreamMessageId(
          sourceMessageId: decoded.sourceMessageId,
          eventId: decoded.eventId,
          promptId: decoded.promptId,
          kind: decoded.kind,
          sessionId: decoded.sessionId,
          turnId: turnId,
        );
        // 标准 ACP 无 Codex final_answer 语义；不设 response phase，
        // 避免 UI 走「完成汇总」卡片样式。
        return AcpMappedUpdate(
          events: <AgentEvent>[
            AgentMessageDeltaEvent(
              messageId: messageId,
              sourceMessageId: decoded.sourceMessageId,
              kind: AgentMessageKind.regular,
              delta: text,
              role: AgentMessageRole.agent,
              status: AgentMessageStatus.streaming,
              sessionId: decoded.sessionId,
              turnId: turnId,
              raw: decoded.raw,
            ),
          ],
        );
      case AcpAgentThoughtChunk():
        final text = AcpContentCodec.textFromContent(decoded.content) ?? '';
        // 迁移期保留现有 thought identity；decoder 本身不参与该决策。
        final itemId = _stableThoughtItemId(
          sourceItemId: decoded.sourceItemId,
          promptId: decoded.promptId,
          sessionId: decoded.sessionId,
          turnId: turnId,
        );
        return AcpMappedUpdate(
          events: <AgentEvent>[
            AgentReasoningDeltaEvent(
              itemId: itemId,
              sourceItemId: decoded.sourceItemId,
              kind: AgentReasoningDeltaKind.text,
              delta: text,
              sessionId: decoded.sessionId,
              turnId: turnId,
              raw: decoded.raw,
            ),
          ],
        );
      case AcpToolCallUpdate():
        final toolCall = _mapToolCall(
          update: decoded,
          sessionId: decoded.sessionId,
          turnId: turnId,
        );
        return AcpMappedUpdate(
          events: <AgentEvent>[AgentToolCallEvent(toolCall)],
        );
      case AcpPlanUpdate():
        final entries = _mapPlanEntries(decoded.entries);
        return AcpMappedUpdate(
          events: <AgentEvent>[
            AgentPlanUpdatedEvent(
              entries: entries,
              sessionId: decoded.sessionId,
              turnId: turnId,
            ),
          ],
        );
      case AcpUsageUpdate():
        // ACP 上下文占用进度：按会话级累计处理，供 header/composer 使用。
        return AcpMappedUpdate(
          events: <AgentEvent>[
            AgentTokenUsageEvent(
              sessionId: decoded.sessionId,
              turnId: turnId,
              isSessionCumulative: true,
              tokenUsage: AgentTokenUsage(
                totalTokens: decoded.used,
                inputTokens: decoded.used,
                outputTokens: 0,
                modelContextWindow: decoded.modelContextWindow,
              ),
              raw: decoded.raw,
            ),
          ],
        );
      case AcpTurnCompletedUpdate():
        // 兼容通过标准 session/update 通道发送的 turn_completed 扩展。
        return _mapTurnCompleted(update: decoded, runningTurnId: turnId);
      case AcpUnknownUpdate():
        return AcpMappedUpdate(unmatchedKind: decoded.kind);
    }
  }

  /// 映射可由厂商扩展复用的回合完成更新。
  AcpMappedUpdate mapTurnCompleted({
    required Map<String, Object?> params,
    required Map<String, Object?> update,
    required String? runningTurnId,
  }) {
    final decoded = decoder.decode(<String, Object?>{
      ...params,
      'update': update,
    });
    if (decoded is! AcpTurnCompletedUpdate) {
      return AcpMappedUpdate(unmatchedKind: decoded.kind);
    }
    return _mapTurnCompleted(update: decoded, runningTurnId: runningTurnId);
  }

  AcpMappedUpdate _mapTurnCompleted({
    required AcpTurnCompletedUpdate update,
    required String? runningTurnId,
  }) {
    // 优先本地 running turn id（与 pending/live 分组一致）；否则读取扩展 prompt id。
    final turnId = runningTurnId ?? update.promptId;
    final sessionId = update.sessionId;
    if (sessionId == null || turnId == null) {
      return const AcpMappedUpdate(unmatchedKind: 'turn_completed');
    }

    final stopReason = update.stopReason;
    final status = _stopReasonToStatus(stopReason);

    // turn_completed 携带的 usage 按本回合绝对用量处理，并兼容 apiDurationMs。
    Duration? duration;
    AgentTokenUsage? tokenUsage;
    final usage = update.usage;
    if (usage != null) {
      final apiDurationMs = usage.apiDurationMs;
      if (apiDurationMs != null && apiDurationMs >= 0) {
        duration = Duration(milliseconds: apiDurationMs);
      }
      tokenUsage = AgentTokenUsage(
        inputTokens: usage.inputTokens ?? 0,
        outputTokens: usage.outputTokens ?? 0,
        totalTokens: usage.totalTokens,
        cachedInputTokens: usage.cachedReadTokens,
        reasoningOutputTokens: usage.reasoningTokens,
        modelContextWindow: usage.modelContextWindow,
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
          raw: usage?.raw ?? const <String, Object?>{},
        ),
      AgentTurnCompletedEvent(
        sessionId: sessionId,
        turnId: turnId,
        status: status,
        duration: duration,
        errorMessage: status == AgentHistoryTurnStatus.failed
            ? stopReason
            : null,
        raw: update.raw,
      ),
    ];

    return AcpMappedUpdate(events: events);
  }

  /// 为无官方 messageId 的 **agent 正文** 流式 chunk 生成聚合 id。
  ///
  /// 优先顺序：
  /// `messageId` → `_meta.eventId` → `promptId` / `runningTurnId` / session。
  ///
  /// - 有 eventId 时按事件分段，工具插入后可自然开新气泡；
  /// - 仅有 turn 作用域时，timeline store 会在操作打断后分配段后缀。
  ///
  /// **不要**用于 `agent_thought_chunk`：思考 chunk 常带独立 eventId，
  /// 按 event 切分会拆成多张思考卡（见 [_stableThoughtItemId]）。
  String _stableStreamMessageId({
    required String? sourceMessageId,
    required String? eventId,
    required String? promptId,
    required String kind,
    required String? sessionId,
    required String? turnId,
  }) {
    if (sourceMessageId != null) {
      return sourceMessageId;
    }
    if (eventId != null) {
      return 'acp-$kind-event-$eventId';
    }
    return 'acp-$kind-${_streamScopeId(promptId: promptId, sessionId: sessionId, turnId: turnId)}';
  }

  /// 思考流的稳定 itemId：整 turn（或显式 messageId）聚合为一张「思考」卡。
  ///
  /// Grok 每个 `agent_thought_chunk` 通常带不同 `_meta.eventId`，若走正文的
  /// eventId 分段策略，会在 timeline 上出现多条互不相关的思考卡片。
  String _stableThoughtItemId({
    required String? sourceItemId,
    required String? promptId,
    required String? sessionId,
    required String? turnId,
  }) {
    if (sourceItemId != null) {
      return sourceItemId;
    }
    final scope = _streamScopeId(
      promptId: promptId,
      sessionId: sessionId,
      turnId: turnId,
    );
    return 'acp-agent_thought_chunk-$scope';
  }

  /// promptId → runningTurnId → session 的流式作用域。
  String _streamScopeId({
    required String? promptId,
    required String? sessionId,
    required String? turnId,
  }) {
    return promptId ?? turnId ?? sessionId ?? 'unknown';
  }

  AgentToolCall _mapToolCall({
    required AcpToolCallUpdate update,
    required String? sessionId,
    required String? turnId,
  }) {
    final id = update.toolCallId;
    final kind = _mapToolKind(update.toolKind);
    final status = _mapToolStatus(update.status);
    final content = AcpContentCodec.toolContentText(update.content);
    final locations = update.locations;
    final rawInput = update.rawInput;
    final rawOutput = update.rawOutput;

    // 不要把 toolCallId（call-...）当标题；用类型 + 路径/命令合成可读文案。
    final title = buildAgentToolCallDisplayTitle(
      toolCallId: id,
      title: update.title,
      kind: kind,
      kindRaw: update.toolKind,
      locations: locations,
      rawInput: rawInput,
    );

    return AgentToolCall(
      id: id,
      title: title,
      kind: kind,
      status: status,
      content: content,
      locations: locations,
      sessionId: sessionId,
      turnId: turnId,
      rawInput: rawInput,
      rawOutput: rawOutput,
      raw: update.raw,
    );
  }

  List<AgentPlanEntry> _mapPlanEntries(List<AcpPlanEntry> value) {
    final entries = value
        .map(
          (entry) => AgentPlanEntry(
            content: entry.content,
            status: entry.status,
            priority: entry.priority,
          ),
        )
        .toList(growable: false);
    return List<AgentPlanEntry>.unmodifiable(entries);
  }

  AgentToolKind _mapToolKind(String? kind) {
    // 兼容 agent 使用 PascalCase（Read/Execute）；统一小写再匹配。
    return parseAgentToolKind(kind);
  }

  AgentToolStatus _mapToolStatus(String? status) {
    // 兼容 Completed/Pending/InProgress 等 PascalCase 状态。
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
}

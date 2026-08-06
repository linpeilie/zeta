import 'package:zeta/src/features/agent/data/mappers/acp_content_codec.dart';
import 'package:zeta/src/features/agent/data/mappers/acp_session_update_decoder.dart';
import 'package:zeta/src/features/agent/data/mappers/grok_error_normalizer.dart';
import 'package:zeta/src/features/agent/data/mappers/grok_stream_identity.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// Grok typed ACP update 到领域事件的映射结果。
class GrokAcpMappedUpdate {
  const GrokAcpMappedUpdate({
    this.events = const <AgentEvent>[],
    this.unmatchedKind,
    this.ignoredReason,
  });

  final List<AgentEvent> events;
  final String? unmatchedKind;
  final String? ignoredReason;
}

/// Grok 专属 ACP update adapter。
///
/// 共享 decoder 只解析协议；message/reasoning entryId、边界、去重与终态均由
/// [GrokStreamIdentity] 决定，输出进入 application 层时已是最终身份。
///
/// ## Token 口径
///
/// Grok multi-step agent turn 在 `turn_completed.usage` 里上报的
/// `totalTokens` / `inputTokens` 是本回合内**全部 model call 的计费合计**，
/// 不是上下文窗口占用。真正的窗口占用出现在流式通知的
/// `params._meta.totalTokens`。
///
/// 本 mapper 在回合内跟踪最新 `_meta.totalTokens`，并在 turn_completed 时
/// 写入 [AgentTokenUsage.lastTotalTokens] / [AgentTokenUsage.lastInputTokens]，
/// 供上下文进度环使用；计费字段仍保留在非 `last*` breakdown。
final class GrokSessionUpdateMapper {
  GrokSessionUpdateMapper({
    this.decoder = const AcpSessionUpdateDecoder(),
    GrokStreamIdentity? identity,
  }) : identity = identity ?? GrokStreamIdentity();

  final AcpSessionUpdateDecoder decoder;
  final GrokStreamIdentity identity;

  /// 当前 turn 内最新的上下文窗口占用（来自 `_meta.totalTokens`）。
  int? _latestContextTokens;

  GrokStreamIdentityDiagnostics get diagnostics => identity.diagnostics;

  int beginTurn({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
    required String turnId,
  }) {
    // 新回合开始时清空占用跟踪，避免串到上一 turn。
    _latestContextTokens = null;
    return identity.beginTurn(
      runtimeScope: runtimeScope,
      sessionId: sessionId,
      turnId: turnId,
    );
  }

  /// 映射标准或 xAI 通道中的 typed ACP update。
  GrokAcpMappedUpdate mapSessionUpdate({
    required Map<String, Object?> params,
    required String? runningTurnId,
    required AgentRuntimeScope runtimeScope,
    GrokTerminalSource terminalSource = GrokTerminalSource.standardNotification,
  }) {
    // 任意流式 chunk 都可能携带当前上下文占用，先于 kind 分支更新跟踪值。
    final changedContextTokens = _noteContextTokensFromParams(params);
    final decoded = decoder.decode(params);
    final mapped = switch (decoded) {
      AcpUserMessageChunk() =>
        // live 用户消息由 ViewModel 乐观插入，避免重复气泡。
        const GrokAcpMappedUpdate(
          unmatchedKind: 'user_message_chunk',
          ignoredReason: 'user message is handled by the local send path',
        ),
      AcpAgentMessageChunk() => _mapMessage(
        decoded,
        runningTurnId: runningTurnId,
        runtimeScope: runtimeScope,
      ),
      AcpAgentThoughtChunk() => _mapReasoning(
        decoded,
        runningTurnId: runningTurnId,
        runtimeScope: runtimeScope,
      ),
      AcpToolCallUpdate() => _mapTool(
        decoded,
        runningTurnId: runningTurnId,
        runtimeScope: runtimeScope,
      ),
      AcpPlanUpdate() => _mapPlan(
        decoded,
        runningTurnId: runningTurnId,
        runtimeScope: runtimeScope,
      ),
      AcpUsageUpdate() => _mapUsage(
        decoded,
        runningTurnId: runningTurnId,
        runtimeScope: runtimeScope,
      ),
      AcpTurnCompletedUpdate() => _mapTurnCompleted(
        decoded,
        runningTurnId: runningTurnId,
        runtimeScope: runtimeScope,
        terminalSource: terminalSource,
      ),
      AcpCurrentModeUpdate() => _mapCurrentMode(
        decoded,
        runtimeScope: runtimeScope,
      ),
      AcpUnknownUpdate() => GrokAcpMappedUpdate(
        unmatchedKind: decoded.kind,
        ignoredReason: decoded.diagnostic ?? 'unsupported update kind',
      ),
    };
    // usage_update 与 turn_completed 已携带完整 token 事件；普通 chunk 才追加
    // 独立的上下文占用事件，避免把实时占用混入计费 footer。
    if (changedContextTokens == null ||
        decoded.sessionId == null ||
        decoded is AcpUsageUpdate ||
        decoded is AcpTurnCompletedUpdate) {
      return mapped;
    }
    return GrokAcpMappedUpdate(
      events: <AgentEvent>[
        ...mapped.events,
        AgentContextWindowUsageEvent(
          usedTokens: changedContextTokens,
          sessionId: decoded.sessionId,
          turnId: runningTurnId,
          raw: decoded.raw,
        ),
      ],
      unmatchedKind: mapped.unmatchedKind,
      ignoredReason: mapped.ignoredReason,
    );
  }

  /// 将 `session/prompt` RPC 的终态纳入同一 first-terminal-wins reducer。
  GrokAcpMappedUpdate mapPromptTerminal({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
    required String turnId,
    required String stopReason,
    required GrokTerminalSource source,
    String? errorMessage,
    Map<String, Object?> raw = const <String, Object?>{},
  }) {
    // 正常 prompt RPC 可能先于带 usage 的 turn_completed 通知返回。
    // 保留本回合上下文占用，让迟到通知补全 token 元数据；取消与异常终态
    // 不再等待权威通知，必须立即清理，避免泄漏到下一 turn。
    if (source != GrokTerminalSource.promptRpc) {
      _latestContextTokens = null;
    }
    final status = _stopReasonToStatus(stopReason);
    final terminal = identity.completeTurn(
      runtimeScope: runtimeScope,
      sessionId: sessionId,
      runningTurnId: turnId,
      promptId: null,
      status: status,
      source: source,
      eventKind: 'session/prompt:${source.name}',
    );
    if (!terminal.accepted) {
      return const GrokAcpMappedUpdate(
        ignoredReason: 'prompt terminal rejected as duplicate or stale',
      );
    }
    return GrokAcpMappedUpdate(
      events: <AgentEvent>[
        AgentTurnCompletedEvent(
          sessionId: terminal.sessionId,
          turnId: terminal.turnId,
          status: terminal.status,
          errorMessage: terminal.status == AgentHistoryTurnStatus.failed
              ? errorMessage ?? stopReason
              : null,
          raw: raw,
        ),
      ],
    );
  }

  bool noteBoundary({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
    required String? runningTurnId,
    required GrokNarrativeBoundaryKind kind,
  }) => identity.noteBoundary(
    runtimeScope: runtimeScope,
    sessionId: sessionId,
    runningTurnId: runningTurnId,
    promptId: null,
    kind: kind,
  );

  void invalidateTurn({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
    required String? runningTurnId,
    required String? promptId,
    required GrokIdentityInvalidationReason reason,
  }) => identity.invalidateTurn(
    runtimeScope: runtimeScope,
    sessionId: sessionId,
    runningTurnId: runningTurnId,
    promptId: promptId,
    reason: reason,
  );

  void invalidateRuntime({
    required AgentRuntimeScope runtimeScope,
    required GrokIdentityInvalidationReason reason,
  }) => identity.invalidateRuntime(runtimeScope: runtimeScope, reason: reason);

  void invalidateSession({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
    required GrokIdentityInvalidationReason reason,
  }) => identity.invalidateSession(
    runtimeScope: runtimeScope,
    sessionId: sessionId,
    reason: reason,
  );

  GrokTurnIdentitySnapshot? snapshot({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
    required String turnId,
  }) => identity.snapshot(
    runtimeScope: runtimeScope,
    sessionId: sessionId,
    turnId: turnId,
  );

  void dispose() {
    _latestContextTokens = null;
    identity.dispose();
  }

  /// 从通知 envelope 的 `_meta.totalTokens` 更新上下文占用跟踪。
  ///
  /// 该字段表示当前上下文占用；优先 `params._meta`，兼容嵌在
  /// `update._meta` 的写法。
  int? _noteContextTokensFromParams(Map<String, Object?> params) {
    final paramsMeta = _stringKeyedMap(params['_meta']);
    final update = _stringKeyedMap(params['update']);
    final updateMeta = update == null ? null : _stringKeyedMap(update['_meta']);
    final contextTokens =
        _positiveInt(paramsMeta?['totalTokens']) ??
        _positiveInt(paramsMeta?['total_tokens']) ??
        _positiveInt(updateMeta?['totalTokens']) ??
        _positiveInt(updateMeta?['total_tokens']);
    if (contextTokens == null || contextTokens == _latestContextTokens) {
      return null;
    }
    _latestContextTokens = contextTokens;
    return contextTokens;
  }

  /// 取出并清空本回合跟踪的上下文占用。
  int? _takeLatestContextTokens() {
    final value = _latestContextTokens;
    _latestContextTokens = null;
    return value;
  }

  /// 从 turn_completed 原始 payload 读取 Grok 专属的 `agent_result`。
  ///
  /// Grok 在 `stop_reason=error` 时用该字段下发服务端真实错误文案；
  /// 兼容 snake_case 与 camelCase 两种命名。该字段只在 Grok 适配层使用，
  /// 共享 decoder 不感知它。
  String? _agentResultFromRaw(Map<String, Object?> raw) {
    final entry = _stringKeyedMap(raw);
    final value = entry?['agent_result'] ?? entry?['agentResult'];
    return value?.toString().trim();
  }

  static Map<String, Object?>? _stringKeyedMap(Object? value) {
    if (value is! Map) {
      return null;
    }
    return value.map(
      (key, dynamic item) => MapEntry(key.toString(), item as Object?),
    );
  }

  static int? _positiveInt(Object? value) {
    final parsed = switch (value) {
      final int number => number,
      final num number => number.toInt(),
      final String text => int.tryParse(text.trim()),
      _ => null,
    };
    if (parsed == null || parsed <= 0) {
      return null;
    }
    return parsed;
  }

  GrokAcpMappedUpdate _mapMessage(
    AcpAgentMessageChunk update, {
    required String? runningTurnId,
    required AgentRuntimeScope runtimeScope,
  }) {
    final text = AcpContentCodec.textFromContent(update.content);
    if (text == null || text.isEmpty) {
      return GrokAcpMappedUpdate(
        unmatchedKind: update.kind,
        ignoredReason: 'empty agent message content',
      );
    }
    final resolved = identity.resolveMessage(
      runtimeScope: runtimeScope,
      sessionId: update.sessionId!,
      runningTurnId: runningTurnId,
      promptId: update.promptId,
      sourceMessageId: update.sourceMessageId,
      eventId: update.eventId,
      eventKind: update.kind,
    );
    if (resolved == null) {
      return const GrokAcpMappedUpdate(
        ignoredReason: 'unresolved message turn scope or duplicate event',
      );
    }
    return GrokAcpMappedUpdate(
      events: <AgentEvent>[
        AgentMessageDeltaEvent(
          messageId: resolved.entryId,
          sourceMessageId: update.sourceMessageId,
          kind: AgentMessageKind.regular,
          delta: text,
          role: AgentMessageRole.agent,
          status: AgentMessageStatus.streaming,
          sessionId: resolved.sessionId,
          turnId: resolved.turnId,
          raw: update.raw,
        ),
      ],
    );
  }

  GrokAcpMappedUpdate _mapReasoning(
    AcpAgentThoughtChunk update, {
    required String? runningTurnId,
    required AgentRuntimeScope runtimeScope,
  }) {
    final text = AcpContentCodec.textFromContent(update.content);
    if (text == null || text.isEmpty) {
      return GrokAcpMappedUpdate(
        unmatchedKind: update.kind,
        ignoredReason: 'empty reasoning content',
      );
    }
    final resolved = identity.resolveReasoning(
      runtimeScope: runtimeScope,
      sessionId: update.sessionId!,
      runningTurnId: runningTurnId,
      promptId: update.promptId,
      sourceItemId: update.sourceItemId,
      eventId: update.eventId,
      eventKind: update.kind,
    );
    if (resolved == null) {
      return const GrokAcpMappedUpdate(
        ignoredReason: 'unresolved reasoning turn scope or duplicate event',
      );
    }
    return GrokAcpMappedUpdate(
      events: <AgentEvent>[
        AgentReasoningDeltaEvent(
          itemId: resolved.entryId,
          sourceItemId: update.sourceItemId,
          kind: AgentReasoningDeltaKind.text,
          delta: text,
          sessionId: resolved.sessionId,
          turnId: resolved.turnId,
          raw: update.raw,
        ),
      ],
    );
  }

  GrokAcpMappedUpdate _mapTool(
    AcpToolCallUpdate update, {
    required String? runningTurnId,
    required AgentRuntimeScope runtimeScope,
  }) {
    final resolved = identity.resolveTool(
      runtimeScope: runtimeScope,
      sessionId: update.sessionId!,
      runningTurnId: runningTurnId,
      promptId: update.promptId,
      toolCallId: update.toolCallId,
      eventId: update.eventId,
      eventKind: update.kind,
    );
    if (resolved == null) {
      return const GrokAcpMappedUpdate(
        ignoredReason: 'unresolved tool turn scope or duplicate event',
      );
    }
    final toolCall = _mapToolCall(
      update: update,
      sessionId: resolved.sessionId,
      turnId: resolved.turnId,
    );
    return GrokAcpMappedUpdate(
      events: <AgentEvent>[AgentToolCallEvent(toolCall)],
    );
  }

  GrokAcpMappedUpdate _mapPlan(
    AcpPlanUpdate update, {
    required String? runningTurnId,
    required AgentRuntimeScope runtimeScope,
  }) {
    final resolved = identity.resolveVisibleBoundaryUpdate(
      runtimeScope: runtimeScope,
      sessionId: update.sessionId!,
      runningTurnId: runningTurnId,
      promptId: update.promptId,
      eventId: update.eventId,
      eventKind: update.kind,
    );
    if (resolved == null) {
      return const GrokAcpMappedUpdate(
        ignoredReason: 'unresolved plan turn scope or duplicate event',
      );
    }
    final entries = update.entries
        .map(
          (entry) => AgentPlanEntry(
            content: entry.content,
            status: entry.status,
            priority: entry.priority,
          ),
        )
        .toList(growable: false);
    return GrokAcpMappedUpdate(
      events: <AgentEvent>[
        AgentPlanUpdatedEvent(
          entries: List<AgentPlanEntry>.unmodifiable(entries),
          sessionId: resolved.sessionId,
          turnId: resolved.turnId,
        ),
      ],
    );
  }

  /// 映射会话级模式更新（`current_mode_update`）。
  ///
  /// 模式是会话级状态，不属于某个 turn 的叙事边界，因此不经过
  /// `resolveVisibleBoundaryUpdate`；未知模式标识宽容降级为忽略。
  ///
  /// Grok 在 `session/prompt` 的 `_meta.mode` 使用 `agent` 表示默认模式，
  /// `currentModeId` 也可能复用同一词汇；中立 [AgentConversationModeId] 仍
  /// 以 `default` 为规范值，别名归一仅在本 adapter 完成。
  GrokAcpMappedUpdate _mapCurrentMode(
    AcpCurrentModeUpdate update, {
    required AgentRuntimeScope runtimeScope,
  }) {
    final sessionId = update.sessionId;
    if (sessionId == null) {
      return const GrokAcpMappedUpdate(ignoredReason: 'missing session id');
    }
    final modeId = _normalizeGrokConversationModeId(update.modeId);
    if (modeId == null || modeId.kind == AgentConversationModeKind.unknown) {
      return GrokAcpMappedUpdate(
        unmatchedKind: update.kind,
        ignoredReason: 'unsupported conversation mode',
      );
    }
    return GrokAcpMappedUpdate(
      events: <AgentEvent>[
        AgentConversationModeUpdatedEvent(
          sessionId: sessionId,
          modeId: modeId,
          raw: update.raw,
        ),
      ],
    );
  }

  /// 将 Grok 协议模式标识归一为中立 [AgentConversationModeId]。
  ///
  /// `agent` 是 Grok 默认模式的 wire 别名（与 `_meta.mode` 一致），映射为
  /// [AgentConversationModeId.defaultMode]；其它未知值保持 unknown。
  static AgentConversationModeId? _normalizeGrokConversationModeId(
    Object? rawValue,
  ) {
    final modeId = AgentConversationModeId.tryFromRaw(rawValue);
    if (modeId == null) {
      return null;
    }
    if (modeId.kind == AgentConversationModeKind.unknown &&
        modeId.rawValue == 'agent') {
      return AgentConversationModeId.defaultMode;
    }
    return modeId;
  }

  GrokAcpMappedUpdate _mapUsage(
    AcpUsageUpdate update, {
    required String? runningTurnId,
    required AgentRuntimeScope runtimeScope,
  }) {
    final resolved = identity.resolveMetadata(
      runtimeScope: runtimeScope,
      sessionId: update.sessionId!,
      runningTurnId: runningTurnId,
      promptId: update.promptId,
      eventId: update.eventId,
      eventKind: update.kind,
    );
    if (resolved == null) {
      return const GrokAcpMappedUpdate(
        ignoredReason: 'unresolved usage turn scope or duplicate event',
      );
    }
    // usage_update.used 表示当前上下文进度，同步刷新占用跟踪。
    if (update.used > 0) {
      _latestContextTokens = update.used;
    }
    return GrokAcpMappedUpdate(
      events: <AgentEvent>[
        AgentTokenUsageEvent(
          sessionId: resolved.sessionId,
          turnId: resolved.turnId,
          isSessionCumulative: true,
          tokenUsage: AgentTokenUsage(
            totalTokens: update.used,
            inputTokens: update.used,
            outputTokens: 0,
            lastTotalTokens: update.used > 0 ? update.used : null,
            lastInputTokens: update.used > 0 ? update.used : null,
            modelContextWindow: update.modelContextWindow,
          ),
          raw: update.raw,
        ),
      ],
    );
  }

  GrokAcpMappedUpdate _mapTurnCompleted(
    AcpTurnCompletedUpdate update, {
    required String? runningTurnId,
    required AgentRuntimeScope runtimeScope,
    required GrokTerminalSource terminalSource,
  }) {
    final status = _stopReasonToStatus(update.stopReason);
    final terminal = identity.completeTurn(
      runtimeScope: runtimeScope,
      sessionId: update.sessionId!,
      runningTurnId: runningTurnId,
      promptId: update.promptId,
      status: status,
      source: terminalSource,
      eventId: update.eventId,
    );
    final shouldEmitCompletion = terminal.accepted;
    final canApplyTerminalMetadata =
        shouldEmitCompletion ||
        terminal.disposition == GrokTerminalDisposition.duplicate;
    if (!canApplyTerminalMetadata) {
      return const GrokAcpMappedUpdate(
        ignoredReason: 'terminal update rejected as duplicate or stale',
      );
    }

    // 即使生命周期终态已由 prompt RPC 接受，迟到的权威通知仍可补全 usage；
    // 仅抑制重复 AgentTurnCompletedEvent，不丢弃 token 元数据。
    final contextTokens = _takeLatestContextTokens();

    Duration? duration;
    AgentTokenUsage? tokenUsage;
    final usage = update.usage;
    if (usage != null) {
      final apiDurationMs = usage.apiDurationMs;
      if (apiDurationMs != null && apiDurationMs >= 0) {
        duration = Duration(milliseconds: apiDurationMs);
      }
      // usage.* = 本回合计费合计（可含多次 model call）；
      // last* = 上下文窗口占用（来自 _meta.totalTokens）。
      tokenUsage = AgentTokenUsage(
        inputTokens: usage.inputTokens ?? 0,
        outputTokens: usage.outputTokens ?? 0,
        totalTokens: usage.totalTokens,
        cachedInputTokens: usage.cachedReadTokens,
        reasoningOutputTokens: usage.reasoningTokens,
        lastInputTokens: contextTokens,
        lastTotalTokens: contextTokens,
        modelContextWindow: usage.modelContextWindow,
      );
    } else if (contextTokens != null) {
      // 无计费 usage 时仍上报上下文占用，避免进度环空白。
      tokenUsage = AgentTokenUsage(
        lastInputTokens: contextTokens,
        lastTotalTokens: contextTokens,
      );
    }

    return GrokAcpMappedUpdate(
      events: <AgentEvent>[
        if (tokenUsage != null)
          AgentTokenUsageEvent(
            sessionId: terminal.sessionId,
            turnId: terminal.turnId,
            isSessionCumulative: false,
            tokenUsage: tokenUsage,
            raw: usage?.raw ?? const <String, Object?>{},
          ),
        if (shouldEmitCompletion)
          AgentTurnCompletedEvent(
            sessionId: terminal.sessionId,
            turnId: terminal.turnId,
            status: terminal.status,
            duration: duration,
            errorMessage: terminal.status == AgentHistoryTurnStatus.failed
                ? grokTerminalErrorMessage(
                    update.stopReason,
                    agentResult: _agentResultFromRaw(update.raw),
                  )
                : null,
            raw: update.raw,
          ),
      ],
    );
  }

  AgentToolCall _mapToolCall({
    required AcpToolCallUpdate update,
    required String sessionId,
    required String turnId,
  }) {
    final kind = parseAgentToolKind(update.toolKind);
    final status = _mapToolStatus(update.status);
    final title = buildAgentToolCallDisplayTitle(
      toolCallId: update.toolCallId,
      title: update.title,
      kind: kind,
      kindRaw: update.toolKind,
      locations: update.locations,
      rawInput: update.rawInput,
    );
    return AgentToolCall(
      id: update.toolCallId,
      title: title,
      kind: kind,
      status: status,
      content: AcpContentCodec.toolContentText(update.content),
      locations: update.locations,
      sessionId: sessionId,
      turnId: turnId,
      rawInput: update.rawInput,
      rawOutput: update.rawOutput,
      raw: update.raw,
    );
  }

  AgentToolStatus _mapToolStatus(String? status) {
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
        normalized.contains('rate_limit') ||
        normalized.contains('rate limit') ||
        normalized.contains('max_token') ||
        normalized.contains('max_turn')) {
      return AgentHistoryTurnStatus.failed;
    }
    return AgentHistoryTurnStatus.completed;
  }
}

import 'package:zeta/src/features/agent/data/mappers/acp_content_codec.dart';
import 'package:zeta/src/features/agent/data/mappers/acp_session_update_decoder.dart';
import 'package:zeta/src/features/agent/data/mappers/grok_stream_identity.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// Grok typed ACP update 到领域事件的映射结果。
class GrokAcpMappedUpdate {
  const GrokAcpMappedUpdate({
    this.events = const <AgentEvent>[],
    this.unmatchedKind,
  });

  final List<AgentEvent> events;
  final String? unmatchedKind;
}

/// Grok 专属 ACP update adapter。
///
/// 共享 decoder 只解析协议；message/reasoning entryId、边界、去重与终态均由
/// [GrokStreamIdentity] 决定，输出进入 application 层时已是最终身份。
final class GrokSessionUpdateMapper {
  GrokSessionUpdateMapper({
    this.decoder = const AcpSessionUpdateDecoder(),
    GrokStreamIdentity? identity,
  }) : identity = identity ?? GrokStreamIdentity();

  final AcpSessionUpdateDecoder decoder;
  final GrokStreamIdentity identity;

  GrokStreamIdentityDiagnostics get diagnostics => identity.diagnostics;

  int beginTurn({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
    required String turnId,
  }) => identity.beginTurn(
    runtimeScope: runtimeScope,
    sessionId: sessionId,
    turnId: turnId,
  );

  /// 映射标准或 xAI 通道中的 typed ACP update。
  GrokAcpMappedUpdate mapSessionUpdate({
    required Map<String, Object?> params,
    required String? runningTurnId,
    required AgentRuntimeScope runtimeScope,
    GrokTerminalSource terminalSource = GrokTerminalSource.standardNotification,
  }) {
    final decoded = decoder.decode(params);
    switch (decoded) {
      case AcpUserMessageChunk():
        // live 用户消息由 ViewModel 乐观插入，避免重复气泡。
        return const GrokAcpMappedUpdate(unmatchedKind: 'user_message_chunk');
      case AcpAgentMessageChunk():
        return _mapMessage(
          decoded,
          runningTurnId: runningTurnId,
          runtimeScope: runtimeScope,
        );
      case AcpAgentThoughtChunk():
        return _mapReasoning(
          decoded,
          runningTurnId: runningTurnId,
          runtimeScope: runtimeScope,
        );
      case AcpToolCallUpdate():
        return _mapTool(
          decoded,
          runningTurnId: runningTurnId,
          runtimeScope: runtimeScope,
        );
      case AcpPlanUpdate():
        return _mapPlan(
          decoded,
          runningTurnId: runningTurnId,
          runtimeScope: runtimeScope,
        );
      case AcpUsageUpdate():
        return _mapUsage(
          decoded,
          runningTurnId: runningTurnId,
          runtimeScope: runtimeScope,
        );
      case AcpTurnCompletedUpdate():
        return _mapTurnCompleted(
          decoded,
          runningTurnId: runningTurnId,
          runtimeScope: runtimeScope,
          terminalSource: terminalSource,
        );
      case AcpUnknownUpdate():
        return GrokAcpMappedUpdate(unmatchedKind: decoded.kind);
    }
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
      return const GrokAcpMappedUpdate();
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

  void dispose() => identity.dispose();

  GrokAcpMappedUpdate _mapMessage(
    AcpAgentMessageChunk update, {
    required String? runningTurnId,
    required AgentRuntimeScope runtimeScope,
  }) {
    final text = AcpContentCodec.textFromContent(update.content);
    if (text == null || text.isEmpty) {
      return GrokAcpMappedUpdate(unmatchedKind: update.kind);
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
      return const GrokAcpMappedUpdate();
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
      return GrokAcpMappedUpdate(unmatchedKind: update.kind);
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
      return const GrokAcpMappedUpdate();
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
      return const GrokAcpMappedUpdate();
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
      return const GrokAcpMappedUpdate();
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
      return const GrokAcpMappedUpdate();
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
    if (!terminal.accepted) {
      return const GrokAcpMappedUpdate();
    }

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
        AgentTurnCompletedEvent(
          sessionId: terminal.sessionId,
          turnId: terminal.turnId,
          status: terminal.status,
          duration: duration,
          errorMessage: terminal.status == AgentHistoryTurnStatus.failed
              ? update.stopReason
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
        normalized.contains('max_token') ||
        normalized.contains('max_turn')) {
      return AgentHistoryTurnStatus.failed;
    }
    return AgentHistoryTurnStatus.completed;
  }
}

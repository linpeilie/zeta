import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_file_change_tracker.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_plan_approval_adapter.dart';
import 'package:zeta/src/features/agent/data/mappers/claude_code_stream_identity.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/fallback_agent_ui_text_catalog.dart';

final _log = loggerFor('zeta.agent.claude_code.event_mapper');

/// 单帧 stream-json → 中立 [AgentEvent] 的映射结果。
final class ClaudeCodeMappedFrame {
  const ClaudeCodeMappedFrame({
    this.events = const <AgentEvent>[],
    this.ignoredType,
    this.ignoredReason,
  });

  final List<AgentEvent> events;

  /// 未识别或故意丢弃的帧 type（诊断用，不含 payload）。
  final String? ignoredType;
  final String? ignoredReason;
}

/// Claude Code stream-json 纯翻译层（T12 最小集）。
///
/// 身份一律问 [ClaudeCodeStreamIdentity]；未识别 type 只计数并丢弃，绝不 throw。
///
/// 覆盖：`system.init` / `assistant` text+thinking+tool_use /
/// `user.tool_result` / `result`（+ usage）。`ExitPlanMode` 交给
/// [planApprovalAdapter]，不会泄漏成普通工具卡。
final class ClaudeCodeEventMapper {
  ClaudeCodeEventMapper({
    required this.providerId,
    ClaudeCodeStreamIdentity? identity,
    ClaudeCodePlanApprovalAdapter? planApprovalAdapter,
    ClaudeCodeFileChangeTracker? fileChangeTracker,
    this.textCatalog = const FallbackAgentUiTextCatalog(),
  }) : identity = identity ?? ClaudeCodeStreamIdentity(),
       planApprovalAdapter =
           planApprovalAdapter ??
           ClaudeCodePlanApprovalAdapter(textCatalog: textCatalog),
       fileChangeTracker = fileChangeTracker ?? ClaudeCodeFileChangeTracker();

  final String providerId;
  final AgentUiTextCatalog textCatalog;
  final ClaudeCodeStreamIdentity identity;
  final ClaudeCodePlanApprovalAdapter planApprovalAdapter;
  final ClaudeCodeFileChangeTracker fileChangeTracker;

  int _unknownTypeDropped = 0;
  int _lateOrMissingTurnDropped = 0;
  int _malformedDropped = 0;
  final Map<AgentRuntimeScope, _ClaudeCodeInitHandshake> _initByRuntimeScope =
      <AgentRuntimeScope, _ClaudeCodeInitHandshake>{};

  /// 未识别 type 丢弃计数（诊断）。
  int get unknownTypeDropped => _unknownTypeDropped;

  /// 缺 turn / 终态后迟到内容丢弃计数。
  int get lateOrMissingTurnDropped => _lateOrMissingTurnDropped;

  /// 坏形状帧丢弃计数。
  int get malformedDropped => _malformedDropped;

  ClaudeCodeStreamIdentityDiagnostics get diagnostics => identity.diagnostics;

  /// 在写 stdin user 行之前由 Provider 调用，mint 的 [turnId] 整回合稳定。
  int beginTurn({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
    required String turnId,
  }) {
    fileChangeTracker.beginTurn(
      runtimeScope: runtimeScope,
      sessionId: sessionId,
    );
    final generation = identity.beginTurn(
      runtimeScope: runtimeScope,
      sessionId: sessionId,
      turnId: turnId,
    );
    planApprovalAdapter.beginTurn(sessionId: sessionId, turnId: turnId);
    return generation;
  }

  /// 映射一行 stream-json 对象。
  ///
  /// [runningTurnId] 为当前 active turn 的 mint id；`system.init` 不依赖它。
  /// [expectedSessionId] 是本次 peer 启动时请求的新建/恢复 session；首个 init
  /// 不匹配时 fail-closed 为错误事件，且该 runtime 不再接受后续 init。
  ClaudeCodeMappedFrame mapFrame({
    required Map<String, Object?> raw,
    required AgentRuntimeScope runtimeScope,
    String? runningTurnId,
    String? expectedSessionId,
  }) {
    final type = raw['type'];
    if (type is! String || type.isEmpty) {
      _malformedDropped += 1;
      return const ClaudeCodeMappedFrame(
        ignoredType: '<missing>',
        ignoredReason: 'missing type',
      );
    }

    try {
      return switch (type) {
        'system' => _mapSystem(
          raw,
          runtimeScope: runtimeScope,
          runningTurnId: runningTurnId,
          expectedSessionId: expectedSessionId,
        ),
        'assistant' => _mapAssistant(
          raw,
          runtimeScope: runtimeScope,
          runningTurnId: runningTurnId,
        ),
        'user' => _mapUser(
          raw,
          runtimeScope: runtimeScope,
          runningTurnId: runningTurnId,
        ),
        'result' => _mapResult(
          raw,
          runtimeScope: runtimeScope,
          runningTurnId: runningTurnId,
        ),
        // control_request 由 Provider + ControlRequestHandler 处理，不进 mapper。
        _ => _dropUnknown(type),
      };
    } catch (error, stackTrace) {
      // 守则：绝不 throw 阻断 pipeline；坏帧记诊断。
      _malformedDropped += 1;
      _log.w(
        'Claude Code mapper swallowed frame error '
        '(type=$type, ${error.runtimeType})',
        error: error,
        stackTrace: stackTrace,
      );
      return ClaudeCodeMappedFrame(
        ignoredType: type,
        ignoredReason: 'mapper exception ${error.runtimeType}',
      );
    }
  }

  void dispose() {
    _initByRuntimeScope.clear();
    planApprovalAdapter.clear();
    fileChangeTracker.dispose();
    identity.dispose();
  }

  /// 统一完成 identity 与 Claude-local tool tracker 生命周期。
  ClaudeCodeTerminalResolution completeTurn({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
    required String? runningTurnId,
    required AgentHistoryTurnStatus status,
    required ClaudeCodeTerminalSource source,
    String? eventId,
    String eventKind = 'result',
  }) {
    final terminal = identity.completeTurn(
      runtimeScope: runtimeScope,
      sessionId: sessionId,
      runningTurnId: runningTurnId,
      status: status,
      source: source,
      eventId: eventId,
      eventKind: eventKind,
    );
    if (terminal.accepted) {
      fileChangeTracker.completeTurn(
        runtimeScope: runtimeScope,
        sessionId: terminal.sessionId,
        turnId: terminal.turnId,
      );
    }
    return terminal;
  }

  void invalidateRuntime({
    required AgentRuntimeScope runtimeScope,
    required ClaudeCodeIdentityInvalidationReason reason,
  }) {
    fileChangeTracker.invalidateRuntime(runtimeScope);
    identity.invalidateRuntime(runtimeScope: runtimeScope, reason: reason);
  }

  ClaudeCodeMappedFrame _mapSystem(
    Map<String, Object?> raw, {
    required AgentRuntimeScope runtimeScope,
    required String? runningTurnId,
    required String? expectedSessionId,
  }) {
    final subtype = raw['subtype'];
    if (subtype == 'init') {
      return _mapSystemInit(
        raw,
        runtimeScope: runtimeScope,
        expectedSessionId: expectedSessionId,
      );
    }
    // thinking_tokens 等：丢弃
    return _dropUnknown('system/${subtype ?? '<none>'}');
  }

  ClaudeCodeMappedFrame _mapSystemInit(
    Map<String, Object?> raw, {
    required AgentRuntimeScope runtimeScope,
    required String? expectedSessionId,
  }) {
    final sessionId = _string(raw['session_id']);
    if (sessionId == null) {
      _malformedDropped += 1;
      return const ClaudeCodeMappedFrame(
        ignoredType: 'system/init',
        ignoredReason: 'missing session_id',
      );
    }
    final previous = _initByRuntimeScope[runtimeScope];
    if (previous != null) {
      if (!previous.accepted) {
        return const ClaudeCodeMappedFrame(
          ignoredType: 'system/init',
          ignoredReason: 'init handshake already rejected',
        );
      }
      if (previous.sessionId == sessionId) {
        return const ClaudeCodeMappedFrame(
          ignoredType: 'system/init',
          ignoredReason: 'duplicate init',
        );
      }
      _malformedDropped += 1;
      return ClaudeCodeMappedFrame(
        events: <AgentEvent>[
          AgentErrorEvent(
            message: textCatalog.sessionIdentityChanged('Claude Code'),
            code: 'claudeCodeSessionMismatch',
            sessionId: expectedSessionId,
          ),
        ],
      );
    }

    final expected = _string(expectedSessionId);
    final matchesExpected = expected == null || sessionId == expected;
    _initByRuntimeScope[runtimeScope] = _ClaudeCodeInitHandshake(
      sessionId: sessionId,
      accepted: matchesExpected,
    );
    if (!matchesExpected) {
      _malformedDropped += 1;
      return ClaudeCodeMappedFrame(
        events: <AgentEvent>[
          AgentErrorEvent(
            message: textCatalog.couldNotRestoreSession('Claude Code'),
            code: 'claudeCodeSessionMismatch',
            sessionId: expected,
          ),
        ],
      );
    }
    final model = _string(raw['model']);
    final cwd = _string(raw['cwd']);
    final sessionRaw = <String, Object?>{
      if (raw['claude_code_version'] != null)
        'claude_code_version': raw['claude_code_version'],
      if (raw['permissionMode'] != null)
        'permissionMode': raw['permissionMode'],
    };
    if (model != null) {
      sessionRaw['model'] = model;
    }
    if (cwd != null) {
      sessionRaw['cwd'] = cwd;
    }
    final session = AgentSession(
      id: sessionId,
      providerId: providerId,
      title: null,
      raw: sessionRaw,
    );
    return ClaudeCodeMappedFrame(
      events: <AgentEvent>[
        AgentSessionStartedEvent(session),
        AgentThreadStatusChangedEvent(
          threadId: sessionId,
          status: AgentThreadRuntimeStatus.idle,
        ),
      ],
    );
  }

  ClaudeCodeMappedFrame _mapAssistant(
    Map<String, Object?> raw, {
    required AgentRuntimeScope runtimeScope,
    required String? runningTurnId,
  }) {
    final sessionId = _string(raw['session_id']);
    if (sessionId == null) {
      _malformedDropped += 1;
      return const ClaudeCodeMappedFrame(
        ignoredType: 'assistant',
        ignoredReason: 'missing session_id',
      );
    }
    final message = _map(raw['message']);
    if (message == null) {
      _malformedDropped += 1;
      return const ClaudeCodeMappedFrame(
        ignoredType: 'assistant',
        ignoredReason: 'missing message',
      );
    }
    final sourceMessageId = _string(message['id']);
    final content = message['content'];
    if (content is! List<Object?>) {
      return const ClaudeCodeMappedFrame(
        ignoredType: 'assistant',
        ignoredReason: 'empty content',
      );
    }

    final frameEventId = _string(raw['uuid']);
    final events = <AgentEvent>[];
    for (var index = 0; index < content.length; index++) {
      final block = _map(content[index]);
      if (block == null) {
        continue;
      }
      final blockType = _string(block['type']);
      if (blockType == 'text') {
        final text = _string(block['text']) ?? '';
        final eventId = frameEventId == null
            ? null
            : '$frameEventId:text:$index';
        // resolveMessage 会关闭当前 reasoning phase（T15/T16 边界）。
        final resolved = identity.resolveMessage(
          runtimeScope: runtimeScope,
          sessionId: sessionId,
          runningTurnId: runningTurnId,
          sourceMessageId: sourceMessageId,
          eventId: eventId,
          eventKind: 'assistant.text',
        );
        if (resolved == null) {
          _lateOrMissingTurnDropped += 1;
          continue;
        }
        planApprovalAdapter.recordAssistantText(
          sessionId: resolved.sessionId,
          turnId: resolved.turnId,
          text: text,
        );
        // stream-json 的 assistant text 是完整快照，且不保证此前出现过正文 delta。
        // 先用同一 entryId 物化消息，再用权威快照完成它；共享 Store 仍保持
        // update-only 语义，不需要为 Claude Code 增加 Provider 分支。
        if (text.isNotEmpty) {
          events.add(
            AgentMessageDeltaEvent(
              messageId: resolved.entryId,
              sourceMessageId: sourceMessageId,
              delta: text,
              role: AgentMessageRole.agent,
              phase: AgentMessagePhase.response,
              status: AgentMessageStatus.completed,
              sessionId: resolved.sessionId,
              turnId: resolved.turnId,
              raw: const <String, Object?>{},
            ),
          );
        }
        events.add(
          AgentMessageUpdatedEvent(
            messageId: resolved.entryId,
            sourceMessageId: sourceMessageId,
            text: text,
            role: AgentMessageRole.agent,
            phase: AgentMessagePhase.response,
            status: AgentMessageStatus.completed,
            sessionId: resolved.sessionId,
            turnId: resolved.turnId,
            raw: const <String, Object?>{},
          ),
        );
        continue;
      }
      if (blockType == 'thinking') {
        final thinking = _string(block['thinking']) ?? '';
        final eventId = frameEventId == null
            ? null
            : '$frameEventId:thinking:$index';
        // sourceItemId 用 message.id：同 phase 连续 thinking 合并；
        // text/tool 打断后 identity 开新 phase entryId。
        final resolved = identity.resolveReasoning(
          runtimeScope: runtimeScope,
          sessionId: sessionId,
          runningTurnId: runningTurnId,
          sourceItemId: sourceMessageId,
          eventId: eventId,
          eventKind: 'assistant.thinking',
        );
        if (resolved == null) {
          _lateOrMissingTurnDropped += 1;
          continue;
        }
        events.add(
          AgentReasoningDeltaEvent(
            itemId: resolved.entryId,
            sourceItemId: sourceMessageId,
            kind: AgentReasoningDeltaKind.text,
            delta: thinking,
            sessionId: resolved.sessionId,
            turnId: resolved.turnId,
            raw: const <String, Object?>{},
          ),
        );
        continue;
      }
      if (blockType == 'tool_use') {
        final toolId = _string(block['id']);
        final toolName = _string(block['name']) ?? 'tool';
        if (toolId == null) {
          _malformedDropped += 1;
          continue;
        }
        final eventId = frameEventId == null
            ? null
            : '$frameEventId:tool_use:$index';
        final resolved = identity.resolveTool(
          runtimeScope: runtimeScope,
          sessionId: sessionId,
          runningTurnId: runningTurnId,
          toolCallId: toolId,
          eventId: eventId,
          eventKind: 'assistant.tool_use',
        );
        if (resolved == null) {
          _lateOrMissingTurnDropped += 1;
          continue;
        }
        final input = _map(block['input']) ?? const <String, Object?>{};
        if (toolName == 'ExitPlanMode') {
          planApprovalAdapter.recordExitPlanToolUse(
            toolUseId: toolId,
            input: input,
            sessionId: resolved.sessionId,
            turnId: resolved.turnId,
          );
          continue;
        }
        final locations = _locationsFromToolInput(input);
        final kind = _kindForClaudeToolName(toolName);
        final tracked = fileChangeTracker.recordToolUse(
          runtimeScope: runtimeScope,
          sessionId: resolved.sessionId,
          turnId: resolved.turnId,
          toolUseId: toolId,
          toolName: toolName,
          kind: kind,
          locations: locations,
          input: input,
        );
        events.add(
          AgentToolCallEvent(
            AgentToolCall(
              id: toolId,
              title: tracked.title,
              kind: tracked.kind,
              status: AgentToolStatus.inProgress,
              locations: tracked.locations,
              sessionId: resolved.sessionId,
              turnId: resolved.turnId,
              rawInput: tracked.rawInput,
              raw: const <String, Object?>{},
              fileChanges: tracked.fileChanges,
            ),
          ),
        );
        continue;
      }
    }
    return ClaudeCodeMappedFrame(events: events);
  }

  /// `user` 帧：仅处理 tool_result；其余（用户回显）静默丢弃。
  ClaudeCodeMappedFrame _mapUser(
    Map<String, Object?> raw, {
    required AgentRuntimeScope runtimeScope,
    required String? runningTurnId,
  }) {
    final sessionId = _string(raw['session_id']);
    if (sessionId == null) {
      _malformedDropped += 1;
      return const ClaudeCodeMappedFrame(
        ignoredType: 'user',
        ignoredReason: 'missing session_id',
      );
    }
    final message = _map(raw['message']);
    if (message == null) {
      return const ClaudeCodeMappedFrame(
        ignoredType: 'user',
        ignoredReason: 'missing message',
      );
    }
    final content = message['content'];
    if (content is! List<Object?>) {
      return const ClaudeCodeMappedFrame(
        ignoredType: 'user',
        ignoredReason: 'empty content',
      );
    }

    final frameEventId = _string(raw['uuid']);
    final events = <AgentEvent>[];
    for (var index = 0; index < content.length; index++) {
      final block = _map(content[index]);
      if (block == null) {
        continue;
      }
      final blockType = _string(block['type']);
      if (blockType != 'tool_result') {
        // 用户回显等：静默丢弃，避免 timeline 重复。
        continue;
      }
      final toolUseId = _string(block['tool_use_id']);
      if (toolUseId == null) {
        _malformedDropped += 1;
        continue;
      }
      if (planApprovalAdapter.shouldSuppressToolResult(toolUseId)) {
        continue;
      }
      final eventId = frameEventId == null
          ? null
          : '$frameEventId:tool_result:$index';
      final resolved = identity.resolveTool(
        runtimeScope: runtimeScope,
        sessionId: sessionId,
        runningTurnId: runningTurnId,
        toolCallId: toolUseId,
        eventId: eventId,
        eventKind: 'user.tool_result',
      );
      if (resolved == null) {
        _lateOrMissingTurnDropped += 1;
        continue;
      }
      final isError = block['is_error'] == true;
      final resultContent = _toolResultContent(block['content']);
      final tracked = fileChangeTracker.resolveToolResult(
        runtimeScope: runtimeScope,
        sessionId: resolved.sessionId,
        turnId: resolved.turnId,
        toolUseId: toolUseId,
      );
      events.add(
        AgentToolCallEvent(
          AgentToolCall(
            id: toolUseId,
            title: tracked?.title ?? toolUseId,
            kind: tracked?.kind ?? AgentToolKind.other,
            status: isError
                ? AgentToolStatus.failed
                : AgentToolStatus.completed,
            content: resultContent,
            locations: tracked?.locations ?? const <String>[],
            sessionId: resolved.sessionId,
            turnId: resolved.turnId,
            rawOutput: resultContent == null
                ? const <String, Object?>{}
                : <String, Object?>{'content': resultContent},
            rawInput: tracked?.rawInput ?? const <String, Object?>{},
            raw: const <String, Object?>{},
            fileChanges: tracked?.fileChanges,
          ),
        ),
      );
    }
    return ClaudeCodeMappedFrame(events: events);
  }

  ClaudeCodeMappedFrame _mapResult(
    Map<String, Object?> raw, {
    required AgentRuntimeScope runtimeScope,
    required String? runningTurnId,
  }) {
    final sessionId = _string(raw['session_id']);
    if (sessionId == null) {
      _malformedDropped += 1;
      return const ClaudeCodeMappedFrame(
        ignoredType: 'result',
        ignoredReason: 'missing session_id',
      );
    }
    final subtype = _string(raw['subtype']) ?? 'success';
    final status = _statusForResultSubtype(subtype);
    final frameEventId = _string(raw['uuid']);
    final terminal = completeTurn(
      runtimeScope: runtimeScope,
      sessionId: sessionId,
      runningTurnId: runningTurnId,
      status: status,
      source: ClaudeCodeTerminalSource.resultFrame,
      eventId: frameEventId,
      eventKind: 'result',
    );
    if (!terminal.accepted) {
      if (terminal.disposition == ClaudeCodeTerminalDisposition.missingScope) {
        _lateOrMissingTurnDropped += 1;
      }
      return ClaudeCodeMappedFrame(
        ignoredType: 'result',
        ignoredReason: 'terminal ${terminal.disposition.name}',
      );
    }
    planApprovalAdapter.completeTurn(
      sessionId: terminal.sessionId,
      turnId: terminal.turnId,
    );

    // usage 走 metadata 通道（允许 terminal 后幂等）；用独立 eventId 避免与 result 去重冲突。
    final usageRaw = _map(raw['usage']);
    AgentTokenUsageEvent? usageEvent;
    if (usageRaw != null) {
      final usageIdentity = identity.resolveMetadata(
        runtimeScope: runtimeScope,
        sessionId: sessionId,
        runningTurnId: terminal.turnId,
        eventId: frameEventId == null ? null : '$frameEventId:usage',
        eventKind: 'result.usage',
      );
      if (usageIdentity != null) {
        final input = _int(usageRaw['input_tokens']);
        final output = _int(usageRaw['output_tokens']);
        final cacheCreate = _int(usageRaw['cache_creation_input_tokens']);
        final cacheRead = _int(usageRaw['cache_read_input_tokens']);
        final cached = _sumOptional(cacheCreate, cacheRead);
        // Anthropic 的 cache_creation/cache_read 是独立于 input_tokens 的额外桶，
        // 不像 OpenAI/xAI 那样已被 total_tokens 隐含覆盖，总量必须显式把它加回来，
        // 否则大量走缓存的回合会被少算。
        usageEvent = AgentTokenUsageEvent(
          sessionId: usageIdentity.sessionId,
          turnId: usageIdentity.turnId,
          isSessionCumulative: false,
          tokenUsage: AgentTokenUsage(
            inputTokens: input,
            outputTokens: output,
            cachedInputTokens: cached,
            totalTokens: _sumOptional(_sumOptional(input, cached), output),
          ),
          raw: const <String, Object?>{},
        );
      }
    }

    final durationMs = _int(raw['duration_ms']);
    final errorMessage = status == AgentHistoryTurnStatus.failed
        ? (_string(raw['result']) ?? subtype)
        : null;

    return ClaudeCodeMappedFrame(
      events: <AgentEvent>[
        ?usageEvent,
        AgentTurnCompletedEvent(
          sessionId: terminal.sessionId,
          turnId: terminal.turnId,
          status: terminal.status,
          errorCode: status == AgentHistoryTurnStatus.completed
              ? null
              : subtype,
          errorMessage: errorMessage,
          duration: durationMs == null
              ? null
              : Duration(milliseconds: durationMs),
          completedAt: DateTime.now(),
          raw: const <String, Object?>{},
        ),
      ],
    );
  }

  ClaudeCodeMappedFrame _dropUnknown(String type) {
    _unknownTypeDropped += 1;
    _log.t('Dropped unrecognized stream-json type=$type');
    return ClaudeCodeMappedFrame(
      ignoredType: type,
      ignoredReason: 'unrecognized type',
    );
  }

  static AgentHistoryTurnStatus _statusForResultSubtype(String subtype) {
    return switch (subtype) {
      'success' => AgentHistoryTurnStatus.completed,
      'error_max_turns' => AgentHistoryTurnStatus.interrupted,
      'error_during_execution' => AgentHistoryTurnStatus.failed,
      _ => AgentHistoryTurnStatus.failed,
    };
  }

  static String? _string(Object? value) {
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    return null;
  }

  static int? _int(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }

  static int? _sumOptional(int? a, int? b) {
    if (a == null && b == null) {
      return null;
    }
    return (a ?? 0) + (b ?? 0);
  }

  static Map<String, Object?>? _map(Object? value) {
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          if (entry.key is String) entry.key as String: entry.value,
      };
    }
    return null;
  }

  /// Claude Code 工具名 → 中立 [AgentToolKind]。
  static AgentToolKind _kindForClaudeToolName(String name) {
    final normalized = name.trim().toLowerCase();
    return switch (normalized) {
      'read' => AgentToolKind.read,
      'edit' || 'write' || 'notebookedit' || 'multiedit' => AgentToolKind.edit,
      'bash' || 'shell' || 'powershell' => AgentToolKind.execute,
      'glob' || 'grep' || 'search' || 'toolsearch' => AgentToolKind.search,
      'webfetch' || 'websearch' || 'fetch' => AgentToolKind.fetch,
      'delete' || 'rm' => AgentToolKind.delete,
      'move' || 'rename' => AgentToolKind.move,
      _ => parseAgentToolKind(normalized),
    };
  }

  static List<String> _locationsFromToolInput(Map<String, Object?> input) {
    final locations = <String>[];
    for (final key in const <String>[
      'file_path',
      'path',
      'filePath',
      'notebook_path',
    ]) {
      final value = _string(input[key]);
      if (value != null) {
        locations.add(value);
      }
    }
    return List<String>.unmodifiable(locations);
  }

  static String? _toolResultContent(Object? content) {
    if (content is String) {
      final trimmed = content.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    if (content is List) {
      final parts = <String>[];
      for (final item in content) {
        if (item is String) {
          final t = item.trim();
          if (t.isNotEmpty) {
            parts.add(t);
          }
        } else if (item is Map) {
          final text = _string(item['text']);
          if (text != null) {
            parts.add(text);
          }
        }
      }
      if (parts.isEmpty) {
        return null;
      }
      return parts.join('\n');
    }
    return null;
  }
}

final class _ClaudeCodeInitHandshake {
  const _ClaudeCodeInitHandshake({
    required this.sessionId,
    required this.accepted,
  });

  final String sessionId;
  final bool accepted;
}

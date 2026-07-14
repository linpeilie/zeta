import 'package:zeta/src/features/agent/data/mappers/acp_content_codec.dart';
import 'package:zeta/src/features/agent/data/mappers/acp_session_update_mapper.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// 收集 `session/load` 期间的标准 ACP `session/update`，并重建中立历史快照。
///
/// ACP 要求历史通知在 `session/load` 响应前发送。调用方应只在请求进行期间把目标
/// session 的通知交给本收集器，响应返回后调用 [build] 冻结结果。
class AcpSessionReplayCollector {
  AcpSessionReplayCollector({
    required this.threadId,
    this.mapper = const AcpSessionUpdateMapper(),
  });

  final String threadId;
  final AcpSessionUpdateMapper mapper;
  final List<_ReplayTurnBuilder> _turns = <_ReplayTurnBuilder>[];
  _ReplayTurnBuilder? _current;

  /// 记录一条标准 `session/update` params；其他 session 或未知更新会被安全忽略。
  void record(Map<String, Object?> params) {
    if (params['sessionId']?.toString() != threadId) {
      return;
    }
    final update = _asMap(params['update']);
    if (update == null) {
      return;
    }
    final kind = update['sessionUpdate']?.toString();
    if (kind == 'user_message_chunk') {
      _recordUserMessage(params: params, update: update);
      return;
    }

    if (_requiresTurn(kind)) {
      _ensureTurn(params: params, update: update);
    }
    final current = _current;
    final mapped = mapper.mapSessionUpdate(
      params: params,
      runningTurnId: current?.id,
    );
    for (final event in mapped.events) {
      switch (event) {
        case AgentMessageDeltaEvent():
          current?.appendMessage(
            id: event.messageId,
            role: event.role,
            text: event.delta,
            raw: event.raw,
          );
        case AgentReasoningDeltaEvent():
          if (event.delta.isNotEmpty) {
            current?.appendThought(
              id: event.itemId,
              text: event.delta,
              raw: event.raw,
            );
          }
        case AgentToolCallEvent():
          current?.upsertTool(event.toolCall);
        case AgentPlanUpdatedEvent():
          final text = event.entries
              .map((entry) {
                final status = entry.status?.trim();
                return status == null || status.isEmpty
                    ? '- ${entry.content}'
                    : '- [$status] ${entry.content}';
              })
              .join('\n');
          if (text.isNotEmpty) {
            current?.appendMessage(
              id: 'acp-plan-${current.id}-${current.entryCount}',
              role: AgentMessageRole.agent,
              text: text,
              raw: <String, Object?>{'type': 'plan', ...update},
            );
          }
        case AgentTokenUsageEvent():
          current?.tokenUsage = event.tokenUsage;
          current?.tokenUsageIsSessionCumulative = event.isSessionCumulative;
        case AgentTurnCompletedEvent():
          if (current != null) {
            current.status = event.status;
            current.duration = event.duration;
            current.errorMessage = event.errorMessage;
            _current = null;
          }
        default:
          // 历史快照只消费消息、思考、工具、计划、用量和回合终态。
          break;
      }
    }
  }

  /// 冻结当前已收集的历史。没有显式终态的 replay turn 视为已完成历史。
  AgentThreadHistorySnapshot build({
    Map<String, Object?> raw = const <String, Object?>{},
  }) {
    _current = null;
    final turns = _turns
        .where((turn) => turn.hasContent)
        .map((turn) => turn.build())
        .toList(growable: false);
    return AgentThreadHistorySnapshot(
      threadId: threadId,
      turns: List<AgentHistoryTurn>.unmodifiable(turns),
      currentTurn: turns.isEmpty ? null : turns.last,
      raw: raw,
    );
  }

  void _recordUserMessage({
    required Map<String, Object?> params,
    required Map<String, Object?> update,
  }) {
    final promptKey = _promptKey(params: params, update: update);
    final current = _current;
    if (current != null &&
        current.hasContent &&
        !current.acceptsUserPrompt(promptKey)) {
      _current = null;
    }
    final turn = _ensureTurn(params: params, update: update);
    turn.noteUserPrompt(promptKey);
    final text = _displayContent(update['content']);
    if (text.isEmpty) {
      return;
    }
    final messageId = update['messageId']?.toString() ?? 'acp-user-${turn.id}';
    turn.appendUserMessage(id: messageId, text: text, raw: update);
  }

  _ReplayTurnBuilder _ensureTurn({
    required Map<String, Object?> params,
    required Map<String, Object?> update,
  }) {
    final existing = _current;
    if (existing != null) {
      return existing;
    }
    final promptId = _promptId(params: params, update: update);
    final id = promptId ?? 'acp-replay-turn-${_turns.length + 1}-$threadId';
    final created = _ReplayTurnBuilder(id: id);
    _turns.add(created);
    _current = created;
    return created;
  }

  bool _requiresTurn(String? kind) {
    return switch (kind) {
      'agent_message_chunk' ||
      'agent_thought_chunk' ||
      'tool_call' ||
      'tool_call_update' ||
      'plan' ||
      'usage_update' ||
      'turn_completed' => true,
      _ => false,
    };
  }
}

class _ReplayTurnBuilder {
  _ReplayTurnBuilder({required this.id});

  final String id;
  final List<AgentHistoryEntry> _entries = <AgentHistoryEntry>[];
  final Map<String, int> _messageIndexById = <String, int>{};
  final Map<String, int> _toolIndexById = <String, int>{};
  String? _userPromptKey;
  int? _userMessageIndex;
  bool _hasAgentContent = false;

  AgentHistoryTurnStatus status = AgentHistoryTurnStatus.completed;
  AgentTokenUsage? tokenUsage;
  bool tokenUsageIsSessionCumulative = true;
  Duration? duration;
  String? errorMessage;

  bool get hasContent => _entries.isNotEmpty;
  int get entryCount => _entries.length;

  bool acceptsUserPrompt(String? promptKey) {
    if (_userMessageIndex == null) {
      return true;
    }
    if (promptKey != null && promptKey == _userPromptKey) {
      return true;
    }
    // 没有 prompt/message id 时，只把连续 user chunk 视为同一条消息。
    return promptKey == null && !_hasAgentContent;
  }

  void noteUserPrompt(String? promptKey) {
    if (promptKey != null) {
      _userPromptKey ??= promptKey;
    }
  }

  void appendUserMessage({
    required String id,
    required String text,
    required Map<String, Object?> raw,
  }) {
    final existingIndex = _userMessageIndex;
    if (existingIndex == null) {
      _userMessageIndex = _entries.length;
      _messageIndexById[id] = _entries.length;
      _entries.add(
        AgentHistoryMessageEntry(
          id: id,
          role: AgentMessageRole.user,
          text: text,
          status: AgentMessageStatus.completed,
          raw: raw,
        ),
      );
      return;
    }
    final existing = _entries[existingIndex] as AgentHistoryMessageEntry;
    _entries[existingIndex] = AgentHistoryMessageEntry(
      id: existing.id,
      role: AgentMessageRole.user,
      text: _mergeText(existing.text, text, separator: '\n'),
      status: AgentMessageStatus.completed,
      raw: raw,
    );
  }

  void appendMessage({
    required String id,
    required AgentMessageRole role,
    required String text,
    required Map<String, Object?> raw,
  }) {
    if (text.isEmpty) {
      return;
    }
    _hasAgentContent = _hasAgentContent || role == AgentMessageRole.agent;
    final existingIndex = _messageIndexById[id];
    if (existingIndex == null) {
      _messageIndexById[id] = _entries.length;
      _entries.add(
        AgentHistoryMessageEntry(
          id: id,
          role: role,
          text: text,
          status: AgentMessageStatus.completed,
          raw: raw,
        ),
      );
      return;
    }
    final existing = _entries[existingIndex] as AgentHistoryMessageEntry;
    _entries[existingIndex] = AgentHistoryMessageEntry(
      id: id,
      role: role,
      text: _mergeText(existing.text, text),
      status: AgentMessageStatus.completed,
      raw: raw,
    );
  }

  void appendThought({
    required String id,
    required String text,
    required Map<String, Object?> raw,
  }) {
    _hasAgentContent = true;
    final existingIndex = _toolIndexById[id];
    if (existingIndex == null) {
      _toolIndexById[id] = _entries.length;
      _entries.add(
        AgentHistoryToolEntry(
          toolCall: AgentToolCall(
            id: id,
            title: 'Thinking',
            kind: AgentToolKind.think,
            status: AgentToolStatus.completed,
            content: text,
            turnId: this.id,
            raw: raw,
          ),
        ),
      );
      return;
    }
    final existing = _entries[existingIndex] as AgentHistoryToolEntry;
    _entries[existingIndex] = AgentHistoryToolEntry(
      toolCall: existing.toolCall.copyWith(
        content: _mergeText(existing.toolCall.content ?? '', text),
        status: AgentToolStatus.completed,
        raw: raw,
      ),
    );
  }

  void upsertTool(AgentToolCall tool) {
    _hasAgentContent = true;
    final existingIndex = _toolIndexById[tool.id];
    final next = existingIndex == null
        ? tool
        : _mergeTool(
            (_entries[existingIndex] as AgentHistoryToolEntry).toolCall,
            tool,
          );
    if (existingIndex == null) {
      _toolIndexById[tool.id] = _entries.length;
      _entries.add(AgentHistoryToolEntry(toolCall: next));
    } else {
      _entries[existingIndex] = AgentHistoryToolEntry(toolCall: next);
    }
  }

  AgentHistoryTurn build() {
    return AgentHistoryTurn(
      id: id,
      entries: List<AgentHistoryEntry>.unmodifiable(_entries),
      status: status,
      duration: duration,
      tokenUsage: tokenUsage,
      tokenUsageIsSessionCumulative: tokenUsageIsSessionCumulative,
      errorMessage: errorMessage,
    );
  }
}

AgentToolCall _mergeTool(AgentToolCall previous, AgentToolCall next) {
  return AgentToolCall(
    id: next.id,
    title: next.title.isNotEmpty ? next.title : previous.title,
    kind: next.kind == AgentToolKind.other ? previous.kind : next.kind,
    status: next.status,
    content: next.content?.isNotEmpty == true ? next.content : previous.content,
    locations: next.locations.isNotEmpty ? next.locations : previous.locations,
    sessionId: next.sessionId ?? previous.sessionId,
    turnId: next.turnId ?? previous.turnId,
    rawInput: next.rawInput.isNotEmpty ? next.rawInput : previous.rawInput,
    rawOutput: next.rawOutput.isNotEmpty ? next.rawOutput : previous.rawOutput,
    raw: next.raw.isNotEmpty ? next.raw : previous.raw,
  );
}

String _mergeText(String previous, String next, {String separator = ''}) {
  if (next.isEmpty || previous == next || previous.endsWith(next)) {
    return previous;
  }
  if (previous.isEmpty || next.startsWith(previous)) {
    return next;
  }
  return '$previous$separator$next';
}

String _displayContent(Object? value) {
  final text = AcpContentCodec.textFromContent(value);
  if (text != null) {
    return text;
  }
  final map = _asMap(value);
  return switch (map?['type']?.toString()) {
    'image' => '[Image]',
    'resource_link' =>
      '[Resource: ${map?['name']?.toString() ?? map?['uri']?.toString() ?? 'unknown'}]',
    _ => '',
  };
}

String? _promptId({
  required Map<String, Object?> params,
  required Map<String, Object?> update,
}) {
  final paramsMeta = _asMap(params['_meta']);
  final updateMeta = _asMap(update['_meta']);
  return updateMeta?['promptId']?.toString() ??
      paramsMeta?['promptId']?.toString() ??
      update['promptId']?.toString() ??
      update['prompt_id']?.toString();
}

String? _promptKey({
  required Map<String, Object?> params,
  required Map<String, Object?> update,
}) {
  final promptId = _promptId(params: params, update: update);
  if (promptId != null && promptId.isNotEmpty) {
    return 'prompt:$promptId';
  }
  final messageId = update['messageId']?.toString();
  if (messageId != null && messageId.isNotEmpty) {
    return 'message:$messageId';
  }
  return null;
}

Map<String, Object?>? _asMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  return value.map((key, item) => MapEntry(key.toString(), item as Object?));
}

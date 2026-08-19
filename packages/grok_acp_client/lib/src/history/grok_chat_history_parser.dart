import 'dart:convert';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:grok_acp_client/src/history/grok_user_content_parser.dart';

/// 从 Grok `chat_history.jsonl` 降级重建多回合历史。
///
/// 过滤 system / system-reminder / user_info 等合成上下文，
/// 以带 `<user_query>` 或 `prompt_index` 的用户消息作为 turn 边界。
class GrokChatHistoryParser {
  const GrokChatHistoryParser();

  AgentThreadHistorySnapshot parse({
    required String threadId,
    required String content,
    Map<String, Object?> raw = const <String, Object?>{},
  }) {
    final turns = <_ChatTurnBuilder>[];
    _ChatTurnBuilder? current;
    var lineNo = 0;
    var thoughtSeq = 0;
    var toolSeq = 0;

    void ensureTurn({String? preferredId}) {
      if (current != null) {
        return;
      }
      final id = preferredId ?? 'grok-chat-turn-${turns.length + 1}-$threadId';
      current = _ChatTurnBuilder(id: id);
      turns.add(current!);
    }

    void closeTurn() {
      current = null;
    }

    for (final line in const LineSplitter().convert(content)) {
      lineNo += 1;
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      Map<String, Object?> map;
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is! Map) {
          continue;
        }
        map = decoded.map(
          (key, value) => MapEntry(key.toString(), value as Object?),
        );
      } on Object catch (_) {
        continue;
      }

      final type = map['type']?.toString() ?? '';
      if (type == 'system') {
        continue;
      }

      final text = _extractTextContent(map['content']);
      if (text == null) {
        continue;
      }

      switch (type) {
        case 'user':
          if (_isSyntheticUserContext(text)) {
            continue;
          }
          final userContent = parseGrokUserContent(
            _extractUserQuery(text) ?? text.trim(),
          );
          if (userContent.text.isEmpty && userContent.localImagePaths.isEmpty) {
            continue;
          }
          if (current != null && current!.hasContent) {
            closeTurn();
          }
          final promptIndex = map['prompt_index'];
          ensureTurn(
            preferredId: promptIndex == null
                ? null
                : 'grok-prompt-$promptIndex-$threadId',
          );
          current!.addMessage(
            AgentHistoryMessageEntry(
              id: 'grok-hist-user-$threadId-$lineNo',
              role: AgentMessageRole.user,
              text: userContent.text,
              status: AgentMessageStatus.completed,
              localImagePaths: userContent.localImagePaths,
              raw: map,
            ),
          );

        case 'assistant':
          final cleaned = text.trim();
          if (cleaned.isEmpty) {
            continue;
          }
          ensureTurn();
          current!.addMessage(
            AgentHistoryMessageEntry(
              id: 'grok-hist-agent-$threadId-$lineNo',
              role: AgentMessageRole.agent,
              text: cleaned,
              status: AgentMessageStatus.completed,
              raw: map,
            ),
          );

        case 'reasoning':
          final cleaned = text.trim();
          if (cleaned.isEmpty) {
            continue;
          }
          ensureTurn();
          thoughtSeq += 1;
          current!.addTool(
            AgentToolCall(
              id: 'grok-hist-thought-$threadId-$thoughtSeq',
              title: 'Thinking',
              kind: AgentToolKind.think,
              status: AgentToolStatus.completed,
              content: cleaned,
              raw: map,
            ),
          );

        case 'tool_result':
        case 'tool':
        case 'function_call_output':
          final cleaned = text.trim();
          if (cleaned.isEmpty) {
            continue;
          }
          ensureTurn();
          toolSeq += 1;
          final title =
              map['name']?.toString() ??
              map['tool_name']?.toString() ??
              'Tool result';
          current!.addTool(
            AgentToolCall(
              id: 'grok-hist-tool-$threadId-$toolSeq',
              title: title,
              status: AgentToolStatus.completed,
              content: cleaned,
              raw: map,
            ),
          );

        default:
          // 未知类型：若有可见文本且非合成上下文，归入 agent 旁白。
          final cleaned = text.trim();
          if (cleaned.isEmpty || _isSyntheticUserContext(cleaned)) {
            continue;
          }
          ensureTurn();
          current!.addMessage(
            AgentHistoryMessageEntry(
              id: 'grok-hist-other-$threadId-$lineNo',
              role: AgentMessageRole.agent,
              text: cleaned,
              status: AgentMessageStatus.completed,
              raw: map,
            ),
          );
      }
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
}

class _ChatTurnBuilder {
  _ChatTurnBuilder({required this.id});

  final String id;
  final List<AgentHistoryEntry> entries = <AgentHistoryEntry>[];

  bool get hasContent => entries.isNotEmpty;

  void addMessage(AgentHistoryMessageEntry entry) => entries.add(entry);

  void addTool(AgentToolCall tool) =>
      entries.add(AgentHistoryToolEntry(toolCall: tool));

  AgentHistoryTurn build() {
    return AgentHistoryTurn(
      id: id,
      entries: List<AgentHistoryEntry>.unmodifiable(entries),
      status: AgentHistoryTurnStatus.completed,
    );
  }
}

bool _isSyntheticUserContext(String text) {
  final trimmed = text.trimLeft();
  if (trimmed.contains('<system-reminder>')) {
    return true;
  }
  if (trimmed.contains('<user_info>')) {
    return true;
  }
  if (trimmed.contains('<git_status>')) {
    return true;
  }
  // 仅有系统上下文包装、没有真实 user_query 时跳过。
  if (trimmed.contains('<user_query>')) {
    return false;
  }
  if (trimmed.startsWith('You are Grok')) {
    return true;
  }
  return false;
}

String? _extractUserQuery(String text) {
  final match = RegExp(
    r'<user_query>\s*([\s\S]*?)\s*</user_query>',
    multiLine: true,
  ).firstMatch(text);
  final body = match?.group(1)?.trim();
  if (body == null || body.isEmpty) {
    return null;
  }
  return body;
}

String? _extractTextContent(Object? content) {
  if (content is String) {
    return content;
  }
  if (content is List) {
    final buffer = StringBuffer();
    for (final item in content) {
      if (item is Map) {
        final map = item.map(
          (key, value) => MapEntry(key.toString(), value as Object?),
        );
        if (map['type']?.toString() == 'text') {
          final text = map['text']?.toString();
          if (text != null) {
            buffer.write(text);
          }
        }
      } else if (item is String) {
        buffer.write(item);
      }
    }
    final text = buffer.toString();
    return text.isEmpty ? null : text;
  }
  if (content is Map) {
    final map = content.map(
      (key, value) => MapEntry(key.toString(), value as Object?),
    );
    return map['text']?.toString() ?? map['content']?.toString();
  }
  return null;
}

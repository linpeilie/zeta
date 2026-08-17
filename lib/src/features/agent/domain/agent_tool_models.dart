import 'package:zeta/src/features/agent/domain/agent_file_change_models.dart';

export 'package:zeta/src/features/agent/domain/agent_file_change_models.dart';

/// Agent 工具调用的中立分类。
///
/// Codex、ACP 或其他 CLI 的原始 item/tool 类型会先映射到这里，再交给 UI 渲染。
enum AgentToolKind {
  read,
  edit,
  delete,
  move,
  search,
  execute,
  think,
  fetch,
  other,
}

/// 工具调用生命周期状态。
enum AgentToolStatus { pending, inProgress, completed, failed, cancelled }

/// 计划步骤的中立状态。
enum AgentPlanEntryStatus { pending, inProgress, completed, unknown }

/// 计划列表中的单个条目。
class AgentPlanEntry {
  const AgentPlanEntry({
    required this.content,
    this.id,
    this.status,
    this.priority,
  });

  /// Provider 提供的稳定 todo id；旧 ACP plan 条目可以为空。
  final String? id;

  /// 计划条目内容。
  final String content;

  /// provider 原始状态，例如 pending/in_progress/completed。
  final String? status;

  /// provider 原始优先级。
  final String? priority;

  /// 将不同 Provider 的原始状态规范化为统一计划状态。
  AgentPlanEntryStatus get normalizedStatus {
    final normalized = status
        ?.trim()
        .replaceAll(RegExp(r'[^a-zA-Z]'), '')
        .toLowerCase();
    return switch (normalized) {
      'pending' => AgentPlanEntryStatus.pending,
      'inprogress' || 'running' || 'started' => AgentPlanEntryStatus.inProgress,
      'completed' || 'complete' || 'done' => AgentPlanEntryStatus.completed,
      _ => AgentPlanEntryStatus.unknown,
    };
  }
}

/// Provider 上报的工具调用。
///
/// [rawInput]、[rawOutput] 和 [raw] 保留原始协议字段，方便调试和后续补齐映射。
/// [startedAt] / [completedAt] / [duration] 由客户端 timeline 维护，用于
/// 进行中 elapsed 与终态冻结展示；mapper 通常不填写。
class AgentToolCall {
  const AgentToolCall({
    required this.id,
    required this.title,
    this.kind = AgentToolKind.other,
    this.status = AgentToolStatus.pending,
    this.content,
    this.locations = const <String>[],
    this.sessionId,
    this.turnId,
    this.startedAt,
    this.completedAt,
    this.duration,
    this.rawInput = const <String, Object?>{},
    this.rawOutput = const <String, Object?>{},
    this.raw = const <String, Object?>{},
    this.fileChanges,
  });

  /// 工具调用 id。
  final String id;

  /// Provider 原始/映射标题；可能是 opaque `call-...` id。
  ///
  /// UI 与活动条应优先使用 [AgentToolCallUiText.displayTitle]。
  final String title;

  /// 中立工具分类。
  final AgentToolKind kind;

  /// 工具生命周期状态。
  final AgentToolStatus status;

  /// 工具正文，例如命令、输出片段或 patch 摘要。
  final String? content;

  /// 工具涉及的文件或位置。
  final List<String> locations;

  /// 可选会话 id，用于将实时事件路由到当前 thread。
  final String? sessionId;

  /// 可选回合 id，用于将实时事件路由到当前 turn。
  final String? turnId;

  /// 本地观测到的开始时间（首次 pending/inProgress 或首条 reasoning）。
  final DateTime? startedAt;

  /// 本地观测到的结束时间。
  final DateTime? completedAt;

  /// 终态冻结耗时；进行中为 null，由 UI 用 [startedAt] 现算。
  final Duration? duration;

  /// 原始输入 payload。
  final Map<String, Object?> rawInput;

  /// 原始输出 payload。
  final Map<String, Object?> rawOutput;

  /// 完整原始事件 payload。
  final Map<String, Object?> raw;

  /// Provider adapter 产出的完整、累计文件变更快照。
  ///
  /// `null` 表示本次工具事件没有结构化文件变更证据；空快照表示权威清空。
  final AgentFileChangeSnapshot? fileChanges;

  bool get isTerminalStatus =>
      status == AgentToolStatus.completed ||
      status == AgentToolStatus.failed ||
      status == AgentToolStatus.cancelled;

  bool get isActiveStatus =>
      status == AgentToolStatus.pending || status == AgentToolStatus.inProgress;

  AgentToolCall copyWith({
    String? id,
    String? title,
    AgentToolKind? kind,
    AgentToolStatus? status,
    String? content,
    List<String>? locations,
    String? sessionId,
    String? turnId,
    DateTime? startedAt,
    DateTime? completedAt,
    Duration? duration,
    Map<String, Object?>? rawInput,
    Map<String, Object?>? rawOutput,
    Map<String, Object?>? raw,
    AgentFileChangeSnapshot? fileChanges,
    bool clearContent = false,
    bool clearFileChanges = false,
  }) {
    return AgentToolCall(
      id: id ?? this.id,
      title: title ?? this.title,
      kind: kind ?? this.kind,
      status: status ?? this.status,
      content: clearContent ? null : (content ?? this.content),
      locations: locations ?? this.locations,
      sessionId: sessionId ?? this.sessionId,
      turnId: turnId ?? this.turnId,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      duration: duration ?? this.duration,
      rawInput: rawInput ?? this.rawInput,
      rawOutput: rawOutput ?? this.rawOutput,
      raw: raw ?? this.raw,
      fileChanges: clearFileChanges ? null : (fileChanges ?? this.fileChanges),
    );
  }
}

/// 判断工具标题是否为无信息的 opaque id（如 `call-abc123`）。
///
/// Grok 等 ACP agent 常省略 `title`，客户端若回退到 `toolCallId` 会把侧栏/
/// 时间线刷成一串 call-...。
bool isOpaqueAgentToolCallTitle(String title, {String? toolCallId}) {
  final trimmed = title.trim();
  if (trimmed.isEmpty) {
    return true;
  }
  if (toolCallId != null && trimmed == toolCallId.trim()) {
    return true;
  }
  final lower = trimmed.toLowerCase();
  if (RegExp(r'^call[-_][0-9a-z]+$', caseSensitive: false).hasMatch(lower)) {
    return true;
  }
  if (RegExp(
    r'^(tool[_-]?call|tc)[-_]?[0-9a-z]+$',
    caseSensitive: false,
  ).hasMatch(lower)) {
    return true;
  }
  // UUID / 长 hex 样式 id
  if (RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  ).hasMatch(lower)) {
    return true;
  }
  return false;
}

/// 判断工具标题是否缺少可识别的动作或目标。
///
/// ACP 的增量更新经常只携带状态；这些占位标题不能覆盖同一调用先前已经收到的
/// 工具名、命令或查询。
bool isNonInformativeAgentToolCallTitle(String title, {String? toolCallId}) {
  if (isOpaqueAgentToolCallTitle(title, toolCallId: toolCallId)) {
    return true;
  }
  return switch (title.trim().toLowerCase()) {
    'tool call' ||
    'mcp tool' ||
    'file change' ||
    'command output' ||
    'tool progress' ||
    '工具调用' ||
    '操作' => true,
    _ => false,
  };
}

/// 从 ACP kind 字符串解析 [AgentToolKind]（兼容 PascalCase）。
AgentToolKind parseAgentToolKind(String? kind) {
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

/// 构建简短但具体的工具展示标题。
///
/// 优先级：
/// 1. provider 给出的非 opaque [title]
/// 2. `类型 · 路径/命令/查询`（来自 locations / rawInput）
/// 3. 仅类型标签
/// 4. 「操作」（绝不回退到 call- id）
String buildAgentToolCallDisplayTitle({
  required String toolCallId,
  required String Function(AgentToolKind kind) kindLabel,
  String? title,
  AgentToolKind kind = AgentToolKind.other,
  String? kindRaw,
  List<String> locations = const <String>[],
  Map<String, Object?> rawInput = const <String, Object?>{},
}) {
  final resolvedKind = kind != AgentToolKind.other
      ? kind
      : parseAgentToolKind(kindRaw);
  final explicit = title?.trim();
  if (explicit != null &&
      explicit.isNotEmpty &&
      !isNonInformativeAgentToolCallTitle(explicit, toolCallId: toolCallId)) {
    return explicit;
  }

  final detail = _toolCallDetail(locations: locations, rawInput: rawInput);
  final resolvedKindLabel = kindLabel(resolvedKind);

  if (detail != null && detail.isNotEmpty) {
    // other 类型时 detail 本身往往已足够（命令/路径）。
    if (resolvedKind == AgentToolKind.other) {
      return detail;
    }
    return '$resolvedKindLabel · $detail';
  }
  return resolvedKindLabel;
}

String? _toolCallDetail({
  required List<String> locations,
  required Map<String, Object?> rawInput,
}) {
  final fromInput = _detailFromRawInput(rawInput);
  if (fromInput != null) {
    return fromInput;
  }
  if (locations.isEmpty) {
    return null;
  }
  return _shortenPath(locations.first);
}

String? _detailFromRawInput(Map<String, Object?> rawInput) {
  if (rawInput.isEmpty) {
    return null;
  }

  const preferredKeys = <String>[
    'command',
    'cmd',
    'shell',
    'script',
    'query',
    'pattern',
    'search',
    'url',
    'uri',
    'path',
    'file',
    'file_path',
    'filePath',
    'target',
    'target_path',
    'targetPath',
    'name',
    'tool',
    'toolName',
    'tool_name',
    'description',
  ];

  for (final key in preferredKeys) {
    final value = rawInput[key];
    final text = _nonEmptyString(value);
    if (text != null) {
      return _isPathLikeKey(key) ? _shortenPath(text) : _shortenText(text);
    }
  }

  // 常见嵌套：{ arguments: { path: ... } } 或 JSON 字符串参数。
  final nested =
      rawInput['arguments'] ?? rawInput['input'] ?? rawInput['params'];
  if (nested is Map) {
    final nestedMap = nested.map(
      (key, value) => MapEntry(key.toString(), value as Object?),
    );
    final nestedDetail = _detailFromRawInput(nestedMap);
    if (nestedDetail != null) {
      return nestedDetail;
    }
  } else {
    final nestedText = _nonEmptyString(nested);
    if (nestedText != null) {
      return _shortenText(nestedText);
    }
  }

  return null;
}

bool _isPathLikeKey(String key) {
  final lower = key.toLowerCase();
  return lower.contains('path') || lower == 'file' || lower == 'target';
}

String? _nonEmptyString(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  if (value is List) {
    final parts = value
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) {
      return null;
    }
    return parts.join(' ');
  }
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

String _shortenPath(String path) {
  final normalized = path.replaceAll('\\', '/').trim();
  if (normalized.isEmpty) {
    return path;
  }
  final segments = normalized
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
  if (segments.isEmpty) {
    return _shortenText(path);
  }
  if (segments.length == 1) {
    return _shortenText(segments.single);
  }
  // 保留末两段，便于区分同名文件。
  final tail = segments.length >= 2
      ? '${segments[segments.length - 2]}/${segments.last}'
      : segments.last;
  return _shortenText(tail);
}

String _shortenText(String text, {int maxChars = 72}) {
  final collapsed = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (collapsed.length <= maxChars) {
    return collapsed;
  }
  return '${collapsed.substring(0, maxChars - 1)}…';
}

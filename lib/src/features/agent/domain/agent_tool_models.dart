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

/// 计划列表中的单个条目。
class AgentPlanEntry {
  const AgentPlanEntry({required this.content, this.status, this.priority});

  /// 计划条目内容。
  final String content;

  /// provider 原始状态，例如 pending/in_progress/completed。
  final String? status;

  /// provider 原始优先级。
  final String? priority;
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
  });

  /// 工具调用 id。
  final String id;

  /// UI 展示标题。
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
    bool clearContent = false,
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
    );
  }
}

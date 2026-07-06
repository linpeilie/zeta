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

  /// 原始输入 payload。
  final Map<String, Object?> rawInput;

  /// 原始输出 payload。
  final Map<String, Object?> rawOutput;

  /// 完整原始事件 payload。
  final Map<String, Object?> raw;
}

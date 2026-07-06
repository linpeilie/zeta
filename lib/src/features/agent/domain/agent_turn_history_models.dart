import 'package:zeta/src/features/agent/domain/agent_message_models.dart';
import 'package:zeta/src/features/agent/domain/agent_tool_models.dart';

/// 一个 thread 的历史快照。
///
/// 历史以 **turn 集合** 为主要返回结构：[turns] 按出现顺序排列，每个
/// [AgentHistoryTurn] 自带该回合内的消息体列表（[AgentHistoryTurn.entries]）。
class AgentThreadHistorySnapshot {
  const AgentThreadHistorySnapshot({
    required this.threadId,
    required this.turns,
    this.currentTurn,
    this.raw = const <String, Object?>{},
  });

  /// provider thread id。
  final String threadId;

  /// 按出现顺序排列的 turn 集合，每个 turn 包含自己的消息体列表。
  final List<AgentHistoryTurn> turns;

  /// 当前或最近一次出现的 turn。
  final AgentHistoryTurn? currentTurn;

  /// 原始 provider payload，便于调试和未来补齐字段。
  final Map<String, Object?> raw;
}

/// 一个 turn 的历史聚合结果。
class AgentHistoryTurn {
  const AgentHistoryTurn({
    required this.id,
    this.entries = const <AgentHistoryEntry>[],
    this.status = AgentHistoryTurnStatus.unknown,
    this.startedAt,
    this.completedAt,
    this.duration,
    this.timeToFirstToken,
    this.cwd,
    this.model,
    this.modelContextWindow,
    this.collaborationMode,
    this.tokenUsage,
    this.raw = const <String, Object?>{},
  });

  /// provider turn id。
  final String id;

  /// 该 turn 下按历史顺序排列的消息与工具记录。
  final List<AgentHistoryEntry> entries;

  /// turn 运行状态。
  final AgentHistoryTurnStatus status;

  /// turn 开始时间。
  final DateTime? startedAt;

  /// turn 完成时间。
  final DateTime? completedAt;

  /// turn 总耗时。
  final Duration? duration;

  /// 首个 token 延迟。
  final Duration? timeToFirstToken;

  /// turn 运行目录。
  final String? cwd;

  /// 使用的模型。
  final String? model;

  /// 模型上下文窗口大小。
  final int? modelContextWindow;

  /// 协作模式。
  final String? collaborationMode;

  /// 该 turn 的 token 消耗统计，来自 `token_count` 事件。
  final AgentTokenUsage? tokenUsage;

  /// 原始 turn 相关 payload 摘要。
  final Map<String, Object?> raw;
}

/// 一个 turn 的 token 消耗统计。
///
/// 对应 Codex `event_msg.payload.type == 'token_count'` 中
/// `info.total_token_usage` 的字段，UI 据此在回合分隔线上展示 token 成本。
class AgentTokenUsage {
  const AgentTokenUsage({
    this.inputTokens,
    this.cachedInputTokens,
    this.outputTokens,
    this.reasoningOutputTokens,
    this.totalTokens,
    this.lastInputTokens,
    this.lastCachedInputTokens,
    this.lastOutputTokens,
    this.lastReasoningOutputTokens,
    this.lastTotalTokens,
  });

  /// 累计输入 token 数（含缓存命中前的全部输入）。
  final int? inputTokens;

  /// 累计缓存命中的输入 token 数。
  final int? cachedInputTokens;

  /// 累计输出 token 数。
  final int? outputTokens;

  /// 累计推理输出 token 数。
  final int? reasoningOutputTokens;

  /// 累计总 token 数。
  final int? totalTokens;

  /// 最近一次请求的输入 token 数。
  final int? lastInputTokens;

  /// 最近一次请求缓存命中的输入 token 数。
  final int? lastCachedInputTokens;

  /// 最近一次请求的输出 token 数。
  final int? lastOutputTokens;

  /// 最近一次请求的推理输出 token 数。
  final int? lastReasoningOutputTokens;

  /// 最近一次请求的总 token 数。
  final int? lastTotalTokens;
}

/// 历史 turn 状态。
enum AgentHistoryTurnStatus { unknown, running, completed }

/// thread 历史时间线条目。
sealed class AgentHistoryEntry {
  const AgentHistoryEntry({
    required this.id,
    this.raw = const <String, Object?>{},
  });

  /// 历史条目的稳定 id。
  final String id;

  /// 原始 provider item payload。
  final Map<String, Object?> raw;
}

/// 历史消息条目。
class AgentHistoryMessageEntry extends AgentHistoryEntry {
  const AgentHistoryMessageEntry({
    required super.id,
    required this.role,
    required this.text,
    this.phase,
    this.status,
    this.duration,
    super.raw,
  });

  /// 消息角色。
  final AgentMessageRole role;

  /// 消息文本。
  final String text;

  /// 消息阶段。
  final AgentMessagePhase? phase;

  /// 消息生命周期状态。
  final AgentMessageStatus? status;

  /// provider 上报或根据 started/completed 时间计算出的耗时。
  final Duration? duration;
}

/// 历史工具调用条目。
class AgentHistoryToolEntry extends AgentHistoryEntry {
  AgentHistoryToolEntry({required this.toolCall, Map<String, Object?>? raw})
    : super(id: toolCall.id, raw: raw ?? toolCall.raw);

  /// 可复用现有工具卡渲染的工具调用摘要。
  final AgentToolCall toolCall;
}

/// 历史事件分类。
enum AgentHistoryEventKind { permission, warning, search, system }

/// 用户输入问答对。
///
/// 对应 Codex `request_user_input` 工具调用中的单个问题及其回复。
/// UI 据此渲染“第一行问题、下一行回答”的紧凑样式。
class AgentUserInputQaPair {
  const AgentUserInputQaPair({
    required this.questionId,
    required this.question,
    this.header,
    this.options = const <String>[],
    this.answers = const <String>[],
  });

  /// 问题 id，用于匹配 `function_call_output` 中的答案。
  final String questionId;

  /// 问题文本。
  final String question;

  /// 问题分组标题，例如“日志去向”。
  final String? header;

  /// 可选项标签列表。
  final List<String> options;

  /// 用户选择的答案标签列表；在收到 output 前为空。
  final List<String> answers;
}

/// 非消息/非工具的历史事件条目。
class AgentHistoryEventEntry extends AgentHistoryEntry {
  const AgentHistoryEventEntry({
    required super.id,
    required this.kind,
    required this.title,
    this.description,
    this.content,
    this.qaPairs,
    super.raw,
  });

  /// 事件类型。
  final AgentHistoryEventKind kind;

  /// 事件标题。
  final String title;

  /// 事件描述。
  final String? description;

  /// 事件正文，例如命令、查询或 URL。
  final String? content;

  /// 结构化用户输入问答对；仅 `request_user_input` 事件会填充，
  /// UI 优先按此字段渲染问答样式。
  final List<AgentUserInputQaPair>? qaPairs;
}

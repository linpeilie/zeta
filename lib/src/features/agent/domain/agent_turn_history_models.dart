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

/// Token 消耗统计。
///
/// 实时来源是 Codex `thread/tokenUsage/updated` 通知（camelCase 字段），
/// 历史来源是 JSONL `event_msg.payload.type == 'token_count'`（snake_case
/// 字段）。
///
/// Codex 上报的 `total` breakdown 是**整个会话的累计用量**。时间线层会：
/// - 将会话累计直接保存在 thread 级状态；
/// - 将单个 turn 的用量存为相对上一 turn 累计的增量（见 [deltaFrom]）。
///
/// `last*` 字段始终表示最近一次请求的用量，不做差分。
/// Codex 的 `reasoning_output_tokens` 在解析时并入 [outputTokens]，
/// 模型层不再单独暴露推理 token 字段。
class AgentTokenUsage {
  const AgentTokenUsage({
    this.inputTokens,
    this.cachedInputTokens,
    this.outputTokens,
    this.totalTokens,
    this.lastInputTokens,
    this.lastCachedInputTokens,
    this.lastOutputTokens,
    this.lastTotalTokens,
    this.modelContextWindow,
  });

  /// 将 Codex 的 output + reasoning_output 合并为单一输出 token 数。
  static int? mergeOutputTokens(int? outputTokens, int? reasoningOutputTokens) {
    if (outputTokens == null && reasoningOutputTokens == null) {
      return null;
    }
    return (outputTokens ?? 0) + (reasoningOutputTokens ?? 0);
  }

  /// 相对 [baseline] 累计用量的本 turn 增量。
  ///
  /// [baseline] 为空时视为全 0（首个 turn）。`last*` 与上下文窗口保留当前值。
  AgentTokenUsage deltaFrom(AgentTokenUsage? baseline) {
    return AgentTokenUsage(
      inputTokens: _nonNegativeDelta(inputTokens, baseline?.inputTokens),
      cachedInputTokens: _nonNegativeDelta(
        cachedInputTokens,
        baseline?.cachedInputTokens,
      ),
      outputTokens: _nonNegativeDelta(outputTokens, baseline?.outputTokens),
      totalTokens: _nonNegativeDelta(totalTokens, baseline?.totalTokens),
      lastInputTokens: lastInputTokens,
      lastCachedInputTokens: lastCachedInputTokens,
      lastOutputTokens: lastOutputTokens,
      lastTotalTokens: lastTotalTokens,
      modelContextWindow: modelContextWindow,
    );
  }

  /// 累加另一份用量的累计 breakdown（忽略 `last*`）。
  AgentTokenUsage addCumulative(AgentTokenUsage other) {
    return AgentTokenUsage(
      inputTokens: _sumOptional(inputTokens, other.inputTokens),
      cachedInputTokens: _sumOptional(
        cachedInputTokens,
        other.cachedInputTokens,
      ),
      outputTokens: _sumOptional(outputTokens, other.outputTokens),
      totalTokens: _sumOptional(totalTokens, other.totalTokens),
      modelContextWindow: other.modelContextWindow ?? modelContextWindow,
    );
  }

  /// 是否包含任何累计 breakdown 数值。
  bool get hasCumulativeBreakdown {
    return inputTokens != null ||
        cachedInputTokens != null ||
        outputTokens != null ||
        totalTokens != null;
  }

  static int? _nonNegativeDelta(int? current, int? baseline) {
    if (current == null) {
      return null;
    }
    final delta = current - (baseline ?? 0);
    return delta < 0 ? 0 : delta;
  }

  static int? _sumOptional(int? left, int? right) {
    if (left == null && right == null) {
      return null;
    }
    return (left ?? 0) + (right ?? 0);
  }

  static const List<String> _displaySuffixes = <String>[
    'k',
    'm',
    'g',
    't',
    'p',
    'e',
    'z',
    'y',
  ];

  /// 输入 token 数（会话累计或 turn 增量，取决于存放位置）。
  final int? inputTokens;

  /// 输入 token 数的展示值。
  String? get displayInputTokens => _displayTokenCount(inputTokens);

  /// 缓存命中的输入 token 数。
  final int? cachedInputTokens;

  /// 缓存命中的输入 token 数展示值。
  String? get displayCachedInputTokens => _displayTokenCount(cachedInputTokens);

  /// 输出 token 数（已含 reasoning_output_tokens）。
  final int? outputTokens;

  /// 输出 token 数展示值。
  String? get displayOutputTokens => _displayTokenCount(outputTokens);

  /// 总 token 数。
  final int? totalTokens;

  /// 总 token 数展示值。
  String? get displayTotalTokens => _displayTokenCount(totalTokens);

  /// 最近一次请求的输入 token 数。
  final int? lastInputTokens;

  /// 最近一次请求输入 token 数展示值。
  String? get displayLastInputTokens => _displayTokenCount(lastInputTokens);

  /// 最近一次请求缓存命中的输入 token 数。
  final int? lastCachedInputTokens;

  /// 最近一次请求缓存输入 token 数展示值。
  String? get displayLastCachedInputTokens =>
      _displayTokenCount(lastCachedInputTokens);

  /// 最近一次请求的输出 token 数（已含 reasoning_output_tokens）。
  final int? lastOutputTokens;

  /// 最近一次请求输出 token 数展示值。
  String? get displayLastOutputTokens => _displayTokenCount(lastOutputTokens);

  /// 最近一次请求的总 token 数。
  final int? lastTotalTokens;

  /// 最近一次请求总 token 数展示值。
  String? get displayLastTotalTokens => _displayTokenCount(lastTotalTokens);

  /// 当前模型上下文窗口大小；UI 可据此展示上下文占用比例。
  final int? modelContextWindow;

  /// 模型上下文窗口大小展示值。
  String? get displayModelContextWindow =>
      _displayTokenCount(modelContextWindow);

  static String? _displayTokenCount(int? tokens) {
    if (tokens == null) {
      return null;
    }
    if (tokens < 1000) {
      return tokens.toString();
    }

    var value = tokens.toDouble();
    var suffixIndex = -1;
    while (value >= 1000 && suffixIndex + 1 < _displaySuffixes.length) {
      value /= 1000;
      suffixIndex += 1;
    }

    if (suffixIndex == -1) {
      return tokens.toString();
    }

    while (true) {
      final digits = value >= 100 ? 0 : 1;
      final formattedValue = value.toStringAsFixed(digits);
      final normalizedValue = formattedValue.endsWith('.0')
          ? formattedValue.substring(0, formattedValue.length - 2)
          : formattedValue;
      final roundedValue = double.parse(normalizedValue);
      if (roundedValue < 1000 || suffixIndex + 1 >= _displaySuffixes.length) {
        return '$normalizedValue${_displaySuffixes[suffixIndex]}';
      }
      value = roundedValue / 1000;
      suffixIndex += 1;
    }
  }
}

/// 历史 turn 状态。
///
/// `interrupted` 与 `failed` 是 Codex `turn/completed` 通知携带的终态，
/// 与正常 `completed` 区分展示。
enum AgentHistoryTurnStatus { unknown, running, completed, interrupted, failed }

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
    this.localImagePaths = const <String>[],
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

  /// 用户消息中的本地图片路径（来自 `localImage` 输入项）。
  final List<String> localImagePaths;
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
    this.isOther = false,
    this.isSecret = false,
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

  /// 是否允许自由文本（协议 `isOther`）。
  final bool isOther;

  /// 是否应按密文输入（协议 `isSecret`）。
  final bool isSecret;
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

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
    this.tokenUsageIsSessionCumulative = true,
    this.errorMessage,
    this.errorCode,
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

  /// 为 true 时 [tokenUsage] 是会话累计（Codex JSONL）；为 false 时为本回合绝对用量（Grok）。
  final bool tokenUsageIsSessionCumulative;

  /// provider 上报的终态错误或中断原因。
  final String? errorMessage;

  /// provider 稳定错误码；用于错误分类和下一步操作提示。
  final String? errorCode;

  /// 原始 turn 相关 payload 摘要。
  final Map<String, Object?> raw;
}

/// 单个 turn 实际使用的模型配置摘要，供 turn footer 等 UI 展示。
class AgentTurnModelConfig {
  const AgentTurnModelConfig({
    this.modelId,
    this.reasoningEffort,
    this.fastEnabled,
  });

  /// 模型 id 或 provider 上报的 model 标识。
  final String? modelId;

  /// 推理深度档位（如 low/medium/high/xhigh）。
  final String? reasoningEffort;

  /// 是否开启 Fast；`true` 时 footer 展示 “Fast”，其它情况不展示。
  final bool? fastEnabled;

  /// 是否含有可展示的配置项。
  bool get hasDisplayable {
    final model = modelId?.trim();
    final effort = reasoningEffort?.trim();
    return (model != null && model.isNotEmpty) ||
        (effort != null && effort.isNotEmpty) ||
        fastEnabled == true;
  }

  /// 从历史 turn 解析本回合模型配置（优先 `turnContext`，回退 turn 顶层字段）。
  static AgentTurnModelConfig? fromHistoryTurn(AgentHistoryTurn turn) {
    final turnContext = _objectMap(turn.raw['turnContext']);
    final source = turnContext.isEmpty ? turn.raw : turnContext;

    final modelId =
        _nonEmptyString(turn.model) ??
        _nonEmptyString(source['model']) ??
        _nonEmptyString(source['modelId']);

    final reasoningEffort =
        _nonEmptyString(source['effort']) ??
        _nonEmptyString(source['reasoningEffort']) ??
        _nonEmptyString(source['reasoning_effort']);

    final serviceTierId =
        _nonEmptyString(source['serviceTier']) ??
        _nonEmptyString(source['service_tier']) ??
        _nonEmptyString(source['serviceTierId']) ??
        _nonEmptyString(source['service_tier_id']);

    final explicitFast =
        _boolValue(source['fast']) ??
        _boolValue(source['fastMode']) ??
        _boolValue(source['isFast']) ??
        _boolValue(source['fast_enabled']);

    final fastEnabled =
        explicitFast ?? _fastEnabledFromServiceTier(serviceTierId);

    final config = AgentTurnModelConfig(
      modelId: modelId,
      reasoningEffort: reasoningEffort,
      fastEnabled: fastEnabled,
    );
    return config.hasDisplayable ? config : null;
  }

  static bool? _fastEnabledFromServiceTier(String? serviceTierId) {
    if (serviceTierId == null) {
      return null;
    }
    final normalized = serviceTierId.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }
    // 与 agentFastServiceTier 启发式一致：fast / priority 视为 Fast。
    if (normalized == 'fast' || normalized == 'priority') {
      return true;
    }
    return false;
  }

  static Map<String, Object?> _objectMap(Object? value) {
    if (value is! Map) {
      return const <String, Object?>{};
    }
    return <String, Object?>{
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }

  static String? _nonEmptyString(Object? value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static bool? _boolValue(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
        return true;
      }
      if (normalized == 'false' || normalized == '0' || normalized == 'no') {
        return false;
      }
    }
    return null;
  }
}

/// 将推理深度档位格式化为 footer 短标签。
String? agentReasoningEffortFooterLabel(String? effort) {
  final normalized = effort?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  return switch (normalized) {
    'none' => '无',
    'minimal' => '最低',
    'low' => '低',
    'medium' => '中',
    'high' => '高',
    'xhigh' => '极高',
    _ => effort!.trim(),
  };
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
/// Codex 的 `reasoning_output_tokens` 单独保存在 [reasoningOutputTokens]，
/// 避免统计层把可见输出与推理消耗混为同一口径。
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
    this.modelContextWindow,
  });

  /// 将 Codex 的总输出拆出推理部分，得到用户可见输出 token。
  static int? visibleOutputTokens(
    int? outputTokens,
    int? reasoningOutputTokens,
  ) {
    if (outputTokens == null && reasoningOutputTokens == null) {
      return null;
    }
    final visible = (outputTokens ?? 0) - (reasoningOutputTokens ?? 0);
    return visible < 0 ? 0 : visible;
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
      reasoningOutputTokens: _nonNegativeDelta(
        reasoningOutputTokens,
        baseline?.reasoningOutputTokens,
      ),
      totalTokens: _nonNegativeDelta(totalTokens, baseline?.totalTokens),
      lastInputTokens: lastInputTokens,
      lastCachedInputTokens: lastCachedInputTokens,
      lastOutputTokens: lastOutputTokens,
      lastReasoningOutputTokens: lastReasoningOutputTokens,
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
      reasoningOutputTokens: _sumOptional(
        reasoningOutputTokens,
        other.reasoningOutputTokens,
      ),
      totalTokens: _sumOptional(totalTokens, other.totalTokens),
      modelContextWindow: other.modelContextWindow ?? modelContextWindow,
    );
  }

  /// 是否包含任何累计 breakdown 数值。
  bool get hasCumulativeBreakdown {
    return inputTokens != null ||
        cachedInputTokens != null ||
        outputTokens != null ||
        reasoningOutputTokens != null ||
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

  /// 可见输出 token 数，不含推理 token。
  final int? outputTokens;

  /// 输出 token 数展示值。
  String? get displayOutputTokens => _displayTokenCount(outputTokens);

  /// 推理输出 token 数。
  final int? reasoningOutputTokens;

  /// 推理输出 token 数展示值。
  String? get displayReasoningOutputTokens =>
      _displayTokenCount(reasoningOutputTokens);

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

  /// 最近一次请求的可见输出 token 数。
  final int? lastOutputTokens;

  /// 最近一次请求输出 token 数展示值。
  String? get displayLastOutputTokens => _displayTokenCount(lastOutputTokens);

  /// 最近一次请求的推理输出 token 数。
  final int? lastReasoningOutputTokens;

  /// 最近一次请求推理输出 token 数展示值。
  String? get displayLastReasoningOutputTokens =>
      _displayTokenCount(lastReasoningOutputTokens);

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
    this.sourceMessageId,
    this.kind = AgentMessageKind.regular,
    this.phase,
    this.status,
    this.duration,
    this.localImagePaths = const <String>[],
    super.raw,
  });

  /// 消息角色。
  final AgentMessageRole role;

  /// Provider 原始消息身份；不作为历史时间线的合并键。
  final String? sourceMessageId;

  /// 消息的显式展示语义。
  final AgentMessageKind kind;

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

/// 用户输入问题的结构化可选项。
class AgentUserInputOption {
  const AgentUserInputOption({
    required this.id,
    required this.label,
    this.description,
  });

  /// 写回 provider 的稳定选项 id。
  final String id;

  /// UI 展示文案。
  final String label;

  /// 可选的补充说明。
  final String? description;
}

/// 用户输入问答对。
///
/// 对应 provider 用户提问中的单个问题及其回复。
/// [options] 保留旧配置和 Codex 历史兼容；新协议应优先填充带稳定 id 的
/// [optionItems]，UI 通过 [resolvedOptions] 统一消费。
class AgentUserInputQaPair {
  const AgentUserInputQaPair({
    required this.questionId,
    required this.question,
    this.header,
    this.options = const <String>[],
    this.optionItems = const <AgentUserInputOption>[],
    this.answers = const <String>[],
    this.allowMultiple = false,
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

  /// 带协议稳定 id 的结构化选项。
  final List<AgentUserInputOption> optionItems;

  /// 统一的结构化选项视图；旧标签会以“id 等于 label”的形式兼容。
  List<AgentUserInputOption> get resolvedOptions {
    if (optionItems.isNotEmpty) {
      return optionItems;
    }
    return List<AgentUserInputOption>.unmodifiable(
      options.map((label) => AgentUserInputOption(id: label, label: label)),
    );
  }

  /// 用户选择的稳定选项 id 或自由文本；在收到 output 前为空。
  final List<String> answers;

  /// 是否允许同时选择多个选项。
  final bool allowMultiple;

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

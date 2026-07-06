/// Agent 后端的类型。
///
/// UI 和会话状态只关心这个中立枚举，不直接绑定某个 CLI 的协议细节。
enum AgentProviderKind { codexAppServer, acp, claudeCode }

/// Provider 与当前回合的连接状态。
///
/// 这些状态会直接映射到 Agent 面板顶部状态胶囊和发送/取消按钮。
enum AgentProviderConnectionState {
  idle,
  connecting,
  ready,
  running,
  unavailable,
  error,
}

/// 对话消息角色。
enum AgentMessageRole { user, agent, system }

/// Agent 消息的阶段。
///
/// Codex 的 `commentary` 表示过程性说明；用户曾写作 `commetary`，解析时也会兼容。
enum AgentMessagePhase { response, commentary, other }

/// Agent 消息的生命周期状态。
enum AgentMessageStatus { streaming, completed, other }

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

/// Agent 向用户请求审批或输入的中立分类。
enum AgentPermissionKind {
  commandExecution,
  fileChange,
  permissions,
  userInput,
  other,
}

/// 内置 Codex provider 的稳定配置 id。
const String defaultAgentProviderId = 'codex';

/// 一个可启动的 Agent provider 定义。
///
/// 该对象保存全局配置，例如 `codex app-server --stdio` 的命令、参数、环境变量和
/// 默认模型。会话只保存选中的 provider id 与 thread metadata，避免把全局定义
/// 复制到每个项目状态里。
class AgentProviderConfig {
  const AgentProviderConfig({
    required this.id,
    required this.displayName,
    required this.kind,
    required this.command,
    this.arguments = const <String>[],
    this.environment = const <String, String>{},
    this.defaultModel,
    this.selectedModel,
    this.selectedReasoningEffort,
    this.selectedServiceTier,
    this.enabled = true,
    this.extra = const <String, Object?>{},
  });

  /// provider 的稳定 id，会话状态通过它引用全局配置。
  final String id;

  /// UI 中展示的名称。
  final String displayName;

  /// provider 协议类型。
  final AgentProviderKind kind;

  /// 启动 CLI 的命令。
  final String command;

  /// 启动 CLI 的参数。
  final List<String> arguments;

  /// 启动 CLI 时附加的环境变量。
  final Map<String, String> environment;

  /// provider 默认模型；为空时使用 CLI 自己的默认值。
  final String? defaultModel;

  /// 用户在输入框选择的模型 id，覆盖 [defaultModel]；为空时回退到默认。
  final String? selectedModel;

  /// 用户选择的推理深度档位（low/medium/high/xhigh）。
  final String? selectedReasoningEffort;

  /// 用户选择的服务档位 id（如 priority）。
  final String? selectedServiceTier;

  /// 是否在配置列表中启用。
  final bool enabled;

  /// 未来 provider 专属配置的扩展字段。
  final Map<String, Object?> extra;

  /// 默认 Codex CLI 配置。
  ///
  /// V1 通过 stdio 启动 app-server，不额外引入 JSON-RPC 第三方依赖。
  static const AgentProviderConfig defaultCodex = AgentProviderConfig(
    id: defaultAgentProviderId,
    displayName: 'Codex CLI',
    kind: AgentProviderKind.codexAppServer,
    command: 'codex',
    arguments: <String>['app-server', '--stdio'],
  );

  /// 复制配置并覆盖部分字段，主要用于持久化用户在输入框中的模型选择。
  AgentProviderConfig copyWith({
    String? id,
    String? displayName,
    AgentProviderKind? kind,
    String? command,
    List<String>? arguments,
    Map<String, String>? environment,
    String? defaultModel,
    String? selectedModel,
    String? selectedReasoningEffort,
    String? selectedServiceTier,
    bool? enabled,
    Map<String, Object?>? extra,
  }) {
    return AgentProviderConfig(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      kind: kind ?? this.kind,
      command: command ?? this.command,
      arguments: arguments ?? this.arguments,
      environment: environment ?? this.environment,
      defaultModel: defaultModel ?? this.defaultModel,
      selectedModel: selectedModel ?? this.selectedModel,
      selectedReasoningEffort:
          selectedReasoningEffort ?? this.selectedReasoningEffort,
      selectedServiceTier: selectedServiceTier ?? this.selectedServiceTier,
      enabled: enabled ?? this.enabled,
      extra: extra ?? this.extra,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'displayName': displayName,
      'kind': kind.name,
      'command': command,
      'arguments': arguments,
      'environment': environment,
      'defaultModel': defaultModel,
      'selectedModel': selectedModel,
      'selectedReasoningEffort': selectedReasoningEffort,
      'selectedServiceTier': selectedServiceTier,
      'enabled': enabled,
      'extra': extra,
    };
  }

  /// 从持久化 JSON 宽容解码 provider 配置。
  ///
  /// 解码失败返回 `null`，调用方可以回退到默认 provider；未知字段不会阻断加载，
  /// 后续协议扩展可放在 [extra] 中。
  static AgentProviderConfig? tryDecode(Object? value) {
    final map = _objectMap(value);
    if (map.isEmpty) {
      return null;
    }

    final id = _optionalString(map['id']);
    final displayName = _optionalString(map['displayName']);
    final command = _optionalString(map['command']);
    final kindName = _optionalString(map['kind']);
    final kind = _providerKind(kindName);

    if (id == null || displayName == null || command == null || kind == null) {
      return null;
    }

    return AgentProviderConfig(
      id: id,
      displayName: displayName,
      kind: kind,
      command: command,
      arguments: _stringList(map['arguments']),
      environment: _stringMap(map['environment']),
      defaultModel: _optionalString(map['defaultModel']),
      selectedModel: _optionalString(map['selectedModel']),
      selectedReasoningEffort: _optionalString(map['selectedReasoningEffort']),
      selectedServiceTier: _optionalString(map['selectedServiceTier']),
      enabled: map['enabled'] is bool ? map['enabled'] as bool : true,
      extra: _objectMap(map['extra']),
    );
  }
}

/// 全局 Agent provider 设置。
///
/// 当前只保存 provider 列表和 active provider；项目/session 级别的 thread id
/// 由 IDE 会话状态维护。
class AgentProviderSettings {
  const AgentProviderSettings({
    this.providers = const <AgentProviderConfig>[
      AgentProviderConfig.defaultCodex,
    ],
    this.activeProviderId = defaultAgentProviderId,
  });

  /// 全局 provider 定义列表。
  final List<AgentProviderConfig> providers;

  /// 当前默认 provider id。
  final String activeProviderId;

  /// 当前选中的 provider；如果配置被删除，则回退到内置 Codex。
  AgentProviderConfig get activeProvider {
    return providers.firstWhere(
      (provider) => provider.id == activeProviderId,
      orElse: () => AgentProviderConfig.defaultCodex,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'version': 1,
      'providers': providers.map((provider) => provider.toJson()).toList(),
      'activeProviderId': activeProviderId,
    };
  }

  /// 读取版本化配置。
  ///
  /// 配置缺失、版本不匹配或内容损坏时都返回默认设置，保证 UI 启动不崩溃。
  static AgentProviderSettings tryDecode(Object? value) {
    final map = _objectMap(value);
    if (map['version'] != 1) {
      return const AgentProviderSettings();
    }

    final providers = _providerList(map['providers']);
    final activeProviderId =
        _optionalString(map['activeProviderId']) ?? defaultAgentProviderId;

    if (providers.isEmpty) {
      return const AgentProviderSettings();
    }

    return AgentProviderSettings(
      providers: List<AgentProviderConfig>.unmodifiable(providers),
      activeProviderId:
          providers.any((provider) => provider.id == activeProviderId)
          ? activeProviderId
          : providers.first.id,
    );
  }

  static List<AgentProviderConfig> _providerList(Object? value) {
    if (value is! List) {
      return const <AgentProviderConfig>[AgentProviderConfig.defaultCodex];
    }

    final providers = <AgentProviderConfig>[];
    final seen = <String>{};
    for (final item in value) {
      final provider = AgentProviderConfig.tryDecode(item);
      if (provider != null && seen.add(provider.id)) {
        providers.add(provider);
      }
    }
    return providers;
  }
}

/// Provider 当前状态和用户可读提示。
class AgentProviderStatus {
  const AgentProviderStatus({
    required this.state,
    required this.message,
    this.details,
  });

  const AgentProviderStatus.idle()
    : state = AgentProviderConnectionState.idle,
      message = 'Ready',
      details = null;

  /// 状态机枚举。
  final AgentProviderConnectionState state;

  /// 展示给用户的一句话状态。
  final String message;

  /// 诊断详情，通常用于错误消息或日志。
  final String? details;
}

/// 发送给 Agent 的工作区上下文。
///
/// V1 只传项目路径和当前文件路径，不读取文件内容，也不自动授权写文件。
class AgentContext {
  const AgentContext({this.projectPath, this.filePath});

  /// 当前项目根目录。
  final String? projectPath;

  /// 当前文件树选中的文件路径。
  final String? filePath;
}

/// Agent thread 当前运行状态。
enum AgentThreadRuntimeStatus { notLoaded, idle, active, systemError, unknown }

/// 项目列表中展示的 thread 摘要。
///
/// 该模型只保存列表展示和恢复会话所需的轻量信息；完整 turn/items 历史仍由
/// provider 在恢复或读取 thread 时按需获取。
class AgentThreadSummary {
  const AgentThreadSummary({
    required this.id,
    required this.providerId,
    required this.projectPath,
    required this.preview,
    required this.createdAt,
    required this.updatedAt,
    required this.status,
    this.title,
    this.sessionPath,
    this.recencyAt,
    this.raw = const <String, Object?>{},
  });

  /// provider thread id。
  final String id;

  /// 创建或返回该 thread 的 provider id。
  final String providerId;

  /// thread 捕获的工作目录，通常等于项目根目录。
  final String projectPath;

  /// 用户可读标题；为空时 UI 会回退到 [preview] 或短 id。
  final String? title;

  /// 本地 Codex session `jsonl` 路径。
  final String? sessionPath;

  /// 通常是首条用户消息。
  final String preview;

  /// 创建时间。
  final DateTime createdAt;

  /// 最近更新时间。
  final DateTime updatedAt;

  /// provider 用于排序的最近活动时间。
  final DateTime? recencyAt;

  /// 运行状态摘要。
  final AgentThreadRuntimeStatus status;

  /// 原始 provider payload，便于调试和未来补齐字段。
  final Map<String, Object?> raw;

  /// UI 展示名称。
  String get displayName {
    final cleanedTitle = title?.trim();
    if (cleanedTitle != null && cleanedTitle.isNotEmpty) {
      return cleanedTitle;
    }
    final cleanedPreview = preview.trim();
    if (cleanedPreview.isNotEmpty) {
      return cleanedPreview;
    }
    return id.length <= 8 ? id : id.substring(0, 8);
  }

  /// 上次活跃时间，优先使用 provider 的 recency 排序时间。
  DateTime? get lastActiveAt => recencyAt ?? updatedAt;

  /// 旧展示标题入口，保留给尚未迁移的调用点。
  String get displayTitle => displayName;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'providerId': providerId,
      'projectPath': projectPath,
      'title': title,
      'sessionPath': sessionPath,
      'preview': preview,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'recencyAt': recencyAt?.millisecondsSinceEpoch,
      'status': status.name,
      'raw': raw,
    };
  }

  /// 从会话缓存宽容恢复 thread 摘要。
  static AgentThreadSummary? tryDecode(Object? value) {
    final map = _objectMap(value);
    if (map.isEmpty) {
      return null;
    }

    final id = _optionalString(map['id']);
    final providerId = _optionalString(map['providerId']);
    final projectPath = _optionalString(map['projectPath']);
    final createdAt = _dateTimeFromMilliseconds(map['createdAt']);
    final updatedAt = _dateTimeFromMilliseconds(map['updatedAt']);
    final raw = _objectMap(map['raw']);
    if (id == null ||
        providerId == null ||
        projectPath == null ||
        createdAt == null ||
        updatedAt == null) {
      return null;
    }

    return AgentThreadSummary(
      id: id,
      providerId: providerId,
      projectPath: projectPath,
      title: _optionalString(map['title']),
      sessionPath:
          _optionalString(map['sessionPath']) ?? _optionalString(raw['path']),
      preview: _optionalString(map['preview']) ?? '',
      createdAt: createdAt,
      updatedAt: updatedAt,
      recencyAt: _dateTimeFromMilliseconds(map['recencyAt']),
      status: _threadRuntimeStatus(map['status']),
      raw: raw,
    );
  }
}

/// thread 分页查询参数。
class AgentThreadListQuery {
  const AgentThreadListQuery({
    required this.projectPath,
    required this.limit,
    this.cursor,
  });

  /// 用 provider cwd 精确匹配项目。
  final String projectPath;

  /// 单页请求数量。
  final int limit;

  /// provider 返回的不透明分页游标。
  final String? cursor;
}

/// thread 分页结果。
class AgentThreadPage {
  const AgentThreadPage({required this.threads, required this.nextCursor});

  /// 当前页 thread 摘要。
  final List<AgentThreadSummary> threads;

  /// 下一页游标；为空表示没有更多。
  final String? nextCursor;
}

/// 一个 thread 的历史快照。
///
/// 历史以 **turn 集合** 为主要返回结构：[turns] 按出现顺序排列，每个
/// [AgentHistoryTurn] 自带该回合内的消息体列表（[AgentHistoryTurn.entries]）。
/// 旧的扁平 [entries] 视图和 [turnsById] 索引保留为计算属性，便于兼容调用方。
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

  /// 按 turn id 查找的索引。
  Map<String, AgentHistoryTurn> get turnsById => <String, AgentHistoryTurn>{
    for (final turn in turns) turn.id: turn,
  };

  /// 所有 turn 的消息体展平后的列表，按 turn 顺序拼接，兼容旧用法。
  List<AgentHistoryEntry> get entries => <AgentHistoryEntry>[
    for (final turn in turns) ...turn.entries,
  ];

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

/// 一条 Agent 会话，对应 Codex app-server 的 thread。
class AgentSession {
  const AgentSession({
    required this.id,
    required this.providerId,
    this.title,
    this.raw = const <String, Object?>{},
  });

  /// provider 会话 id；Codex 中对应 thread id。
  final String id;

  /// 创建该会话的 provider id。
  final String providerId;

  /// provider 返回的可选标题。
  final String? title;

  /// 原始协议 payload，便于调试和未来补充字段。
  final Map<String, Object?> raw;
}

/// 一次用户请求或 steer，对应 Codex app-server 的 turn。
class AgentTurn {
  const AgentTurn({
    required this.id,
    required this.sessionId,
    this.raw = const <String, Object?>{},
  });

  /// provider 回合 id；Codex 中对应 turn id。
  final String id;

  /// 回合所属会话 id。
  final String sessionId;

  /// 原始协议 payload。
  final Map<String, Object?> raw;
}

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

/// Provider 发出的审批或输入请求。
///
/// UI 用该模型渲染审批卡片，再通过 [AgentPermissionDecision] 把结果传回 provider。
class AgentPermissionRequest {
  const AgentPermissionRequest({
    required this.id,
    required this.title,
    required this.kind,
    this.description,
    this.command,
    this.cwd,
    this.sessionId,
    this.turnId,
    this.fileChanges = const <String, Object?>{},
    this.raw = const <String, Object?>{},
  });

  /// 审批请求 id，UI 用它作为稳定 key。
  final String id;

  /// 审批卡片标题。
  final String title;

  /// 审批类型。
  final AgentPermissionKind kind;

  /// provider 给出的原因或说明。
  final String? description;

  /// 命令执行审批中的命令文本。
  final String? command;

  /// 命令执行目录。
  final String? cwd;

  /// 可选会话 id，用于将实时事件路由到当前 thread。
  final String? sessionId;

  /// 可选回合 id，用于将实时事件路由到当前 turn。
  final String? turnId;

  /// 文件变更审批中的变更摘要。
  final Map<String, Object?> fileChanges;

  /// 原始审批请求 payload。
  final Map<String, Object?> raw;
}

/// 用户对审批请求的决定。
class AgentPermissionDecision {
  const AgentPermissionDecision({
    required this.requestId,
    required this.approved,
    this.cancelTurn = false,
    this.message,
  });

  /// 对应 [AgentPermissionRequest.id]。
  final String requestId;

  /// 是否同意。
  final bool approved;

  /// 拒绝时是否同时取消当前 turn。
  final bool cancelTurn;

  /// 可选的人类说明，预留给支持文本反馈的 provider。
  final String? message;
}

/// Agent provider 向 UI 推送的统一事件基类。
sealed class AgentEvent {
  const AgentEvent();
}

/// Provider 状态变化事件。
class AgentStatusEvent extends AgentEvent {
  const AgentStatusEvent(this.status);

  /// 最新 provider 状态。
  final AgentProviderStatus status;
}

/// 新会话已创建或恢复。
class AgentSessionStartedEvent extends AgentEvent {
  const AgentSessionStartedEvent(this.session);

  /// 已创建或恢复的会话。
  final AgentSession session;
}

/// 新回合已开始。
class AgentTurnStartedEvent extends AgentEvent {
  const AgentTurnStartedEvent(this.turn);

  /// 已开始的回合。
  final AgentTurn turn;
}

/// 回合已完成。
class AgentTurnCompletedEvent extends AgentEvent {
  const AgentTurnCompletedEvent({
    required this.sessionId,
    required this.turnId,
    this.raw = const <String, Object?>{},
  });

  /// 完成回合所属会话 id。
  final String sessionId;

  /// 完成的回合 id。
  final String turnId;

  /// 原始完成事件 payload。
  final Map<String, Object?> raw;
}

/// 回合 token 用量更新。
///
/// 对应 Codex `turn/tokenCount` 通知，UI 据此在回合分隔线展示 token 成本。
class AgentTokenUsageEvent extends AgentEvent {
  const AgentTokenUsageEvent({
    required this.tokenUsage,
    this.sessionId,
    this.turnId,
    this.raw = const <String, Object?>{},
  });

  /// 所属会话 id。
  final String? sessionId;

  /// 所属回合 id；为空时由 ViewModel 归入当前活跃回合。
  final String? turnId;

  /// 本次上报的 token 用量。
  final AgentTokenUsage tokenUsage;

  /// 原始通知 payload。
  final Map<String, Object?> raw;
}

/// Agent 消息的流式增量。
class AgentMessageDeltaEvent extends AgentEvent {
  const AgentMessageDeltaEvent({
    required this.messageId,
    required this.delta,
    required this.role,
    this.phase,
    this.status,
    this.duration,
    this.raw = const <String, Object?>{},
    this.sessionId,
    this.turnId,
  });

  /// provider 消息 id，用于合并同一条消息的多个 delta。
  final String messageId;

  /// 本次增量文本。
  final String delta;

  /// 消息角色。
  final AgentMessageRole role;

  /// 可选消息阶段。
  final AgentMessagePhase? phase;

  /// 可选消息状态。
  final AgentMessageStatus? status;

  /// 可选耗时。
  final Duration? duration;

  /// 原始 provider payload。
  final Map<String, Object?> raw;

  /// 可选会话 id。
  final String? sessionId;

  /// 可选回合 id。
  final String? turnId;
}

/// Agent 消息 metadata 或最终文本更新。
class AgentMessageUpdatedEvent extends AgentEvent {
  const AgentMessageUpdatedEvent({
    required this.messageId,
    this.text,
    this.role,
    this.phase,
    this.status,
    this.duration,
    this.raw = const <String, Object?>{},
    this.sessionId,
    this.turnId,
  });

  /// provider 消息 id。
  final String messageId;

  /// 可选完整文本。
  final String? text;

  /// 可选消息角色。
  final AgentMessageRole? role;

  /// 可选消息阶段。
  final AgentMessagePhase? phase;

  /// 可选消息状态。
  final AgentMessageStatus? status;

  /// 可选耗时。
  final Duration? duration;

  /// 原始 provider payload。
  final Map<String, Object?> raw;

  /// 可选会话 id。
  final String? sessionId;

  /// 可选回合 id。
  final String? turnId;
}

/// Agent 计划更新。
class AgentPlanUpdatedEvent extends AgentEvent {
  const AgentPlanUpdatedEvent({
    required this.entries,
    this.sessionId,
    this.turnId,
  });

  /// 最新计划条目。
  final List<AgentPlanEntry> entries;

  /// 可选会话 id。
  final String? sessionId;

  /// 可选回合 id。
  final String? turnId;
}

/// 工具调用新增或更新。
class AgentToolCallEvent extends AgentEvent {
  const AgentToolCallEvent(this.toolCall);

  /// 新增或更新的工具调用。
  final AgentToolCall toolCall;
}

/// Provider 请求用户审批或输入。
class AgentPermissionRequestedEvent extends AgentEvent {
  const AgentPermissionRequestedEvent(this.request);

  /// 等待用户处理的审批请求。
  final AgentPermissionRequest request;
}

/// 协议错误、stderr 或 provider 运行错误。
class AgentErrorEvent extends AgentEvent {
  const AgentErrorEvent({
    required this.message,
    this.details,
    this.sessionId,
    this.turnId,
    this.raw = const <String, Object?>{},
  });

  /// 错误概要。
  final String message;

  /// 错误详情。
  final String? details;

  /// 可选会话 id；全局 stderr / protocol 错误为空。
  final String? sessionId;

  /// 可选回合 id；全局 stderr / protocol 错误为空。
  final String? turnId;

  /// 原始错误 payload。
  final Map<String, Object?> raw;
}

/// 模型支持的推理深度档位。
///
/// 对应 Codex `model/list` 中 `supportedReasoningEfforts` 数组元素，
/// UI 据此在输入框左侧渲染思考按钮的选项列表。
class AgentModelReasoningEffort {
  const AgentModelReasoningEffort({required this.effort, this.description});

  /// 档位标识，如 low/medium/high/xhigh。
  final String effort;

  /// 可选的人类可读说明。
  final String? description;
}

/// 模型服务档位（速率）。
///
/// 对应 Codex `model/list` 中 `serviceTiers` 数组元素，
/// UI 据此在输入框左侧渲染速率选择按钮。
class AgentModelServiceTier {
  const AgentModelServiceTier({
    required this.id,
    required this.name,
    this.description,
  });

  /// 档位 id，如 priority。
  final String id;

  /// 展示名称，如 Fast。
  final String name;

  /// 可选说明。
  final String? description;
}

/// 可选模型信息。
///
/// 由 `model/list` 返回，UI 据此构建模型下拉、思考按钮和速率按钮。
class AgentModelInfo {
  const AgentModelInfo({
    required this.id,
    required this.model,
    required this.displayName,
    this.description,
    this.hidden = false,
    this.supportedReasoningEfforts = const <AgentModelReasoningEffort>[],
    this.defaultReasoningEffort,
    this.serviceTiers = const <AgentModelServiceTier>[],
    this.defaultServiceTier,
    this.isDefault = false,
    this.raw = const <String, Object?>{},
  });

  /// 模型稳定 id。
  final String id;

  /// 模型标识，与 CLI 参数中的 model 字段一致。
  final String model;

  /// UI 展示名称。
  final String displayName;

  /// 可选描述。
  final String? description;

  /// 是否在 CLI 中被标记为隐藏。
  final bool hidden;

  /// 支持的推理深度档位列表。
  final List<AgentModelReasoningEffort> supportedReasoningEfforts;

  /// 默认推理深度档位。
  final String? defaultReasoningEffort;

  /// 可选服务档位列表。
  final List<AgentModelServiceTier> serviceTiers;

  /// 默认服务档位 id。
  final String? defaultServiceTier;

  /// 是否为 CLI 默认模型。
  final bool isDefault;

  /// 原始 provider payload。
  final Map<String, Object?> raw;
}

/// `model/list` 分页结果。
class AgentModelList {
  const AgentModelList({required this.models, this.nextCursor});

  /// 当前页模型列表。
  final List<AgentModelInfo> models;

  /// 下一页游标；为空表示没有更多。
  final String? nextCursor;
}

/// 用户在输入框选择的模型组合。
///
/// 三个字段均可为空，表示使用 CLI 默认值。持久化到 [AgentProviderConfig]，
/// 并在 `turn/start` 时覆盖默认 model 参数。
class AgentModelSelection {
  const AgentModelSelection({
    this.modelId,
    this.reasoningEffort,
    this.serviceTierId,
  });

  /// 选中的模型 id。
  final String? modelId;

  /// 选中的推理深度档位。
  final String? reasoningEffort;

  /// 选中的服务档位 id。
  final String? serviceTierId;

  /// 是否所有字段都为空。
  bool get isEmpty =>
      modelId == null && reasoningEffort == null && serviceTierId == null;
}

/// provider 拉取到模型列表后推送的事件。
///
/// ViewModel 据此更新输入框下方的模型/思考/速率控件。
class AgentModelListEvent extends AgentEvent {
  const AgentModelListEvent(this.models);

  /// 最新可用的模型列表。
  final AgentModelList models;
}

String? _optionalString(Object? value) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  return null;
}

AgentProviderKind? _providerKind(String? value) {
  if (value == null) {
    return null;
  }
  for (final kind in AgentProviderKind.values) {
    if (kind.name == value) {
      return kind;
    }
  }
  return null;
}

List<String> _stringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return value.whereType<String>().where((item) => item.isNotEmpty).toList();
}

Map<String, String> _stringMap(Object? value) {
  if (value is! Map) {
    return const <String, String>{};
  }

  final result = <String, String>{};
  for (final entry in value.entries) {
    final key = entry.key;
    final item = entry.value;
    if (key is String) {
      result[key] = item is String ? item : '$item';
    }
  }
  return result;
}

Map<String, Object?> _objectMap(Object? value) {
  if (value is Map) {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is String) {
        result[entry.key as String] = entry.value;
      }
    }
    return Map<String, Object?>.unmodifiable(result);
  }
  return const <String, Object?>{};
}

DateTime? _dateTimeFromMilliseconds(Object? value) {
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  return null;
}

AgentThreadRuntimeStatus _threadRuntimeStatus(Object? value) {
  final statusName = _optionalString(value);
  if (statusName == null) {
    return AgentThreadRuntimeStatus.unknown;
  }
  for (final status in AgentThreadRuntimeStatus.values) {
    if (status.name == statusName) {
      return status;
    }
  }
  return AgentThreadRuntimeStatus.unknown;
}

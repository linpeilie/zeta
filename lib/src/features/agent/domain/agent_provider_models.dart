import 'package:zeta/src/features/agent/domain/agent_model_selection_models.dart';

/// [AgentProviderConfig.copyWith] 中「未传参」与「显式传 null」的区分哨兵。
const Object agentProviderConfigUnset = Object();

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

/// 内置 Codex provider 的稳定配置 id。
const String defaultAgentProviderId = 'codex';

/// 内置 Grok ACP provider 的稳定配置 id。
const String grokAgentProviderId = 'grok';

/// 内置 Claude Code provider 的稳定配置 id。
const String defaultClaudeCodeProviderId = 'claude_code';

/// Claude Code 账号数据增强开关在 Provider 配置中的稳定 key。
///
/// 这是 Zeta 自有配置，不是 Claude Code wire 字段；缺省值视为开启。
const String claudeCodeAccountDataEnrichmentKey =
    'claudeCode.accountDataEnrichment';

/// 一个可启动的 Agent provider 定义。
///
/// 该对象保存全局配置，例如 `codex app-server` 的命令、参数、环境变量和
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
    this.modelPreferences = const <String, AgentModelPreference>{},
    this.selectedPermissionOptionId,
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

  /// 按模型保存的最近一次有效配置。
  final Map<String, AgentModelPreference> modelPreferences;

  /// 中立权限选项 id（V2 唯一权限真源：Codex profile 或 Grok mode 等）。
  final String? selectedPermissionOptionId;

  /// 是否在配置列表中启用。
  final bool enabled;

  /// 解析后的权限选项 id（等同 [selectedPermissionOptionId] 去空白）。
  String? get resolvedPermissionOptionId {
    final option = selectedPermissionOptionId?.trim();
    if (option != null && option.isNotEmpty) {
      return option;
    }
    return null;
  }

  /// 未来 provider 专属配置的扩展字段。
  final Map<String, Object?> extra;

  /// 默认 Codex CLI 配置。
  ///
  /// V1 通过 stdio 启动 app-server，不额外引入 JSON-RPC 第三方依赖。
  static const AgentProviderConfig defaultCodex = AgentProviderConfig(
    id: defaultAgentProviderId,
    displayName: 'Codex',
    kind: AgentProviderKind.codexAppServer,
    command: 'codex',
    arguments: <String>['app-server'],
  );

  /// 默认 Grok CLI ACP stdio 配置。
  ///
  /// 启动 `grok agent stdio`，通过标准 ACP JSON-RPC 与 Zeta 对话。
  static const AgentProviderConfig defaultGrok = AgentProviderConfig(
    id: grokAgentProviderId,
    displayName: 'Grok',
    kind: AgentProviderKind.acp,
    command: 'grok',
    arguments: <String>['agent', 'stdio'],
  );

  /// 将内置 Provider 的历史展示名称归一化为当前产品名称。
  static String normalizeDisplayName(String id, String displayName) {
    return switch (id) {
      defaultAgentProviderId => defaultCodex.displayName,
      grokAgentProviderId => defaultGrok.displayName,
      defaultClaudeCodeProviderId => defaultClaudeCode.displayName,
      _ => displayName,
    };
  }

  /// 默认 Claude Code CLI stream-json 配置。
  ///
  /// 启动参数（`--print` / stream-json 等）由 data 层 process starter 按会话
  /// 动态拼装；此处只固定命令与 kind。
  static const AgentProviderConfig defaultClaudeCode = AgentProviderConfig(
    id: defaultClaudeCodeProviderId,
    displayName: 'Claude',
    kind: AgentProviderKind.claudeCode,
    command: 'claude',
  );

  /// 复制配置并覆盖部分字段。
  ///
  /// 权限偏好请优先用 [withPermissionPreference] 以支持显式清空；
  /// [selectedPermissionOptionId] 使用 [agentProviderConfigUnset] 区分未传与 null。
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
    Map<String, AgentModelPreference>? modelPreferences,
    Object? selectedPermissionOptionId = agentProviderConfigUnset,
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
      modelPreferences: modelPreferences ?? this.modelPreferences,
      selectedPermissionOptionId:
          identical(selectedPermissionOptionId, agentProviderConfigUnset)
          ? this.selectedPermissionOptionId
          : selectedPermissionOptionId as String?,
      enabled: enabled ?? this.enabled,
      extra: extra ?? this.extra,
    );
  }

  /// 原子设置权限偏好为单一 optionId。
  ///
  /// [optionId] 为 null 或空白时表示清除用户偏好（回落 provider 默认）。
  AgentProviderConfig withPermissionPreference(String? optionId) {
    final trimmed = optionId?.trim();
    final normalized = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    return AgentProviderConfig(
      id: id,
      displayName: displayName,
      kind: kind,
      command: command,
      arguments: arguments,
      environment: environment,
      defaultModel: defaultModel,
      selectedModel: selectedModel,
      selectedReasoningEffort: selectedReasoningEffort,
      selectedServiceTier: selectedServiceTier,
      modelPreferences: modelPreferences,
      selectedPermissionOptionId: normalized,
      enabled: enabled,
      extra: extra,
    );
  }

  /// 原子替换当前模型选择和全部模型级偏好。
  ///
  /// 与 [copyWith] 分开是为了允许将 nullable 选择字段明确清空，例如关闭
  /// Fast 时必须把 `selectedServiceTier` 持久化为 `null`。
  AgentProviderConfig withModelConfiguration({
    required AgentModelSelection selection,
    required Map<String, AgentModelPreference> preferences,
  }) {
    return AgentProviderConfig(
      id: id,
      displayName: normalizeDisplayName(id, displayName),
      kind: kind,
      command: command,
      arguments: arguments,
      environment: environment,
      defaultModel: defaultModel,
      selectedModel: selection.modelId,
      selectedReasoningEffort: selection.reasoningEffort,
      selectedServiceTier: selection.serviceTierId,
      modelPreferences: Map<String, AgentModelPreference>.unmodifiable(
        preferences,
      ),
      selectedPermissionOptionId: selectedPermissionOptionId,
      enabled: enabled,
      extra: extra,
    );
  }

  /// 序列化为 V2 白名单字段；权限只写 [selectedPermissionOptionId]。
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
      'modelPreferences': <String, Object?>{
        for (final entry in modelPreferences.entries)
          entry.key: entry.value.toJson(),
      },
      // Provider-specific legacy migration 由 data codec 负责；domain 只写 V2。
      'selectedPermissionOptionId': resolvedPermissionOptionId,
      'enabled': enabled,
      'extra': extra,
    };
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
      AgentProviderConfig.defaultGrok,
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

  /// 复制设置并覆盖部分字段。
  AgentProviderSettings copyWith({
    List<AgentProviderConfig>? providers,
    String? activeProviderId,
  }) {
    return AgentProviderSettings(
      providers: providers ?? this.providers,
      activeProviderId: activeProviderId ?? this.activeProviderId,
    );
  }

  /// 当前写入的 settings 结构版本（V2：权限仅 optionId）。
  static const int currentVersion = 2;

  /// 可解码的 settings 外层版本；V1 权限迁移由 data codec 预处理。
  static const Set<int> supportedVersions = <int>{1, 2};

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'version': currentVersion,
      'providers': providers.map((provider) => provider.toJson()).toList(),
      'activeProviderId': activeProviderId,
    };
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

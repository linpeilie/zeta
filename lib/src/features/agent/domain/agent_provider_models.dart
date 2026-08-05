import 'package:zeta/src/features/agent/domain/agent_model_codec.dart';
import 'package:zeta/src/features/agent/domain/agent_model_selection_models.dart';
import 'package:zeta/src/features/agent/domain/agent_permission_selection_models.dart';

/// Agent 后端的类型。
///
/// UI 和会话状态只关心这个中立枚举，不直接绑定某个 CLI 的协议细节。
enum AgentProviderKind { codexAppServer, acp, cursorAcp, claudeCode }

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

/// 内置 Cursor ACP provider 的稳定配置 id。
const String cursorAgentProviderId = 'cursor';

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
    this.selectedApprovalPolicy,
    this.selectedSandboxPolicy,
    this.selectedPermissionProfileId,
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

  /// 用户选择的审批策略（`AskForApproval` 字符串变体）。
  final String? selectedApprovalPolicy;

  /// 用户选择的沙箱策略（域内 camelCase）。
  final String? selectedSandboxPolicy;

  /// 用户选择的 permission profile id（可选；Codex 兼容字段）。
  final String? selectedPermissionProfileId;

  /// 中立权限选项 id（统一主键：Codex profile 或 Grok mode 等）。
  ///
  /// 读取时若为空，会回落 [selectedPermissionProfileId] 或旧
  /// `selectedPermissionMode` 字段（见 [tryDecode]）。
  final String? selectedPermissionOptionId;

  /// 是否在配置列表中启用。
  final bool enabled;

  /// 解析后的权限选项 id（option → profile 兼容回落）。
  String? get resolvedPermissionOptionId {
    final option = selectedPermissionOptionId?.trim();
    if (option != null && option.isNotEmpty) {
      return option;
    }
    final profile = selectedPermissionProfileId?.trim();
    if (profile != null && profile.isNotEmpty) {
      return profile;
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
      _ => displayName,
    };
  }

  /// 旧 Cursor CLI ACP stdio 配置，仅供旧配置解码与退役回归测试。
  ///
  /// 该配置不加入产品目录，[DefaultAgentProviderFactory] 会拒绝创建其运行时。
  static const AgentProviderConfig defaultCursor = AgentProviderConfig(
    id: cursorAgentProviderId,
    displayName: 'Cursor Agent',
    kind: AgentProviderKind.cursorAcp,
    command: 'agent',
    arguments: <String>['acp'],
    enabled: false,
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
    Map<String, AgentModelPreference>? modelPreferences,
    String? selectedApprovalPolicy,
    String? selectedSandboxPolicy,
    String? selectedPermissionProfileId,
    String? selectedPermissionOptionId,
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
      selectedApprovalPolicy:
          selectedApprovalPolicy ?? this.selectedApprovalPolicy,
      selectedSandboxPolicy:
          selectedSandboxPolicy ?? this.selectedSandboxPolicy,
      selectedPermissionProfileId:
          selectedPermissionProfileId ?? this.selectedPermissionProfileId,
      selectedPermissionOptionId:
          selectedPermissionOptionId ?? this.selectedPermissionOptionId,
      enabled: enabled ?? this.enabled,
      extra: extra ?? this.extra,
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
      selectedApprovalPolicy: selectedApprovalPolicy,
      selectedSandboxPolicy: selectedSandboxPolicy,
      selectedPermissionProfileId: selectedPermissionProfileId,
      selectedPermissionOptionId: selectedPermissionOptionId,
      enabled: enabled,
      extra: extra,
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
      'modelPreferences': <String, Object?>{
        for (final entry in modelPreferences.entries)
          entry.key: entry.value.toJson(),
      },
      'selectedApprovalPolicy': selectedApprovalPolicy,
      'selectedSandboxPolicy': selectedSandboxPolicy,
      'selectedPermissionProfileId': selectedPermissionProfileId,
      'selectedPermissionOptionId': selectedPermissionOptionId,
      'enabled': enabled,
      'extra': extra,
    };
  }

  /// 从持久化 JSON 宽容解码 provider 配置。
  ///
  /// 解码失败返回 `null`，调用方可以回退到默认 provider；未知字段不会阻断加载，
  /// 后续协议扩展可放在 [extra] 中。
  static AgentProviderConfig? tryDecode(Object? value) {
    final map = decodeObjectMap(value);
    if (map.isEmpty) {
      return null;
    }

    final id = decodeOptionalString(map['id']);
    final displayName = decodeOptionalString(map['displayName']);
    final command = decodeOptionalString(map['command']);
    final kindName = decodeOptionalString(map['kind']);
    final kind = _providerKind(kindName);

    if (id == null || displayName == null || command == null || kind == null) {
      return null;
    }

    return AgentProviderConfig(
      id: id,
      displayName: normalizeDisplayName(id, displayName),
      kind: kind,
      command: command,
      arguments: decodeStringList(map['arguments']),
      environment: decodeStringMap(map['environment']),
      defaultModel: decodeOptionalString(map['defaultModel']),
      selectedModel: decodeOptionalString(map['selectedModel']),
      selectedReasoningEffort: decodeOptionalString(
        map['selectedReasoningEffort'],
      ),
      selectedServiceTier: decodeOptionalString(map['selectedServiceTier']),
      modelPreferences: _decodeModelPreferences(map['modelPreferences']),
      selectedApprovalPolicy:
          AgentPermissionSelectionSnapshot.normalizePersistedApprovalPolicy(
            decodeOptionalString(map['selectedApprovalPolicy']),
          ),
      selectedSandboxPolicy: decodeOptionalString(map['selectedSandboxPolicy']),
      selectedPermissionProfileId: decodeOptionalString(
        map['selectedPermissionProfileId'],
      ),
      // 统一 optionId；兼容旧 selectedPermissionMode / profile 字段。
      selectedPermissionOptionId:
          decodeOptionalString(map['selectedPermissionOptionId']) ??
          decodeOptionalString(map['selectedPermissionMode']) ??
          decodeOptionalString(map['selectedPermissionProfileId']),
      enabled: map['enabled'] is bool ? map['enabled'] as bool : true,
      extra: decodeObjectMap(map['extra']),
    );
  }
}

Map<String, AgentModelPreference> _decodeModelPreferences(Object? value) {
  final decoded = <String, AgentModelPreference>{};
  if (value is Map) {
    for (final entry in value.entries) {
      final preference = AgentModelPreference.tryDecode(entry.value);
      if (preference != null) {
        decoded[preference.modelId] = preference;
      }
    }
  } else if (value is List) {
    // 兼容早期设计稿或手工配置采用数组的形式。
    for (final item in value) {
      final preference = AgentModelPreference.tryDecode(item);
      if (preference != null) {
        decoded[preference.modelId] = preference;
      }
    }
  }
  return Map<String, AgentModelPreference>.unmodifiable(decoded);
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
  /// 旧 Cursor 配置仍会按原字段解码，但不会再自动加入新的产品目录。
  static AgentProviderSettings tryDecode(Object? value) {
    final map = decodeObjectMap(value);
    if (map['version'] != 1) {
      return const AgentProviderSettings();
    }

    final providers = _ensureBuiltinProviders(_providerList(map['providers']));
    final activeProviderId =
        decodeOptionalString(map['activeProviderId']) ?? defaultAgentProviderId;

    if (providers.isEmpty) {
      return const AgentProviderSettings();
    }

    return AgentProviderSettings(
      providers: List<AgentProviderConfig>.unmodifiable(providers),
      activeProviderId:
          providers.any((provider) => provider.id == activeProviderId) ||
              activeProviderId == cursorAgentProviderId
          ? activeProviderId
          : providers.first.id,
    );
  }

  static List<AgentProviderConfig> _providerList(Object? value) {
    if (value is! List) {
      return const <AgentProviderConfig>[
        AgentProviderConfig.defaultCodex,
        AgentProviderConfig.defaultGrok,
      ];
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

  /// 保证仍受支持的内置 Codex / Grok 始终出现。
  ///
  /// 输入中已有的旧 Cursor 配置会原样保留，但不再为新配置自动补齐。
  static List<AgentProviderConfig> _ensureBuiltinProviders(
    List<AgentProviderConfig> providers,
  ) {
    final result = List<AgentProviderConfig>.from(providers);
    final ids = result.map((provider) => provider.id).toSet();
    if (!ids.contains(AgentProviderConfig.defaultCodex.id)) {
      result.insert(0, AgentProviderConfig.defaultCodex);
    }
    if (!ids.contains(AgentProviderConfig.defaultGrok.id)) {
      result.add(AgentProviderConfig.defaultGrok);
    }
    return result;
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

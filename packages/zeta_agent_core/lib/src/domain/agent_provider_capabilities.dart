import 'package:zeta_agent_core/src/domain/agent_provider_models.dart';

/// 初始化前按 kind 查询保守静态能力。具体映射由 data/app 组合层注入。
typedef AgentProviderStaticCapabilitiesFor =
    AgentProviderCapabilities Function(AgentProviderKind kind);

/// Provider 的启动时机约束。
///
/// 该策略属于初始化前可判断的静态能力，应用层据此决定是否可以在尚未选中项目时
/// 预加载模型或启动 CLI。
class AgentProviderBootstrapPolicy {
  const AgentProviderBootstrapPolicy({
    required this.requiresWorkspace,
    required this.allowsEagerModelPreload,
  });

  /// 启动 provider 前是否必须先获得项目工作目录。
  final bool requiresWorkspace;

  /// 是否允许应用启动阶段提前初始化并拉取模型。
  final bool allowsEagerModelPreload;

  /// 不依赖工作区、可提前初始化的 provider。
  static const eager = AgentProviderBootstrapPolicy(
    requiresWorkspace: false,
    allowsEagerModelPreload: true,
  );

  /// 生命周期与工作区绑定的 provider。
  static const workspaceScoped = AgentProviderBootstrapPolicy(
    requiresWorkspace: true,
    allowsEagerModelPreload: false,
  );
}

/// Agent provider 向应用层声明的中立能力集合。
///
/// 操作是否存在以 [AgentProviderBundle] 端口是否非空为单一真源。本对象只承载：
/// 初始化前可判断的保守静态声明，以及握手后 runtime 覆盖的动态位。
/// 输入模态、reasoning effort、service tier 以模型 / runtime typed 能力为准。
///
/// 能力默认采用保守语义：只有 provider 能真实完成操作时才设为 `true`。
/// UI 用它隐藏不可用入口，应用层和 provider 自身仍需在执行前再次校验。
///
/// 权限选项选择不使用静态 capability 位：是否可用由
/// [AgentProviderBundle.permissionPolicy] 端口是否非空决定。
/// 具体厂商默认值由 data 组合层注入，本文件不列举 Provider 名称。
class AgentProviderCapabilities {
  const AgentProviderCapabilities({
    this.canCreateSession = false,
    this.canResumeSession = false,
    this.canListThreads = false,
    this.canReadHistory = false,
    this.canDeleteThread = false,
    this.canRemoveThreadFromList = false,
    this.canPrompt = false,
    this.canCancelTurn = false,
    this.canSteerTurn = false,
    this.canRenameThread = false,
    this.canArchiveThread = false,
    this.canUnarchiveThread = false,
    this.canForkThread = false,
    this.canForkThreadAtTurn = false,
    this.canCompactThread = false,
    this.supportsTextInput = true,
    this.supportsLocalImageInput = false,
    this.supportsResourceInput = false,
    this.supportsSkillInput = false,
    this.supportsPermissionRequests = false,
    this.supportsUserQuestions = false,
    this.supportsPlanApproval = false,
    this.supportsModelSelection = false,
    this.supportsModeSelection = false,
    this.supportsReasoningOptions = false,
    this.supportsServiceTierSelection = false,
    this.supportsUsage = false,
    this.bootstrapPolicy = AgentProviderBootstrapPolicy.eager,
  });

  final bool canCreateSession;
  final bool canResumeSession;
  final bool canListThreads;
  final bool canReadHistory;
  final bool canDeleteThread;

  /// 是否可只移除 Zeta 本地列表记录，不影响 provider 端历史。
  final bool canRemoveThreadFromList;
  final bool canPrompt;
  final bool canCancelTurn;
  final bool canSteerTurn;
  final bool canRenameThread;
  final bool canArchiveThread;
  final bool canUnarchiveThread;
  final bool canForkThread;

  /// 是否可在指定历史 turn 结束处创建分支。
  final bool canForkThreadAtTurn;
  final bool canCompactThread;
  final bool supportsTextInput;
  final bool supportsLocalImageInput;
  final bool supportsResourceInput;

  /// 是否支持结构化 skill 输入与 skill 目录发现。
  final bool supportsSkillInput;
  final bool supportsPermissionRequests;
  final bool supportsUserQuestions;
  final bool supportsPlanApproval;
  final bool supportsModelSelection;
  final bool supportsModeSelection;
  final bool supportsReasoningOptions;
  final bool supportsServiceTierSelection;
  final bool supportsUsage;
  final AgentProviderBootstrapPolicy bootstrapPolicy;

  AgentProviderCapabilities copyWith({
    bool? canCreateSession,
    bool? canResumeSession,
    bool? canListThreads,
    bool? canReadHistory,
    bool? canDeleteThread,
    bool? canRemoveThreadFromList,
    bool? canPrompt,
    bool? canCancelTurn,
    bool? canSteerTurn,
    bool? canRenameThread,
    bool? canArchiveThread,
    bool? canUnarchiveThread,
    bool? canForkThread,
    bool? canForkThreadAtTurn,
    bool? canCompactThread,
    bool? supportsTextInput,
    bool? supportsLocalImageInput,
    bool? supportsResourceInput,
    bool? supportsSkillInput,
    bool? supportsPermissionRequests,
    bool? supportsUserQuestions,
    bool? supportsPlanApproval,
    bool? supportsModelSelection,
    bool? supportsModeSelection,
    bool? supportsReasoningOptions,
    bool? supportsServiceTierSelection,
    bool? supportsUsage,
    AgentProviderBootstrapPolicy? bootstrapPolicy,
  }) {
    return AgentProviderCapabilities(
      canCreateSession: canCreateSession ?? this.canCreateSession,
      canResumeSession: canResumeSession ?? this.canResumeSession,
      canListThreads: canListThreads ?? this.canListThreads,
      canReadHistory: canReadHistory ?? this.canReadHistory,
      canDeleteThread: canDeleteThread ?? this.canDeleteThread,
      canRemoveThreadFromList:
          canRemoveThreadFromList ?? this.canRemoveThreadFromList,
      canPrompt: canPrompt ?? this.canPrompt,
      canCancelTurn: canCancelTurn ?? this.canCancelTurn,
      canSteerTurn: canSteerTurn ?? this.canSteerTurn,
      canRenameThread: canRenameThread ?? this.canRenameThread,
      canArchiveThread: canArchiveThread ?? this.canArchiveThread,
      canUnarchiveThread: canUnarchiveThread ?? this.canUnarchiveThread,
      canForkThread: canForkThread ?? this.canForkThread,
      canForkThreadAtTurn: canForkThreadAtTurn ?? this.canForkThreadAtTurn,
      canCompactThread: canCompactThread ?? this.canCompactThread,
      supportsTextInput: supportsTextInput ?? this.supportsTextInput,
      supportsLocalImageInput:
          supportsLocalImageInput ?? this.supportsLocalImageInput,
      supportsResourceInput:
          supportsResourceInput ?? this.supportsResourceInput,
      supportsSkillInput: supportsSkillInput ?? this.supportsSkillInput,
      supportsPermissionRequests:
          supportsPermissionRequests ?? this.supportsPermissionRequests,
      supportsUserQuestions:
          supportsUserQuestions ?? this.supportsUserQuestions,
      supportsPlanApproval: supportsPlanApproval ?? this.supportsPlanApproval,
      supportsModelSelection:
          supportsModelSelection ?? this.supportsModelSelection,
      supportsModeSelection:
          supportsModeSelection ?? this.supportsModeSelection,
      supportsReasoningOptions:
          supportsReasoningOptions ?? this.supportsReasoningOptions,
      supportsServiceTierSelection:
          supportsServiceTierSelection ?? this.supportsServiceTierSelection,
      supportsUsage: supportsUsage ?? this.supportsUsage,
      bootstrapPolicy: bootstrapPolicy ?? this.bootstrapPolicy,
    );
  }

  /// 尚未接入或已退役的 provider 使用全关闭能力，避免误显示可操作入口。
  static const unsupported = AgentProviderCapabilities();
}

import 'package:zeta/src/features/agent/domain/agent_provider_models.dart';

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
/// 能力默认采用保守语义：只有 provider 能真实完成操作时才设为 `true`。
/// UI 用它隐藏不可用入口，应用层和 provider 自身仍需在执行前再次校验。
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
    this.canRollbackThread = false,
    this.canCompactThread = false,
    this.supportsTextInput = true,
    this.supportsLocalImageInput = false,
    this.supportsResourceInput = false,
    this.supportsPermissionRequests = false,
    this.supportsUserQuestions = false,
    this.supportsPlanApproval = false,
    this.supportsModelSelection = false,
    this.supportsModeSelection = false,
    this.supportsReasoningOptions = false,
    this.supportsServiceTierSelection = false,
    this.supportsPermissionPolicySelection = false,
    this.supportsPermissionProfiles = false,
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
  final bool canRollbackThread;
  final bool canCompactThread;
  final bool supportsTextInput;
  final bool supportsLocalImageInput;
  final bool supportsResourceInput;
  final bool supportsPermissionRequests;
  final bool supportsUserQuestions;
  final bool supportsPlanApproval;
  final bool supportsModelSelection;
  final bool supportsModeSelection;
  final bool supportsReasoningOptions;
  final bool supportsServiceTierSelection;
  final bool supportsPermissionPolicySelection;
  final bool supportsPermissionProfiles;
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
    bool? canRollbackThread,
    bool? canCompactThread,
    bool? supportsTextInput,
    bool? supportsLocalImageInput,
    bool? supportsResourceInput,
    bool? supportsPermissionRequests,
    bool? supportsUserQuestions,
    bool? supportsPlanApproval,
    bool? supportsModelSelection,
    bool? supportsModeSelection,
    bool? supportsReasoningOptions,
    bool? supportsServiceTierSelection,
    bool? supportsPermissionPolicySelection,
    bool? supportsPermissionProfiles,
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
      canRollbackThread: canRollbackThread ?? this.canRollbackThread,
      canCompactThread: canCompactThread ?? this.canCompactThread,
      supportsTextInput: supportsTextInput ?? this.supportsTextInput,
      supportsLocalImageInput:
          supportsLocalImageInput ?? this.supportsLocalImageInput,
      supportsResourceInput:
          supportsResourceInput ?? this.supportsResourceInput,
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
      supportsPermissionPolicySelection:
          supportsPermissionPolicySelection ??
          this.supportsPermissionPolicySelection,
      supportsPermissionProfiles:
          supportsPermissionProfiles ?? this.supportsPermissionProfiles,
      supportsUsage: supportsUsage ?? this.supportsUsage,
      bootstrapPolicy: bootstrapPolicy ?? this.bootstrapPolicy,
    );
  }

  /// Codex app-server 当前已落地能力。
  static const codexAppServer = AgentProviderCapabilities(
    canCreateSession: true,
    canResumeSession: true,
    canListThreads: true,
    canReadHistory: true,
    canDeleteThread: true,
    canPrompt: true,
    canCancelTurn: true,
    canSteerTurn: true,
    canRenameThread: true,
    canArchiveThread: true,
    canUnarchiveThread: true,
    canForkThread: true,
    canRollbackThread: true,
    canCompactThread: true,
    supportsLocalImageInput: true,
    supportsResourceInput: true,
    supportsPermissionRequests: true,
    supportsUserQuestions: true,
    supportsPlanApproval: true,
    supportsModelSelection: true,
    supportsReasoningOptions: true,
    supportsServiceTierSelection: true,
    supportsPermissionPolicySelection: true,
    supportsPermissionProfiles: true,
    supportsUsage: true,
  );

  /// Grok ACP 当前真实可用能力。
  ///
  /// 本地图片当前只会退化为路径文本，因此不声明图片输入能力；Codex 专属 thread
  /// 操作也保持关闭，避免 UI 继续依赖静默 no-op。
  static const grokAcp = AgentProviderCapabilities(
    canCreateSession: true,
    canResumeSession: true,
    canListThreads: true,
    canReadHistory: true,
    canPrompt: true,
    canCancelTurn: true,
    supportsResourceInput: true,
    supportsPermissionRequests: true,
    supportsModelSelection: true,
    supportsReasoningOptions: true,
    supportsUsage: true,
  );

  /// Cursor ACP Phase 3 的静态能力。
  ///
  /// 本地最小索引始终可列出并移除；远端历史加载、删除、图片和资源输入必须等
  /// initialize 明确协商后再动态开启。
  static const cursorAcp = AgentProviderCapabilities(
    canCreateSession: true,
    canListThreads: true,
    canRemoveThreadFromList: true,
    canPrompt: true,
    canCancelTurn: true,
    supportsPermissionRequests: true,
    bootstrapPolicy: AgentProviderBootstrapPolicy.workspaceScoped,
  );

  /// 尚未接入的 provider 使用全关闭能力，避免误显示可操作入口。
  static const unsupported = AgentProviderCapabilities();

  /// 在 provider 尚未实例化时，根据持久化 kind 提供保守静态能力。
  static AgentProviderCapabilities defaultsFor(AgentProviderKind kind) {
    return switch (kind) {
      AgentProviderKind.codexAppServer => codexAppServer,
      AgentProviderKind.acp => grokAcp,
      AgentProviderKind.cursorAcp => cursorAcp,
      AgentProviderKind.claudeCode => unsupported,
    };
  }
}

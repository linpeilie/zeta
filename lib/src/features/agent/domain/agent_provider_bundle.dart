import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';

/// Provider 的稳定能力端口集合。
///
/// 由 [AgentProvider] 适配生成；application/presentation 只依赖这里暴露的中立
/// capability port，避免按 Provider 类型分支或接触协议实现。
final class AgentProviderBundle {
  const AgentProviderBundle({
    required this.runtime,
    required this.conversation,
    this.threadCatalog,
    this.threadSubscription,
    this.threadNaming,
    this.threadArchival,
    this.threadDeletion,
    this.threadCompaction,
    this.threadBranching,
    this.turnSteering,
    this.permissionResponses,
    this.questions,
    this.deniedActionOverride,
    this.modelCatalog,
    this.conversationModes,
    this.skills,
    this.localThreadList,
    this.sessionConfiguration,
    this.planApproval,
    this.permissionPolicy,
    this.usageQuota,
  });

  factory AgentProviderBundle.adapt(AgentProvider provider) {
    final capabilities = provider.capabilities;
    return AgentProviderBundle(
      runtime: _LegacyAgentRuntimePort(provider),
      conversation: _LegacyAgentConversationPort(provider),
      threadCatalog: capabilities.canListThreads || capabilities.canReadHistory
          ? _LegacyAgentThreadCatalogPort(provider)
          : null,
      threadSubscription: switch (provider) {
        final AgentThreadSubscriptionProvider subscriptionProvider =>
          _LegacyAgentThreadSubscriptionPort(subscriptionProvider),
        _ => null,
      },
      threadNaming: capabilities.canRenameThread
          ? _LegacyAgentThreadNamingPort(provider)
          : null,
      threadArchival:
          capabilities.canArchiveThread || capabilities.canUnarchiveThread
          ? _LegacyAgentThreadArchivalPort(provider)
          : null,
      threadDeletion: capabilities.canDeleteThread
          ? _LegacyAgentThreadDeletionPort(provider)
          : null,
      threadCompaction: capabilities.canCompactThread
          ? _LegacyAgentThreadCompactionPort(provider)
          : null,
      threadBranching: capabilities.canForkThread
          ? _LegacyAgentThreadBranchingPort(provider)
          : null,
      turnSteering: capabilities.canSteerTurn
          ? _LegacyAgentTurnSteeringPort(provider)
          : null,
      permissionResponses: capabilities.supportsPermissionRequests
          ? _LegacyAgentPermissionResponsePort(provider)
          : null,
      questions: capabilities.supportsUserQuestions
          ? switch (provider) {
              final AgentQuestionResponseProvider responder =>
                _LegacyAgentQuestionResponsePort(responder),
              _ => null,
            }
          : null,
      deniedActionOverride: switch (provider) {
        final AgentDeniedActionOverridePort overridePort => overridePort,
        _ => null,
      },
      modelCatalog:
          capabilities.supportsModelSelection ||
              capabilities.supportsReasoningOptions ||
              capabilities.supportsServiceTierSelection
          ? _LegacyAgentModelCatalogPort(provider)
          : null,
      conversationModes: switch (provider) {
        final AgentConversationModeCatalogProvider modeCatalogProvider =>
          _LegacyAgentConversationModeCatalogPort(modeCatalogProvider),
        _ => null,
      },
      skills: capabilities.supportsSkillInput
          ? switch (provider) {
              final AgentSkillsCatalogProvider skillsProvider =>
                _LegacyAgentSkillsPort(skillsProvider),
              _ => null,
            }
          : null,
      localThreadList: switch (provider) {
        final AgentLocalThreadListProvider localThreadListProvider =>
          _LegacyAgentLocalThreadListPort(localThreadListProvider),
        _ => null,
      },
      sessionConfiguration: switch (provider) {
        final AgentSessionConfigProvider sessionConfigProvider =>
          _LegacyAgentSessionConfigurationPort(sessionConfigProvider),
        _ => null,
      },
      planApproval: switch (provider) {
        final AgentPlanApprovalProvider planApprovalProvider =>
          _LegacyAgentPlanApprovalPort(planApprovalProvider),
        _ => null,
      },
      // 权限策略 port：仅由实现 AgentPermissionPolicyProvider 的 data adapter 暴露。
      permissionPolicy: switch (provider) {
        final AgentPermissionPolicyProvider policyProvider =>
          policyProvider.permissionPolicy,
        _ => null,
      },
      usageQuota: switch (provider) {
        final AgentUsageQuotaProvider usageQuotaProvider => usageQuotaProvider,
        _ => null,
      },
    );
  }

  final AgentRuntimePort runtime;
  final AgentConversationPort conversation;
  final AgentThreadCatalogPort? threadCatalog;
  final AgentThreadSubscriptionPort? threadSubscription;
  final AgentThreadNamingPort? threadNaming;
  final AgentThreadArchivalPort? threadArchival;
  final AgentThreadDeletionPort? threadDeletion;
  final AgentThreadCompactionPort? threadCompaction;
  final AgentThreadBranchingPort? threadBranching;
  final AgentTurnSteeringPort? turnSteering;
  final AgentPermissionResponsePort? permissionResponses;
  final AgentQuestionResponsePort? questions;
  final AgentDeniedActionOverridePort? deniedActionOverride;
  final AgentModelCatalogPort? modelCatalog;
  final AgentConversationModeCatalogPort? conversationModes;
  final AgentSkillsPort? skills;
  final AgentLocalThreadListPort? localThreadList;
  final AgentSessionConfigurationPort? sessionConfiguration;
  final AgentPlanApprovalPort? planApproval;

  /// 可选权限策略端口；为 null 表示 provider 不支持权限模式/profile 选择。
  final AgentPermissionPolicyPort? permissionPolicy;

  /// 可选账号套餐与用量窗口读取端口。
  final AgentUsageQuotaProvider? usageQuota;

  AgentProviderCapabilities get capabilities => runtime.capabilities;
}

/// 旧 [AgentProvider] 到 [AgentProviderBundle] 的迁移期适配入口。
extension AgentProviderBundleAdapter on AgentProvider {
  AgentProviderBundle get bundle => AgentProviderBundle.adapt(this);
}

/// 直接创建原生 [AgentProviderBundle] 的工厂。
///
/// 方法名使用 [createBundle]，避免与仍返回 raw [AgentProvider] 的
/// [AgentProviderFactory.create] 冲突。
abstract interface class AgentProviderBundleFactory {
  AgentProviderBundle createBundle(AgentProviderConfig config);
}

/// 运行时基础端口，收敛配置、生命周期和连接诊断信息。
abstract interface class AgentRuntimePort {
  AgentProviderConfig get config;

  AgentProviderCapabilities get capabilities;

  Stream<AgentEvent> get events;

  AgentRuntimeInfo? get runtimeInfo;

  AgentProviderLifecycleState get lifecycleState;

  AgentRuntimeScope? get runtimeScope;

  /// 将 Composer 当前选择同步到这个运行实例。
  ///
  /// 这是运行时配置动作，不属于模型目录读取；通过中立端口暴露后，application /
  /// presentation 不需要为了同步选择而持有原始 [AgentProvider]。
  void updateModelSelection(AgentModelSelection selection);

  Future<void> initialize();

  Future<void> dispose();
}

/// 对话核心端口。
abstract interface class AgentConversationPort {
  Future<AgentSession> startSession({
    required AgentContext context,
    AgentPermissionRequestSnapshot permissionSnapshot =
        const AgentPermissionRequestSnapshot.providerFallback(),
  });

  Future<AgentSession> resumeSession(
    String sessionId, {
    required AgentContext context,
    AgentPermissionRequestSnapshot permissionSnapshot =
        const AgentPermissionRequestSnapshot.providerFallback(),
  });

  /// 发起新回合，并把 [configuration] 作为该次调用独占的不可变快照传给 Provider。
  Future<AgentTurn> sendMessage({
    required AgentSession session,
    required AgentContext context,
    String? message,
    List<AgentUserInput>? inputs,
    String? clientUserMessageId,
    AgentTurnConfiguration configuration = const AgentTurnConfiguration(),
  });

  Future<void> cancelTurn(AgentTurn turn);
}

/// Thread 目录与历史读取端口。
abstract interface class AgentThreadCatalogPort {
  Future<AgentThreadPage> listThreads({required AgentThreadListQuery query});

  Future<AgentThreadHistorySnapshot> readThreadHistory({
    required String threadId,
    String? sessionPath,
    String? projectPath,
  });
}

/// 远端 thread 订阅释放端口。
abstract interface class AgentThreadSubscriptionPort {
  Future<void> unsubscribeThread(String threadId);
}

/// Thread 重命名端口。
abstract interface class AgentThreadNamingPort {
  Future<void> renameThread({required String threadId, required String name});
}

/// Thread 归档 / 取消归档端口。
abstract interface class AgentThreadArchivalPort {
  Future<void> archiveThread(String threadId);

  Future<void> unarchiveThread(String threadId);
}

/// Thread 删除端口。
abstract interface class AgentThreadDeletionPort {
  Future<void> deleteThread(String threadId);
}

/// Thread 上下文压缩端口。
abstract interface class AgentThreadCompactionPort {
  Future<void> compactThread(String threadId);
}

/// Thread 分支端口。
abstract interface class AgentThreadBranchingPort {
  Future<AgentSession> forkThread({
    required String threadId,
    required AgentContext context,
    AgentForkBoundary boundary = const AgentForkCurrentHead(),
    AgentPermissionRequestSnapshot permissionSnapshot =
        const AgentPermissionRequestSnapshot.providerFallback(),
  });
}

/// 活动 turn 追加指令端口。
abstract interface class AgentTurnSteeringPort {
  Future<void> steerTurn({
    required AgentSession session,
    required String expectedTurnId,
    required AgentContext context,
    String? message,
    List<AgentUserInput>? inputs,
    String? clientUserMessageId,
  });
}

/// 权限审批回写端口。
abstract interface class AgentPermissionResponsePort {
  Future<void> respondToPermission(AgentPermissionDecision decision);
}

/// 用户提问回写端口。
abstract interface class AgentQuestionResponsePort {
  Future<void> respondToQuestion(AgentQuestionResponse response);
}

/// 被拒操作人工放行端口。
///
/// 只接受 typed [AgentDeniedActionOverrideRequest]；不得接收协议对象。
abstract interface class AgentDeniedActionOverridePort {
  Future<void> approveDeniedAction(AgentDeniedActionOverrideRequest request);
}

/// 模型目录端口。
abstract interface class AgentModelCatalogPort {
  Future<AgentModelList> listModels({
    int limit = 20,
    bool includeHidden = false,
    bool forceRefresh = false,
  });
}

/// Provider 中立的对话模式目录端口。
abstract interface class AgentConversationModeCatalogPort {
  /// 读取当前运行时可用的对话模式预设。
  Future<AgentConversationModeCatalog> listConversationModes();
}

/// Provider 中立的 Skill 目录端口。
abstract interface class AgentSkillsPort {
  /// 读取指定 cwd 下可用的 skill 目录。
  Future<AgentSkillsCatalog> listSkills({
    List<String> cwds = const <String>[],
    bool forceReload = false,
  });

  /// Skill 文件变更失效信号。
  Stream<void> get skillsChanged;
}

/// 只移除 Zeta 本地 thread 列表记录的可选端口。
abstract interface class AgentLocalThreadListPort {
  Future<void> removeThreadFromList(String threadId);
}

/// Session 动态配置端口。
abstract interface class AgentSessionConfigurationPort {
  List<AgentSessionConfigOption> sessionConfigOptions(String sessionId);

  Future<void> setSessionConfigOption({
    required String sessionId,
    required String configId,
    required Object value,
  });
}

/// 独立计划审批端口。
abstract interface class AgentPlanApprovalPort {
  Future<void> respondToPlanApproval(AgentPlanApprovalDecision decision);
}

final class _LegacyAgentRuntimePort implements AgentRuntimePort {
  const _LegacyAgentRuntimePort(this._provider);

  final AgentProvider _provider;

  @override
  AgentProviderConfig get config => _provider.config;

  @override
  AgentProviderCapabilities get capabilities => _provider.capabilities;

  @override
  Stream<AgentEvent> get events => _provider.events;

  @override
  AgentRuntimeInfo? get runtimeInfo {
    return switch (_provider) {
      final AgentRuntimeInfoProvider runtimeInfoProvider =>
        runtimeInfoProvider.runtimeInfo,
      _ => null,
    };
  }

  @override
  AgentProviderLifecycleState get lifecycleState {
    return switch (_provider) {
      final AgentRuntimeLifecycleProvider lifecycleProvider =>
        lifecycleProvider.lifecycleState,
      _ => AgentProviderLifecycleState.stopped,
    };
  }

  @override
  AgentRuntimeScope? get runtimeScope {
    return switch (_provider) {
      final AgentRuntimeScopeProvider scopeProvider =>
        scopeProvider.runtimeScope,
      _ => null,
    };
  }

  @override
  void updateModelSelection(AgentModelSelection selection) {
    _provider.updateModelSelection(selection);
  }

  @override
  Future<void> dispose() => _provider.dispose();

  @override
  Future<void> initialize() => _provider.initialize();
}

final class _LegacyAgentConversationPort implements AgentConversationPort {
  const _LegacyAgentConversationPort(this._provider);

  final AgentProvider _provider;

  @override
  Future<void> cancelTurn(AgentTurn turn) => _provider.cancelTurn(turn);

  @override
  Future<AgentSession> resumeSession(
    String sessionId, {
    required AgentContext context,
    AgentPermissionRequestSnapshot permissionSnapshot =
        const AgentPermissionRequestSnapshot.providerFallback(),
  }) {
    return _provider.resumeSession(
      sessionId,
      context: context,
      permissionSnapshot: permissionSnapshot,
    );
  }

  @override
  Future<AgentTurn> sendMessage({
    required AgentSession session,
    required AgentContext context,
    String? message,
    List<AgentUserInput>? inputs,
    String? clientUserMessageId,
    AgentTurnConfiguration configuration = const AgentTurnConfiguration(),
  }) {
    return _provider.sendMessage(
      session: session,
      context: context,
      message: message,
      inputs: inputs,
      clientUserMessageId: clientUserMessageId,
      configuration: configuration,
    );
  }

  @override
  Future<AgentSession> startSession({
    required AgentContext context,
    AgentPermissionRequestSnapshot permissionSnapshot =
        const AgentPermissionRequestSnapshot.providerFallback(),
  }) {
    return _provider.startSession(
      context: context,
      permissionSnapshot: permissionSnapshot,
    );
  }
}

final class _LegacyAgentThreadCatalogPort implements AgentThreadCatalogPort {
  const _LegacyAgentThreadCatalogPort(this._provider);

  final AgentProvider _provider;

  @override
  Future<AgentThreadPage> listThreads({required AgentThreadListQuery query}) {
    return _provider.listThreads(query: query);
  }

  @override
  Future<AgentThreadHistorySnapshot> readThreadHistory({
    required String threadId,
    String? sessionPath,
    String? projectPath,
  }) {
    return _provider.readThreadHistory(
      threadId: threadId,
      sessionPath: sessionPath,
      projectPath: projectPath,
    );
  }
}

final class _LegacyAgentThreadSubscriptionPort
    implements AgentThreadSubscriptionPort {
  const _LegacyAgentThreadSubscriptionPort(this._provider);

  final AgentThreadSubscriptionProvider _provider;

  @override
  Future<void> unsubscribeThread(String threadId) {
    return _provider.unsubscribeThread(threadId);
  }
}

final class _LegacyAgentThreadNamingPort implements AgentThreadNamingPort {
  const _LegacyAgentThreadNamingPort(this._provider);

  final AgentProvider _provider;

  @override
  Future<void> renameThread({required String threadId, required String name}) {
    return _provider.renameThread(threadId: threadId, name: name);
  }
}

final class _LegacyAgentThreadArchivalPort implements AgentThreadArchivalPort {
  const _LegacyAgentThreadArchivalPort(this._provider);

  final AgentProvider _provider;

  @override
  Future<void> archiveThread(String threadId) {
    return _provider.archiveThread(threadId);
  }

  @override
  Future<void> unarchiveThread(String threadId) {
    return _provider.unarchiveThread(threadId);
  }
}

final class _LegacyAgentThreadDeletionPort implements AgentThreadDeletionPort {
  const _LegacyAgentThreadDeletionPort(this._provider);

  final AgentProvider _provider;

  @override
  Future<void> deleteThread(String threadId) {
    return _provider.deleteThread(threadId);
  }
}

final class _LegacyAgentThreadCompactionPort
    implements AgentThreadCompactionPort {
  const _LegacyAgentThreadCompactionPort(this._provider);

  final AgentProvider _provider;

  @override
  Future<void> compactThread(String threadId) {
    return _provider.compactThread(threadId);
  }
}

final class _LegacyAgentThreadBranchingPort
    implements AgentThreadBranchingPort {
  const _LegacyAgentThreadBranchingPort(this._provider);

  final AgentProvider _provider;

  @override
  Future<AgentSession> forkThread({
    required String threadId,
    required AgentContext context,
    AgentForkBoundary boundary = const AgentForkCurrentHead(),
    AgentPermissionRequestSnapshot permissionSnapshot =
        const AgentPermissionRequestSnapshot.providerFallback(),
  }) {
    return _provider.forkThread(
      threadId: threadId,
      context: context,
      boundary: boundary,
      permissionSnapshot: permissionSnapshot,
    );
  }
}

final class _LegacyAgentTurnSteeringPort implements AgentTurnSteeringPort {
  const _LegacyAgentTurnSteeringPort(this._provider);

  final AgentProvider _provider;

  @override
  Future<void> steerTurn({
    required AgentSession session,
    required String expectedTurnId,
    required AgentContext context,
    String? message,
    List<AgentUserInput>? inputs,
    String? clientUserMessageId,
  }) {
    return _provider.steerTurn(
      session: session,
      expectedTurnId: expectedTurnId,
      context: context,
      message: message,
      inputs: inputs,
      clientUserMessageId: clientUserMessageId,
    );
  }
}

final class _LegacyAgentPermissionResponsePort
    implements AgentPermissionResponsePort {
  const _LegacyAgentPermissionResponsePort(this._provider);

  final AgentProvider _provider;

  @override
  Future<void> respondToPermission(AgentPermissionDecision decision) {
    return _provider.respondToPermission(decision);
  }
}

final class _LegacyAgentQuestionResponsePort
    implements AgentQuestionResponsePort {
  const _LegacyAgentQuestionResponsePort(this._provider);

  final AgentQuestionResponseProvider _provider;

  @override
  Future<void> respondToQuestion(AgentQuestionResponse response) {
    return _provider.respondToQuestion(response);
  }
}

final class _LegacyAgentModelCatalogPort implements AgentModelCatalogPort {
  const _LegacyAgentModelCatalogPort(this._provider);

  final AgentProvider _provider;

  @override
  Future<AgentModelList> listModels({
    int limit = 20,
    bool includeHidden = false,
    bool forceRefresh = false,
  }) {
    if (forceRefresh && _provider is AgentRefreshableModelCatalogProvider) {
      return (_provider as AgentRefreshableModelCatalogProvider).refreshModels(
        limit: limit,
        includeHidden: includeHidden,
      );
    }
    return _provider.listModels(limit: limit, includeHidden: includeHidden);
  }
}

final class _LegacyAgentConversationModeCatalogPort
    implements AgentConversationModeCatalogPort {
  const _LegacyAgentConversationModeCatalogPort(this._provider);

  final AgentConversationModeCatalogProvider _provider;

  @override
  Future<AgentConversationModeCatalog> listConversationModes() {
    return _provider.listConversationModes();
  }
}

final class _LegacyAgentSkillsPort implements AgentSkillsPort {
  const _LegacyAgentSkillsPort(this._provider);

  final AgentSkillsCatalogProvider _provider;

  @override
  Future<AgentSkillsCatalog> listSkills({
    List<String> cwds = const <String>[],
    bool forceReload = false,
  }) {
    return _provider.listSkills(cwds: cwds, forceReload: forceReload);
  }

  @override
  Stream<void> get skillsChanged => _provider.skillsChanged;
}

final class _LegacyAgentLocalThreadListPort
    implements AgentLocalThreadListPort {
  const _LegacyAgentLocalThreadListPort(this._provider);

  final AgentLocalThreadListProvider _provider;

  @override
  Future<void> removeThreadFromList(String threadId) {
    return _provider.removeThreadFromList(threadId);
  }
}

final class _LegacyAgentSessionConfigurationPort
    implements AgentSessionConfigurationPort {
  const _LegacyAgentSessionConfigurationPort(this._provider);

  final AgentSessionConfigProvider _provider;

  @override
  List<AgentSessionConfigOption> sessionConfigOptions(String sessionId) {
    return _provider.sessionConfigOptions(sessionId);
  }

  @override
  Future<void> setSessionConfigOption({
    required String sessionId,
    required String configId,
    required Object value,
  }) {
    return _provider.setSessionConfigOption(
      sessionId: sessionId,
      configId: configId,
      value: value,
    );
  }
}

final class _LegacyAgentPlanApprovalPort implements AgentPlanApprovalPort {
  const _LegacyAgentPlanApprovalPort(this._provider);

  final AgentPlanApprovalProvider _provider;

  @override
  Future<void> respondToPlanApproval(AgentPlanApprovalDecision decision) {
    return _provider.respondToPlanApproval(decision);
  }
}

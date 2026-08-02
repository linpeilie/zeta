import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';

/// Phase 2 迁移期的 Provider 能力端口集合。
///
/// 当前仍由旧 [AgentProvider] 适配生成，应用层逐步改为依赖 bundle 暴露的端口，
/// 避免继续通过 `is SomeOptionalProvider` 直接耦合旧接口层。
final class AgentProviderBundle {
  const AgentProviderBundle({
    required this.runtime,
    required this.conversation,
    this.threadCatalog,
    this.threadMutations,
    this.threadBranching,
    this.turnSteering,
    this.interactions,
    this.modelCatalog,
    this.conversationModes,
    this.skills,
    this.localThreadList,
    this.sessionConfiguration,
    this.planApproval,
  });

  factory AgentProviderBundle.adapt(AgentProvider provider) {
    final capabilities = provider.capabilities;
    return AgentProviderBundle(
      runtime: _LegacyAgentRuntimePort(provider),
      conversation: _LegacyAgentConversationPort(provider),
      threadCatalog: capabilities.canListThreads || capabilities.canReadHistory
          ? _LegacyAgentThreadCatalogPort(provider)
          : null,
      threadMutations:
          capabilities.canRenameThread ||
              capabilities.canArchiveThread ||
              capabilities.canUnarchiveThread ||
              capabilities.canDeleteThread ||
              capabilities.canCompactThread
          ? _LegacyAgentThreadMutationsPort(provider)
          : null,
      threadBranching: capabilities.canForkThread
          ? _LegacyAgentThreadBranchingPort(provider)
          : null,
      turnSteering: capabilities.canSteerTurn
          ? _LegacyAgentTurnSteeringPort(provider)
          : null,
      interactions:
          capabilities.supportsPermissionRequests ||
              capabilities.supportsUserQuestions
          ? _LegacyAgentInteractionPort(provider, switch (provider) {
              final AgentQuestionResponseProvider responder => responder,
              _ => null,
            })
          : null,
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
    );
  }

  final AgentRuntimePort runtime;
  final AgentConversationPort conversation;
  final AgentThreadCatalogPort? threadCatalog;
  final AgentThreadMutationsPort? threadMutations;
  final AgentThreadBranchingPort? threadBranching;
  final AgentTurnSteeringPort? turnSteering;
  final AgentInteractionPort? interactions;
  final AgentModelCatalogPort? modelCatalog;
  final AgentConversationModeCatalogPort? conversationModes;
  final AgentSkillsPort? skills;
  final AgentLocalThreadListPort? localThreadList;
  final AgentSessionConfigurationPort? sessionConfiguration;
  final AgentPlanApprovalPort? planApproval;

  AgentProvider get provider => runtime.provider;

  AgentProviderCapabilities get capabilities => runtime.capabilities;
}

/// 旧 [AgentProvider] 到 [AgentProviderBundle] 的迁移期适配入口。
extension AgentProviderBundleAdapter on AgentProvider {
  AgentProviderBundle get bundle => AgentProviderBundle.adapt(this);
}

/// 运行时基础端口，收敛配置、生命周期和连接诊断信息。
abstract interface class AgentRuntimePort {
  AgentProvider get provider;

  AgentProviderConfig get config;

  AgentProviderCapabilities get capabilities;

  Stream<AgentEvent> get events;

  AgentRuntimeInfo? get runtimeInfo;

  AgentProviderLifecycleState get lifecycleState;

  AgentRuntimeScope? get runtimeScope;

  Future<void> initialize();

  Future<void> dispose();
}

/// 对话核心端口。
abstract interface class AgentConversationPort {
  Future<AgentSession> startSession({required AgentContext context});

  Future<AgentSession> resumeSession(
    String sessionId, {
    required AgentContext context,
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

  Future<void> unsubscribeThread(String threadId);
}

/// Thread 变更端口。
abstract interface class AgentThreadMutationsPort {
  Future<void> renameThread({required String threadId, required String name});

  Future<void> archiveThread(String threadId);

  Future<void> unarchiveThread(String threadId);

  Future<void> deleteThread(String threadId);

  Future<void> compactThread(String threadId);
}

/// Thread 分支端口。
abstract interface class AgentThreadBranchingPort {
  Future<AgentSession> forkThread({
    required String threadId,
    required AgentContext context,
    AgentForkBoundary boundary = const AgentForkCurrentHead(),
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

/// 用户交互回写端口。
abstract interface class AgentInteractionPort {
  Future<void> respondToPermission(AgentPermissionDecision decision);

  Future<void> respondToQuestion(AgentQuestionResponse response);

  Future<void> approveGuardianDeniedAction({
    required String threadId,
    required Object event,
  });
}

/// 模型目录端口。
abstract interface class AgentModelCatalogPort {
  Future<AgentModelList> listModels({
    int limit = 20,
    bool includeHidden = false,
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
  const _LegacyAgentRuntimePort(this.provider);

  @override
  final AgentProvider provider;

  @override
  AgentProviderConfig get config => provider.config;

  @override
  AgentProviderCapabilities get capabilities => provider.capabilities;

  @override
  Stream<AgentEvent> get events => provider.events;

  @override
  AgentRuntimeInfo? get runtimeInfo {
    return switch (provider) {
      final AgentRuntimeInfoProvider runtimeInfoProvider =>
        runtimeInfoProvider.runtimeInfo,
      _ => null,
    };
  }

  @override
  AgentProviderLifecycleState get lifecycleState {
    return switch (provider) {
      final AgentRuntimeLifecycleProvider lifecycleProvider =>
        lifecycleProvider.lifecycleState,
      _ => AgentProviderLifecycleState.stopped,
    };
  }

  @override
  AgentRuntimeScope? get runtimeScope {
    return switch (provider) {
      final AgentRuntimeScopeProvider scopeProvider =>
        scopeProvider.runtimeScope,
      _ => null,
    };
  }

  @override
  Future<void> dispose() => provider.dispose();

  @override
  Future<void> initialize() => provider.initialize();
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
  }) {
    return _provider.resumeSession(sessionId, context: context);
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
  Future<AgentSession> startSession({required AgentContext context}) {
    return _provider.startSession(context: context);
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

  @override
  Future<void> unsubscribeThread(String threadId) {
    return _provider.unsubscribeThread(threadId);
  }
}

final class _LegacyAgentThreadMutationsPort
    implements AgentThreadMutationsPort {
  const _LegacyAgentThreadMutationsPort(this._provider);

  final AgentProvider _provider;

  @override
  Future<void> archiveThread(String threadId) {
    return _provider.archiveThread(threadId);
  }

  @override
  Future<void> compactThread(String threadId) {
    return _provider.compactThread(threadId);
  }

  @override
  Future<void> deleteThread(String threadId) {
    return _provider.deleteThread(threadId);
  }

  @override
  Future<void> renameThread({required String threadId, required String name}) {
    return _provider.renameThread(threadId: threadId, name: name);
  }

  @override
  Future<void> unarchiveThread(String threadId) {
    return _provider.unarchiveThread(threadId);
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
  }) {
    return _provider.forkThread(
      threadId: threadId,
      context: context,
      boundary: boundary,
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

final class _LegacyAgentInteractionPort implements AgentInteractionPort {
  const _LegacyAgentInteractionPort(this._provider, this._questionResponder);

  final AgentProvider _provider;
  final AgentQuestionResponseProvider? _questionResponder;

  @override
  Future<void> approveGuardianDeniedAction({
    required String threadId,
    required Object event,
  }) {
    return _provider.approveGuardianDeniedAction(
      threadId: threadId,
      event: event,
    );
  }

  @override
  Future<void> respondToPermission(AgentPermissionDecision decision) {
    return _provider.respondToPermission(decision);
  }

  @override
  Future<void> respondToQuestion(AgentQuestionResponse response) {
    final responder = _questionResponder;
    if (responder == null) {
      return Future<void>.error(
        UnsupportedError('Provider does not support user questions'),
      );
    }
    return responder.respondToQuestion(response);
  }
}

final class _LegacyAgentModelCatalogPort implements AgentModelCatalogPort {
  const _LegacyAgentModelCatalogPort(this._provider);

  final AgentProvider _provider;

  @override
  Future<AgentModelList> listModels({
    int limit = 20,
    bool includeHidden = false,
  }) {
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

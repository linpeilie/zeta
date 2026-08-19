// Capability ports intentionally remain independently implementable interfaces.
// ignore_for_file: one_member_abstracts

import 'package:agent_provider_contracts/src/bundle/agent_provider_capabilities.dart';
import 'package:agent_provider_contracts/src/models/models.dart';

/// Provider 的稳定能力端口集合。
///
/// Application / Presentation 只依赖这里暴露的中立 capability port，
/// 避免按 Provider 类型分支或接触协议实现。
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

/// 直接创建原生 [AgentProviderBundle] 的工厂。
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
  /// presentation 不需要为了同步选择而持有原始 runtime 实现。
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

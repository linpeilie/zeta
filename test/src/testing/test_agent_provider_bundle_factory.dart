import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 测试用 Bundle 工厂：把实现了中立端口的 host 组装成 `AgentProviderBundle`。
///
/// `create` 返回 host 对象本身，便于测试断言"拿到的是哪个实例"。
///
/// **可选端口按 host 实际实现推断**（见 [testAgentProviderBundle]）。这不是过渡
/// 期的遗留写法——测试 host 各自实现的可选端口子集不同，若在每个调用点手写完整
/// 端口列表，等于把 capability 矩阵复制 11 份，改一个端口要同步改 11 处。
/// 必选端口（runtime / conversation）仍然强制校验，缺失直接抛错而非静默降级。
mixin TestAgentProviderBundleFactory implements AgentProviderBundleFactory {
  Object create(AgentProviderConfig config);

  @override
  AgentProviderBundle createBundle(AgentProviderConfig config) {
    return testAgentProviderBundle(create(config));
  }
}

/// 按 host 实际实现的端口组装 Bundle。
///
/// 必选端口缺失时 **fail-closed**（抛 `StateError`），不构造半残的 Bundle。
AgentProviderBundle testAgentProviderBundle(Object host) {
  final runtime = host;
  if (runtime is! AgentRuntimePort) {
    throw StateError('test host must implement AgentRuntimePort');
  }
  if (host is! AgentConversationPort) {
    throw StateError('test host must implement AgentConversationPort');
  }
  return AgentProviderBundle(
    runtime: runtime,
    conversation: host,
    threadCatalog: _asPort<AgentThreadCatalogPort>(host),
    threadSubscription: _asPort<AgentThreadSubscriptionPort>(host),
    threadNaming: _asPort<AgentThreadNamingPort>(host),
    threadArchival: _asPort<AgentThreadArchivalPort>(host),
    threadDeletion: _asPort<AgentThreadDeletionPort>(host),
    threadCompaction: _asPort<AgentThreadCompactionPort>(host),
    threadBranching: _asPort<AgentThreadBranchingPort>(host),
    turnSteering: _asPort<AgentTurnSteeringPort>(host),
    permissionResponses: _asPort<AgentPermissionResponsePort>(host),
    questions: _asPort<AgentQuestionResponsePort>(host),
    deniedActionOverride: _asPort<AgentDeniedActionOverridePort>(host),
    modelCatalog: _asPort<AgentModelCatalogPort>(host),
    conversationModes: _asPort<AgentConversationModeCatalogPort>(host),
    skills: _asPort<AgentSkillsPort>(host),
    localThreadList: _asPort<AgentLocalThreadListPort>(host),
    sessionConfiguration: _asPort<AgentSessionConfigurationPort>(host),
    planApproval: _asPort<AgentPlanApprovalPort>(host),
    permissionPolicy: switch (host) {
      final TestPermissionPolicyHost policyHost => policyHost.permissionPolicy,
      _ => null,
    },
    usageQuota: _asPort<AgentUsageQuotaProvider>(host),
  );
}

T? _asPort<T>(Object host) => host is T ? host as T : null;

/// 测试 host 可选暴露权限策略 port。
abstract interface class TestPermissionPolicyHost {
  AgentPermissionPolicyPort get permissionPolicy;
}

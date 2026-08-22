import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 测试用：把实现了中立端口的 host 收成 Bundle。
///
/// `create` 仍返回 host 对象，便于测试记录实例；S5 之后不再经过 adapt()。
mixin LegacyBundleFactoryMixin implements AgentProviderBundleFactory {
  Object create(AgentProviderConfig config);

  @override
  AgentProviderBundle createBundle(AgentProviderConfig config) {
    return nativeTestBundle(create(config));
  }
}

/// 按 host 实际实现的端口组装原生 Bundle。
AgentProviderBundle nativeTestBundle(Object host) {
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

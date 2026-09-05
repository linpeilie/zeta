import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_provider_sdk/zeta_agent_provider_sdk.dart';
import 'datasources/app_server/codex_app_server_agent_provider.dart';

/// 由已构造的 Codex adapter 组装原生 Bundle。
AgentProviderBundle nativeBundleFromCodex(
  CodexAppServerAgentProvider provider,
) {
  return AgentProviderBundle(
    runtime: provider,
    conversation: provider,
    threadCatalog: provider,
    threadSubscription: provider,
    threadNaming: provider,
    threadArchival: provider,
    threadDeletion: provider,
    threadCompaction: provider,
    threadBranching: provider,
    turnSteering: provider,
    permissionResponses: provider,
    questions: provider,
    deniedActionOverride: provider,
    modelCatalog: provider,
    conversationModes: provider,
    skills: provider,
    permissionPolicy: provider.permissionPolicy,
    usageQuota: provider,
  );
}

/// 直接创建 Codex 原生 Bundle。
AgentProviderBundle createCodexBundle(
  AgentProviderConfig config, {
  JsonRpcPeer? peer,
  JsonRpcPeerFactory? peerFactory,
  AgentUiTextCatalog textCatalog = const FallbackAgentUiTextCatalog(),
}) {
  return nativeBundleFromCodex(
    CodexAppServerAgentProvider(
      config: config,
      peer: peer,
      peerFactory: peerFactory,
      textCatalog: textCatalog,
    ),
  );
}

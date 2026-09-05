import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_provider_sdk/zeta_agent_provider_sdk.dart';
import 'datasources/acp/grok_acp_agent_provider.dart';

/// 由已构造的 Grok adapter 组装原生 Bundle。
AgentProviderBundle nativeBundleFromGrok(GrokAcpAgentProvider provider) {
  return AgentProviderBundle(
    runtime: provider,
    conversation: provider,
    threadCatalog: provider,
    threadNaming: provider,
    threadDeletion: provider,
    permissionResponses: provider,
    questions: provider,
    modelCatalog: provider,
    conversationModes: provider,
    skills: provider,
    planApproval: provider,
    permissionPolicy: provider.permissionPolicy,
    usageQuota: provider,
  );
}

/// 直接创建 Grok 原生 Bundle。
AgentProviderBundle createGrokBundle(
  AgentProviderConfig config, {
  JsonRpcPeer? peer,
  JsonRpcPeerFactory? peerFactory,
  AgentUiTextCatalog textCatalog = const FallbackAgentUiTextCatalog(),
}) {
  return nativeBundleFromGrok(
    GrokAcpAgentProvider(
      config: config,
      peer: peer,
      peerFactory: peerFactory,
      textCatalog: textCatalog,
    ),
  );
}

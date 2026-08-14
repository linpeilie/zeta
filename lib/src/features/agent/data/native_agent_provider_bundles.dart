import 'package:zeta/src/features/agent/data/datasources/acp/grok_acp_agent_provider.dart'
    hide JsonRpcPeerFactory;
import 'package:zeta/src/features/agent/data/datasources/app_server/codex_app_server_agent_provider.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_agent_provider.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_cli_metadata_coordinator.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_hidden_thread_store.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_permission_policy_adapter.dart';
import 'package:zeta/src/features/agent/data/datasources/transport/json_rpc_stdio_transport.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider_bundle.dart';

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

/// 由已构造的 Claude Code adapter 组装原生 Bundle。
AgentProviderBundle nativeBundleFromClaudeCode(
  ClaudeCodeAgentProvider provider,
) {
  return AgentProviderBundle(
    runtime: provider,
    conversation: provider,
    threadCatalog: provider,
    threadCompaction: provider,
    permissionResponses: provider,
    questions: provider,
    modelCatalog: provider,
    localThreadList: provider,
    planApproval: provider,
    permissionPolicy: provider.permissionPolicy,
    usageQuota: provider,
  );
}

/// 直接创建 Codex 原生 Bundle。
AgentProviderBundle createCodexBundle(
  AgentProviderConfig config, {
  JsonRpcPeer? peer,
  JsonRpcPeerFactory? peerFactory,
}) {
  return nativeBundleFromCodex(
    CodexAppServerAgentProvider(
      config: config,
      peer: peer,
      peerFactory: peerFactory,
    ),
  );
}

/// 直接创建 Grok 原生 Bundle。
AgentProviderBundle createGrokBundle(
  AgentProviderConfig config, {
  JsonRpcPeer? peer,
  JsonRpcPeerFactory? peerFactory,
}) {
  return nativeBundleFromGrok(
    GrokAcpAgentProvider(config: config, peer: peer, peerFactory: peerFactory),
  );
}

/// 直接创建 Claude Code 原生 Bundle。
AgentProviderBundle createClaudeCodeBundle(
  AgentProviderConfig config, {
  ClaudeCodeCliMetadataLoader? metadataLoader,
  ClaudeCodeSessionDecisionStoreFactory? sessionDecisionStoreFactory,
  ClaudeCodeHiddenThreadStore? hiddenThreadStore,
  ProcessStarter? processStarter,
}) {
  return nativeBundleFromClaudeCode(
    ClaudeCodeAgentProvider(
      config: config,
      metadataLoader: metadataLoader,
      sessionDecisionStoreFactory: sessionDecisionStoreFactory,
      hiddenThreadStore: hiddenThreadStore,
      processStarter: processStarter,
    ),
  );
}

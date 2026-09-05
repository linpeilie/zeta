import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_provider_sdk/zeta_agent_provider_sdk.dart';
import 'datasources/claude_code/claude_code_cli_metadata_coordinator.dart';
import 'datasources/claude_code/claude_code_agent_provider.dart';
import 'datasources/claude_code/claude_code_permission_policy_adapter.dart';
import 'datasources/claude_code/claude_code_hidden_thread_store.dart';

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

/// 直接创建 Claude Code 原生 Bundle。
AgentProviderBundle createClaudeCodeBundle(
  AgentProviderConfig config, {
  ClaudeCodeCliMetadataLoader? metadataLoader,
  ClaudeCodeSessionDecisionStoreFactory? sessionDecisionStoreFactory,
  ClaudeCodeHiddenThreadStore? hiddenThreadStore,
  ProcessStarter? processStarter,
  AgentUiTextCatalog textCatalog = const FallbackAgentUiTextCatalog(),
}) {
  return nativeBundleFromClaudeCode(
    ClaudeCodeAgentProvider(
      config: config,
      metadataLoader: metadataLoader,
      sessionDecisionStoreFactory: sessionDecisionStoreFactory,
      hiddenThreadStore: hiddenThreadStore,
      processStarter: processStarter,
      textCatalog: textCatalog,
    ),
  );
}

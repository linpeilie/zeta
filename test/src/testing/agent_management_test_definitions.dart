export 'agent_provider_implementations.dart'
    show
        codexAgentManagementDefinition,
        grokAgentManagementDefinition,
        claudeCodeAgentManagementDefinition;
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'agent_provider_implementations.dart';

final Map<String, AgentDefinition> testAgentManagementDefinitions =
    Map.unmodifiable({
      for (final c in testAgentManagementContributions)
        c.providerId: c.definition,
    });
final List<AgentManagementContribution> testAgentManagementContributions =
    List.unmodifiable([
      createCodexManagementContribution(),
      createGrokManagementContribution(),
      createClaudeCodeManagementContribution(),
    ]);
final List<AgentUsageContribution> testAgentUsageContributions =
    List.unmodifiable([
      createCodexUsageContribution(),
      createGrokUsageContribution(),
      createClaudeCodeUsageContribution(),
    ]);
const AgentCliManagementCapabilities testClaudeManagementCapabilities =
    claudeCodeManagementCapabilities;

/// 持久化字节的测试样本；e2e 校验它与插件声明一致。
const String testAccountDataEnrichmentKey = 'claudeCode.accountDataEnrichment';

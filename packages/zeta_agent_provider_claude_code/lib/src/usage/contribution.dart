import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta_agent_provider_claude_code/claude_code_plugin.dart';
import 'claude_code_token_usage_source.dart';

/// 用量源沿用宿主提供的分区端口及默认文案。
AgentUsageContribution createClaudeCodeUsageContribution() =>
    AgentUsageContribution(
      providerType: claudeCodeAgentProviderType,
      createSource: (services, config) => ClaudeCodeTokenUsageSource(
        config: config,
        partitionStore: services.partitionPort,
        textCatalog: services.textCatalog,
      ),
    );

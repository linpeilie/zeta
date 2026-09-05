import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta_agent_provider_grok/grok_plugin.dart';
import 'grok_token_usage_source.dart';

/// 用量源沿用宿主提供的分区端口及默认文案。
AgentUsageContribution createGrokUsageContribution() => AgentUsageContribution(
  providerType: grokAgentProviderType,
  createSource: (services, config) => GrokTokenUsageSource(
    config: config,
    partitionStore: services.partitionPort,
    textCatalog: services.textCatalog,
  ),
);

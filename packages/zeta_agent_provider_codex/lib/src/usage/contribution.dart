import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta_agent_provider_codex/codex_plugin.dart';
import 'codex_token_usage_source.dart';

/// 用量源沿用宿主提供的分区端口及默认文案。
AgentUsageContribution createCodexUsageContribution() => AgentUsageContribution(
  providerType: codexAgentProviderType,
  createSource: (services, config) => CodexTokenUsageSource(
    config: config,
    partitionStore: services.partitionPort,
    textCatalog: services.textCatalog,
  ),
);

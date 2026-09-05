import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';

/// 插件拥有的管理元数据，字段值保持原定义。
const AgentDefinition grokAgentManagementDefinition = AgentDefinition(
  id: 'grok',
  displayName: 'Grok',
  vendor: 'xAI',
  commandName: 'grok',
  protocol: 'ACP JSON-RPC',
  transport: 'stdin / stdout',
  configFormat: 'TOML',
  defaultConfigRelativePath: '.grok/config.toml',
  npmPackage: '',
);

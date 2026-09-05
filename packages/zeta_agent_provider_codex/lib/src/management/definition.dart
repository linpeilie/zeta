import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';

/// 插件拥有的管理元数据，字段值保持原定义。
const AgentDefinition codexAgentManagementDefinition = AgentDefinition(
  id: 'codex',
  displayName: 'Codex',
  vendor: 'OpenAI',
  commandName: 'codex',
  protocol: 'JSON-RPC',
  transport: 'stdin / stdout',
  configFormat: 'TOML',
  defaultConfigRelativePath: '.codex/config.toml',
  npmPackage: '@openai/codex',
);

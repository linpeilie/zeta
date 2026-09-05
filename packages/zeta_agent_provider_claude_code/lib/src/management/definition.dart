import '../datasources/claude_code/claude_code_provider_config.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';

/// 插件拥有的管理元数据，字段值保持原定义。
const AgentDefinition claudeCodeAgentManagementDefinition = AgentDefinition(
  id: 'claude_code',
  displayName: 'Claude',
  vendor: 'Anthropic',
  commandName: 'claude',
  protocol: 'stream-json',
  transport: 'stdin / stdout',
  configFormat: 'JSON',
  defaultConfigRelativePath: '.claude/settings.json',
  npmPackage: '@anthropic-ai/claude-code',
);

/// 管理能力与持久化增强键同源声明。
const AgentCliManagementCapabilities claudeCodeManagementCapabilities =
    AgentCliManagementCapabilities(
      accountDataEnrichmentExtraKey: claudeCodeAccountDataEnrichmentKey,
      requiresConnectionTestConfirmation: true,
    );

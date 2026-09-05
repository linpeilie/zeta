import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta_agent_provider_claude_code/claude_code_plugin.dart';
import 'definition.dart';
import 'claude_code_agent_management_repository.dart';

/// 声明管理工厂；构造对象图不会启动 CLI 或读取文件。
AgentManagementContribution createClaudeCodeManagementContribution() =>
    AgentManagementContribution(
      providerId: defaultClaudeCodeProviderId,
      definition: claudeCodeAgentManagementDefinition,
      createRepository: (services) => ClaudeCodeAgentManagementRepository(
        textCatalog: services.textCatalog,
      ),
    );

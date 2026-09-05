import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta_agent_provider_codex/codex_plugin.dart';
import 'definition.dart';
import 'codex_agent_management_repository.dart';

/// 声明管理工厂；构造对象图不会启动 CLI 或读取文件。
AgentManagementContribution createCodexManagementContribution() =>
    AgentManagementContribution(
      providerId: defaultAgentProviderId,
      definition: codexAgentManagementDefinition,
      createRepository: (services) => CodexAgentManagementRepository(
        runtimeRegistry: services.runtimeRegistry,
        modelCatalogRepository: services.modelCatalog,
        textCatalog: services.textCatalog,
      ),
    );

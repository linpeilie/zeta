import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta_agent_provider_grok/grok_plugin.dart';
import 'definition.dart';
import 'grok_agent_management_repository.dart';

/// 声明管理工厂；构造对象图不会启动 CLI 或读取文件。
AgentManagementContribution createGrokManagementContribution() =>
    AgentManagementContribution(
      providerId: grokAgentProviderId,
      definition: grokAgentManagementDefinition,
      createRepository: (services) => GrokAgentManagementRepository(
        runtimeRegistry: services.runtimeRegistry,
        modelCatalogRepository: services.modelCatalog,
        textCatalog: services.textCatalog,
      ),
    );

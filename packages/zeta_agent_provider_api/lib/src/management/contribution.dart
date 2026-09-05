import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_plugin_kernel/zeta_plugin_kernel.dart';
import 'models.dart';
import 'agent_cli_management_repository.dart';
import 'agent_management_text_catalog.dart';
import 'model_catalog_port.dart';

/// 插件管理仓库可借用的宿主服务，不授予宿主存储权限。
final class AgentManagementHostServices {
  const AgentManagementHostServices({
    required this.textCatalog,
    required this.runtimeRegistry,
    this.modelCatalog,
  });
  final AgentManagementTextCatalog textCatalog;
  final AgentProviderRuntimeRegistry runtimeRegistry;
  final AgentManagementModelCatalogPort? modelCatalog;
}

/// 激活插件声明的管理元数据与仓库工厂。
final class AgentManagementContribution extends ZetaPluginContribution {
  const AgentManagementContribution({
    required this.providerId,
    required this.definition,
    required this.createRepository,
  });
  final String providerId;
  final AgentDefinition definition;
  final AgentCliManagementRepository Function(
    AgentManagementHostServices services,
  )
  createRepository;
  @override
  String get contributionKind => 'zeta.agent.management-repository';
}

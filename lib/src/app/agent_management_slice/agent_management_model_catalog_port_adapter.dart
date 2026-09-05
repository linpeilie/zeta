import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/agent/application/agent_model_catalog_repository.dart';

/// 管理插件共享宿主缓存，不能触碰其他仓库操作。
final class AgentManagementModelCatalogPortAdapter
    implements AgentManagementModelCatalogPort {
  const AgentManagementModelCatalogPortAdapter(this.repository);
  final AgentModelCatalogRepository repository;
  @override
  Future<AgentModelCatalogLoadResult> load({
    required AgentProviderConfig config,
    required String source,
    required AgentModelCatalogLoader refreshLoader,
    bool forceRefresh = false,
  }) => repository.load(
    config: config,
    source: source,
    refreshLoader: refreshLoader,
    forceRefresh: forceRefresh,
  );
}

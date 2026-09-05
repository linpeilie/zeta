import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 按插件声明的协议类型创建用量来源；未知类型保持 unsupported。
final class ContributedAgentTokenUsageSourceRegistry
    implements AgentTokenUsageSourceRegistry {
  ContributedAgentTokenUsageSourceRegistry(
    Iterable<AgentUsageContribution> contributions, {
    required this.services,
  }) {
    final byType = <AgentProviderTypeId, AgentUsageContribution>{};
    for (final contribution in contributions) {
      if (byType.containsKey(contribution.providerType)) {
        throw StateError('Duplicate Agent usage provider type');
      }
      byType[contribution.providerType] = contribution;
    }
    if (byType.isEmpty) {
      throw StateError('No plugin contributed token usage sources');
    }
    _byType = Map.unmodifiable(byType);
  }
  late final Map<AgentProviderTypeId, AgentUsageContribution> _byType;
  final AgentUsageHostServices services;
  @override
  AgentTokenUsageSource? createFor(AgentProviderConfig config) =>
      _byType[config.kind]?.createSource(services, config);
}

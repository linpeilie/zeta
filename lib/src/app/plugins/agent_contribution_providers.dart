import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta/src/app/plugins/zeta_plugin_providers.dart';
import 'package:zeta/src/app/plugins/zeta_plugin_catalog.dart';

/// 两类宿主贡献共享同一次激活并校验的快照。
final resolvedAgentHostContributionsProvider =
    Provider<ResolvedAgentHostContributions>((ref) {
      ref.watch(resolvedAgentProviderPluginsProvider);
      return ref
          .watch(zetaPluginCatalogProvider)
          .resolveAgentHostContributions();
    }, name: 'resolvedAgentHostContributions');

/// 管理贡献的独立测试接缝；覆盖后不触发插件目录创建。
final agentManagementContributionsProvider =
    Provider<List<AgentManagementContribution>>(
      (ref) => ref.watch(resolvedAgentHostContributionsProvider).management,
      name: 'agentManagementContributions',
    );

/// 用量贡献的独立测试接缝；覆盖后不触发插件目录创建。
final agentUsageContributionsProvider = Provider<List<AgentUsageContribution>>(
  (ref) => ref.watch(resolvedAgentHostContributionsProvider).usage,
  name: 'agentUsageContributions',
);

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta/src/app/plugins/agent_provider_manifest.dart';

import 'package:zeta/src/app/composition/app_dependencies.dart';
import 'package:zeta/src/app/localization/zeta_text_catalog_providers.dart';
import 'package:zeta/src/app/plugins/zeta_plugin_catalog.dart';

/// 编译期插件目录。
///
/// 依赖显示语言（插件贡献的 Provider 会带走 [agentUiTextCatalogProvider]），
/// 因此第一次读必须发生在组合根冻结语言之后——提前读会从文本目录那里 fail-closed
/// 抛出来，而不是拿一份 fallback 文案把 Provider 建出来。
///
/// **不在这里 `ref.onDispose`**：插件目录是 Agent runtime 的上游依赖，必须等
/// runtime 全部退出之后才能关。这个顺序由
/// `ZetaAppComposition.shutdownOwnedAgentResources` 统一保证，容器只负责创建。
final zetaPluginCatalogProvider = Provider<ZetaPluginCatalog>(
  (ref) => ZetaPluginCatalog.builtIn(
    factories: zetaAgentProviderPluginFactories(
      claudeCodeSessionDecisionStoreFactory: ref.watch(
        claudeCodeSessionDecisionStoreFactoryProvider,
      ),
      claudeCodeHiddenThreadStore: ref.watch(
        claudeCodeHiddenThreadStoreProvider,
      ),
      textCatalog: ref.watch(agentUiTextCatalogProvider),
    ),
    metrics: ref.watch(zetaMetricsPortProvider),
  ),
  name: 'zetaPluginCatalog',
);

/// 激活后的 Provider 贡献。
///
/// 激活是同步的：首帧就需要 Agent Provider 工厂，异步激活会引入一个"还没有
/// 工厂"的中间态。
final resolvedAgentProviderPluginsProvider =
    Provider<ResolvedAgentProviderPlugins>(
      (ref) => ref
          .watch(zetaPluginCatalogProvider)
          .activateAndResolveAgentProviders(),
      name: 'resolvedAgentProviderPlugins',
    );

/// 插件贡献出的 Provider definitions。
final agentProviderDefinitionCatalogProvider =
    Provider<AgentProviderDefinitionCatalog>(
      (ref) => ref.watch(resolvedAgentProviderPluginsProvider).definitions,
      name: 'agentProviderDefinitionCatalog',
    );

/// 按 Provider type 路由的聚合 bundle 工厂。
///
/// 测试覆盖这一个 provider 就能换掉整条 Agent 运行链，插件目录随之不再建。
final agentProviderBundleFactoryProvider = Provider<AgentProviderBundleFactory>(
  (ref) => ref.watch(resolvedAgentProviderPluginsProvider).bundleFactory,
  name: 'agentProviderBundleFactory',
);

/// Agent Provider 运行时池。
///
/// 持有 CLI 进程与 JSON-RPC transport，**关闭顺序在插件目录之前**，见
/// `shutdownAgentResourcesInOrder`。谁覆盖谁把实例交给容器：组合根会在
/// `dispose()` 里关掉它从这个 provider 读到的实例。
final agentProviderRuntimeRegistryProvider =
    Provider<AgentProviderRuntimeRegistry>(
      (ref) => AgentProviderRuntimeRegistry(
        providerFactory: ref.watch(agentProviderBundleFactoryProvider),
        metrics: ref.watch(zetaMetricsPortProvider),
        providerMetricLabel: zetaAgentProviderDefinitionCatalog.metricLabelFor,
      ),
      name: 'agentProviderRuntimeRegistry',
    );

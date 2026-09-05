import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/app/plugins/zeta_plugin_providers.dart';
import 'package:zeta/src/app/provider_settings_slice/provider_settings_slice_runners.dart';
import 'package:zeta/src/app/storage/zeta_store_providers.dart';
import 'package:zeta/src/features/agent/application/provider_settings_slice/agent_provider_settings_slice_store.dart';

/// Provider Settings 切片的 app-session 装配。
///
/// 状态由 application notifier 唯一持有；这里仅把 Provider definition、共享模型
/// 目录仓库、配置存储和 runtime registry 收敛成中立依赖与 runner 工厂。
List<Override> providerSettingsSliceOverrides() {
  return <Override>[
    agentProviderSettingsSliceDependenciesProvider.overrideWith((ref) {
      final definitions = ref.watch(agentProviderDefinitionCatalogProvider);
      return AgentProviderSettingsSliceDependencies(
        initialSettings: definitions.defaultSettings,
        modelCatalogRepository: ref.watch(agentModelCatalogRepositoryProvider),
        staticCapabilitiesFor: definitions.staticCapabilitiesFor,
        modelCatalogSourceFor: definitions.modelCatalogSourceFor,
        globalRuntime: AgentProviderGlobalRuntime(
          runtimeRegistry: ref.watch(agentProviderRuntimeRegistryProvider),
        ),
      );
    }),
    agentProviderSettingsSliceEffectRunnerFactoryProvider.overrideWith((ref) {
      final configStore = ref.watch(agentProviderConfigStoreProvider);
      final modelCatalogRepository = ref.watch(
        agentModelCatalogRepositoryProvider,
      );
      final runtimeRegistry = ref.watch(agentProviderRuntimeRegistryProvider);
      return (notifier) => AgentProviderSettingsSliceRunnerAdapter(
        configStore: configStore,
        modelCatalogRepository: modelCatalogRepository,
        runtimeRegistry: runtimeRegistry,
        notifier: notifier,
      );
    }),
  ];
}

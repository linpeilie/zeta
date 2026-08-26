import 'package:zeta/src/app/provider_settings_slice/provider_settings_slice_composition.dart';
import 'package:zeta/src/features/agent/application/agent_model_catalog_repository.dart';
import 'package:zeta/src/features/agent/application/provider_settings_slice/agent_provider_settings_slice_store.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';

import 'ide_test_harness.dart';

final class ProviderSettingsTestComposition {
  ProviderSettingsTestComposition._({
    required this.composition,
    required this.runtimeRegistry,
    required this.ownsRuntimeRegistry,
  });

  final ProviderSettingsSliceComposition composition;
  final AgentProviderRuntimeRegistry runtimeRegistry;
  final bool ownsRuntimeRegistry;

  AgentProviderSettingsSliceStore get store => composition.store;

  Future<AgentModelCatalogLoadResult> loadActiveModelCatalog() =>
      composition.loadActiveModelCatalog();

  Future<void> dispose() async {
    composition.dispose();
    if (ownsRuntimeRegistry) {
      await runtimeRegistry.close();
    }
  }
}

ProviderSettingsTestComposition createProviderSettingsTestComposition({
  required AgentProviderConfigStore configStore,
  AgentProviderRuntimeRegistry? runtimeRegistry,
  AgentModelCatalogRepository? modelCatalogRepository,
  AgentProviderDefinitionCatalog? providerDefinitions,
}) {
  final definitions =
      providerDefinitions ?? builtInAgentProviderDefinitionCatalog;
  final catalog =
      modelCatalogRepository ??
      AgentModelCatalogRepository(
        store: MemoryAgentModelCatalogCacheStore(),
        fingerprintExtraKeysFor:
            definitions.modelCatalogFingerprintExtraKeysFor,
      );
  final registry =
      runtimeRegistry ??
      AgentProviderRuntimeRegistry(
        providerFactory: FakeAgentProviderBundleBuilder.fromFake(
          FakeAgentProvider(),
        ),
      );
  return ProviderSettingsTestComposition._(
    composition: ProviderSettingsSliceComposition.create(
      configStore: configStore,
      modelCatalogRepository: catalog,
      runtimeRegistry: registry,
      providerDefinitions: definitions,
    ),
    runtimeRegistry: registry,
    ownsRuntimeRegistry: runtimeRegistry == null,
  );
}

/// 用生产 Provider settings slice 组装测试实例，避免测试复制状态或副作用语义。
AgentProviderSettingsSliceStore createProviderSettingsTestStore({
  required AgentProviderConfigStore configStore,
  required AgentProviderRuntimeRegistry runtimeRegistry,
  AgentModelCatalogRepository? modelCatalogRepository,
  AgentProviderDefinitionCatalog? providerDefinitions,
}) {
  final definitions =
      providerDefinitions ?? builtInAgentProviderDefinitionCatalog;
  final catalog =
      modelCatalogRepository ??
      AgentModelCatalogRepository(
        store: MemoryAgentModelCatalogCacheStore(),
        fingerprintExtraKeysFor:
            definitions.modelCatalogFingerprintExtraKeysFor,
      );
  return ProviderSettingsSliceComposition.create(
    configStore: configStore,
    modelCatalogRepository: catalog,
    runtimeRegistry: runtimeRegistry,
    providerDefinitions: definitions,
  ).store;
}

extension AgentProviderSettingsSliceStoreTestDisposal
    on AgentProviderSettingsSliceStore {
  void dispose() => close();
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:zeta/src/app/provider_settings_slice/provider_settings_slice_runners.dart';
import 'package:zeta/src/features/agent/application/agent_model_catalog_repository.dart';
import 'package:zeta/src/features/agent/application/provider_settings_slice/agent_model_catalog_projection.dart';
import 'package:zeta/src/features/agent/application/provider_settings_slice/agent_provider_settings_slice_store.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta/src/app/plugins/agent_provider_manifest.dart';

import 'ide_test_harness.dart';

final class ProviderSettingsTestComposition {
  ProviderSettingsTestComposition._({
    required this.container,
    required this.runtimeRegistry,
    required this.ownsRuntimeRegistry,
  });

  final ProviderContainer container;
  final AgentProviderRuntimeRegistry runtimeRegistry;
  final bool ownsRuntimeRegistry;

  AgentProviderSettingsSliceNotifier get store =>
      container.read(agentProviderSettingsSliceProvider.notifier);

  Future<AgentModelCatalogLoadResult> loadActiveModelCatalog({
    bool forceRefresh = false,
  }) => store.loadActiveModelCatalog(forceRefresh: forceRefresh);

  AgentModelCatalogQuery queryForConfig(
    AgentProviderConfig config, {
    bool includeHidden = false,
  }) => store.queryForConfig(config, includeHidden: includeHidden);

  Future<AgentModelCatalogLoadResult> loadModelCatalog(
    AgentModelCatalogQuery query, {
    bool forceRefresh = false,
    void Function(AgentModelCatalogSnapshot snapshot)? onCacheHit,
  }) => store.loadModelCatalogQuery(
    query,
    forceRefresh: forceRefresh,
    onCacheHit: onCacheHit,
  );

  Future<void> dispose() async {
    container.dispose();
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
  final definitions = providerDefinitions ?? zetaAgentProviderDefinitionCatalog;
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
    container: _providerSettingsContainer(
      configStore: configStore,
      runtimeRegistry: registry,
      modelCatalogRepository: catalog,
      providerDefinitions: definitions,
    ),
    runtimeRegistry: registry,
    ownsRuntimeRegistry: runtimeRegistry == null,
  );
}

final _storeContainers = Expando<ProviderContainer>(
  'provider-settings-test-container',
);

/// 用生产 Provider settings notifier 组装测试实例，避免复制状态或副作用语义。
AgentProviderSettingsSliceNotifier createProviderSettingsTestStore({
  required AgentProviderConfigStore configStore,
  required AgentProviderRuntimeRegistry runtimeRegistry,
  AgentModelCatalogRepository? modelCatalogRepository,
  AgentProviderDefinitionCatalog? providerDefinitions,
}) {
  final definitions = providerDefinitions ?? zetaAgentProviderDefinitionCatalog;
  final catalog =
      modelCatalogRepository ??
      AgentModelCatalogRepository(
        store: MemoryAgentModelCatalogCacheStore(),
        fingerprintExtraKeysFor:
            definitions.modelCatalogFingerprintExtraKeysFor,
      );
  final container = _providerSettingsContainer(
    configStore: configStore,
    runtimeRegistry: runtimeRegistry,
    modelCatalogRepository: catalog,
    providerDefinitions: definitions,
  );
  final notifier = container.read(agentProviderSettingsSliceProvider.notifier);
  _storeContainers[notifier] = container;
  return notifier;
}

ProviderContainer _providerSettingsContainer({
  required AgentProviderConfigStore configStore,
  required AgentProviderRuntimeRegistry runtimeRegistry,
  required AgentModelCatalogRepository modelCatalogRepository,
  required AgentProviderDefinitionCatalog providerDefinitions,
}) {
  return ProviderContainer(
    overrides: <Override>[
      agentProviderSettingsSliceDependenciesProvider.overrideWithValue(
        AgentProviderSettingsSliceDependencies(
          initialSettings: providerDefinitions.defaultSettings,
          modelCatalogRepository: modelCatalogRepository,
          staticCapabilitiesFor: providerDefinitions.staticCapabilitiesFor,
          modelCatalogSourceFor: providerDefinitions.modelCatalogSourceFor,
          globalRuntime: AgentProviderGlobalRuntime(
            runtimeRegistry: runtimeRegistry,
          ),
        ),
      ),
      agentProviderSettingsSliceEffectRunnerFactoryProvider.overrideWithValue((
        notifier,
      ) {
        return AgentProviderSettingsSliceRunnerAdapter(
          configStore: configStore,
          modelCatalogRepository: modelCatalogRepository,
          runtimeRegistry: runtimeRegistry,
          notifier: notifier,
        );
      }),
    ],
  );
}

extension AgentProviderSettingsSliceNotifierTestDisposal
    on AgentProviderSettingsSliceNotifier {
  void dispose() {
    _storeContainers[this]?.dispose();
    _storeContainers[this] = null;
  }
}

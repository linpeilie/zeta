import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';

import 'package:zeta/src/app/provider_settings_slice/provider_settings_slice_runners.dart';
import 'package:zeta/src/features/agent/application/agent_model_catalog_repository.dart';
import 'package:zeta/src/features/agent/application/provider_settings_slice/agent_model_catalog_projection.dart';
import 'package:zeta/src/features/agent/application/provider_settings_slice/agent_provider_settings_slice_effect.dart';
import 'package:zeta/src/features/agent/application/provider_settings_slice/agent_provider_settings_slice_state.dart';
import 'package:zeta/src/features/agent/application/provider_settings_slice/agent_provider_settings_slice_store.dart';

/// Phase 3 第 2 批 2a/2b 的 app-session 组合。
///
/// store 是唯一运行态 owner；runner 持有 IO/runtime 端口；Riverpod 只镜像 store。
/// flag 关闭时不创建本对象，确保与旧 controller 二选一、无双写。
final class ProviderSettingsSliceComposition
    implements AgentModelCatalogProjectionSource {
  ProviderSettingsSliceComposition._({
    required this.store,
    required this._runner,
  });

  final AgentProviderSettingsSliceStore store;
  final AgentProviderSettingsSliceRunnerAdapter _runner;

  factory ProviderSettingsSliceComposition.create({
    required AgentProviderConfigStore configStore,
    required AgentModelCatalogRepository modelCatalogRepository,
    required AgentProviderRuntimeRegistry runtimeRegistry,
    required AgentProviderDefinitionCatalog providerDefinitions,
  }) {
    final deferredRunner = _DeferredProviderSettingsRunner();
    final store = AgentProviderSettingsSliceStore(
      initialState: AgentProviderSettingsSliceState(
        settings: providerDefinitions.defaultSettings,
      ),
      effectRunner: deferredRunner,
      modelCatalogRepository: modelCatalogRepository,
      staticCapabilitiesFor: providerDefinitions.staticCapabilitiesFor,
      modelCatalogSourceFor: providerDefinitions.modelCatalogSourceFor,
    );
    final runner = AgentProviderSettingsSliceRunnerAdapter(
      configStore: configStore,
      modelCatalogRepository: modelCatalogRepository,
      runtimeRegistry: runtimeRegistry,
      globalRuntime: AgentProviderGlobalRuntime(
        runtimeRegistry: runtimeRegistry,
      ),
      sliceStore: store,
    );
    deferredRunner.delegate = runner;
    return ProviderSettingsSliceComposition._(store: store, runner: runner);
  }

  Future<AgentModelCatalogLoadResult> loadActiveModelCatalog({
    bool forceRefresh = false,
    void Function(AgentModelCatalogSnapshot snapshot)? onCacheHit,
  }) {
    return _runner.loadActiveModelCatalog(
      forceRefresh: forceRefresh,
      onCacheHit: onCacheHit,
    );
  }

  @override
  AgentModelCatalogQuery queryForConfig(
    AgentProviderConfig config, {
    bool includeHidden = false,
  }) {
    return _runner.queryForConfig(config, includeHidden: includeHidden);
  }

  @override
  Future<AgentModelCatalogLoadResult> loadModelCatalog(
    AgentModelCatalogQuery query, {
    bool forceRefresh = false,
    void Function(AgentModelCatalogSnapshot snapshot)? onCacheHit,
  }) {
    return _runner.loadModelCatalog(
      query,
      forceRefresh: forceRefresh,
      onCacheHit: onCacheHit,
    );
  }

  void dispose() => store.close();
}

final class _DeferredProviderSettingsRunner
    implements AgentProviderSettingsSliceEffectRunner {
  AgentProviderSettingsSliceEffectRunner? delegate;

  @override
  void run(AgentProviderSettingsSliceEffect effect) => delegate?.run(effect);
}

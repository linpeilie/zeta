import 'dart:async';

import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/features/agent/application/agent_model_catalog_repository.dart';
import 'package:zeta/src/features/agent/application/provider_settings_slice/agent_model_catalog_projection.dart';
import 'package:zeta/src/features/agent/application/provider_settings_slice/agent_provider_settings_slice_effect.dart';
import 'package:zeta/src/features/agent/application/provider_settings_slice/agent_provider_settings_slice_store.dart';

final _log = zetaLoggerFor('zeta.agent.provider_settings_slice_runner');

/// Provider settings 切片的 app 组合层 effect runner。
///
/// 配置保存使用单写者队列；每个 effect 内保持旧 controller 的并行语义：配置
/// 落盘、模型目录失效与 runtime 失效一并等待后才回流 result intent。
final class AgentProviderSettingsSliceRunnerAdapter
    implements AgentProviderSettingsSliceEffectRunner {
  AgentProviderSettingsSliceRunnerAdapter({
    required AgentProviderConfigStore configStore,
    required AgentModelCatalogRepository modelCatalogRepository,
    required AgentProviderRuntimeRegistry runtimeRegistry,
    required AgentProviderGlobalRuntime globalRuntime,
    required AgentProviderSettingsSliceStore sliceStore,
  }) : this._(
         configStore,
         modelCatalogRepository,
         runtimeRegistry,
         globalRuntime,
         sliceStore,
       );

  AgentProviderSettingsSliceRunnerAdapter._(
    this._configStore,
    this._modelCatalogRepository,
    this._runtimeRegistry,
    this._globalRuntime,
    this._sliceStore,
  );

  final AgentProviderConfigStore _configStore;
  final AgentModelCatalogRepository _modelCatalogRepository;
  final AgentProviderRuntimeRegistry _runtimeRegistry;
  final AgentProviderGlobalRuntime _globalRuntime;
  final AgentProviderSettingsSliceStore _sliceStore;

  Future<void> _persistQueue = Future<void>.value();

  @override
  void run(AgentProviderSettingsSliceEffect effect) {
    switch (effect) {
      case ProviderSettingsLoadEffect():
        unawaited(_load(effect));
      case ProviderSettingsPersistEffect():
        _persistQueue = _persistQueue.then((_) => _persist(effect));
    }
  }

  Future<void> _load(ProviderSettingsLoadEffect effect) async {
    if (_sliceStore.isClosed) {
      return;
    }
    try {
      final settings = await _configStore.load();
      _sliceStore.loaded(effect.operationId, settings);
    } catch (error, stackTrace) {
      _log.w('Could not load Provider settings (${error.runtimeType})');
      _sliceStore.loadFailed(effect.operationId, error, stackTrace);
    }
  }

  Future<void> _persist(ProviderSettingsPersistEffect effect) async {
    if (_sliceStore.isClosed) {
      return;
    }
    try {
      final updated = effect.updatedConfig;
      final previous = effect.previousConfig;
      final invalidatesModelCatalog =
          updated != null &&
          (previous == null ||
              !zetaMapEquals(previous.environment, updated.environment) ||
              _modelCatalogRepository.configFingerprint(previous) !=
                  _modelCatalogRepository.configFingerprint(updated));

      final modelCatalogInvalidation = invalidatesModelCatalog
          ? _modelCatalogRepository.invalidateProvider(updated.id)
          : Future<void>.value();
      final runtimeInvalidation = updated == null
          ? Future<void>.value()
          : effect.restartProvider
          ? _runtimeRegistry.invalidateProvider(updated.id)
          : invalidatesModelCatalog
          ? _runtimeRegistry.invalidateScope(
              updated.id,
              AgentProviderRuntimeScopeKey.global,
            )
          : Future<void>.value();

      await Future.wait<void>(<Future<void>>[
        _configStore.save(effect.settings),
        modelCatalogInvalidation,
        runtimeInvalidation,
      ]);
      _sliceStore.persisted(effect.operationId);
    } catch (error, stackTrace) {
      _log.w('Could not persist Provider settings (${error.runtimeType})');
      _sliceStore.persistFailed(effect.operationId, error, stackTrace);
    }
  }

  /// 为 Riverpod family 生成不含环境值的稳定查询键。
  AgentModelCatalogQuery queryForConfig(
    AgentProviderConfig config, {
    bool includeHidden = false,
  }) {
    return AgentModelCatalogQuery(
      providerId: config.id,
      configFingerprint: _modelCatalogRepository.configFingerprint(config),
      includeHidden: includeHidden,
    );
  }

  /// 使用现有共享仓储读取查询指定的 Provider 模型目录。
  Future<AgentModelCatalogLoadResult> loadModelCatalog(
    AgentModelCatalogQuery query, {
    bool forceRefresh = false,
    void Function(AgentModelCatalogSnapshot snapshot)? onCacheHit,
  }) async {
    await _sliceStore.loadSettings();
    final config = _sliceStore.providerConfigById(query.providerId);
    if (config == null) {
      throw AgentModelCatalogQueryRejected(
        providerId: query.providerId,
        reason: AgentModelCatalogQueryRejectionReason.unknownProvider,
      );
    }
    if (queryForConfig(config, includeHidden: query.includeHidden) != query) {
      throw AgentModelCatalogQueryRejected(
        providerId: query.providerId,
        reason: AgentModelCatalogQueryRejectionReason.configChanged,
      );
    }
    if (!_sliceStore
        .capabilitiesForProviderId(config.id)
        .supportsModelSelection) {
      throw UnsupportedError(
        'Provider ${config.id} does not support model catalogs',
      );
    }
    return _modelCatalogRepository.load(
      config: config,
      source: config.displayName,
      includeHidden: query.includeHidden,
      forceRefresh: forceRefresh,
      onCacheHit: onCacheHit,
      refreshLoader: () {
        return _globalRuntime.run(config, (runtime) {
          final modelCatalog = runtime.bundle.modelCatalog;
          if (modelCatalog == null) {
            throw UnsupportedError(
              'Provider ${config.id} does not support model catalogs',
            );
          }
          return fetchAgentProviderModels(
            modelCatalog,
            forceRefresh: true,
            includeHidden: query.includeHidden,
          );
        });
      },
    );
  }

  /// 兼容 shell 预热入口：把 active Provider 转成同一个 keyed 查询。
  Future<AgentModelCatalogLoadResult> loadActiveModelCatalog({
    bool forceRefresh = false,
    void Function(AgentModelCatalogSnapshot snapshot)? onCacheHit,
  }) async {
    await _sliceStore.loadSettings();
    return loadModelCatalog(
      queryForConfig(_sliceStore.activeProviderConfig),
      forceRefresh: forceRefresh,
      onCacheHit: onCacheHit,
    );
  }
}

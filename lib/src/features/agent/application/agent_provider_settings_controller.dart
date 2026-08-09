import 'package:flutter/foundation.dart';

import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/agent/application/agent_model_catalog_repository.dart';
import 'package:zeta/src/features/agent/application/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/application/agent_provider_global_runtime.dart';
import 'package:zeta/src/features/agent/application/agent_provider_runtime_registry.dart';
import 'package:zeta/src/features/agent/application/agent_provider_settings_port.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

final _log = loggerFor('zeta.agent.provider_controller');

/// IDE 内共享的 Provider 设置控制器。
///
/// 负责配置、启停、默认 Provider、模型与权限偏好持久化。它不持有 Provider、
/// runtime lease 或会话权限状态；全局操作统一委托给 global runtime。
class AgentProviderSettingsController extends ChangeNotifier
    implements AgentProviderSettingsPort {
  AgentProviderSettingsController({
    required this.configStore,
    required this.runtimeRegistry,
    AgentModelCatalogRepository? modelCatalogRepository,
    AgentProviderGlobalRuntime? globalRuntime,
  }) : modelCatalogRepository =
           modelCatalogRepository ??
           AgentModelCatalogRepository(
             store: _MemoryAgentModelCatalogCacheStore(),
           ),
       _globalRuntime =
           globalRuntime ??
           AgentProviderGlobalRuntime(runtimeRegistry: runtimeRegistry);

  final AgentProviderConfigStore configStore;
  @override
  final AgentModelCatalogRepository modelCatalogRepository;
  final AgentProviderRuntimeRegistry runtimeRegistry;
  final AgentProviderGlobalRuntime _globalRuntime;

  AgentProviderSettings _settings = const AgentProviderSettings();
  CursorRetirementResolution _runtimeSelection = CursorRetirementPolicy.resolve(
    const AgentProviderSettings(),
  );
  Future<AgentProviderSettings>? _settingsFuture;
  bool _disposed = false;

  /// 当前 active provider 设置。
  @override
  AgentProviderSettings get settings => _settings;

  /// 当前 active provider id。
  @override
  String get activeProviderId => _runtimeSelection.effectiveProvider.id;

  /// 当前 active provider 展示名称。
  @override
  String get activeProviderName =>
      _runtimeSelection.effectiveProvider.displayName;

  /// 当前 active provider 的配置。
  @override
  AgentProviderConfig get activeProviderConfig =>
      _runtimeSelection.effectiveProvider;

  /// 当前是否存在可安全进入运行时的 Provider。
  @override
  bool get hasRuntimeProvider => _runtimeSelection.hasRuntimeProvider;

  /// 旧 Cursor 选择触发 fallback 时展示给用户的原因。
  @override
  String? get unavailableSelectionReason => _runtimeSelection.unavailableReason;

  /// 已启用的 provider 配置（用于跨 provider thread 列表等）。
  @override
  List<AgentProviderConfig> get enabledProviders {
    return List<AgentProviderConfig>.unmodifiable(
      CursorRetirementPolicy.enabledRuntimeProviders(_settings.providers),
    );
  }

  /// 指定 provider 是否允许创建新的可写会话。
  @override
  bool isProviderEnabled(String providerId) {
    if (CursorRetirementPolicy.isRetiredProviderId(providerId)) {
      return false;
    }
    for (final provider in _settings.providers) {
      if (provider.id == providerId) {
        return provider.enabled &&
            !CursorRetirementPolicy.isRetiredProvider(provider);
      }
    }
    return false;
  }

  /// 按 id 查找配置；不存在时返回 null。
  @override
  AgentProviderConfig? providerConfigById(String providerId) {
    for (final provider in _settings.providers) {
      if (provider.id == providerId) {
        return provider;
      }
    }
    return null;
  }

  /// 查询指定 provider 的保守静态能力；动态能力只在 global/session 操作上下文内读取。
  @override
  AgentProviderCapabilities capabilitiesForProviderId(String providerId) {
    final config = providerConfigById(providerId);
    if (CursorRetirementPolicy.unavailableReasonFor(
          providerId: providerId,
          config: config,
        ) !=
        null) {
      return AgentProviderCapabilities.unsupported;
    }
    if (config == null) {
      return AgentProviderCapabilities.unsupported;
    }
    return AgentProviderCapabilities.defaultsFor(config.kind);
  }

  /// 更新一个 provider 的全局配置，并按需重建运行实例。
  @override
  Future<void> updateProviderConfig(
    AgentProviderConfig updated, {
    bool restartProvider = false,
  }) async {
    await loadSettings();
    final previousConfig = providerConfigById(updated.id);
    // 环境变量值不进入可持久化指纹；在本次配置更新中仍要直接比较并失效，
    // 避免切换账号或 endpoint 后短暂复用旧目录。
    final invalidatesModelCatalog =
        previousConfig == null ||
        !mapEquals(previousConfig.environment, updated.environment) ||
        modelCatalogRepository.configFingerprint(previousConfig) !=
            modelCatalogRepository.configFingerprint(updated);
    final providers = <AgentProviderConfig>[
      for (final provider in _settings.providers)
        if (provider.id == updated.id) updated else provider,
    ];
    if (!providers.any((provider) => provider.id == updated.id)) {
      providers.add(updated);
    }
    _settings = AgentProviderSettings(
      providers: List<AgentProviderConfig>.unmodifiable(providers),
      activeProviderId: _settings.activeProviderId,
    );
    _applyRuntimeSelection();

    final shouldRestartProvider = restartProvider;
    // Repository 会在首个 await 前推进 provider generation；立即发起失效，并让
    // 缓存 I/O 与可能较慢的运行实例关闭、配置落盘并行执行。
    final Future<void> modelCatalogInvalidation = invalidatesModelCatalog
        ? modelCatalogRepository.invalidateProvider(updated.id)
        : Future<void>.value();
    if (shouldRestartProvider) {
      await runtimeRegistry.invalidateProvider(updated.id);
    }

    await configStore.save(_settings);
    await modelCatalogInvalidation;
    _notify();
  }

  /// 启用或禁用 provider；禁用时终止当前运行实例。
  @override
  Future<void> setProviderEnabled(String providerId, bool enabled) async {
    await loadSettings();
    final unavailable = unavailableReasonForProviderId(providerId);
    if (unavailable != null) {
      throw UnsupportedError(unavailable);
    }
    final current = _settings.providers.firstWhere(
      (provider) => provider.id == providerId,
      orElse: () => AgentProviderConfig.defaultCodex,
    );
    if (current.enabled == enabled) {
      return;
    }
    await updateProviderConfig(
      current.copyWith(enabled: enabled),
      restartProvider: !enabled,
    );
    if (!enabled && _settings.activeProviderId == providerId) {
      final fallbacks = CursorRetirementPolicy.enabledRuntimeProviders(
        _settings.providers,
      ).where((provider) => provider.id != providerId);
      if (fallbacks.isNotEmpty) {
        await setActiveProvider(fallbacks.first.id);
      }
    }
  }

  /// 切换当前 active provider，并重建运行实例。
  @override
  Future<void> setActiveProvider(String providerId) async {
    await loadSettings();
    final unavailable = unavailableReasonForProviderId(providerId);
    if (unavailable != null) {
      throw UnsupportedError(unavailable);
    }
    if (_settings.activeProviderId == providerId &&
        activeProviderId == providerId) {
      return;
    }
    final exists = _settings.providers.any(
      (provider) => provider.id == providerId,
    );
    if (!exists) {
      throw ArgumentError.value(providerId, 'providerId', 'Unknown provider');
    }
    final enabled = isProviderEnabled(providerId);
    if (!enabled) {
      throw StateError('Provider $providerId is disabled');
    }

    _settings = _settings.copyWith(activeProviderId: providerId);
    _applyRuntimeSelection();
    await configStore.save(_settings);
    _log.i('Switched active Agent provider to $providerId');
    _notify();
  }

  /// 持久化用户在输入框选择的模型组合到 active provider 配置。
  ///
  /// 写入 configStore 并同步内存中的 settings，下次创建 provider 时会读取。
  @override
  Future<void> persistModelSelection(
    AgentModelSelection selection,
    Map<String, AgentModelPreference> preferences,
  ) async {
    final providerId = activeProviderId;
    final updatedProviders = _settings.providers.map((provider) {
      if (provider.id != providerId) {
        return provider;
      }
      return provider.withModelConfiguration(
        selection: selection,
        preferences: preferences,
      );
    }).toList();
    final updatedSettings = AgentProviderSettings(
      providers: List<AgentProviderConfig>.unmodifiable(updatedProviders),
      activeProviderId: _settings.activeProviderId,
    );
    try {
      await configStore.save(updatedSettings);
      _settings = updatedSettings;
      _applyRuntimeSelection();
      _log.t('Persisted model selection for provider $providerId');
    } catch (error, stackTrace) {
      _log.w(
        'Could not persist model selection',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
    _notify();
  }

  /// 持久化权限 optionId（V2 唯一权限真源）。
  @override
  Future<void> persistPermissionOptionId(String optionId) {
    return persistPermissionOptionIdForProvider(activeProviderId, optionId);
  }

  /// 按稳定 Provider ID 持久化权限；会话 Binding 不依赖全局 active 选择。
  @override
  Future<void> persistPermissionOptionIdForProvider(
    String providerId,
    String optionId,
  ) async {
    final trimmed = optionId.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final updatedProviders = _settings.providers.map((provider) {
      if (provider.id != providerId) {
        return provider;
      }
      return provider.withPermissionPreference(trimmed);
    }).toList();
    _settings = AgentProviderSettings(
      providers: List<AgentProviderConfig>.unmodifiable(updatedProviders),
      activeProviderId: _settings.activeProviderId,
    );
    _applyRuntimeSelection();
    try {
      await configStore.save(_settings);
      _log.t('Persisted permission option for provider $providerId');
    } catch (error, stackTrace) {
      _log.w(
        'Could not persist permission option',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
    _notify();
  }

  /// 清除当前 provider 的权限偏好（写回 null optionId）。
  Future<void> clearPermissionPreference() async {
    final providerId = activeProviderId;
    final updatedProviders = _settings.providers.map((provider) {
      if (provider.id != providerId) {
        return provider;
      }
      return provider.withPermissionPreference(null);
    }).toList();
    _settings = AgentProviderSettings(
      providers: List<AgentProviderConfig>.unmodifiable(updatedProviders),
      activeProviderId: _settings.activeProviderId,
    );
    _applyRuntimeSelection();
    try {
      await configStore.save(_settings);
      _log.t('Cleared permission preference for provider $providerId');
    } catch (error, stackTrace) {
      _log.w(
        'Could not clear permission preference',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
    _notify();
  }

  /// 加载全局 provider 设置。
  @override
  Future<AgentProviderSettings> loadSettings() {
    final existing = _settingsFuture;
    if (existing != null) {
      return existing;
    }

    final future = configStore.load().then((settings) {
      _settings = settings;
      _applyRuntimeSelection();
      _log.t(
        'Loaded Agent provider selection ${settings.activeProviderId}; '
        'effective=$activeProviderId',
      );
      _notify();
      return settings;
    });
    _settingsFuture = future;
    return future;
  }

  /// 重新从持久化层读取 provider 设置。
  ///
  /// 当其他运行时实例已经落盘了新的 active provider 或模型/权限配置时，
  /// 调用方可用此方法让当前 controller 与磁盘真源重新对齐。
  Future<AgentProviderSettings> reloadSettings() {
    _settingsFuture = null;
    return loadSettings();
  }

  /// 使用应用级缓存读取并按需后台刷新当前 Provider 的模型目录。
  Future<AgentModelCatalogLoadResult> loadActiveModelCatalog({
    bool forceRefresh = false,
    void Function(AgentModelCatalogSnapshot snapshot)? onCacheHit,
  }) async {
    await loadSettings();
    final config = activeProviderConfig;
    return modelCatalogRepository.load(
      config: config,
      source: _modelCatalogSource(config),
      forceRefresh: forceRefresh,
      onCacheHit: onCacheHit,
      refreshLoader: () async {
        return _globalRuntime.run(config, (runtime) {
          final modelCatalog = runtime.bundle.modelCatalog;
          if (modelCatalog == null) {
            return Future<AgentModelList>.value(
              const AgentModelList(models: <AgentModelInfo>[]),
            );
          }
          return fetchAgentProviderModels(modelCatalog, forceRefresh: true);
        });
      },
    );
  }

  /// 返回指定旧 Provider 无法进入运行时的原因。
  @override
  String? unavailableReasonForProviderId(String providerId) {
    return CursorRetirementPolicy.unavailableReasonFor(
      providerId: providerId,
      config: providerConfigById(providerId),
    );
  }

  void _applyRuntimeSelection() {
    _runtimeSelection = CursorRetirementPolicy.resolve(_settings);
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }
}

String _modelCatalogSource(AgentProviderConfig config) {
  return switch (config.kind) {
    AgentProviderKind.codexAppServer => 'Codex app-server',
    AgentProviderKind.acp => 'Grok ACP',
    _ => config.displayName,
  };
}

final class _MemoryAgentModelCatalogCacheStore
    implements AgentModelCatalogCacheStore {
  List<AgentModelCatalogSnapshot> _snapshots =
      const <AgentModelCatalogSnapshot>[];

  @override
  Future<List<AgentModelCatalogSnapshot>> load() async =>
      List<AgentModelCatalogSnapshot>.unmodifiable(_snapshots);

  @override
  Future<void> save(List<AgentModelCatalogSnapshot> snapshots) async {
    _snapshots = List<AgentModelCatalogSnapshot>.unmodifiable(snapshots);
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';

final _log = loggerFor('zeta.agent.provider_controller');

/// IDE 内共享的 active Agent provider 生命周期控制器。
///
/// 左侧 thread 列表和中间 Agent 面板都通过它获取 provider，避免同一个 provider
/// 配置被重复启动多个进程。该对象不解释业务事件，只负责设置加载、实例创建和释放。
class ActiveAgentProviderController extends ChangeNotifier {
  ActiveAgentProviderController({
    required this.providerFactory,
    required this.configStore,
  });

  final AgentProviderFactory providerFactory;
  final AgentProviderConfigStore configStore;

  AgentProviderSettings _settings = const AgentProviderSettings();
  CursorRetirementResolution _runtimeSelection = CursorRetirementPolicy.resolve(
    const AgentProviderSettings(),
  );
  AgentProvider? _provider;
  Future<AgentProviderSettings>? _settingsFuture;
  Future<AgentProvider>? _providerFuture;
  bool _disposed = false;

  /// 当前 active provider 设置。
  AgentProviderSettings get settings => _settings;

  /// 当前 active provider id。
  String get activeProviderId => _runtimeSelection.effectiveProvider.id;

  /// 当前 active provider 展示名称。
  String get activeProviderName =>
      _runtimeSelection.effectiveProvider.displayName;

  /// 当前 active provider 的配置。
  AgentProviderConfig get activeProviderConfig =>
      _runtimeSelection.effectiveProvider;

  /// 当前是否存在可安全进入运行时的 Provider。
  bool get hasRuntimeProvider => _runtimeSelection.hasRuntimeProvider;

  /// 旧 Cursor 选择触发 fallback 时展示给用户的原因。
  String? get unavailableSelectionReason => _runtimeSelection.unavailableReason;

  /// 已启用的 provider 配置（用于跨 provider thread 列表等）。
  List<AgentProviderConfig> get enabledProviders {
    return List<AgentProviderConfig>.unmodifiable(
      CursorRetirementPolicy.enabledRuntimeProviders(_settings.providers),
    );
  }

  /// 指定 provider 是否允许创建新的可写会话。
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
  AgentProviderConfig? providerConfigById(String providerId) {
    for (final provider in _settings.providers) {
      if (provider.id == providerId) {
        return provider;
      }
    }
    return null;
  }

  /// 查询指定 provider 的能力；共享实例存在时优先返回握手后的动态能力。
  AgentProviderCapabilities capabilitiesForProviderId(String providerId) {
    final config = providerConfigById(providerId);
    if (CursorRetirementPolicy.unavailableReasonFor(
          providerId: providerId,
          config: config,
        ) !=
        null) {
      return AgentProviderCapabilities.unsupported;
    }
    final running = _provider;
    if (running != null && running.config.id == providerId) {
      return running.capabilities;
    }
    if (config == null) {
      return AgentProviderCapabilities.unsupported;
    }
    return AgentProviderCapabilities.defaultsFor(config.kind);
  }

  /// 打开指定配置的 provider 实例。
  ///
  /// 若与当前 active 相同则复用共享实例；否则创建**临时**实例，调用方在
  /// [isSharedActiveProvider] 为 false 时必须 [AgentProvider.dispose]。
  Future<AgentProvider> openProvider(AgentProviderConfig config) async {
    await loadSettings();
    final unavailable = CursorRetirementPolicy.unavailableReasonFor(
      providerId: config.id,
      config: config,
    );
    if (unavailable != null) {
      throw UnsupportedError(unavailable);
    }
    final existing = _provider;
    if (existing != null && existing.config.id == config.id) {
      return existing;
    }
    _log.fine('Opening ephemeral Agent provider ${config.id}');
    return providerFactory.create(config);
  }

  /// 是否为 [activeProvider] 持有的共享实例。
  bool isSharedActiveProvider(AgentProvider provider) {
    return identical(_provider, provider);
  }

  /// 更新一个 provider 的全局配置，并按需重建运行实例。
  Future<void> updateProviderConfig(
    AgentProviderConfig updated, {
    bool restartProvider = false,
  }) async {
    await loadSettings();
    final providers = <AgentProviderConfig>[
      for (final provider in _settings.providers)
        if (provider.id == updated.id) updated else provider,
    ];
    if (!providers.any((provider) => provider.id == updated.id)) {
      providers.add(updated);
    }
    final previousActiveProviderId = activeProviderId;
    _settings = AgentProviderSettings(
      providers: List<AgentProviderConfig>.unmodifiable(providers),
      activeProviderId: _settings.activeProviderId,
    );
    _applyRuntimeSelection();

    final shouldRestartActiveProvider =
        restartProvider && updated.id == previousActiveProviderId;
    if (shouldRestartActiveProvider) {
      final creating = _providerFuture;
      if (creating != null) {
        try {
          await creating;
        } catch (_) {
          // 创建失败也要继续落盘新配置，下一次启动会使用更新后的值。
        }
      }
      final existing = _provider;
      _provider = null;
      await existing?.dispose();
    }

    await configStore.save(_settings);
    _notify();
  }

  /// 启用或禁用 provider；禁用时终止当前运行实例。
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

    final creating = _providerFuture;
    if (creating != null) {
      try {
        await creating;
      } catch (_) {
        // 忽略创建失败，继续切换。
      }
    }
    final existing = _provider;
    _provider = null;
    await existing?.dispose();

    _settings = _settings.copyWith(activeProviderId: providerId);
    _applyRuntimeSelection();
    await configStore.save(_settings);
    _log.info('Switched active Agent provider to $providerId');
    _notify();
  }

  /// 持久化用户在输入框选择的模型组合到 active provider 配置。
  ///
  /// 写入 configStore 并同步内存中的 settings，下次创建 provider 时会读取。
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
      _log.fine('Persisted model selection for provider $providerId');
    } catch (error, stackTrace) {
      _log.warning('Could not persist model selection', error, stackTrace);
      rethrow;
    }
    _notify();
  }

  /// 持久化审批/沙箱策略选择。
  Future<void> persistPermissionSelection(
    AgentPermissionSelection selection,
  ) async {
    final providerId = activeProviderId;
    final updatedProviders = _settings.providers.map((provider) {
      if (provider.id != providerId) {
        return provider;
      }
      return provider.copyWith(
        selectedApprovalPolicy: selection.approvalPolicy,
        selectedSandboxPolicy: selection.sandboxPolicy,
        selectedPermissionProfileId: selection.permissionProfileId,
      );
    }).toList();
    _settings = AgentProviderSettings(
      providers: List<AgentProviderConfig>.unmodifiable(updatedProviders),
      activeProviderId: _settings.activeProviderId,
    );
    _applyRuntimeSelection();
    try {
      await configStore.save(_settings);
      _log.fine('Persisted permission selection for provider $providerId');
    } catch (error, stackTrace) {
      _log.warning('Could not persist permission selection', error, stackTrace);
    }
    _notify();
  }

  /// 加载全局 provider 设置。
  Future<AgentProviderSettings> loadSettings() {
    final existing = _settingsFuture;
    if (existing != null) {
      return existing;
    }

    final future = configStore.load().then((settings) {
      _settings = settings;
      _applyRuntimeSelection();
      _log.fine(
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

  /// 获取 active provider；必要时会懒启动实例。
  Future<AgentProvider> activeProvider() async {
    await loadSettings();

    if (!hasRuntimeProvider) {
      throw StateError(
        unavailableSelectionReason ?? 'No Agent provider is available',
      );
    }

    final existing = _provider;
    if (existing != null && existing.config.id == activeProviderId) {
      return existing;
    }

    final creating = _providerFuture;
    if (creating != null) {
      return creating;
    }

    final future = _createProvider();
    _providerFuture = future;
    try {
      return await future;
    } finally {
      if (identical(_providerFuture, future)) {
        _providerFuture = null;
      }
    }
  }

  Future<AgentProvider> _createProvider() async {
    final existing = _provider;
    _provider = null;
    await existing?.dispose();
    final expectedConfig = activeProviderConfig;
    _log.fine('Creating shared Agent provider: ${expectedConfig.id}');
    final provider = providerFactory.create(expectedConfig);
    final actualProviderId = provider.config.id;
    if (actualProviderId != expectedConfig.id) {
      // factory 身份错配会让 activeProvider 的调用方不断尝试重建实例；尽早失败，
      // 避免通知/微任务循环持续占用 CPU 和内存。
      try {
        await provider.dispose();
      } catch (error, stackTrace) {
        _log.warning(
          'Could not dispose mismatched Agent provider $actualProviderId',
          error,
          stackTrace,
        );
      }
      throw StateError(
        'AgentProviderFactory returned $actualProviderId for '
        '${expectedConfig.id}',
      );
    }
    _provider = provider;
    _notify();
    return provider;
  }

  /// 返回指定旧 Provider 无法进入运行时的原因。
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
    _disposed = true;
    unawaited(_provider?.dispose());
    super.dispose();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }
}

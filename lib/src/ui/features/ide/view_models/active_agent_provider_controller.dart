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
  AgentProvider? _provider;
  Future<AgentProviderSettings>? _settingsFuture;
  Future<AgentProvider>? _providerFuture;
  bool _disposed = false;

  /// 当前 active provider 设置。
  AgentProviderSettings get settings => _settings;

  /// 当前 active provider id。
  String get activeProviderId => _settings.activeProvider.id;

  /// 当前 active provider 展示名称。
  String get activeProviderName => _settings.activeProvider.displayName;

  /// 当前 active provider 的配置。
  AgentProviderConfig get activeProviderConfig => _settings.activeProvider;

  /// 已启用的 provider 配置（用于跨 provider thread 列表等）。
  List<AgentProviderConfig> get enabledProviders {
    return List<AgentProviderConfig>.unmodifiable(
      _settings.providers.where((provider) => provider.enabled),
    );
  }

  /// 指定 provider 是否允许创建新的可写会话。
  bool isProviderEnabled(String providerId) {
    for (final provider in _settings.providers) {
      if (provider.id == providerId) {
        return provider.enabled;
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
    final running = _provider;
    if (running != null && running.config.id == providerId) {
      return running.capabilities;
    }
    final config = providerConfigById(providerId);
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
    _settings = AgentProviderSettings(
      providers: List<AgentProviderConfig>.unmodifiable(providers),
      activeProviderId: _settings.activeProviderId,
    );

    final shouldRestartActiveProvider =
        restartProvider && updated.id == _settings.activeProviderId;
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
      final fallback = _settings.providers.firstWhere(
        (provider) => provider.enabled && provider.id != providerId,
        orElse: () => current,
      );
      if (fallback.id != providerId) {
        await setActiveProvider(fallback.id);
      }
    }
  }

  /// 切换当前 active provider，并重建运行实例。
  Future<void> setActiveProvider(String providerId) async {
    await loadSettings();
    if (_settings.activeProviderId == providerId) {
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
    await configStore.save(_settings);
    _log.info('Switched active Agent provider to $providerId');
    _notify();
  }

  /// 持久化用户在输入框选择的模型组合到 active provider 配置。
  ///
  /// 写入 configStore 并同步内存中的 settings，下次创建 provider 时会读取。
  Future<void> persistModelSelection(AgentModelSelection selection) async {
    final providerId = _settings.activeProvider.id;
    final updatedProviders = _settings.providers.map((provider) {
      if (provider.id != providerId) {
        return provider;
      }
      return provider.copyWith(
        selectedModel: selection.modelId,
        selectedReasoningEffort: selection.reasoningEffort,
        selectedServiceTier: selection.serviceTierId,
      );
    }).toList();
    _settings = AgentProviderSettings(
      providers: List<AgentProviderConfig>.unmodifiable(updatedProviders),
      activeProviderId: providerId,
    );
    try {
      await configStore.save(_settings);
      _log.fine('Persisted model selection for provider $providerId');
    } catch (error, stackTrace) {
      _log.warning('Could not persist model selection', error, stackTrace);
    }
    _notify();
  }

  /// 持久化审批/沙箱策略选择。
  Future<void> persistPermissionSelection(
    AgentPermissionSelection selection,
  ) async {
    final providerId = _settings.activeProvider.id;
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
      activeProviderId: providerId,
    );
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
      _log.fine('Loaded active Agent provider ${settings.activeProvider.id}');
      _notify();
      return settings;
    });
    _settingsFuture = future;
    return future;
  }

  /// 获取 active provider；必要时会懒启动实例。
  Future<AgentProvider> activeProvider() async {
    await loadSettings();

    final existing = _provider;
    if (existing != null && existing.config.id == _settings.activeProvider.id) {
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
    final expectedConfig = _settings.activeProvider;
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

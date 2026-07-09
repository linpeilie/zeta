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
    await existing?.dispose();
    _log.fine('Creating shared Agent provider: ${_settings.activeProvider.id}');
    final provider = providerFactory.create(_settings.activeProvider);
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

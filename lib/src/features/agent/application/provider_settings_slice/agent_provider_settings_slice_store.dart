import 'dart:async';

import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/features/agent/application/agent_model_catalog_repository.dart';
import 'package:zeta/src/features/agent/application/agent_provider_settings_port.dart';
import 'package:zeta/src/features/agent/application/provider_settings_slice/agent_provider_settings_slice_effect.dart';
import 'package:zeta/src/features/agent/application/provider_settings_slice/agent_provider_settings_slice_intent.dart';
import 'package:zeta/src/features/agent/application/provider_settings_slice/agent_provider_settings_slice_reducer.dart';
import 'package:zeta/src/features/agent/application/provider_settings_slice/agent_provider_settings_slice_state.dart';

abstract interface class AgentProviderSettingsSliceEffectRunner {
  void run(AgentProviderSettingsSliceEffect effect);
}

/// Provider settings 的纯 Dart MVI store。
///
/// 同时实现稳定的纯 Dart [AgentProviderSettingsPort]；Riverpod 只通过
/// [subscribe] 镜像本 store，不复制业务事实。
final class AgentProviderSettingsSliceStore
    implements AgentProviderSettingsPort {
  AgentProviderSettingsSliceStore({
    required AgentProviderSettingsSliceState initialState,
    required this.effectRunner,
    required this.modelCatalogRepository,
    required this.staticCapabilitiesFor,
    String Function(AgentProviderConfig config)? modelCatalogSourceFor,
    OperationIdGenerator Function(String scope)? operationIdGeneratorFactory,
  }) : _state = initialState,
       _modelCatalogSourceFor =
           modelCatalogSourceFor ?? ((config) => config.displayName),
       _generatorFactory =
           operationIdGeneratorFactory ??
           ((scope) => OperationIdGenerator(scope: scope));

  static const String loadOperationScope = 'provider-settings/load';
  static const String persistOperationScope = 'provider-settings/persist';

  final AgentProviderSettingsSliceEffectRunner effectRunner;
  @override
  final AgentModelCatalogRepository modelCatalogRepository;
  final AgentProviderStaticCapabilitiesFor staticCapabilitiesFor;
  final String Function(AgentProviderConfig config) _modelCatalogSourceFor;
  final OperationIdGenerator Function(String scope) _generatorFactory;
  final Map<String, OperationIdGenerator> _generators =
      <String, OperationIdGenerator>{};
  final List<void Function()> _listeners = <void Function()>[];
  final Map<OperationId, Completer<void>> _persistCompleters =
      <OperationId, Completer<void>>{};

  AgentProviderSettingsSliceState _state;
  Future<AgentProviderSettings>? _loadFuture;
  Completer<AgentProviderSettings>? _loadCompleter;
  bool _closed = false;

  AgentProviderSettingsSliceState get state => _state;
  bool get isClosed => _closed;

  @override
  AgentProviderSettings get settings => _state.settings;

  @override
  String get activeProviderId => _state.settings.activeProvider.id;

  @override
  String get activeProviderName => _state.settings.activeProvider.displayName;

  @override
  AgentProviderConfig get activeProviderConfig =>
      _state.settings.activeProvider;

  @override
  List<AgentProviderConfig> get enabledProviders =>
      AgentProviderSettingsSelectors.enabledProviders(_state);

  @override
  bool isProviderEnabled(String providerId) =>
      providerConfigById(providerId)?.enabled ?? false;

  @override
  AgentProviderConfig? providerConfigById(String providerId) {
    for (final provider in _state.settings.providers) {
      if (provider.id == providerId) {
        return provider;
      }
    }
    return null;
  }

  @override
  AgentProviderCapabilities capabilitiesForProviderId(String providerId) {
    final config = providerConfigById(providerId);
    if (config == null) {
      return AgentProviderCapabilities.unsupported;
    }
    return staticCapabilitiesFor(config.kind);
  }

  @override
  String modelCatalogSourceFor(AgentProviderConfig config) =>
      _modelCatalogSourceFor(config);

  @override
  void Function() subscribe(void Function() listener) {
    _ensureOpen();
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  @override
  Future<AgentProviderSettings> loadSettings() {
    _ensureOpen();
    final existing = _loadFuture;
    if (existing != null) {
      return existing;
    }
    final operationId = _nextOperationId(loadOperationScope);
    final completer = Completer<AgentProviderSettings>();
    _loadCompleter = completer;
    _loadFuture = completer.future;
    _dispatch(ProviderSettingsLoadRequested(operationId));
    return completer.future;
  }

  @override
  Future<void> updateProviderConfig(
    AgentProviderConfig updated, {
    bool restartProvider = false,
  }) async {
    await loadSettings();
    return _submitPersist(
      (operationId) => ProviderConfigUpdateRequested(
        operationId,
        updated,
        restartProvider: restartProvider,
      ),
    );
  }

  @override
  Future<void> setProviderEnabled(String providerId, bool enabled) async {
    await loadSettings();
    final current = providerConfigById(providerId);
    if (current == null) {
      throw ArgumentError.value(providerId, 'providerId', 'Unknown provider');
    }
    if (current.enabled == enabled) {
      return;
    }
    return _submitPersist(
      (operationId) => ProviderEnabledToggled(operationId, providerId, enabled),
    );
  }

  @override
  Future<void> setActiveProvider(String providerId) async {
    await loadSettings();
    if (_state.settings.activeProviderId == providerId &&
        activeProviderId == providerId) {
      return;
    }
    final config = providerConfigById(providerId);
    if (config == null) {
      throw ArgumentError.value(providerId, 'providerId', 'Unknown provider');
    }
    if (!config.enabled) {
      throw StateError('Provider $providerId is disabled');
    }
    return _submitPersist(
      (operationId) => ActiveProviderSelected(operationId, providerId),
    );
  }

  @override
  Future<void> persistModelSelection(
    AgentModelSelection selection,
    Map<String, AgentModelPreference> preferences,
  ) {
    return _submitPersist(
      (operationId) => ProviderModelSelectionPersistRequested(
        operationId,
        selection,
        Map<String, AgentModelPreference>.unmodifiable(preferences),
      ),
    );
  }

  @override
  Future<void> persistPermissionOptionId(String optionId) {
    return persistPermissionOptionIdForProvider(activeProviderId, optionId);
  }

  @override
  Future<void> persistPermissionOptionIdForProvider(
    String providerId,
    String optionId,
  ) {
    final trimmed = optionId.trim();
    if (trimmed.isEmpty) {
      return Future<void>.value();
    }
    return _submitPersist(
      (operationId) => ProviderPermissionOptionPersistRequested(
        operationId,
        providerId,
        trimmed,
      ),
    );
  }

  /// Effect runner 回流：加载成功。
  void loaded(OperationId operationId, AgentProviderSettings settings) {
    if (_closed) {
      return;
    }
    final accepted = _state.loadOperationId == operationId;
    _dispatch(ProviderSettingsLoaded(operationId, settings));
    if (accepted) {
      _loadCompleter?.complete(settings);
      _loadCompleter = null;
    }
  }

  /// Effect runner 回流：加载失败。原始异常只用于结算调用 Future。
  void loadFailed(
    OperationId operationId,
    Object error,
    StackTrace stackTrace,
  ) {
    if (_closed) {
      return;
    }
    final accepted = _state.loadOperationId == operationId;
    _dispatch(ProviderSettingsLoadFailed(operationId));
    if (accepted) {
      _loadCompleter?.completeError(error, stackTrace);
      _loadCompleter = null;
    }
  }

  /// Effect runner 回流：持久化成功。
  void persisted(OperationId operationId) {
    if (!_closed) {
      _dispatch(ProviderSettingsPersisted(operationId));
    }
    _persistCompleters.remove(operationId)?.complete();
  }

  /// Effect runner 回流：持久化失败。state 不保存 [error] 正文。
  void persistFailed(
    OperationId operationId,
    Object error,
    StackTrace stackTrace,
  ) {
    if (!_closed) {
      _dispatch(ProviderSettingsPersistFailed(operationId));
    }
    _persistCompleters.remove(operationId)?.completeError(error, stackTrace);
  }

  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _listeners.clear();
    final error = StateError('AgentProviderSettingsSliceStore is closed');
    final loadCompleter = _loadCompleter;
    if (loadCompleter != null && !loadCompleter.isCompleted) {
      loadCompleter.completeError(error);
    }
    _loadCompleter = null;
    for (final completer in _persistCompleters.values) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
    _persistCompleters.clear();
  }

  Future<void> _submitPersist(
    AgentProviderSettingsSliceIntent Function(OperationId operationId)
    createIntent,
  ) {
    _ensureOpen();
    final operationId = _nextOperationId(persistOperationScope);
    final completer = Completer<void>();
    _persistCompleters[operationId] = completer;
    final hasEffect = _dispatch(createIntent(operationId));
    if (!hasEffect) {
      _persistCompleters.remove(operationId);
      completer.complete();
    }
    return completer.future;
  }

  bool _dispatch(AgentProviderSettingsSliceIntent intent) {
    if (_closed) {
      return false;
    }
    final before = _state;
    final transition = agentProviderSettingsSliceReduce(before, intent);
    if (transition.state != before) {
      _state = transition.state;
      _notifyListeners();
    }
    for (final effect in transition.effects) {
      effectRunner.run(effect);
    }
    return transition.effects.isNotEmpty;
  }

  OperationId _nextOperationId(String scope) {
    return _generators
        .putIfAbsent(scope, () => _generatorFactory(scope))
        .next();
  }

  void _notifyListeners() {
    final snapshot = List<void Function()>.of(_listeners);
    for (final listener in snapshot) {
      listener();
    }
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('AgentProviderSettingsSliceStore is closed');
    }
  }
}

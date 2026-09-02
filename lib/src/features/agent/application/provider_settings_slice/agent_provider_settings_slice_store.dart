import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/features/agent/application/agent_model_catalog_repository.dart';
import 'package:zeta/src/features/agent/application/agent_provider_settings_port.dart';
import 'package:zeta/src/features/agent/application/provider_settings_slice/agent_model_catalog_projection.dart';
import 'package:zeta/src/features/agent/application/provider_settings_slice/agent_provider_settings_slice_effect.dart';
import 'package:zeta/src/features/agent/application/provider_settings_slice/agent_provider_settings_slice_intent.dart';
import 'package:zeta/src/features/agent/application/provider_settings_slice/agent_provider_settings_slice_reducer.dart';
import 'package:zeta/src/features/agent/application/provider_settings_slice/agent_provider_settings_slice_state.dart';

abstract interface class AgentProviderSettingsSliceEffectRunner {
  void run(AgentProviderSettingsSliceEffect effect);
}

/// runner 工厂：拿到 notifier 本身，副作用结果可直接回流唯一状态 owner。
typedef AgentProviderSettingsSliceEffectRunnerFactory =
    AgentProviderSettingsSliceEffectRunner Function(
      AgentProviderSettingsSliceNotifier notifier,
    );

/// Provider settings 切片所需的中立 application 依赖。
///
/// 具体 Provider definition、共享模型目录仓库与全局 runtime 的选择留在 app
/// 组合层；本层只消费已经收敛好的中立端口和函数。
final class AgentProviderSettingsSliceDependencies {
  AgentProviderSettingsSliceDependencies({
    required this.initialSettings,
    required this.modelCatalogRepository,
    required this.staticCapabilitiesFor,
    required this.modelCatalogSourceFor,
    required this.globalRuntime,
    OperationIdGenerator Function(String scope)? operationIdGeneratorFactory,
  }) : operationIdGeneratorFactory =
           operationIdGeneratorFactory ??
           ((scope) => OperationIdGenerator(scope: scope));

  final AgentProviderSettings initialSettings;
  final AgentModelCatalogRepository modelCatalogRepository;
  final AgentProviderStaticCapabilitiesFor staticCapabilitiesFor;
  final String Function(AgentProviderConfig config) modelCatalogSourceFor;
  final AgentProviderGlobalRuntime globalRuntime;
  final OperationIdGenerator Function(String scope) operationIdGeneratorFactory;
}

/// 组合根必须安装的切片依赖；缺失时 fail-closed。
final agentProviderSettingsSliceDependenciesProvider =
    Provider<AgentProviderSettingsSliceDependencies>(
      (ref) => throw StateError(
        'agentProviderSettingsSliceDependenciesProvider was read before the '
        'composition root overrode it',
      ),
      name: 'agentProviderSettingsSliceDependencies',
    );

/// 组合根必须安装的 effect runner 工厂；缺失时不伪造静默成功。
final agentProviderSettingsSliceEffectRunnerFactoryProvider =
    Provider<AgentProviderSettingsSliceEffectRunnerFactory>(
      (ref) => throw StateError(
        'agentProviderSettingsSliceEffectRunnerFactoryProvider was read '
        'before the composition root overrode it',
      ),
      name: 'agentProviderSettingsSliceEffectRunnerFactory',
    );

/// Provider settings 的唯一 app-session 状态 owner。
///
/// 不是 autoDispose：配置载入、落盘和 runtime 失效跟随应用会话，不能由设置页是否
/// 挂载决定生命周期。
final agentProviderSettingsSliceProvider =
    NotifierProvider<
      AgentProviderSettingsSliceNotifier,
      AgentProviderSettingsSliceState
    >(
      AgentProviderSettingsSliceNotifier.new,
      name: 'agentProviderSettingsSlice',
    );

/// Provider settings 的 Riverpod MVI notifier。
///
/// 同时实现稳定的纯 Dart [AgentProviderSettingsPort]，旧的手写 listener 由
/// [Notifier.listenSelf] 取代，不再需要 presentation 镜像 owner。
final class AgentProviderSettingsSliceNotifier
    extends Notifier<AgentProviderSettingsSliceState>
    implements AgentProviderSettingsPort {
  static const String loadOperationScope = 'provider-settings/load';
  static const String persistOperationScope = 'provider-settings/persist';

  late AgentProviderSettingsSliceEffectRunner _effectRunner;

  /// 模型目录仓库；只在本 notifier 内部使用，不经端口暴露给 presentation。
  late AgentModelCatalogRepository _modelCatalogRepository;
  late AgentProviderStaticCapabilitiesFor _staticCapabilitiesFor;
  late String Function(AgentProviderConfig config) _modelCatalogSourceFor;
  late AgentProviderGlobalRuntime _globalRuntime;
  late OperationIdGenerator Function(String scope) _generatorFactory;
  final Map<String, OperationIdGenerator> _generators =
      <String, OperationIdGenerator>{};
  final Map<OperationId, Completer<void>> _persistCompleters =
      <OperationId, Completer<void>>{};

  late AgentProviderSettingsSliceState _working;
  Future<AgentProviderSettings>? _loadFuture;
  Completer<AgentProviderSettings>? _loadCompleter;
  bool _closed = false;

  @override
  AgentProviderSettingsSliceState build() {
    final dependencies = ref.watch(
      agentProviderSettingsSliceDependenciesProvider,
    );
    _modelCatalogRepository = dependencies.modelCatalogRepository;
    _staticCapabilitiesFor = dependencies.staticCapabilitiesFor;
    _modelCatalogSourceFor = dependencies.modelCatalogSourceFor;
    _globalRuntime = dependencies.globalRuntime;
    _generatorFactory = dependencies.operationIdGeneratorFactory;
    _effectRunner = ref.watch(
      agentProviderSettingsSliceEffectRunnerFactoryProvider,
    )(this);
    _working = AgentProviderSettingsSliceState(
      settings: dependencies.initialSettings,
    );
    ref.onDispose(_handleDispose);
    return _working;
  }

  /// 命令与 runner 同步读取已提交状态；Riverpod 广播仍由同一个 owner 完成。
  @override
  AgentProviderSettingsSliceState get state => _working;

  bool get isClosed => _closed;

  @override
  AgentProviderSettings get settings => _working.settings;

  @override
  String get activeProviderId => _working.settings.activeProvider.id;

  @override
  String get activeProviderName => _working.settings.activeProvider.displayName;

  @override
  AgentProviderConfig get activeProviderConfig =>
      _working.settings.activeProvider;

  @override
  List<AgentProviderConfig> get enabledProviders =>
      AgentProviderSettingsSelectors.enabledProviders(_working);

  @override
  bool isProviderEnabled(String providerId) =>
      providerConfigById(providerId)?.enabled ?? false;

  @override
  AgentProviderConfig? providerConfigById(String providerId) {
    for (final provider in _working.settings.providers) {
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
    return _staticCapabilitiesFor(config.kind);
  }

  @override
  String modelCatalogSourceFor(AgentProviderConfig config) =>
      _modelCatalogSourceFor(config);

  @override
  Future<void> recordModelCatalog({
    required AgentProviderConfig config,
    required AgentModelList models,
    required String source,
  }) {
    return _modelCatalogRepository.record(
      config: config,
      models: models,
      source: source,
    );
  }

  @override
  Future<AgentModelCatalogLoadResult> loadModelCatalog({
    required AgentProviderConfig config,
    required AgentModelCatalogLoader refreshLoader,
    bool forceRefresh = false,
    void Function(AgentModelCatalogSnapshot snapshot)? onCacheHit,
  }) {
    return _modelCatalogRepository.load(
      config: config,
      source: modelCatalogSourceFor(config),
      refreshLoader: refreshLoader,
      forceRefresh: forceRefresh,
      onCacheHit: onCacheHit,
    );
  }

  /// 为模型目录 family 生成不含环境值的稳定查询键。
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

  /// 使用共享仓储读取 keyed Provider 模型目录。
  Future<AgentModelCatalogLoadResult> loadModelCatalogQuery(
    AgentModelCatalogQuery query, {
    bool forceRefresh = false,
    void Function(AgentModelCatalogSnapshot snapshot)? onCacheHit,
  }) async {
    await loadSettings();
    final config = providerConfigById(query.providerId);
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
    if (!capabilitiesForProviderId(config.id).supportsModelSelection) {
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

  /// 兼容 Shell 预热入口；内部仍收敛到同一个 keyed 查询。
  Future<AgentModelCatalogLoadResult> loadActiveModelCatalog({
    bool forceRefresh = false,
    void Function(AgentModelCatalogSnapshot snapshot)? onCacheHit,
  }) async {
    await loadSettings();
    return loadModelCatalogQuery(
      queryForConfig(activeProviderConfig),
      forceRefresh: forceRefresh,
      onCacheHit: onCacheHit,
    );
  }

  @override
  void Function() subscribe(void Function() listener) {
    _ensureOpen();
    return listenSelf((previous, next) => listener());
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
    if (_working.settings.activeProviderId == providerId &&
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
    final accepted = _working.loadOperationId == operationId;
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
    final accepted = _working.loadOperationId == operationId;
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

  void _handleDispose() {
    if (_closed) {
      return;
    }
    _closed = true;
    final error = StateError('AgentProviderSettingsSliceNotifier is disposed');
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
    final before = _working;
    final transition = agentProviderSettingsSliceReduce(before, intent);
    if (transition.state != before) {
      _working = transition.state;
      state = _working;
    }
    for (final effect in transition.effects) {
      _effectRunner.run(effect);
    }
    return transition.effects.isNotEmpty;
  }

  OperationId _nextOperationId(String scope) {
    return _generators
        .putIfAbsent(scope, () => _generatorFactory(scope))
        .next();
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('AgentProviderSettingsSliceNotifier is disposed');
    }
  }
}

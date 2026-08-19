import 'dart:async';
import 'dart:convert';

import 'package:agent_config_client/agent_config_client.dart';
import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:equatable/equatable.dart';
import 'package:zeta_logging/zeta_logging.dart';

// Public named parameters deliberately mirror the architecture contract while
// assigning private dependencies in the initializer list.
// ignore_for_file: prefer_initializing_formals

/// An immutable snapshot of all persisted Provider definitions.
final class ProviderConfigSnapshot extends Equatable {
  /// Creates a Provider configuration snapshot.
  ProviderConfigSnapshot({
    required Iterable<AgentProviderConfig> configs,
    required this.revision,
  }) : configs = List<AgentProviderConfig>.unmodifiable(configs);

  /// The initial snapshot exposed while [AgentProviderRepository.ready] waits.
  static final empty = ProviderConfigSnapshot(
    configs: const <AgentProviderConfig>[],
    revision: 0,
  );

  /// Provider definitions in persistence order.
  final List<AgentProviderConfig> configs;

  /// Monotonically increasing in-memory revision.
  final int revision;

  /// Returns the definition for [providerId], or null when it is unknown.
  AgentProviderConfig? providerById(String providerId) {
    for (final config in configs) {
      if (config.id == providerId) {
        return config;
      }
    }
    return null;
  }

  @override
  List<Object?> get props => <Object?>[configs, revision];
}

/// Stable operation categories for Repository failures.
enum AgentProviderRepositoryOperation {
  /// Initial configuration read.
  initialize,

  /// Synchronous bundle resolution.
  resolveBundle,

  /// Global runtime initialization.
  initializeRuntime,

  /// Model catalog load or refresh.
  modelCatalog,

  /// Conversation-mode catalog load.
  conversationModes,

  /// Skill catalog load.
  skills,

  /// Permission catalog load.
  permissionOptions,

  /// Permission selection application.
  applyPermissionSelection,

  /// Explicit default-model persistence.
  persistDefaultModel,

  /// Repository shutdown.
  close,
}

/// A typed Provider failure that preserves its original diagnostic context.
final class AgentProviderRepositoryException implements Exception {
  /// Creates a Repository exception.
  const AgentProviderRepositoryException({
    required this.failure,
    required this.operation,
    required this.cause,
    required this.stackTrace,
  });

  /// Vendor-neutral failure exposed to the application layer.
  final AgentProviderFailure failure;

  /// Repository operation that failed.
  final AgentProviderRepositoryOperation operation;

  /// Original exception retained for sanitized diagnostic logging only.
  final Object cause;

  /// Original stack trace retained for sanitized diagnostic logging only.
  final StackTrace stackTrace;

  @override
  String toString() =>
      'AgentProviderRepositoryException(${operation.name}, '
      '${failure.code.name})';
}

/// Agent Provider configuration, global runtime, and external-catalog owner.
final class AgentProviderRepository {
  /// Creates the Repository and immediately starts loading configuration.
  AgentProviderRepository({
    required ProviderConfigStore configStore,
    required AgentModelCatalogCacheStore modelCatalogCache,
    required Map<AgentProviderKind, AgentProviderBundleFactory> bundleFactories,
    required AppLogger logger,
    Duration modelCatalogFreshFor = const Duration(hours: 1),
    Duration modelCatalogMaxStaleFor = const Duration(days: 7),
    DateTime Function()? clock,
  }) : _configStore = configStore,
       _modelCatalogCache = modelCatalogCache,
       _bundleFactories =
           Map<AgentProviderKind, AgentProviderBundleFactory>.unmodifiable(
             bundleFactories,
           ),
       _logger = logger,
       _modelCatalogFreshFor = modelCatalogFreshFor,
       _modelCatalogMaxStaleFor = modelCatalogMaxStaleFor,
       _clock = clock ?? DateTime.now {
    _ready = _initialize();
    _modelCacheReady = _loadModelCacheBestEffort();
  }

  final ProviderConfigStore _configStore;
  final AgentModelCatalogCacheStore _modelCatalogCache;
  final Map<AgentProviderKind, AgentProviderBundleFactory> _bundleFactories;
  final AppLogger _logger;
  final Duration _modelCatalogFreshFor;
  final Duration _modelCatalogMaxStaleFor;
  final DateTime Function() _clock;

  final StreamController<ProviderConfigSnapshot> _configController =
      StreamController<ProviderConfigSnapshot>.broadcast(sync: true);
  final Map<String, AgentProviderBundle> _bundles =
      <String, AgentProviderBundle>{};
  final Map<String, Future<void>> _runtimeInitializations =
      <String, Future<void>>{};
  final Map<String, AgentModelCatalogSnapshot> _modelSnapshots =
      <String, AgentModelCatalogSnapshot>{};
  final Map<String, Future<AgentModelList>> _modelRefreshes =
      <String, Future<AgentModelList>>{};
  final Map<String, AgentConversationModeCatalog> _modeCatalogs =
      <String, AgentConversationModeCatalog>{};
  final Map<String, AgentPermissionCatalog> _permissionCatalogs =
      <String, AgentPermissionCatalog>{};
  final Map<String, AgentSkillsCatalog> _skillsCatalogs =
      <String, AgentSkillsCatalog>{};
  final Map<String, Future<AgentSkillsCatalog>> _skillsLoads =
      <String, Future<AgentSkillsCatalog>>{};
  final Map<String, StreamSubscription<void>> _skillsSubscriptions =
      <String, StreamSubscription<void>>{};
  final Map<String, int> _skillsInvalidationGenerations = <String, int>{};
  final Map<String, int> _skillsLoadedGenerations = <String, int>{};

  late final Future<void> _ready;
  late final Future<void> _modelCacheReady;
  ProviderConfigSnapshot _configSnapshot = ProviderConfigSnapshot.empty;
  Future<void> _configWriteQueue = Future<void>.value();
  Future<void> _modelCacheSaveQueue = Future<void>.value();
  bool _closed = false;

  /// Completes once persisted configuration has been loaded.
  ///
  /// Callers must await this before using the synchronous [bundleFor] API.
  Future<void> get ready => _ready;

  /// Emits immutable snapshots after successful external-data changes.
  Stream<ProviderConfigSnapshot> get configChanges => _configController.stream;

  /// Most recently loaded or persisted configuration snapshot.
  ProviderConfigSnapshot get configSnapshot => _configSnapshot;

  /// Returns the process-wide global bundle for [providerId].
  AgentProviderBundle bundleFor(String providerId) {
    _ensureOpen();
    if (_configSnapshot.revision == 0) {
      throw _localFailure(
        operation: AgentProviderRepositoryOperation.resolveBundle,
        code: AgentProviderFailureCode.unavailable,
        diagnosticCode: 'repository_not_ready',
        cause: StateError('Provider configuration is not ready'),
      );
    }
    final config = _requireConfig(providerId);
    final resolvedProviderId = config.id;
    if (!config.enabled) {
      throw _localFailure(
        operation: AgentProviderRepositoryOperation.resolveBundle,
        code: AgentProviderFailureCode.unavailable,
        diagnosticCode: 'provider_disabled',
        cause: StateError('Provider is disabled'),
      );
    }
    final existing = _bundles[resolvedProviderId];
    if (existing != null) {
      return existing;
    }
    final factory = _bundleFactories[config.kind];
    if (factory == null) {
      throw _localFailure(
        operation: AgentProviderRepositoryOperation.resolveBundle,
        code: AgentProviderFailureCode.invalidConfiguration,
        diagnosticCode: 'bundle_factory_missing',
        cause: StateError('Provider bundle factory is missing'),
      );
    }
    try {
      return _bundles.putIfAbsent(
        resolvedProviderId,
        () => factory.createBundle(config),
      );
    } on Object catch (error, stackTrace) {
      throw _translate(
        error,
        stackTrace,
        AgentProviderRepositoryOperation.resolveBundle,
      );
    }
  }

  /// Returns a cached model catalog or refreshes it from the Provider.
  Future<AgentModelList> modelCatalog(
    String providerId, {
    bool forceRefresh = false,
  }) async {
    await _awaitReady();
    final config = _requireConfig(providerId);
    await _modelCacheReady;
    final fingerprint = _configFingerprint(config);
    final resolvedProviderId = config.id;
    final cached = _cachedModelSnapshot(resolvedProviderId, fingerprint);
    if (!forceRefresh && cached != null && _isFresh(cached)) {
      return cached.models;
    }

    final refreshKey = '$resolvedProviderId\u0000$fingerprint';
    final existing = _modelRefreshes[refreshKey];
    if (existing != null) {
      return existing;
    }
    final operation = _refreshModelCatalog(
      config,
      fingerprint: fingerprint,
      stale: cached,
    );
    _modelRefreshes[refreshKey] = operation;
    try {
      return await operation;
    } finally {
      if (identical(_modelRefreshes[refreshKey], operation)) {
        unawaited(_modelRefreshes.remove(refreshKey));
      }
    }
  }

  /// Loads the available conversation modes for [providerId].
  Future<AgentConversationModeCatalog> conversationModes(
    String providerId,
  ) async {
    final resolvedProviderId = await _resolvedProviderId(providerId);
    try {
      final catalog =
          await _runCapability<
            AgentConversationModeCatalogPort,
            AgentConversationModeCatalog
          >(
            providerId,
            operation: AgentProviderRepositoryOperation.conversationModes,
            select: (bundle) => bundle.conversationModes,
            invoke: (port) => port.listConversationModes(),
            unsupportedCode: 'conversation_modes_unsupported',
          );
      _modeCatalogs[resolvedProviderId] = catalog;
      return catalog;
    } on AgentProviderRepositoryException {
      final stale = _modeCatalogs[resolvedProviderId];
      if (stale != null) {
        return stale;
      }
      rethrow;
    }
  }

  /// Loads the available skills for [providerId] and [cwds].
  Future<AgentSkillsCatalog> skills(
    String providerId, {
    List<String> cwds = const <String>[],
  }) async {
    final resolvedProviderId = await _resolvedProviderId(providerId);
    final immutableCwds = List<String>.unmodifiable(cwds);
    final key = _skillsCacheKey(resolvedProviderId, immutableCwds);
    final existing = _skillsLoads[key];
    if (existing != null) {
      return existing;
    }
    final generation = _skillsInvalidationGenerations[resolvedProviderId] ?? 0;
    final forceReload =
        _skillsLoadedGenerations[key] != null &&
        _skillsLoadedGenerations[key] != generation;
    final operation = _loadSkills(
      resolvedProviderId,
      key: key,
      cwds: immutableCwds,
      generation: generation,
      forceReload: forceReload,
    );
    _skillsLoads[key] = operation;
    try {
      return await operation;
    } finally {
      if (identical(_skillsLoads[key], operation)) {
        unawaited(_skillsLoads.remove(key));
      }
    }
  }

  /// Loads the permission options for [providerId].
  Future<AgentPermissionCatalog> permissionOptions(String providerId) async {
    final resolvedProviderId = await _resolvedProviderId(providerId);
    try {
      final catalog =
          await _runCapability<
            AgentPermissionPolicyPort,
            AgentPermissionCatalog
          >(
            providerId,
            operation: AgentProviderRepositoryOperation.permissionOptions,
            select: (bundle) => bundle.permissionPolicy,
            invoke: (port) => port.listPermissionOptions(),
            unsupportedCode: 'permission_policy_unsupported',
          );
      _permissionCatalogs[resolvedProviderId] = catalog;
      return catalog;
    } on AgentProviderRepositoryException {
      final stale = _permissionCatalogs[resolvedProviderId];
      if (stale != null) {
        return stale;
      }
      rethrow;
    }
  }

  /// Applies an explicit permission selection without storing UI state.
  Future<AgentPermissionApplyResult> applyPermissionSelection(
    String providerId,
    AgentPermissionSelection selection,
  ) => _runCapability<AgentPermissionPolicyPort, AgentPermissionApplyResult>(
    providerId,
    operation: AgentProviderRepositoryOperation.applyPermissionSelection,
    select: (bundle) => bundle.permissionPolicy,
    invoke: (port) => port.applyPermissionSelection(selection),
    unsupportedCode: 'permission_policy_unsupported',
  );

  /// Persists an explicitly submitted default model selection.
  Future<void> persistDefaultModel(
    String providerId,
    AgentModelSelection selection,
  ) {
    final operation = _configWriteQueue.then((_) async {
      await _awaitReady();
      final current = _requireConfig(providerId);
      final resolvedProviderId = current.id;
      final updated = current.withModelConfiguration(
        selection: selection,
        preferences: current.modelPreferences,
      );
      final configs = <AgentProviderConfig>[
        for (final config in _configSnapshot.configs)
          if (config.id == resolvedProviderId) updated else config,
      ];
      try {
        await _configStore.write(configs);
      } on Object catch (error, stackTrace) {
        throw _translate(
          error,
          stackTrace,
          AgentProviderRepositoryOperation.persistDefaultModel,
        );
      }
      _publishConfigs(configs);
      try {
        _bundles[resolvedProviderId]?.runtime.updateModelSelection(selection);
      } on Object catch (error, stackTrace) {
        throw _translate(
          error,
          stackTrace,
          AgentProviderRepositoryOperation.persistDefaultModel,
        );
      }
    });
    _configWriteQueue = operation.catchError((Object _) {});
    return operation;
  }

  /// Disposes all global runtimes and closes Repository streams.
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    Object? firstError;
    StackTrace? firstStackTrace;
    try {
      await _ready;
    } on Object catch (error, stackTrace) {
      firstError = error;
      firstStackTrace = stackTrace;
    }
    try {
      await _configWriteQueue;
      await _modelCacheReady;
      await _modelCacheSaveQueue;
      await Future.wait<void>(<Future<void>>[
        ..._skillsSubscriptions.values.map(
          (subscription) => subscription.cancel(),
        ),
        ..._bundles.values.map((bundle) => bundle.runtime.dispose()),
      ]);
    } on Object catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    } finally {
      _bundles.clear();
      _runtimeInitializations.clear();
      _skillsSubscriptions.clear();
      await _configController.close();
    }
    if (firstError != null) {
      final stackTrace = firstStackTrace!;
      throw _translate(
        firstError,
        stackTrace,
        AgentProviderRepositoryOperation.close,
      );
    }
  }

  Future<void> _initialize() async {
    try {
      final loaded = await _configStore.read();
      final configs = loaded.isEmpty
          ? <AgentProviderConfig>[
              AgentProviderConfig.defaultCodex,
              AgentProviderConfig.defaultGrok,
            ]
          : loaded;
      _validateConfigs(configs);
      if (!_closed) {
        _publishConfigs(configs);
      }
    } on Object catch (error, stackTrace) {
      final translated = _translate(
        error,
        stackTrace,
        AgentProviderRepositoryOperation.initialize,
      );
      if (!_closed) {
        _configController.addError(translated, translated.stackTrace);
      }
      throw translated;
    }
  }

  Future<void> _awaitReady() async {
    _ensureOpen();
    await _ready;
    _ensureOpen();
  }

  Future<T> _runCapability<P extends Object, T>(
    String providerId, {
    required AgentProviderRepositoryOperation operation,
    required P? Function(AgentProviderBundle bundle) select,
    required Future<T> Function(P port) invoke,
    required String unsupportedCode,
  }) async {
    await _awaitReady();
    final resolvedProviderId = _requireConfig(providerId).id;
    final bundle = bundleFor(resolvedProviderId);
    await _initializeRuntime(resolvedProviderId, bundle);
    final port = select(bundle);
    if (port == null) {
      throw _localFailure(
        operation: operation,
        code: AgentProviderFailureCode.unavailable,
        diagnosticCode: unsupportedCode,
        cause: UnsupportedError('Provider capability is unavailable'),
      );
    }
    try {
      return await invoke(port);
    } on Object catch (error, stackTrace) {
      throw _translate(error, stackTrace, operation);
    }
  }

  Future<String> _resolvedProviderId(String providerId) async {
    await _awaitReady();
    return _requireConfig(providerId).id;
  }

  Future<AgentSkillsCatalog> _loadSkills(
    String providerId, {
    required String key,
    required List<String> cwds,
    required int generation,
    required bool forceReload,
  }) async {
    try {
      final catalog = await _runCapability<AgentSkillsPort, AgentSkillsCatalog>(
        providerId,
        operation: AgentProviderRepositoryOperation.skills,
        select: (bundle) => bundle.skills,
        invoke: (port) {
          _ensureSkillsSubscription(providerId, port);
          return port.listSkills(cwds: cwds, forceReload: forceReload);
        },
        unsupportedCode: 'skills_unsupported',
      );
      _skillsCatalogs[key] = catalog;
      _skillsLoadedGenerations[key] = generation;
      return catalog;
    } on AgentProviderRepositoryException {
      final stale = _skillsCatalogs[key];
      if (stale != null) {
        return stale;
      }
      rethrow;
    }
  }

  void _ensureSkillsSubscription(String providerId, AgentSkillsPort port) {
    _skillsSubscriptions.putIfAbsent(
      providerId,
      () => port.skillsChanged.listen(
        (_) {
          _skillsInvalidationGenerations[providerId] =
              (_skillsInvalidationGenerations[providerId] ?? 0) + 1;
        },
        onError: (Object error, StackTrace stackTrace) {
          _skillsInvalidationGenerations[providerId] =
              (_skillsInvalidationGenerations[providerId] ?? 0) + 1;
          _logger.w(
            'Skill catalog invalidation stream failed',
            error: error,
            stackTrace: stackTrace,
          );
        },
      ),
    );
  }

  Future<void> _initializeRuntime(
    String providerId,
    AgentProviderBundle bundle,
  ) async {
    final existing = _runtimeInitializations[providerId];
    if (existing != null) {
      return existing;
    }
    Future<void>? initialization;
    try {
      initialization = bundle.runtime.initialize();
      _runtimeInitializations[providerId] = initialization;
      await initialization;
    } on Object catch (error, stackTrace) {
      if (initialization != null &&
          identical(_runtimeInitializations[providerId], initialization)) {
        unawaited(_runtimeInitializations.remove(providerId));
      }
      throw _translate(
        error,
        stackTrace,
        AgentProviderRepositoryOperation.initializeRuntime,
      );
    }
  }

  Future<AgentModelList> _refreshModelCatalog(
    AgentProviderConfig config, {
    required String fingerprint,
    required AgentModelCatalogSnapshot? stale,
  }) async {
    final bundle = bundleFor(config.id);
    await _initializeRuntime(
      config.id,
      bundle,
    );
    final port = bundle.modelCatalog;
    if (port == null) {
      throw _localFailure(
        operation: AgentProviderRepositoryOperation.modelCatalog,
        code: AgentProviderFailureCode.unavailable,
        diagnosticCode: 'model_catalog_unsupported',
        cause: UnsupportedError('Provider model catalog is unavailable'),
      );
    }
    try {
      final models = await port.listModels(forceRefresh: true);
      if (models.models.isEmpty) {
        return stale?.models ?? models;
      }
      final snapshot = AgentModelCatalogSnapshot(
        providerId: config.id,
        configFingerprint: fingerprint,
        includeHidden: false,
        models: models,
        fetchedAt: _clock().toUtc(),
        source: config.kind.name,
      );
      _modelSnapshots[_modelCacheKey(config.id)] = snapshot;
      await _persistModelCacheBestEffort();
      return models;
    } on Object catch (error, stackTrace) {
      if (stale != null) {
        _logger.w(
          'Could not refresh model catalog; using last known good catalog',
          error: error,
          stackTrace: stackTrace,
        );
        return stale.models;
      }
      throw _translate(
        error,
        stackTrace,
        AgentProviderRepositoryOperation.modelCatalog,
      );
    }
  }

  Future<void> _loadModelCacheBestEffort() async {
    try {
      final loaded = await _modelCatalogCache.load();
      for (final snapshot in loaded) {
        if (snapshot.includeHidden) {
          continue;
        }
        final key = _modelCacheKey(snapshot.providerId);
        final previous = _modelSnapshots[key];
        if (previous == null ||
            snapshot.fetchedAt.isAfter(previous.fetchedAt)) {
          _modelSnapshots[key] = snapshot;
        }
      }
    } on Object catch (error, stackTrace) {
      _logger.w(
        'Could not read model catalog cache; refreshing from Provider',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _persistModelCacheBestEffort() {
    final snapshots = List<AgentModelCatalogSnapshot>.unmodifiable(
      _modelSnapshots.values,
    );
    return _modelCacheSaveQueue = _modelCacheSaveQueue.then((_) async {
      try {
        await _modelCatalogCache.save(snapshots);
      } on Object catch (error, stackTrace) {
        _logger.w(
          'Could not persist model catalog cache',
          error: error,
          stackTrace: stackTrace,
        );
      }
    });
  }

  AgentModelCatalogSnapshot? _cachedModelSnapshot(
    String providerId,
    String fingerprint,
  ) {
    final key = _modelCacheKey(providerId);
    final snapshot = _modelSnapshots[key];
    if (snapshot == null || snapshot.configFingerprint != fingerprint) {
      return null;
    }
    final age = _clock().toUtc().difference(snapshot.fetchedAt.toUtc());
    if (age.isNegative || age > _modelCatalogMaxStaleFor) {
      _modelSnapshots.remove(key);
      return null;
    }
    return snapshot;
  }

  bool _isFresh(AgentModelCatalogSnapshot snapshot) =>
      _clock().toUtc().difference(snapshot.fetchedAt.toUtc()) <=
      _modelCatalogFreshFor;

  AgentProviderConfig _requireConfig(String providerId) {
    final normalized = providerId.trim();
    final config = _configSnapshot.providerById(normalized);
    if (normalized.isEmpty || config == null) {
      throw _localFailure(
        operation: AgentProviderRepositoryOperation.resolveBundle,
        code: AgentProviderFailureCode.invalidConfiguration,
        diagnosticCode: 'provider_unknown',
        cause: ArgumentError.value(providerId, 'providerId'),
      );
    }
    return config;
  }

  void _publishConfigs(Iterable<AgentProviderConfig> configs) {
    _configSnapshot = ProviderConfigSnapshot(
      configs: configs,
      revision: _configSnapshot.revision + 1,
    );
    if (!_configController.isClosed) {
      _configController.add(_configSnapshot);
    }
  }

  void _validateConfigs(List<AgentProviderConfig> configs) {
    final ids = <String>{};
    for (final config in configs) {
      if (config.id.trim().isEmpty || !ids.add(config.id)) {
        throw const FormatException('Invalid Provider configuration');
      }
    }
  }

  void _ensureOpen() {
    if (_closed) {
      throw _localFailure(
        operation: AgentProviderRepositoryOperation.resolveBundle,
        code: AgentProviderFailureCode.unavailable,
        diagnosticCode: 'repository_closed',
        cause: StateError('Provider Repository is closed'),
      );
    }
  }

  AgentProviderRepositoryException _translate(
    Object error,
    StackTrace stackTrace,
    AgentProviderRepositoryOperation operation,
  ) {
    if (error is AgentProviderRepositoryException) {
      return error;
    }
    final code = switch (error) {
      TimeoutException() => AgentProviderFailureCode.timeout,
      AgentConfigDecodeException() =>
        AgentProviderFailureCode.invalidConfiguration,
      FormatException() ||
      ArgumentError() => AgentProviderFailureCode.invalidConfiguration,
      _ => AgentProviderFailureCode.unknown,
    };
    final translated = AgentProviderRepositoryException(
      failure: AgentProviderFailure(
        code: code,
        diagnosticCode: '${operation.name}_failed',
      ),
      operation: operation,
      cause: error,
      stackTrace: stackTrace,
    );
    _logger.w(
      'Agent Provider Repository operation failed: ${operation.name}',
      error: error,
      stackTrace: stackTrace,
    );
    return translated;
  }

  AgentProviderRepositoryException _localFailure({
    required AgentProviderRepositoryOperation operation,
    required AgentProviderFailureCode code,
    required String diagnosticCode,
    required Object cause,
  }) => AgentProviderRepositoryException(
    failure: AgentProviderFailure(
      code: code,
      diagnosticCode: diagnosticCode,
    ),
    operation: operation,
    cause: cause,
    stackTrace: StackTrace.current,
  );
}

String _modelCacheKey(String providerId) => '$providerId\u0000visible';

String _skillsCacheKey(String providerId, List<String> cwds) =>
    '$providerId\u0000${jsonEncode(cwds)}';

String _configFingerprint(AgentProviderConfig config) {
  final environmentKeys = config.environment.keys.toList()..sort();
  const extraKeys = <String>[
    claudeCodeAccountDataEnrichmentKey,
    'cliPath',
    'detectedCurrentVersion',
    'modelProvider',
    'modelProviderId',
    'profile',
  ];
  final safeJson = jsonEncode(<String, Object?>{
    'kind': config.kind.name,
    'command': config.command,
    'arguments': config.arguments,
    'defaultModel': config.defaultModel,
    'environmentKeys': environmentKeys,
    'extra': <String, Object?>{
      for (final key in extraKeys)
        if (config.extra.containsKey(key)) key: '${config.extra[key]}',
    },
  });
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(safeJson)) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

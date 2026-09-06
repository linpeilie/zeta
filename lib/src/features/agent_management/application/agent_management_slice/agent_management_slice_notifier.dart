import '../agent_management_runtime_facts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'agent_management_slice_dependencies.dart';
import 'dart:async';

import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/agent_management/application/agent_management_operations.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_intent.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_reducer.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_state.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';

final _log = zetaLoggerFor('zeta.agent.management');

final agentManagementSliceProvider =
    NotifierProvider<AgentManagementSliceNotifier, AgentManagementSliceState>(
      AgentManagementSliceNotifier.new,
      name: 'agentManagementSlice',
    );

final agentManagementOperationsProvider = Provider<AgentManagementOperations>(
  (ref) => ref.watch(agentManagementSliceProvider.notifier),
);

/// The application session owns state, command waiters and physical executions.
final class AgentManagementSliceNotifier
    extends Notifier<AgentManagementSliceState>
    implements
        AgentManagementOperations,
        AgentManagementResultSink,
        AgentManagementOwnerLifecycle {
  @override
  AgentManagementSliceState build() {
    if (_built) throw StateError('Management owner requires a new app session');
    _built = true;
    final dependencies = ref.read(agentManagementSliceDependenciesProvider);
    configurationNotLoadedMessage = dependencies.configurationNotLoadedMessage;
    accountDataEnrichmentEnabledFor =
        dependencies.accountDataEnrichmentEnabledFor;
    _generatorFactory =
        dependencies.operationIdGeneratorFactory ??
        ((scope) => OperationIdGenerator(scope: scope));
    effectRunner = ref.read(agentManagementRunnerFactoryProvider)(this);
    ref.onDispose(stopAcceptingCommandsAndSettleWaiters);
    return projectManagementRuntimeState(dependencies.initialState);
  }

  static const String initializeOperationScope = 'agent-management/initialize';
  static const String detectionOperationScope = 'agent-management/detect';

  late final AgentManagementSliceEffectRunner effectRunner;
  late final String configurationNotLoadedMessage;
  late final bool Function(AgentProviderConfig) accountDataEnrichmentEnabledFor;
  late final OperationIdGenerator Function(String scope) _generatorFactory;
  final Map<String, OperationIdGenerator> _generators =
      <String, OperationIdGenerator>{};
  final Map<OperationId, Completer<void>> _voidCompleters =
      <OperationId, Completer<void>>{};
  final Map<OperationId, Completer<AgentConnectionTestResult?>>
  _connectionCompleters =
      <OperationId, Completer<AgentConnectionTestResult?>>{};
  final Map<OperationId, Completer<AgentConfigurationDocument?>>
  _configurationLoadCompleters =
      <OperationId, Completer<AgentConfigurationDocument?>>{};
  final Map<OperationId, Completer<AgentConfigurationSaveResult>>
  _configurationSaveCompleters =
      <OperationId, Completer<AgentConfigurationSaveResult>>{};
  final Map<OperationId, Completer<List<AgentLogEntry>>> _logsCompleters =
      <OperationId, Completer<List<AgentLogEntry>>>{};

  bool _built = false;
  final Set<Future<void>> _physicalExecutions = {};
  Future<void>? _drainFuture;
  bool _autoDetectAfterInitialize = false;
  Future<void>? _initializeFuture;
  Completer<void>? _initializeCompleter;
  bool _closed = false;

  @override
  AgentManagementSliceState get current => state;

  @override
  bool get isClosed => _closed;

  @override
  List<ManagedAgent> get agents => AgentManagementSliceSelectors.agents(state);

  @override
  ManagedAgent get agent => AgentManagementSliceSelectors.selectedAgent(state);

  @override
  String get selectedAgentId => state.selectedAgentId;

  @override
  AgentDetectionProgress? get detectionProgress => state.detectionProgress;

  @override
  AgentConfigurationDocument? get configuration =>
      AgentManagementSliceSelectors.selectedConfiguration(state);

  @override
  List<AgentLogEntry> get logs => List<AgentLogEntry>.unmodifiable(
    AgentManagementSliceSelectors.selectedLogs(state),
  );

  @override
  bool get initialized => state.initialized;

  @override
  bool get detecting => _isPending(AgentManagementOperationKind.detection);

  @override
  bool get testing => _isPending(
    AgentManagementOperationKind.connectionTest,
    agentId: selectedAgentId,
  );

  @override
  bool get loadingConfiguration => _isPending(
    AgentManagementOperationKind.configurationLoad,
    agentId: selectedAgentId,
  );

  @override
  bool get savingConfiguration => _isPending(
    AgentManagementOperationKind.configurationSave,
    agentId: selectedAgentId,
  );

  @override
  bool get loadingLogs => _isPending(
    AgentManagementOperationKind.logsLoad,
    agentId: selectedAgentId,
  );

  @override
  bool get updatingAccountDataEnrichment => _isPending(
    AgentManagementOperationKind.accountDataEnrichmentUpdate,
    agentId: selectedAgentId,
  );

  @override
  String? get operationError =>
      AgentManagementSliceSelectors.visibleOperationError(state);

  @override
  bool get supportsAccountDataEnrichment =>
      AgentManagementSliceSelectors.supportsAccountDataEnrichment(state);

  @override
  bool get accountDataEnrichmentEnabled {
    if (!supportsAccountDataEnrichment) {
      return false;
    }
    final config = AgentManagementSliceSelectors.selectedProviderConfig(state);
    return config != null && accountDataEnrichmentEnabledFor(config);
  }

  @override
  List<AgentProviderConfig> get availableThreadProviders =>
      AgentManagementSliceSelectors.availableThreadProviders(state);

  @override
  Future<List<AgentProviderConfig>> loadAvailableThreadProviders() async {
    await initialize();
    return availableThreadProviders;
  }

  @override
  void selectAgent(String agentId) {
    _ensureOpen();
    _dispatch(AgentSelected(agentId));
  }

  @override
  Future<void> initialize({bool autoDetect = false}) {
    if (_closed) {
      return Future<void>.error(
        StateError('AgentManagementSliceStore is closed'),
      );
    }
    if (state.initialized) {
      if (autoDetect && !detecting) _startAutoDetect();
      return Future<void>.value();
    }
    _autoDetectAfterInitialize |= autoDetect;
    final existing = _initializeFuture;
    if (existing != null) return existing;
    final operationId = _nextOperationId(initializeOperationScope);
    final completer = Completer<void>();
    _initializeCompleter = completer;
    final future = _initializeFuture = completer.future;
    try {
      _dispatch(ManagementInitializeRequested(operationId));
    } catch (error, trace) {
      initializationFailed(operationId, error, trace);
    }
    return future;
  }

  @override
  Future<void> detect() async {
    _ensureOpen();
    if (detecting) {
      return;
    }
    await initialize();
    _ensureOpen();
    final operationId = _nextOperationId(detectionOperationScope);
    final completer = Completer<void>();
    _voidCompleters[operationId] = completer;
    _dispatch(DetectionRequested(operationId));
    return completer.future;
  }

  @override
  Future<void> setEnabled(bool enabled) {
    _ensureOpen();
    final current = agent;
    if (current.enabled == enabled) {
      return Future<void>.value();
    }
    final operationId = _nextAgentOperationId(
      'provider-enabled',
      current.definition.id,
    );
    final completer = Completer<void>();
    _voidCompleters[operationId] = completer;
    _dispatch(
      ProviderEnabledToggled(
        operationId: operationId,
        agentId: current.definition.id,
        enabled: enabled,
      ),
    );
    return completer.future;
  }

  @override
  Future<void> setAccountDataEnrichmentEnabled(bool enabled) async {
    _ensureOpen();
    await initialize();
    _ensureOpen();
    if (!supportsAccountDataEnrichment) {
      throw UnsupportedError(
        'Agent $selectedAgentId does not support account data enrichment',
      );
    }
    if (updatingAccountDataEnrichment ||
        accountDataEnrichmentEnabled == enabled) {
      return;
    }
    final agentId = selectedAgentId;
    final operationId = _nextAgentOperationId(
      'account-data-enrichment',
      agentId,
    );
    final completer = Completer<void>();
    _voidCompleters[operationId] = completer;
    _dispatch(
      AccountDataEnrichmentToggled(
        operationId: operationId,
        agentId: agentId,
        enabled: enabled,
      ),
    );
    await completer.future;
  }

  @override
  Future<AgentConnectionTestResult?> testConnection() {
    _ensureOpen();
    if (testing) {
      return Future<AgentConnectionTestResult?>.value();
    }
    final agentId = selectedAgentId;
    final operationId = _nextAgentOperationId('connection-test', agentId);
    final completer = Completer<AgentConnectionTestResult?>();
    _connectionCompleters[operationId] = completer;
    _dispatch(
      ConnectionTestRequested(operationId: operationId, agentId: agentId),
    );
    return completer.future;
  }

  @override
  Future<AgentConfigurationDocument?> loadConfiguration() {
    _ensureOpen();
    if (loadingConfiguration) {
      return Future<AgentConfigurationDocument?>.value(configuration);
    }
    final agentId = selectedAgentId;
    final operationId = _nextAgentOperationId('configuration-load', agentId);
    final completer = Completer<AgentConfigurationDocument?>();
    _configurationLoadCompleters[operationId] = completer;
    _dispatch(
      ConfigurationLoadRequested(operationId: operationId, agentId: agentId),
    );
    return completer.future;
  }

  @override
  String? validateConfiguration(String content) {
    _ensureOpen();
    return effectRunner.validateConfiguration(selectedAgentId, content);
  }

  @override
  Future<AgentConfigurationSaveResult> saveConfiguration(
    String content, {
    bool overwriteExternalChanges = false,
  }) {
    _ensureOpen();
    final original = configuration;
    if (original == null) {
      throw StateError(configurationNotLoadedMessage);
    }
    final agentId = selectedAgentId;
    final operationId = _nextAgentOperationId('configuration-save', agentId);
    final completer = Completer<AgentConfigurationSaveResult>();
    _configurationSaveCompleters[operationId] = completer;
    _dispatch(
      ConfigurationSaveRequested(
        operationId: operationId,
        agentId: agentId,
        original: original,
        content: content,
        overwriteExternalChanges: overwriteExternalChanges,
      ),
    );
    return completer.future;
  }

  @override
  Future<List<AgentLogEntry>> loadLogs() {
    _ensureOpen();
    if (loadingLogs) {
      return Future<List<AgentLogEntry>>.value(logs);
    }
    final agentId = selectedAgentId;
    final operationId = _nextAgentOperationId('logs-load', agentId);
    final completer = Completer<List<AgentLogEntry>>();
    _logsCompleters[operationId] = completer;
    _dispatch(LogsLoadRequested(operationId: operationId, agentId: agentId));
    return completer.future;
  }

  /// Provider settings store ingress。
  @override
  void providerSettingsChanged(AgentProviderSettings settings) {
    if (_closed) return;
    _dispatch(ProviderSettingsSnapshotChanged(settings));
  }

  /// Shell session 事实 ingress；无需当前选中 Provider。
  @override
  void runtimeFactsReplaced(AgentManagementRuntimeFacts facts) {
    if (_closed) return;
    _dispatch(RuntimeFactsReplaced(facts));
  }

  @override
  void initializationSucceeded(
    OperationId operationId,
    AgentProviderSettings settings,
    Map<String, ManagedAgent> agentsById,
  ) {
    if (_closed) return;
    final accepted = _accepts(
      AgentManagementOperationKind.initialize,
      operationId,
    );
    _dispatch(
      ManagementInitialized(
        operationId: operationId,
        providerSettings: settings,
        agentsById: agentsById,
      ),
    );
    if (accepted) {
      final completer = _initializeCompleter;
      _initializeCompleter = null;
      _initializeFuture = null;
      if (completer != null && !completer.isCompleted) completer.complete();
      final autoDetect = _autoDetectAfterInitialize;
      _autoDetectAfterInitialize = false;
      if (autoDetect && !_closed && !detecting) _startAutoDetect();
    }
  }

  @override
  void initializationFailed(
    OperationId operationId,
    Object error,
    StackTrace stackTrace,
  ) {
    if (_closed) return;
    final accepted = _accepts(
      AgentManagementOperationKind.initialize,
      operationId,
    );
    _dispatch(ManagementInitializationFailed(operationId));
    if (accepted) {
      final completer = _initializeCompleter;
      _initializeCompleter = null;
      _initializeFuture = null;
      _autoDetectAfterInitialize = false;
      if (completer != null && !completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    }
  }

  @override
  void detectionStarted(OperationId operationId, String agentId) {
    if (_closed) return;
    _dispatch(
      AgentDetectionStarted(operationId: operationId, agentId: agentId),
    );
  }

  @override
  void detectionProgressReported(
    OperationId operationId,
    String agentId,
    AgentDetectionProgress progress,
    ManagedAgent partial,
  ) {
    if (_closed) return;
    _dispatch(
      AgentDetectionProgressReported(
        operationId: operationId,
        agentId: agentId,
        progress: progress,
        partial: partial,
      ),
    );
  }

  @override
  void agentDetected(
    OperationId operationId,
    String agentId,
    ManagedAgent detected,
  ) {
    if (_closed) return;
    _dispatch(
      AgentDetectionSucceeded(
        operationId: operationId,
        agentId: agentId,
        agent: detected,
      ),
    );
  }

  @override
  void detectionCompleted(OperationId operationId) {
    if (_closed) return;
    _dispatch(DetectionCompleted(operationId));
    _voidCompleters.remove(operationId)?.complete();
  }

  @override
  void detectionFailed(OperationId operationId, String message) {
    if (_closed) return;
    _dispatch(DetectionFailed(operationId: operationId, message: message));
    _voidCompleters.remove(operationId)?.complete();
  }

  @override
  void providerEnabledUpdated(
    OperationId operationId,
    String agentId,
    bool enabled,
    AgentProviderSettings settings,
  ) {
    if (_closed) return;
    _dispatch(
      ProviderEnabledUpdated(
        operationId: operationId,
        agentId: agentId,
        enabled: enabled,
        providerSettings: settings,
      ),
    );
    _voidCompleters.remove(operationId)?.complete();
  }

  @override
  void providerEnabledUpdateFailed(
    OperationId operationId,
    String agentId,
    String message,
  ) {
    if (_closed) return;
    _dispatch(
      ProviderEnabledUpdateFailed(
        operationId: operationId,
        agentId: agentId,
        message: message,
      ),
    );
    _voidCompleters.remove(operationId)?.complete();
  }

  @override
  void accountDataEnrichmentUpdated(
    OperationId operationId,
    String agentId,
    AgentProviderSettings settings,
  ) {
    if (_closed) return;
    _dispatch(
      AccountDataEnrichmentUpdated(
        operationId: operationId,
        agentId: agentId,
        providerSettings: settings,
      ),
    );
    _voidCompleters.remove(operationId)?.complete();
  }

  @override
  void accountDataEnrichmentUpdateFailed(
    OperationId operationId,
    String agentId,
    String message,
  ) {
    if (_closed) return;
    _dispatch(
      AccountDataEnrichmentUpdateFailed(
        operationId: operationId,
        agentId: agentId,
        message: message,
      ),
    );
    _voidCompleters.remove(operationId)?.complete();
  }

  @override
  void connectionTestSucceeded({
    required OperationId operationId,
    required String agentId,
    required AgentConnectionTestResult result,
    required List<AgentModelInfo> models,
    required String modelSource,
    required DateTime modelsUpdatedAt,
  }) {
    if (_closed) return;
    _dispatch(
      ConnectionTestSucceeded(
        operationId: operationId,
        agentId: agentId,
        result: result,
        models: models,
        modelSource: modelSource,
        modelsUpdatedAt: modelsUpdatedAt,
      ),
    );
    _connectionCompleters.remove(operationId)?.complete(result);
  }

  @override
  void connectionTestFailed(
    OperationId operationId,
    String agentId,
    String message,
  ) {
    if (_closed) return;
    _dispatch(
      ConnectionTestFailed(
        operationId: operationId,
        agentId: agentId,
        message: message,
      ),
    );
    _connectionCompleters.remove(operationId)?.complete(null);
  }

  @override
  void configurationLoaded(
    OperationId operationId,
    String agentId,
    AgentConfigurationDocument document,
  ) {
    if (_closed) return;
    _dispatch(
      ConfigurationLoadSucceeded(
        operationId: operationId,
        agentId: agentId,
        document: document,
      ),
    );
    _configurationLoadCompleters.remove(operationId)?.complete(document);
  }

  @override
  void configurationLoadFailed(
    OperationId operationId,
    String agentId,
    String message,
  ) {
    if (_closed) return;
    _dispatch(
      ConfigurationLoadFailed(
        operationId: operationId,
        agentId: agentId,
        message: message,
      ),
    );
    _configurationLoadCompleters.remove(operationId)?.complete(null);
  }

  @override
  void configurationSaved(
    OperationId operationId,
    String agentId,
    String originalSignature,
    AgentConfigurationSaveResult result,
  ) {
    if (_closed) return;
    _dispatch(
      ConfigurationSaveSucceeded(
        operationId: operationId,
        agentId: agentId,
        originalSignature: originalSignature,
        result: result,
      ),
    );
    _configurationSaveCompleters.remove(operationId)?.complete(result);
  }

  @override
  void configurationSaveFailed(
    OperationId operationId,
    String agentId,
    Object error,
    StackTrace stackTrace,
  ) {
    if (_closed) return;
    _dispatch(
      ConfigurationSaveFailed(operationId: operationId, agentId: agentId),
    );
    _configurationSaveCompleters
        .remove(operationId)
        ?.completeError(error, stackTrace);
  }

  @override
  void logsLoaded(
    OperationId operationId,
    String agentId,
    List<String> paths,
    List<AgentLogEntry> entries,
  ) {
    if (_closed) return;
    _dispatch(
      LogsLoadSucceeded(
        operationId: operationId,
        agentId: agentId,
        paths: paths,
        logs: entries,
      ),
    );
    _logsCompleters
        .remove(operationId)
        ?.complete(List<AgentLogEntry>.unmodifiable(entries));
  }

  @override
  void logsLoadFailed(OperationId operationId, String agentId, String message) {
    if (_closed) return;
    _dispatch(
      LogsLoadFailed(
        operationId: operationId,
        agentId: agentId,
        message: message,
      ),
    );
    _logsCompleters.remove(operationId)?.complete(const <AgentLogEntry>[]);
  }

  @override
  void stopAcceptingCommandsAndSettleWaiters() {
    if (_closed) {
      return;
    }
    _closed = true;
    final error = StateError('AgentManagementSliceStore is closed');
    _completeClosed(_initializeCompleter, error);
    _initializeCompleter = null;
    _initializeFuture = null;
    for (final completer in _voidCompleters.values) {
      _completeClosed(completer, error);
    }
    for (final completer in _connectionCompleters.values) {
      _completeClosed(completer, error);
    }
    for (final completer in _configurationLoadCompleters.values) {
      _completeClosed(completer, error);
    }
    for (final completer in _configurationSaveCompleters.values) {
      _completeClosed(completer, error);
    }
    for (final completer in _logsCompleters.values) {
      _completeClosed(completer, error);
    }
    _voidCompleters.clear();
    _connectionCompleters.clear();
    _configurationLoadCompleters.clear();
    _configurationSaveCompleters.clear();
    _logsCompleters.clear();
  }

  void _trackAndReport(Future<void> execution) {
    _physicalExecutions.add(execution);
    unawaited(() async {
      try {
        await execution;
      } catch (_) {
        // A fixed classification only: never log configuration/error contents.
        try {
          _log.e('Unexpected Agent management execution failure');
        } catch (_) {}
      } finally {
        _physicalExecutions.remove(execution);
      }
    }());
  }

  @override
  Future<void> drainExecutions() {
    if (!_closed) throw StateError('Management owner must stop before drain');
    return _drainFuture ??= _drainPhysicalExecutions();
  }

  Future<void> _drainPhysicalExecutions() async {
    while (_physicalExecutions.isNotEmpty) {
      await Future.wait<void>(
        List<Future<void>>.of(_physicalExecutions),
        eagerError: false,
      );
    }
  }

  bool _dispatch(AgentManagementSliceIntent intent) {
    if (_closed) {
      return false;
    }
    final before = state;
    final transition = agentManagementSliceReduce(before, intent);
    if (!identical(transition.state, before)) {
      state = transition.state;
    }
    for (final effect in transition.effects) {
      if (_closed) break;
      final execution = Completer<void>();
      _trackAndReport(execution.future);
      try {
        execution.complete(effectRunner.run(effect));
      } catch (error, trace) {
        execution.completeError(error, trace);
      }
    }
    return transition.effects.isNotEmpty;
  }

  bool _isPending(AgentManagementOperationKind kind, {String? agentId}) =>
      AgentManagementSliceSelectors.isPending(state, kind, agentId: agentId);

  bool _accepts(
    AgentManagementOperationKind kind,
    OperationId operationId, {
    String? agentId,
  }) =>
      state.pendingOperations[AgentManagementOperationKey(kind, agentId)] ==
      operationId;

  OperationId _nextAgentOperationId(String operation, String agentId) =>
      _nextOperationId('$operation/$agentId');

  OperationId _nextOperationId(String scope) =>
      _generators.putIfAbsent(scope, () => _generatorFactory(scope)).next();

  void _startAutoDetect() {
    unawaited(
      detect().onError((error, stackTrace) {
        // autoDetect 没有调用方可接收 Future；页面销毁导致的关闭错误在此消费，
        // 其他异常仍保留原栈抛出。
        if (!_closed) {
          Error.throwWithStackTrace(
            error ?? StateError('Agent management auto-detect failed'),
            stackTrace,
          );
        }
      }),
    );
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('AgentManagementSliceStore is closed');
    }
  }
}

void _completeClosed<T>(Completer<T>? completer, Object error) {
  if (completer != null && !completer.isCompleted) {
    completer.completeError(error);
  }
}

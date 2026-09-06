import 'agent_management_slice_effect.dart';
import '../agent_management_detection_port.dart';
import '../agent_management_agent_view.dart';
import '../agent_management_detection_state.dart';
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
  final Map<OperationId, Completer<AgentManagementConnectionCheckSummary?>>
  _connectionCompleters =
      <OperationId, Completer<AgentManagementConnectionCheckSummary?>>{};
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
  List<AgentManagementAgentView> get agents =>
      AgentManagementSliceSelectors.agents(state);

  @override
  AgentManagementAgentView get agent =>
      AgentManagementSliceSelectors.selectedAgent(state);

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
  bool get detecting => state.detection.isLoading;

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
      if (autoDetect) _startAutoDetect();
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
  Future<AgentManagementDetectionRunResult> detect() => refreshDetection();

  @override
  Future<AgentManagementDetectionRunResult> ensureDetected() =>
      _requestDetection(explicit: false);
  @override
  Future<AgentManagementDetectionRunResult> refreshDetection() =>
      _requestDetection(explicit: true);

  _ActiveDetectionRun? _activeRun;
  int _ownerGeneration = 0;

  Future<AgentManagementDetectionRunResult> _requestDetection({
    required bool explicit,
  }) {
    if (_closed) return Future.value(AgentManagementDetectionRunResult.closed);
    final active = _activeRun;
    if (active != null) return active.caller.future;
    if (!explicit && state.detection.automaticAttemptConsumed) {
      return Future.value(
        state.detection.lastResult ??
            AgentManagementDetectionRunResult.canceled,
      );
    }
    final run = _ActiveDetectionRun(
      _nextOperationId(detectionOperationScope),
      _ownerGeneration,
      state.catalogGeneration,
    );
    // 占位和排空登记都先于 dispatch，抵抗同步 observer 重入。
    _activeRun = run;
    _trackAndReport(run.executionDone.future);
    unawaited(_executeDetection(run));
    return run.caller.future;
  }

  bool _acceptsRun(_ActiveDetectionRun run) =>
      !_closed &&
      identical(_activeRun, run) &&
      _ownerGeneration == run.ownerGeneration &&
      state.catalogGeneration == run.catalogGeneration &&
      !run.cancellation.isCanceled;
  void _requireRun(_ActiveDetectionRun run) {
    if (!_acceptsRun(run)) throw const AgentManagementDetectionCanceled();
  }

  Future<void> _executeDetection(_ActiveDetectionRun run) async {
    try {
      _dispatch(DetectionRequested(run.id));
      _requireRun(run);
      await initialize(autoDetect: false);
      _requireRun(run);
      final ids = List<String>.unmodifiable(state.orderedAgentIds);
      _dispatch(DetectionRunStarted(run.id, ids));
      _requireRun(run);
      await effectRunner.run(
        DetectAgentsEffect(
          run.id,
          providerIds: ids,
          catalogGeneration: run.catalogGeneration,
          ownerGeneration: run.ownerGeneration,
          cancellation: run.cancellation,
        ),
      );
      _requireRun(run);
      final outcomes = state.detection.outcomesByProviderId.values;
      final succeeded = outcomes
          .where((v) => v == ProviderDetectionOutcome.succeeded)
          .length;
      final result = ids.isNotEmpty && succeeded == ids.length
          ? AgentManagementDetectionRunResult.succeeded
          : succeeded > 0
          ? AgentManagementDetectionRunResult.partialFailure
          : AgentManagementDetectionRunResult.failed(_detectionFailure(run));
      _finishDetection(run, result);
    } on AgentManagementDetectionCanceled {
      _finishDetection(
        run,
        _closed
            ? AgentManagementDetectionRunResult.closed
            : AgentManagementDetectionRunResult.canceled,
      );
    } catch (_) {
      _finishDetection(
        run,
        _closed
            ? AgentManagementDetectionRunResult.closed
            : AgentManagementDetectionRunResult.failed(_detectionFailure(run)),
      );
    } finally {
      if (!run.caller.isCompleted) {
        run.settle(
          _closed
              ? AgentManagementDetectionRunResult.closed
              : AgentManagementDetectionRunResult.canceled,
        );
      }
      if (identical(_activeRun, run)) _activeRun = null;
      run.executionDone.complete();
    }
  }

  AgentManagementFailure _detectionFailure(_ActiveDetectionRun run) =>
      AgentManagementFailure(
        kind: AgentManagementFailureKind.detection,
        operationId: run.id,
      );
  void _finishDetection(
    _ActiveDetectionRun run,
    AgentManagementDetectionRunResult result,
  ) {
    if (!run.caller.isCompleted) {
      // 先确定终态再发布，避免 observer 的取消改写已经完成的结果。
      run.settle(result);
      if (!_closed && identical(_activeRun, run)) {
        _dispatch(DetectionRunFinished(run.id, result));
      }
    }
  }

  @override
  void cancelDetection() {
    final run = _activeRun;
    if (run == null) return;
    run.cancellation.cancel();
    _finishDetection(run, AgentManagementDetectionRunResult.canceled);
  }

  /// 新目录必须使用新 generation；相同 id 的新定义不能接收旧结果。
  void replaceDetectionCatalog(
    int generation,
    Map<String, AgentManagementDisplayDefinition> definitions,
  ) {
    if (_closed || generation == state.catalogGeneration) return;
    cancelDetection();
    _dispatch(ManagementCatalogReplaced(generation, definitions));
  }

  @override
  bool acceptDetectionResult(
    OperationId id,
    int ownerGeneration,
    int catalogGeneration,
    AgentManagementDetectionEvent event,
  ) {
    final run = _activeRun;
    if (run == null ||
        run.id != id ||
        run.ownerGeneration != ownerGeneration ||
        run.catalogGeneration != catalogGeneration ||
        !_acceptsRun(run)) {
      return false;
    }
    final before = state;
    _dispatch(DetectionResultAccepted(id, event));
    return !identical(before, state);
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
  Future<AgentManagementConnectionCheckSummary?> testConnection() {
    _ensureOpen();
    if (testing) {
      return Future<AgentManagementConnectionCheckSummary?>.value();
    }
    final agentId = selectedAgentId;
    final operationId = _nextAgentOperationId('connection-test', agentId);
    final completer = Completer<AgentManagementConnectionCheckSummary?>();
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
    Map<String, AgentDetectionConfirmedRecord> confirmedByProviderId,
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
        confirmedByProviderId: confirmedByProviderId,
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
    required AgentManagementConnectionCheckSummary result,
    required List<AgentModelInfo> models,
    required String modelSource,
    required DateTime modelsUpdatedAt,
  }) {
    if (_closed) return;
    if (!_accepts(
      AgentManagementOperationKind.connectionTest,
      operationId,
      agentId: agentId,
    )) {
      _connectionCompleters.remove(operationId)?.complete(null);
      return;
    }
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
    int fileCount,
    List<AgentLogEntry> entries,
  ) {
    if (_closed) return;
    _dispatch(
      LogsLoadSucceeded(
        operationId: operationId,
        agentId: agentId,
        fileCount: fileCount,
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
    _ownerGeneration += 1;
    final run = _activeRun;
    if (run != null) {
      run.cancellation.cancel();
      run.settle(AgentManagementDetectionRunResult.closed);
    }
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
      try {
        state = transition.state;
      } catch (_) {
        // 发布已提交后，观察者失败不能回滚结果或让调用者悬挂。
        try {
          _log.e('Agent management observer failed');
        } catch (_) {}
      }
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
    unawaited(ensureDetected());
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

final class _DetectionCancellation implements AgentManagementCancellation {
  bool _canceled = false;
  @override
  bool get isCanceled => _canceled;
  void cancel() {
    _canceled = true;
  }

  @override
  void throwIfCanceled() {
    if (_canceled) throw const AgentManagementDetectionCanceled();
  }
}

final class _ActiveDetectionRun {
  _ActiveDetectionRun(this.id, this.ownerGeneration, this.catalogGeneration);
  final OperationId id;
  final int ownerGeneration;
  final int catalogGeneration;
  final cancellation = _DetectionCancellation();
  final caller = Completer<AgentManagementDetectionRunResult>();
  final executionDone = Completer<void>();
  void settle(AgentManagementDetectionRunResult result) {
    if (!caller.isCompleted) caller.complete(result);
  }
}

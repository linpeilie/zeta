import 'dart:async';

import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/agent_management/application/agent_management_operations.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_effect.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_intent.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_reducer.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_state.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';

/// Agent management effect 的 app 组合层执行入口。
abstract interface class AgentManagementSliceEffectRunner {
  void run(AgentManagementSliceEffect effect);

  /// 配置校验是 repository 的同步纯计算，不进入 reducer 的异步状态。
  String? validateConfiguration(String agentId, String content);
}

/// 页面 scope 的纯 Dart Agent management MVI store。
final class AgentManagementSliceStore implements AgentManagementOperations {
  AgentManagementSliceStore({
    required AgentManagementSliceState initialState,
    required this.effectRunner,
    required this.configurationNotLoadedMessage,
    OperationIdGenerator Function(String scope)? operationIdGeneratorFactory,
  }) : _state = initialState,
       _generatorFactory =
           operationIdGeneratorFactory ??
           ((scope) => OperationIdGenerator(scope: scope));

  static const String initializeOperationScope = 'agent-management/initialize';
  static const String detectionOperationScope = 'agent-management/detect';

  final AgentManagementSliceEffectRunner effectRunner;
  final String configurationNotLoadedMessage;
  final OperationIdGenerator Function(String scope) _generatorFactory;
  final Map<String, OperationIdGenerator> _generators =
      <String, OperationIdGenerator>{};
  final List<void Function()> _listeners = <void Function()>[];
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

  AgentManagementSliceState _state;
  Future<void>? _initializeFuture;
  Completer<void>? _initializeCompleter;
  bool _closed = false;

  AgentManagementSliceState get state => _state;

  bool get isClosed => _closed;

  @override
  List<ManagedAgent> get agents => AgentManagementSliceSelectors.agents(_state);

  @override
  ManagedAgent get agent => AgentManagementSliceSelectors.selectedAgent(_state);

  @override
  String get selectedAgentId => _state.selectedAgentId;

  @override
  AgentDetectionProgress? get detectionProgress => _state.detectionProgress;

  @override
  AgentConfigurationDocument? get configuration =>
      AgentManagementSliceSelectors.selectedConfiguration(_state);

  @override
  List<AgentLogEntry> get logs => List<AgentLogEntry>.unmodifiable(
    AgentManagementSliceSelectors.selectedLogs(_state),
  );

  @override
  bool get initialized => _state.initialized;

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
      AgentManagementSliceSelectors.visibleOperationError(_state);

  @override
  bool get supportsAccountDataEnrichment =>
      AgentManagementSliceSelectors.supportsAccountDataEnrichment(_state);

  @override
  bool get accountDataEnrichmentEnabled =>
      AgentManagementSliceSelectors.accountDataEnrichmentEnabled(_state);

  @override
  List<AgentProviderConfig> get availableThreadProviders =>
      AgentManagementSliceSelectors.availableThreadProviders(_state);

  void addListener(void Function() listener) => _listeners.add(listener);

  void removeListener(void Function() listener) => _listeners.remove(listener);

  void Function() subscribe(void Function() listener) {
    addListener(listener);
    return () => removeListener(listener);
  }

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
  Future<void> initialize({bool autoDetect = false}) async {
    _ensureOpen();
    if (_state.initialized) {
      if (autoDetect && !detecting) {
        _startAutoDetect();
      }
      return;
    }
    final existing = _initializeFuture;
    if (existing != null) {
      await existing;
      if (autoDetect && !detecting) {
        _startAutoDetect();
      }
      return;
    }
    final operationId = _nextOperationId(initializeOperationScope);
    final completer = Completer<void>();
    _initializeCompleter = completer;
    _initializeFuture = completer.future;
    try {
      // listener 属于 presentation 边界，异常不能把共享初始化 Future 永久留在
      // pending。把同步 dispatch 也纳入清理区间，下一次请求即可重新初始化。
      _dispatch(ManagementInitializeRequested(operationId));
      await completer.future;
    } finally {
      if (identical(_initializeCompleter, completer)) {
        _initializeCompleter = null;
        _initializeFuture = null;
      }
    }
    if (autoDetect && !_closed && !detecting) {
      _startAutoDetect();
    }
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
  void providerSettingsChanged(AgentProviderSettings settings) {
    if (!_closed) {
      _dispatch(ProviderSettingsSnapshotChanged(settings));
    }
  }

  /// runtime owner ingress。
  void runtimeSnapshotChanged(String agentId, AgentRuntimeState runtimeState) {
    if (!_closed) {
      _dispatch(
        RuntimeSnapshotChanged(agentId: agentId, runtimeState: runtimeState),
      );
    }
  }

  void initializationSucceeded(
    OperationId operationId,
    AgentProviderSettings settings,
    Map<String, ManagedAgent> agentsById,
  ) {
    if (_closed) {
      return;
    }
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
      _initializeCompleter?.complete();
    }
  }

  void initializationFailed(
    OperationId operationId,
    Object error,
    StackTrace stackTrace,
  ) {
    if (_closed) {
      return;
    }
    final accepted = _accepts(
      AgentManagementOperationKind.initialize,
      operationId,
    );
    _dispatch(ManagementInitializationFailed(operationId));
    if (accepted) {
      _initializeCompleter?.completeError(error, stackTrace);
    }
  }

  void detectionStarted(OperationId operationId, String agentId) {
    if (!_closed) {
      _dispatch(
        AgentDetectionStarted(operationId: operationId, agentId: agentId),
      );
    }
  }

  void detectionProgressReported(
    OperationId operationId,
    String agentId,
    AgentDetectionProgress progress,
    ManagedAgent partial,
  ) {
    if (!_closed) {
      _dispatch(
        AgentDetectionProgressReported(
          operationId: operationId,
          agentId: agentId,
          progress: progress,
          partial: partial,
        ),
      );
    }
  }

  void agentDetected(
    OperationId operationId,
    String agentId,
    ManagedAgent detected,
  ) {
    if (!_closed) {
      _dispatch(
        AgentDetectionSucceeded(
          operationId: operationId,
          agentId: agentId,
          agent: detected,
        ),
      );
    }
  }

  void detectionCompleted(OperationId operationId) {
    if (!_closed) {
      _dispatch(DetectionCompleted(operationId));
    }
    _voidCompleters.remove(operationId)?.complete();
  }

  void detectionFailed(OperationId operationId, String message) {
    if (!_closed) {
      _dispatch(DetectionFailed(operationId: operationId, message: message));
    }
    _voidCompleters.remove(operationId)?.complete();
  }

  void providerEnabledUpdated(
    OperationId operationId,
    String agentId,
    bool enabled,
    AgentProviderSettings settings,
  ) {
    if (!_closed) {
      _dispatch(
        ProviderEnabledUpdated(
          operationId: operationId,
          agentId: agentId,
          enabled: enabled,
          providerSettings: settings,
        ),
      );
    }
    _voidCompleters.remove(operationId)?.complete();
  }

  void providerEnabledUpdateFailed(
    OperationId operationId,
    String agentId,
    String message,
  ) {
    if (!_closed) {
      _dispatch(
        ProviderEnabledUpdateFailed(
          operationId: operationId,
          agentId: agentId,
          message: message,
        ),
      );
    }
    _voidCompleters.remove(operationId)?.complete();
  }

  void accountDataEnrichmentUpdated(
    OperationId operationId,
    String agentId,
    AgentProviderSettings settings,
  ) {
    if (!_closed) {
      _dispatch(
        AccountDataEnrichmentUpdated(
          operationId: operationId,
          agentId: agentId,
          providerSettings: settings,
        ),
      );
    }
    _voidCompleters.remove(operationId)?.complete();
  }

  void accountDataEnrichmentUpdateFailed(
    OperationId operationId,
    String agentId,
    String message,
  ) {
    if (!_closed) {
      _dispatch(
        AccountDataEnrichmentUpdateFailed(
          operationId: operationId,
          agentId: agentId,
          message: message,
        ),
      );
    }
    _voidCompleters.remove(operationId)?.complete();
  }

  void connectionTestSucceeded({
    required OperationId operationId,
    required String agentId,
    required AgentConnectionTestResult result,
    required List<AgentModelInfo> models,
    required String modelSource,
    required DateTime modelsUpdatedAt,
  }) {
    if (!_closed) {
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
    }
    _connectionCompleters.remove(operationId)?.complete(result);
  }

  void connectionTestFailed(
    OperationId operationId,
    String agentId,
    String message,
  ) {
    if (!_closed) {
      _dispatch(
        ConnectionTestFailed(
          operationId: operationId,
          agentId: agentId,
          message: message,
        ),
      );
    }
    _connectionCompleters.remove(operationId)?.complete(null);
  }

  void configurationLoaded(
    OperationId operationId,
    String agentId,
    AgentConfigurationDocument document,
  ) {
    if (!_closed) {
      _dispatch(
        ConfigurationLoadSucceeded(
          operationId: operationId,
          agentId: agentId,
          document: document,
        ),
      );
    }
    _configurationLoadCompleters.remove(operationId)?.complete(document);
  }

  void configurationLoadFailed(
    OperationId operationId,
    String agentId,
    String message,
  ) {
    if (!_closed) {
      _dispatch(
        ConfigurationLoadFailed(
          operationId: operationId,
          agentId: agentId,
          message: message,
        ),
      );
    }
    _configurationLoadCompleters.remove(operationId)?.complete(null);
  }

  void configurationSaved(
    OperationId operationId,
    String agentId,
    String originalSignature,
    AgentConfigurationSaveResult result,
  ) {
    if (!_closed) {
      _dispatch(
        ConfigurationSaveSucceeded(
          operationId: operationId,
          agentId: agentId,
          originalSignature: originalSignature,
          result: result,
        ),
      );
    }
    _configurationSaveCompleters.remove(operationId)?.complete(result);
  }

  void configurationSaveFailed(
    OperationId operationId,
    String agentId,
    Object error,
    StackTrace stackTrace,
  ) {
    if (!_closed) {
      _dispatch(
        ConfigurationSaveFailed(operationId: operationId, agentId: agentId),
      );
    }
    _configurationSaveCompleters
        .remove(operationId)
        ?.completeError(error, stackTrace);
  }

  void logsLoaded(
    OperationId operationId,
    String agentId,
    List<String> paths,
    List<AgentLogEntry> entries,
  ) {
    if (!_closed) {
      _dispatch(
        LogsLoadSucceeded(
          operationId: operationId,
          agentId: agentId,
          paths: paths,
          logs: entries,
        ),
      );
    }
    _logsCompleters
        .remove(operationId)
        ?.complete(List<AgentLogEntry>.unmodifiable(entries));
  }

  void logsLoadFailed(OperationId operationId, String agentId, String message) {
    if (!_closed) {
      _dispatch(
        LogsLoadFailed(
          operationId: operationId,
          agentId: agentId,
          message: message,
        ),
      );
    }
    _logsCompleters.remove(operationId)?.complete(const <AgentLogEntry>[]);
  }

  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _listeners.clear();
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

  bool _dispatch(AgentManagementSliceIntent intent) {
    if (_closed) {
      return false;
    }
    final before = _state;
    final transition = agentManagementSliceReduce(before, intent);
    if (!identical(transition.state, before)) {
      _state = transition.state;
      _notifyListeners();
    }
    for (final effect in transition.effects) {
      effectRunner.run(effect);
    }
    return transition.effects.isNotEmpty;
  }

  bool _isPending(AgentManagementOperationKind kind, {String? agentId}) =>
      AgentManagementSliceSelectors.isPending(_state, kind, agentId: agentId);

  bool _accepts(
    AgentManagementOperationKind kind,
    OperationId operationId, {
    String? agentId,
  }) =>
      _state.pendingOperations[AgentManagementOperationKey(kind, agentId)] ==
      operationId;

  OperationId _nextAgentOperationId(String operation, String agentId) =>
      _nextOperationId('$operation/$agentId');

  OperationId _nextOperationId(String scope) =>
      _generators.putIfAbsent(scope, () => _generatorFactory(scope)).next();

  void _notifyListeners() {
    final snapshot = List<void Function()>.of(_listeners);
    for (final listener in snapshot) {
      listener();
    }
  }

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

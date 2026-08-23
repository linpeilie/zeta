import 'dart:async';

import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/usage_statistics/application/agent_usage_panel_operations.dart';
import 'package:zeta/src/features/usage_statistics/application/agent_usage_panel_slice/agent_usage_panel_slice_effect.dart';
import 'package:zeta/src/features/usage_statistics/application/agent_usage_panel_slice/agent_usage_panel_slice_intent.dart';
import 'package:zeta/src/features/usage_statistics/application/agent_usage_panel_slice/agent_usage_panel_slice_reducer.dart';
import 'package:zeta/src/features/usage_statistics/application/agent_usage_panel_slice/agent_usage_panel_slice_state.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_panel_models.dart';

/// Agent Usage Panel effect 的 app 组合层执行入口。
abstract interface class AgentUsagePanelSliceEffectRunner {
  AgentUsagePanelRepository get repository;

  void run(AgentUsagePanelSliceEffect effect);

  void close();
}

typedef _ProviderLoad = ({OperationId operationId, Future<void> future});

/// Agent Usage Panel 的纯 Dart MVI owner。
final class AgentUsagePanelSliceStore implements AgentUsagePanelOperations {
  AgentUsagePanelSliceStore({
    required AgentUsagePanelSliceState initialState,
    required this.effectRunner,
    OperationIdGenerator? directoryOperationIdGenerator,
    OperationIdGenerator Function(String providerId)?
    providerOperationIdGenerator,
  }) : _state = initialState,
       _directoryOperationIdGenerator =
           directoryOperationIdGenerator ??
           OperationIdGenerator(scope: 'agent-usage/directory'),
       _providerOperationIdGenerator =
           providerOperationIdGenerator ??
           ((providerId) =>
               OperationIdGenerator(scope: 'agent-usage/provider/$providerId'));

  final AgentUsagePanelSliceEffectRunner effectRunner;
  final OperationIdGenerator _directoryOperationIdGenerator;
  final OperationIdGenerator Function(String providerId)
  _providerOperationIdGenerator;
  final Map<String, OperationIdGenerator> _providerGenerators =
      <String, OperationIdGenerator>{};
  final List<void Function()> _listeners = <void Function()>[];
  final Map<OperationId, Completer<void>> _directoryCompleters =
      <OperationId, Completer<void>>{};
  final Map<OperationId, Completer<void>> _providerCompleters =
      <OperationId, Completer<void>>{};
  final Map<String, _ProviderLoad> _providerLoads = <String, _ProviderLoad>{};

  AgentUsagePanelSliceState _state;
  bool _closed = false;

  AgentUsagePanelSliceState get state => _state;
  bool get isClosed => _closed;

  @override
  AgentUsagePanelRepository get repository => effectRunner.repository;

  @override
  List<AgentUsagePanelProviderState> get providers => _state.providers;

  @override
  String? get preferredProviderId => _state.preferredProviderId;

  @override
  String? get selectedProviderId => _state.selectedProviderId;

  @override
  DateTime? get lastUpdated => _state.lastUpdated;

  @override
  String? get errorMessage => _state.directoryError;

  @override
  bool get hasDiscoveredProviders => _state.directoryDiscovered;

  @override
  bool get isLoading => AgentUsagePanelSliceSelectors.isLoading(_state);

  @override
  AgentUsagePanelProviderState? get selectedProvider =>
      AgentUsagePanelSliceSelectors.selectedProvider(_state);

  @override
  List<AgentUsagePanelEntry> get entries =>
      AgentUsagePanelSliceSelectors.entries(_state);

  @override
  AgentUsagePanelEntry? get selectedEntry => selectedProvider?.entry;

  void addListener(void Function() listener) => _listeners.add(listener);

  void removeListener(void Function() listener) => _listeners.remove(listener);

  void Function() subscribe(void Function() listener) {
    addListener(listener);
    return () => removeListener(listener);
  }

  @override
  Future<void> refresh({
    bool forceRefresh = true,
    bool showLoading = true,
  }) async {
    _ensureOpen();
    if (!_state.directoryDiscovered || _state.providers.isEmpty) {
      await _requestDirectory(showLoading: showLoading);
    }
    final providerId = _state.selectedProviderId;
    if (providerId == null || _closed) {
      return;
    }
    await _ensureProviderLoaded(
      providerId,
      forceRefresh: forceRefresh,
      showLoading: showLoading,
    );
  }

  @override
  Future<void> synchronizeProviders({bool showLoading = false}) async {
    _ensureOpen();
    await _requestDirectory(showLoading: showLoading);
    final providerId = _state.selectedProviderId;
    if (providerId == null || _closed) {
      return;
    }
    await _ensureProviderLoaded(
      providerId,
      forceRefresh: false,
      showLoading: showLoading,
    );
  }

  @override
  void selectProvider(String providerId) {
    _ensureOpen();
    final normalized = _normalizeProviderId(providerId);
    if (normalized == null || !_containsProvider(normalized)) {
      return;
    }
    _dispatch(AgentUsageProviderSelected(normalized));
    unawaited(_ensureProviderLoaded(normalized));
  }

  @override
  void restorePreferredProviderId(String? providerId) {
    _ensureOpen();
    final normalized = _normalizeProviderId(providerId);
    final selectionAlreadyMatches =
        !_state.directoryDiscovered ||
        _state.selectedProviderId == normalized &&
            (normalized == null || _containsProvider(normalized));
    if (_state.preferredProviderId == normalized && selectionAlreadyMatches) {
      final selected = _state.selectedProviderId;
      if (selected != null) {
        unawaited(_ensureProviderLoaded(selected));
      }
      return;
    }
    _dispatch(AgentUsagePreferredProviderRestored(normalized));
    final selected = _state.selectedProviderId;
    if (selected != null) {
      unawaited(_ensureProviderLoaded(selected));
    }
  }

  @override
  void selectProviderFromTurn(String providerId) {
    _ensureOpen();
    final normalized = _normalizeProviderId(providerId);
    if (normalized == null) {
      return;
    }
    _dispatch(AgentUsageProviderSelectedFromTurn(normalized));
  }

  Future<void> _requestDirectory({required bool showLoading}) {
    final operationId = _directoryOperationIdGenerator.next();
    final completer = Completer<void>();
    _directoryCompleters[operationId] = completer;
    try {
      _dispatch(
        AgentUsageDirectoryRequested(
          operationId: operationId,
          showLoading: showLoading,
        ),
      );
    } catch (_) {
      _directoryCompleters.remove(operationId);
      rethrow;
    }
    return completer.future;
  }

  Future<void> _ensureProviderLoaded(
    String providerId, {
    bool forceRefresh = false,
    bool showLoading = true,
  }) {
    final providerState = _stateFor(providerId);
    if (providerState == null ||
        (!forceRefresh &&
            providerState.status == AgentUsagePanelProviderLoadStatus.loaded)) {
      return Future<void>.value();
    }
    final existing = _providerLoads[providerId];
    if (existing != null) {
      return existing.future;
    }
    final operationId = _providerGenerators
        .putIfAbsent(
          providerId,
          () => _providerOperationIdGenerator(providerId),
        )
        .next();
    final completer = Completer<void>();
    _providerCompleters[operationId] = completer;
    final load = (operationId: operationId, future: completer.future);
    _providerLoads[providerId] = load;
    try {
      _dispatch(
        AgentUsageProviderLoadRequested(
          operationId: operationId,
          providerId: providerId,
          forceRefresh: forceRefresh,
          showLoading: showLoading,
        ),
      );
    } catch (_) {
      _providerLoads.remove(providerId);
      _providerCompleters.remove(operationId);
      rethrow;
    }
    return completer.future;
  }

  /// runner 合并目录刷新后，以最后一次结果统一结算本 drain 的所有请求。
  void directoryLoaded({
    required List<OperationId> operationIds,
    required List<AgentUsagePanelProvider> providers,
  }) {
    if (_closed || operationIds.isEmpty) {
      return;
    }
    final previousIds = _state.providers
        .map((state) => state.provider.providerId)
        .toSet();
    _dispatch(
      AgentUsageDirectoryLoaded(
        operationId: operationIds.last,
        providers: providers,
      ),
    );
    final nextIds = providers.map((provider) => provider.providerId).toSet();
    for (final removedId in previousIds.difference(nextIds)) {
      _providerLoads.remove(removedId);
    }
    _completeDirectories(operationIds);
  }

  void directoryFailed({
    required List<OperationId> operationIds,
    required String message,
  }) {
    if (_closed || operationIds.isEmpty) {
      return;
    }
    _dispatch(
      AgentUsageDirectoryFailed(
        operationId: operationIds.last,
        message: message,
      ),
    );
    _completeDirectories(operationIds);
  }

  void providerLoaded({
    required OperationId operationId,
    required String providerId,
    required AgentUsagePanelProviderResult result,
  }) {
    if (_closed) {
      return;
    }
    _dispatch(
      AgentUsageProviderLoaded(
        operationId: operationId,
        providerId: providerId,
        result: result,
      ),
    );
    _completeProvider(operationId, providerId);
  }

  void providerFailed({
    required OperationId operationId,
    required String providerId,
    required String message,
    bool synchronizeDirectory = false,
  }) {
    if (_closed) {
      return;
    }
    _dispatch(
      AgentUsageProviderFailed(
        operationId: operationId,
        providerId: providerId,
        message: message,
      ),
    );
    _completeProvider(operationId, providerId);
    if (synchronizeDirectory && !_closed) {
      unawaited(synchronizeProviders());
    }
  }

  void _completeDirectories(List<OperationId> operationIds) {
    for (final operationId in operationIds) {
      final completer = _directoryCompleters.remove(operationId);
      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }
    }
  }

  void _completeProvider(OperationId operationId, String providerId) {
    final load = _providerLoads[providerId];
    if (load?.operationId == operationId) {
      _providerLoads.remove(providerId);
    }
    final completer = _providerCompleters.remove(operationId);
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  void _dispatch(AgentUsagePanelSliceIntent intent) {
    if (_closed) {
      return;
    }
    final transition = agentUsagePanelSliceReduce(_state, intent);
    final nextState = transition.state;
    if (!identical(nextState, _state)) {
      _state = nextState;
      for (final listener in List<void Function()>.of(_listeners)) {
        listener();
      }
    }
    for (final effect in transition.effects) {
      effectRunner.run(effect);
    }
  }

  AgentUsagePanelProviderState? _stateFor(String providerId) {
    for (final providerState in _state.providers) {
      if (providerState.provider.providerId == providerId) {
        return providerState;
      }
    }
    return null;
  }

  bool _containsProvider(String providerId) => _stateFor(providerId) != null;

  void _ensureOpen() {
    if (_closed) {
      throw StateError('AgentUsagePanelSliceStore is closed');
    }
  }

  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    effectRunner.close();
    for (final completer in <Completer<void>>[
      ..._directoryCompleters.values,
      ..._providerCompleters.values,
    ]) {
      if (!completer.isCompleted) {
        // refresh/synchronize 可能由 coordinator 以 unawaited 触发；关闭表示
        // 取消本 scope，调用方正常收敛，迟到结果由 runner 的 closed guard 丢弃。
        completer.complete();
      }
    }
    _directoryCompleters.clear();
    _providerCompleters.clear();
    _providerLoads.clear();
    _listeners.clear();
  }

  @override
  void dispose() => close();
}

String? _normalizeProviderId(String? providerId) {
  final normalized = providerId?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

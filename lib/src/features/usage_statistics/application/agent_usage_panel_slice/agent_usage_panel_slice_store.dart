import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/usage_statistics/application/agent_usage_panel_operations.dart';
import 'package:zeta/src/features/usage_statistics/application/agent_usage_panel_slice/agent_usage_panel_slice_effect.dart';
import 'package:zeta/src/features/usage_statistics/application/agent_usage_panel_slice/agent_usage_panel_slice_intent.dart';
import 'package:zeta/src/features/usage_statistics/application/agent_usage_panel_slice/agent_usage_panel_slice_reducer.dart';
import 'package:zeta/src/features/usage_statistics/application/agent_usage_panel_slice/agent_usage_panel_slice_state.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_panel_models.dart';

/// Agent Usage Panel effect 的 app 组合层执行入口。
abstract interface class AgentUsagePanelSliceEffectRunner {
  void run(AgentUsagePanelSliceEffect effect);

  void close();
}

/// runner 工厂：把 notifier 作为 typed 回流目标，避免 runner 延迟反向绑定。
typedef AgentUsagePanelSliceEffectRunnerFactory =
    AgentUsagePanelSliceEffectRunner Function(
      AgentUsagePanelSliceNotifier notifier,
    );

/// Agent Usage Panel 切片所需的中立 application 依赖。
final class AgentUsagePanelSliceDependencies {
  AgentUsagePanelSliceDependencies({
    required this.repository,
    AgentUsagePanelSliceState? initialState,
    OperationIdGenerator? directoryOperationIdGenerator,
    OperationIdGenerator Function(String providerId)?
    providerOperationIdGenerator,
  }) : initialState = initialState ?? AgentUsagePanelSliceState(),
       directoryOperationIdGenerator =
           directoryOperationIdGenerator ??
           OperationIdGenerator(scope: 'agent-usage/directory'),
       providerOperationIdGenerator =
           providerOperationIdGenerator ??
           ((providerId) =>
               OperationIdGenerator(scope: 'agent-usage/provider/$providerId'));

  final AgentUsagePanelSliceState initialState;
  final AgentUsagePanelRepository repository;
  final OperationIdGenerator directoryOperationIdGenerator;
  final OperationIdGenerator Function(String providerId)
  providerOperationIdGenerator;
}

/// 组合根必须安装的切片依赖；缺失时 fail-closed。
final agentUsagePanelSliceDependenciesProvider =
    Provider<AgentUsagePanelSliceDependencies>(
      (ref) => throw StateError(
        'agentUsagePanelSliceDependenciesProvider was read before the '
        'composition root overrode it',
      ),
      name: 'agentUsagePanelSliceDependencies',
    );

/// 组合根必须安装的 runner 工厂；缺失时不伪造加载或选择持久化成功。
final agentUsagePanelSliceEffectRunnerFactoryProvider =
    Provider<AgentUsagePanelSliceEffectRunnerFactory>(
      (ref) => throw StateError(
        'agentUsagePanelSliceEffectRunnerFactoryProvider was read before '
        'the composition root overrode it',
      ),
      name: 'agentUsagePanelSliceEffectRunnerFactory',
    );

/// Agent Usage Panel 的唯一 app-session 状态 owner。
///
/// 不是 autoDispose：目录发现、Provider 单飞查询与选择偏好跟随应用会话。
final agentUsagePanelSliceProvider =
    NotifierProvider<AgentUsagePanelSliceNotifier, AgentUsagePanelSliceState>(
      AgentUsagePanelSliceNotifier.new,
      name: 'agentUsagePanelSlice',
    );

typedef _ProviderLoad = ({OperationId operationId, Future<void> future});

/// Agent Usage Panel 的 Riverpod MVI owner。
final class AgentUsagePanelSliceNotifier
    extends Notifier<AgentUsagePanelSliceState>
    implements AgentUsagePanelOperations {
  late AgentUsagePanelSliceEffectRunner _effectRunner;
  late AgentUsagePanelRepository _repository;
  late OperationIdGenerator _directoryOperationIdGenerator;
  late OperationIdGenerator Function(String providerId)
  _providerOperationIdGenerator;
  final Map<String, OperationIdGenerator> _providerGenerators =
      <String, OperationIdGenerator>{};
  final Map<OperationId, Completer<void>> _directoryCompleters =
      <OperationId, Completer<void>>{};
  final Map<OperationId, Completer<void>> _providerCompleters =
      <OperationId, Completer<void>>{};
  final Map<String, _ProviderLoad> _providerLoads = <String, _ProviderLoad>{};

  late AgentUsagePanelSliceState _working;
  bool _publishScheduled = false;
  bool _closed = false;

  @override
  AgentUsagePanelSliceState build() {
    final dependencies = ref.watch(agentUsagePanelSliceDependenciesProvider);
    _repository = dependencies.repository;
    _directoryOperationIdGenerator = dependencies.directoryOperationIdGenerator;
    _providerOperationIdGenerator = dependencies.providerOperationIdGenerator;
    _working = dependencies.initialState;
    _effectRunner = ref.watch(agentUsagePanelSliceEffectRunnerFactoryProvider)(
      this,
    );
    ref.onDispose(_handleDispose);
    return _working;
  }

  @override
  AgentUsagePanelSliceState get state => _working;

  bool get isClosed => _closed;

  /// 组合测试使用的只读接线出口；presentation 仍只依赖操作端口。
  AgentUsagePanelRepository get repository => _repository;

  @override
  List<AgentUsagePanelProviderState> get providers => _working.providers;

  @override
  String? get preferredProviderId => _working.preferredProviderId;

  @override
  String? get selectedProviderId => _working.selectedProviderId;

  @override
  DateTime? get lastUpdated => _working.lastUpdated;

  @override
  String? get errorMessage => _working.directoryError;

  @override
  bool get hasDiscoveredProviders => _working.directoryDiscovered;

  @override
  bool get isLoading => AgentUsagePanelSliceSelectors.isLoading(_working);

  @override
  AgentUsagePanelProviderState? get selectedProvider =>
      AgentUsagePanelSliceSelectors.selectedProvider(_working);

  @override
  List<AgentUsagePanelEntry> get entries =>
      AgentUsagePanelSliceSelectors.entries(_working);

  @override
  AgentUsagePanelEntry? get selectedEntry => selectedProvider?.entry;

  @override
  Future<void> refresh({
    bool forceRefresh = true,
    bool showLoading = true,
  }) async {
    _ensureOpen();
    if (!_working.directoryDiscovered || _working.providers.isEmpty) {
      await _requestDirectory(showLoading: showLoading);
    }
    final providerId = _working.selectedProviderId;
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
    final providerId = _working.selectedProviderId;
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
        !_working.directoryDiscovered ||
        _working.selectedProviderId == normalized &&
            (normalized == null || _containsProvider(normalized));
    if (_working.preferredProviderId == normalized && selectionAlreadyMatches) {
      final selected = _working.selectedProviderId;
      if (selected != null) {
        unawaited(_ensureProviderLoaded(selected));
      }
      return;
    }
    _dispatch(AgentUsagePreferredProviderRestored(normalized));
    final selected = _working.selectedProviderId;
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
    final previousIds = _working.providers
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
    final transition = agentUsagePanelSliceReduce(_working, intent);
    final nextState = transition.state;
    if (!identical(nextState, _working)) {
      _working = nextState;
      _schedulePublish();
    }
    for (final effect in transition.effects) {
      _effectRunner.run(effect);
    }
  }

  AgentUsagePanelProviderState? _stateFor(String providerId) {
    for (final providerState in _working.providers) {
      if (providerState.provider.providerId == providerId) {
        return providerState;
      }
    }
    return null;
  }

  bool _containsProvider(String providerId) => _stateFor(providerId) != null;

  void _ensureOpen() {
    if (_closed) {
      throw StateError('AgentUsagePanelSliceNotifier is disposed');
    }
  }

  /// Shell restore 与 Widget 事件都可同步提交，广播统一在安全的 microtask 发布。
  void _schedulePublish() {
    if (_publishScheduled || _closed) {
      return;
    }
    _publishScheduled = true;
    scheduleMicrotask(() {
      _publishScheduled = false;
      if (!_closed) {
        state = _working;
      }
    });
  }

  void _handleDispose() {
    if (_closed) {
      return;
    }
    _closed = true;
    _effectRunner.close();
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
  }
}

String? _normalizeProviderId(String? providerId) {
  final normalized = providerId?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

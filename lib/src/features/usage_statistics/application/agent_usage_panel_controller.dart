import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:zeta/src/features/usage_statistics/domain/agent_usage_panel_models.dart';

/// 单个 Provider 的侧栏加载阶段。
enum AgentUsagePanelProviderLoadStatus { notLoaded, loading, loaded, failed }

/// 单个 Provider 在 Agent 用量面板中的不可变加载状态。
@immutable
class AgentUsagePanelProviderState {
  const AgentUsagePanelProviderState({
    required this.provider,
    required this.status,
    this.entry,
    this.loadError,
  });

  final AgentUsagePanelProvider provider;

  /// 最近一次成功数据；刷新失败或刷新期间继续保留。
  final AgentUsagePanelEntry? entry;

  final AgentUsagePanelProviderLoadStatus status;

  /// 仅影响当前 Provider 的加载错误。
  final String? loadError;

  bool get isLoading => status == AgentUsagePanelProviderLoadStatus.loading;
}

/// 编排 Provider Tab、按需加载状态与局部错误的轻量控制器。
class AgentUsagePanelController extends ChangeNotifier {
  AgentUsagePanelController({
    required this.repository,
    String? initialPreferredProviderId,
    this.onSelectionChanged,
  }) : _preferredProviderId = _normalizeProviderId(initialPreferredProviderId);

  final AgentUsagePanelRepository repository;

  /// 可持久化选择偏好发生变化时回调；恢复 seed 本身不会触发。
  final ValueChanged<String?>? onSelectionChanged;

  List<AgentUsagePanelProviderState> _providers =
      const <AgentUsagePanelProviderState>[];
  String? _preferredProviderId;
  String? _selectedProviderId;
  DateTime? _lastUpdated;
  String? _errorMessage;
  bool _discovering = false;
  bool _directoryDiscovered = false;
  bool _directoryRefreshPending = false;
  bool _directoryLoadingRequested = false;
  Future<void>? _directoryDrain;
  final Map<String, int> _providerGenerations = <String, int>{};
  final Map<String, Future<void>> _providerLoads = <String, Future<void>>{};
  bool _disposed = false;

  /// 按 Provider 配置目录顺序排列的状态快照。
  List<AgentUsagePanelProviderState> get providers => _providers;

  /// 最近的恢复、手动或 Turn 终态选择意图；目录到达前也会保留。
  String? get preferredProviderId => _preferredProviderId;

  /// 当前 Provider 目录中真实有效的选择。
  String? get selectedProviderId => _selectedProviderId;
  DateTime? get lastUpdated => _lastUpdated;

  /// Provider 目录级错误；单 Provider 错误保存在对应状态中。
  String? get errorMessage => _errorMessage;

  /// 首次显式刷新是否已经建立过目录；宿主用它过滤设置加载自身的启动通知。
  bool get hasDiscoveredProviders => _directoryDiscovered;

  /// 顶部刷新状态只跟随目录或当前 Tab，不被后台 Tab 阻塞。
  bool get isLoading => _discovering || (selectedProvider?.isLoading ?? false);

  AgentUsagePanelProviderState? get selectedProvider {
    if (_providers.isEmpty) {
      return null;
    }
    return _providers.firstWhere(
      (state) => state.provider.providerId == _selectedProviderId,
      orElse: () => _providers.first,
    );
  }

  /// 兼容只消费成功数据的调用方；新 UI 应优先使用 [providers]。
  List<AgentUsagePanelEntry> get entries =>
      List<AgentUsagePanelEntry>.unmodifiable(
        _providers
            .map((state) => state.entry)
            .whereType<AgentUsagePanelEntry>(),
      );

  AgentUsagePanelEntry? get selectedEntry => selectedProvider?.entry;

  /// 刷新当前选中 Provider；首次调用会先发现完整目录。
  ///
  /// [showLoading] 为 false 时做静默刷新：已有内容继续展示且不点亮当前
  /// Tab；尚无数据时仍展示首屏加载态，避免空白闪烁。
  Future<void> refresh({
    bool forceRefresh = true,
    bool showLoading = true,
  }) async {
    if (!_directoryDiscovered || _providers.isEmpty) {
      await _reloadProviderDirectory(showLoading: showLoading);
    }
    final providerId = _selectedProviderId;
    if (providerId == null || _disposed) {
      return;
    }
    await _ensureProviderLoaded(
      providerId,
      forceRefresh: forceRefresh,
      showLoading: showLoading,
    );
  }

  /// Provider 配置变化后同步目录，并只补载当前尚未读取的 Tab。
  Future<void> synchronizeProviders({bool showLoading = false}) async {
    await _reloadProviderDirectory(showLoading: showLoading);
    final providerId = _selectedProviderId;
    if (providerId == null || _disposed) {
      return;
    }
    await _ensureProviderLoaded(
      providerId,
      forceRefresh: false,
      showLoading: showLoading,
    );
  }

  void selectProvider(String providerId) {
    final normalized = _normalizeProviderId(providerId);
    if (normalized == null ||
        !_providers.any((state) => state.provider.providerId == normalized)) {
      return;
    }
    final changed =
        _preferredProviderId != normalized || _selectedProviderId != normalized;
    _preferredProviderId = normalized;
    _selectedProviderId = normalized;
    if (changed) {
      onSelectionChanged?.call(normalized);
      _notify();
    }
    unawaited(_ensureProviderLoaded(normalized));
  }

  /// 应用恢复偏好但不回调，避免恢复值再次触发持久化循环。
  void restorePreferredProviderId(String? providerId) {
    final normalized = _normalizeProviderId(providerId);
    if (_preferredProviderId == normalized &&
        (!_directoryDiscovered || _selectionMatchesPreference())) {
      final selected = _selectedProviderId;
      if (selected != null) {
        unawaited(_ensureProviderLoaded(selected));
      }
      return;
    }
    _preferredProviderId = normalized;
    if (_directoryDiscovered) {
      _resolveSelectionFromDirectory();
    }
    _notify();
    final selected = _selectedProviderId;
    if (selected != null) {
      unawaited(_ensureProviderLoaded(selected));
    }
  }

  /// 记录 Turn 终态所属 Provider；自动选择覆盖此前手动偏好。
  void selectProviderFromTurn(String providerId) {
    final normalized = _normalizeProviderId(providerId);
    if (normalized == null) {
      return;
    }
    if (_preferredProviderId == normalized) {
      return;
    }
    _preferredProviderId = normalized;
    if (!_directoryDiscovered) {
      onSelectionChanged?.call(normalized);
      _notify();
      return;
    }
    if (_providers.any((state) => state.provider.providerId == normalized)) {
      _selectedProviderId = normalized;
      onSelectionChanged?.call(normalized);
    } else {
      _resolveSelectionFromDirectory();
    }
    _notify();
  }

  Future<void> _reloadProviderDirectory({required bool showLoading}) {
    _directoryRefreshPending = true;
    _directoryLoadingRequested =
        _directoryLoadingRequested || showLoading || _providers.isEmpty;
    final existing = _directoryDrain;
    if (existing != null) {
      return existing;
    }

    late final Future<void> drain;
    drain = _drainProviderDirectory().whenComplete(() {
      if (identical(_directoryDrain, drain)) {
        _directoryDrain = null;
      }
    });
    _directoryDrain = drain;
    return drain;
  }

  Future<void> _drainProviderDirectory() async {
    while (_directoryRefreshPending && !_disposed) {
      _directoryRefreshPending = false;
      final showLoading = _directoryLoadingRequested;
      _directoryLoadingRequested = false;
      await _loadProviderDirectoryOnce(showLoading: showLoading);
    }
  }

  Future<void> _loadProviderDirectoryOnce({required bool showLoading}) async {
    _discovering = showLoading;
    _errorMessage = null;
    _notify();
    try {
      final providers = await repository.discoverProviders();
      if (_disposed) {
        return;
      }
      _applyProviderDirectory(providers);
    } catch (_) {
      if (_disposed) {
        return;
      }
      _errorMessage = 'Agent 用量暂时无法读取';
    } finally {
      if (!_disposed) {
        _discovering = false;
        _notify();
      }
    }
  }

  Future<void> _ensureProviderLoaded(
    String providerId, {
    bool forceRefresh = false,
    bool showLoading = true,
  }) {
    final state = _stateFor(providerId);
    if (state == null ||
        (!forceRefresh &&
            state.status == AgentUsagePanelProviderLoadStatus.loaded)) {
      return Future<void>.value();
    }
    final existing = _providerLoads[providerId];
    if (existing != null) {
      return existing;
    }

    final generation = (_providerGenerations[providerId] ?? 0) + 1;
    _providerGenerations[providerId] = generation;
    final indicateLoading = showLoading || state.entry == null;
    _replaceProvider(
      providerId,
      (current) => AgentUsagePanelProviderState(
        provider: current.provider,
        entry: current.entry,
        status: indicateLoading
            ? AgentUsagePanelProviderLoadStatus.loading
            : current.entry == null
            ? AgentUsagePanelProviderLoadStatus.loading
            : AgentUsagePanelProviderLoadStatus.loaded,
      ),
    );
    _notify();

    late final Future<void> tracked;
    tracked =
        _loadProvider(
          providerId,
          generation: generation,
          forceRefresh: forceRefresh,
        ).whenComplete(() {
          if (identical(_providerLoads[providerId], tracked)) {
            _providerLoads.remove(providerId);
          }
        });
    _providerLoads[providerId] = tracked;
    return tracked;
  }

  Future<void> _loadProvider(
    String providerId, {
    required int generation,
    required bool forceRefresh,
  }) async {
    try {
      final result = await repository.loadProvider(
        providerId,
        forceRefresh: forceRefresh,
      );
      if (!_isProviderCurrent(providerId, generation)) {
        return;
      }
      if (result == null) {
        _replaceProvider(
          providerId,
          (state) => AgentUsagePanelProviderState(
            provider: state.provider,
            entry: state.entry,
            status: AgentUsagePanelProviderLoadStatus.failed,
            loadError: '该 Agent 已禁用或不可用',
          ),
        );
        _notify();
        unawaited(synchronizeProviders());
        return;
      }
      _replaceProvider(
        providerId,
        (state) => AgentUsagePanelProviderState(
          provider: state.provider,
          entry: result.entry,
          status: AgentUsagePanelProviderLoadStatus.loaded,
        ),
      );
      _lastUpdated = result.refreshedAt;
      _notify();
    } catch (_) {
      if (!_isProviderCurrent(providerId, generation)) {
        return;
      }
      _replaceProvider(
        providerId,
        (state) => AgentUsagePanelProviderState(
          provider: state.provider,
          entry: state.entry,
          status: AgentUsagePanelProviderLoadStatus.failed,
          loadError: 'Agent 用量暂时无法读取',
        ),
      );
      _notify();
    }
  }

  void _applyProviderDirectory(List<AgentUsagePanelProvider> providers) {
    final previousById = <String, AgentUsagePanelProviderState>{
      for (final state in _providers) state.provider.providerId: state,
    };
    final nextIds = providers.map((provider) => provider.providerId).toSet();
    for (final previousId in previousById.keys) {
      if (nextIds.contains(previousId)) {
        continue;
      }
      _providerGenerations[previousId] =
          (_providerGenerations[previousId] ?? 0) + 1;
      _providerLoads.remove(previousId);
    }
    _providers = List<AgentUsagePanelProviderState>.unmodifiable(
      providers.map((provider) {
        final previous = previousById[provider.providerId];
        return AgentUsagePanelProviderState(
          provider: provider,
          entry: previous?.entry,
          status:
              previous?.status ?? AgentUsagePanelProviderLoadStatus.notLoaded,
          loadError: previous?.loadError,
        );
      }),
    );
    _directoryDiscovered = true;
    _resolveSelectionFromDirectory();
  }

  bool _selectionMatchesPreference() {
    final preferred = _preferredProviderId;
    return preferred == null
        ? _selectedProviderId == null
        : _selectedProviderId == preferred &&
              _providers.any((state) => state.provider.providerId == preferred);
  }

  void _resolveSelectionFromDirectory() {
    final preferred = _preferredProviderId;
    if (preferred != null &&
        _providers.any((state) => state.provider.providerId == preferred)) {
      _selectedProviderId = preferred;
      return;
    }

    final fallback = _providers.firstOrNull?.provider.providerId;
    final preferenceChanged = fallback != preferred;
    _preferredProviderId = fallback;
    _selectedProviderId = fallback;
    if (preferenceChanged) {
      onSelectionChanged?.call(fallback);
    }
  }

  AgentUsagePanelProviderState? _stateFor(String providerId) {
    for (final state in _providers) {
      if (state.provider.providerId == providerId) {
        return state;
      }
    }
    return null;
  }

  void _replaceProvider(
    String providerId,
    AgentUsagePanelProviderState Function(AgentUsagePanelProviderState state)
    replace,
  ) {
    final index = _providers.indexWhere(
      (state) => state.provider.providerId == providerId,
    );
    if (index < 0) {
      return;
    }
    final updated = _providers.toList();
    updated[index] = replace(updated[index]);
    _providers = List<AgentUsagePanelProviderState>.unmodifiable(updated);
  }

  bool _isProviderCurrent(String providerId, int generation) =>
      !_disposed &&
      _providerGenerations[providerId] == generation &&
      _stateFor(providerId) != null;

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _directoryRefreshPending = false;
    for (final providerId in _providerGenerations.keys.toList()) {
      _providerGenerations[providerId] =
          (_providerGenerations[providerId] ?? 0) + 1;
    }
    _providerLoads.clear();
    super.dispose();
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

String? _normalizeProviderId(String? providerId) {
  final normalized = providerId?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

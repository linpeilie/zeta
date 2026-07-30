import 'package:flutter/foundation.dart';

import 'package:zeta/src/features/usage_statistics/domain/agent_usage_panel_models.dart';

/// 单个 Provider 在 Agent 用量面板中的不可变加载状态。
@immutable
class AgentUsagePanelProviderState {
  const AgentUsagePanelProviderState({
    required this.provider,
    required this.isLoading,
    this.entry,
    this.loadError,
  });

  final AgentUsagePanelProvider provider;

  /// 最近一次成功数据；刷新期间继续保留。
  final AgentUsagePanelEntry? entry;

  final bool isLoading;

  /// 仅影响当前 Provider 的加载错误。
  final String? loadError;
}

/// 编排 Provider Tab、渐进式刷新状态与局部错误的轻量控制器。
class AgentUsagePanelController extends ChangeNotifier {
  AgentUsagePanelController({required this.repository});

  final AgentUsagePanelRepository repository;

  List<AgentUsagePanelProviderState> _providers =
      const <AgentUsagePanelProviderState>[];
  String? _selectedProviderId;
  DateTime? _lastUpdated;
  String? _errorMessage;
  bool _discovering = false;
  int _loadToken = 0;
  bool _disposed = false;

  /// 按 Provider 配置目录顺序排列的状态快照。
  List<AgentUsagePanelProviderState> get providers => _providers;

  String? get selectedProviderId => _selectedProviderId;
  DateTime? get lastUpdated => _lastUpdated;

  /// Provider 目录级错误；单 Provider 错误保存在对应状态中。
  String? get errorMessage => _errorMessage;

  bool get isLoading =>
      _discovering || _providers.any((provider) => provider.isLoading);

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

  /// 刷新全部已启用 Provider；旧数据在刷新期间继续展示。
  ///
  /// [showLoading] 为 false 时做静默刷新（如 turn 完成后的后台更新）：保留当前
  /// 展示内容且不切换 [isLoading]，避免面板顶部反复出现加载横条。无任何
  /// Provider 数据时仍展示首屏加载态，避免空白闪烁。
  Future<void> refresh({
    bool forceRefresh = true,
    bool showLoading = true,
  }) async {
    final token = ++_loadToken;
    // 已有目录时静默刷新不亮加载态；空面板首次加载仍需要指示。
    final indicateLoading = showLoading || _providers.isEmpty;
    _discovering = indicateLoading && _providers.isEmpty;
    _errorMessage = null;
    if (indicateLoading) {
      _providers = List<AgentUsagePanelProviderState>.unmodifiable(
        _providers.map(
          (state) => AgentUsagePanelProviderState(
            provider: state.provider,
            entry: state.entry,
            isLoading: true,
          ),
        ),
      );
    }
    _notify();

    try {
      await for (final event in repository.load(forceRefresh: forceRefresh)) {
        if (!_isCurrent(token)) {
          return;
        }
        switch (event) {
          case AgentUsagePanelProvidersDiscovered():
            _applyProviderDirectory(
              event.providers,
              markLoading: indicateLoading,
            );
          case AgentUsagePanelProviderLoaded():
            _replaceProvider(
              event.entry.providerId,
              (state) => AgentUsagePanelProviderState(
                provider: state.provider,
                entry: event.entry,
                isLoading: false,
              ),
            );
          case AgentUsagePanelProviderFailed():
            _replaceProvider(
              event.provider.providerId,
              (state) => AgentUsagePanelProviderState(
                provider: state.provider,
                entry: state.entry,
                isLoading: false,
                loadError: event.message,
              ),
            );
          case AgentUsagePanelLoadCompleted():
            _lastUpdated = event.refreshedAt;
            _discovering = false;
            _finishPendingProviders();
        }
        _notify();
      }
    } catch (_) {
      if (!_isCurrent(token)) {
        return;
      }
      _errorMessage = 'Agent 用量暂时无法读取';
      _discovering = false;
      _finishPendingProviders();
      _notify();
    } finally {
      if (_isCurrent(token)) {
        _discovering = false;
        _finishPendingProviders();
        _notify();
      }
    }
  }

  void selectProvider(String providerId) {
    if (_selectedProviderId == providerId ||
        !_providers.any((state) => state.provider.providerId == providerId)) {
      return;
    }
    _selectedProviderId = providerId;
    _notify();
  }

  void _applyProviderDirectory(
    List<AgentUsagePanelProvider> providers, {
    required bool markLoading,
  }) {
    final previousById = <String, AgentUsagePanelProviderState>{
      for (final state in _providers) state.provider.providerId: state,
    };
    _providers = List<AgentUsagePanelProviderState>.unmodifiable(
      providers.map((provider) {
        final previous = previousById[provider.providerId];
        return AgentUsagePanelProviderState(
          provider: provider,
          entry: previous?.entry,
          // 静默刷新时保留原加载标记，避免已有数据时闪加载横条。
          isLoading: markLoading,
          loadError: markLoading ? null : previous?.loadError,
        );
      }),
    );
    _discovering = false;
    final previousSelection = _selectedProviderId;
    _selectedProviderId =
        _providers.any(
          (state) => state.provider.providerId == previousSelection,
        )
        ? previousSelection
        : _providers.firstOrNull?.provider.providerId;
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

  void _finishPendingProviders() {
    if (!_providers.any((state) => state.isLoading)) {
      return;
    }
    _providers = List<AgentUsagePanelProviderState>.unmodifiable(
      _providers.map(
        (state) => state.isLoading
            ? AgentUsagePanelProviderState(
                provider: state.provider,
                entry: state.entry,
                isLoading: false,
                loadError: state.loadError,
              )
            : state,
      ),
    );
  }

  bool _isCurrent(int token) => !_disposed && token == _loadToken;

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _loadToken += 1;
    super.dispose();
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

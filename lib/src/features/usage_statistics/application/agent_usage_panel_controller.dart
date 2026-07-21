import 'package:flutter/foundation.dart';

import 'package:zeta/src/features/usage_statistics/domain/agent_usage_panel_models.dart';

/// 编排 Provider Tab、刷新状态与局部错误的轻量控制器。
class AgentUsagePanelController extends ChangeNotifier {
  AgentUsagePanelController({required this.repository});

  final AgentUsagePanelRepository repository;

  List<AgentUsagePanelEntry> _entries = const <AgentUsagePanelEntry>[];
  String? _selectedProviderId;
  DateTime? _lastUpdated;
  String? _errorMessage;
  bool _loading = false;
  int _loadToken = 0;
  bool _disposed = false;

  List<AgentUsagePanelEntry> get entries => _entries;
  String? get selectedProviderId => _selectedProviderId;
  DateTime? get lastUpdated => _lastUpdated;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _loading;

  AgentUsagePanelEntry? get selectedEntry {
    if (_entries.isEmpty) {
      return null;
    }
    return _entries.firstWhere(
      (entry) => entry.providerId == _selectedProviderId,
      orElse: () => _entries.first,
    );
  }

  /// 刷新全部已启用 Provider；旧数据在刷新期间继续展示。
  Future<void> refresh({bool forceRefresh = true}) async {
    final token = ++_loadToken;
    _loading = true;
    _errorMessage = null;
    _notify();
    try {
      final snapshot = await repository.load(forceRefresh: forceRefresh);
      if (!_isCurrent(token)) {
        return;
      }
      final previousSelection = _selectedProviderId;
      _entries = snapshot.entries;
      _lastUpdated = snapshot.refreshedAt;
      _selectedProviderId =
          _entries.any((entry) => entry.providerId == previousSelection)
          ? previousSelection
          : _entries.firstOrNull?.providerId;
    } catch (_) {
      if (!_isCurrent(token)) {
        return;
      }
      _errorMessage = 'Agent 用量暂时无法读取';
    } finally {
      if (_isCurrent(token)) {
        _loading = false;
        _notify();
      }
    }
  }

  void selectProvider(String providerId) {
    if (_selectedProviderId == providerId ||
        !_entries.any((entry) => entry.providerId == providerId)) {
      return;
    }
    _selectedProviderId = providerId;
    _notify();
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

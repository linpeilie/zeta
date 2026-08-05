import 'package:zeta/src/features/agent/domain/agent_permission_policy_models.dart';

/// 独立管理 permission catalog 的加载、stale retention 与 generation 守卫。
final class AgentPermissionCatalogController {
  AgentPermissionPolicyPort? _port;
  AgentPermissionCatalog? _lastKnownGoodCatalog;
  Object? _lastError;
  bool _isLoading = false;
  int _generation = 0;
  bool _disposed = false;

  AgentPermissionPolicyPort? get port => _port;
  AgentPermissionCatalog? get catalog => _lastKnownGoodCatalog;
  bool get isLoading => _isLoading;
  Object? get lastError => _lastError;
  List<AgentPermissionOption> get options =>
      _lastKnownGoodCatalog?.options ?? const <AgentPermissionOption>[];

  AgentPermissionSelection? get catalogDefault {
    final optionId = _lastKnownGoodCatalog?.defaultOptionId.trim();
    if (optionId == null || optionId.isEmpty) {
      return null;
    }
    return AgentPermissionSelection(optionId: optionId);
  }

  void bind(AgentPermissionPolicyPort? port) {
    if (_disposed || identical(_port, port)) {
      return;
    }
    _generation += 1;
    _port = port;
    _lastKnownGoodCatalog = null;
    _lastError = null;
    _isLoading = false;
  }

  /// 成功时原子提交完整目录；失败时保留 last-known-good。
  ///
  /// 同一绑定上的后发 refresh 优先，旧 generation 的异步结果不得回写。
  Future<bool> refresh() async {
    if (_disposed) {
      return false;
    }
    final port = _port;
    if (port == null) {
      final changed =
          _lastKnownGoodCatalog != null || _lastError != null || _isLoading;
      _generation += 1;
      _lastKnownGoodCatalog = null;
      _lastError = null;
      _isLoading = false;
      return changed;
    }
    final generation = ++_generation;
    _isLoading = true;
    _lastError = null;
    try {
      final catalog = await port.listPermissionOptions();
      if (_disposed || generation != _generation || !identical(port, _port)) {
        return false;
      }
      _lastKnownGoodCatalog = catalog;
      _lastError = null;
      _isLoading = false;
      return true;
    } catch (error) {
      if (_disposed || generation != _generation || !identical(port, _port)) {
        return false;
      }
      _lastError = error;
      _isLoading = false;
      return true;
    }
  }

  Object? takeLastError() {
    final error = _lastError;
    _lastError = null;
    return error;
  }

  void dispose() {
    _disposed = true;
    _generation += 1;
    _port = null;
    _lastKnownGoodCatalog = null;
    _lastError = null;
    _isLoading = false;
  }
}

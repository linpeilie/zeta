import 'package:zeta_agent_core/src/domain/agent_permission_policy_models.dart';

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

  /// 绑定目录端口，并使旧端口上的异步刷新立即失效。
  ///
  /// 同一逻辑 Provider 从 global runtime 切换到 session runtime 时，调用方可用
  /// [preserveLastKnownGood] 保留已经完整加载的目录，随后再通过 [refresh] 以新端口
  /// 重新校验。真正切换 Provider 或解绑端口时必须清空，避免跨 Provider 泄漏目录。
  void bind(
    AgentPermissionPolicyPort? port, {
    bool preserveLastKnownGood = false,
  }) {
    if (_disposed || identical(_port, port)) {
      return;
    }
    _generation += 1;
    _port = port;
    if (!preserveLastKnownGood || port == null) {
      _lastKnownGoodCatalog = null;
    }
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

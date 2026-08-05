import 'package:zeta/src/features/agent/domain/agent_permission_policy_models.dart';

/// 独立管理 permission catalog 的加载、stale retention 与 generation 守卫。
final class AgentPermissionCatalogController {
  AgentPermissionPolicyPort? _port;
  AgentPermissionCatalog? _catalog;
  int _generation = 0;
  bool _disposed = false;

  AgentPermissionPolicyPort? get port => _port;
  AgentPermissionCatalog? get catalog => _catalog;
  List<AgentPermissionOption> get options =>
      _catalog?.options ?? const <AgentPermissionOption>[];

  AgentPermissionSelection? get catalogDefault {
    final optionId = _catalog?.defaultOptionId.trim();
    if (optionId == null || optionId.isEmpty) {
      return null;
    }
    return AgentPermissionSelection(optionId: optionId);
  }

  void bind(AgentPermissionPolicyPort? port) {
    if (_disposed) {
      return;
    }
    _generation += 1;
    _port = port;
    _catalog = null;
  }

  /// 临时失败保留旧目录；旧 generation 的异步结果不得回写。
  Future<bool> refresh() async {
    if (_disposed) {
      return false;
    }
    final port = _port;
    final generation = _generation;
    if (port == null) {
      _catalog = null;
      return true;
    }
    try {
      final catalog = await port.listPermissionOptions();
      if (_disposed || generation != _generation || !identical(port, _port)) {
        return false;
      }
      if (catalog.options.isEmpty && (_catalog?.options.isNotEmpty ?? false)) {
        return false;
      }
      _catalog = catalog;
      return true;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _disposed = true;
    _generation += 1;
    _port = null;
    _catalog = null;
  }
}

import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 从 Provider 权威来源刷新模型目录。
///
/// 只有共享仓储判断缓存缺失、过期或被强制刷新时才会调用；实现必须绕过 Provider
/// 实例内的目录缓存，避免下层缓存重新延长共享仓储的 TTL。
typedef AgentModelCatalogLoader = Future<AgentModelList> Function();

/// 一次模型目录读取的结果。
class AgentModelCatalogLoadResult {
  const AgentModelCatalogLoadResult({
    required this.models,
    required this.fetchedAt,
    required this.fromCache,
    required this.refreshed,
    required this.isStale,
    this.refreshError,
  });

  final AgentModelList models;
  final DateTime fetchedAt;
  final bool fromCache;
  final bool refreshed;
  final bool isStale;

  /// 后台刷新失败时保留的错误；此时 [models] 仍是最近一次可用缓存。
  final Object? refreshError;
}

/// 按 Provider 能力选择普通读取或强制刷新。
Future<AgentModelList> fetchAgentProviderModels(
  AgentModelCatalogPort modelCatalog, {
  bool forceRefresh = false,
  int limit = 20,
  bool includeHidden = false,
}) {
  return modelCatalog.listModels(
    limit: limit,
    includeHidden: includeHidden,
    forceRefresh: forceRefresh,
  );
}

/// 管理检测借用宿主模型目录缓存的最小端口。
abstract interface class AgentManagementModelCatalogPort {
  Future<AgentModelCatalogLoadResult> load({
    required AgentProviderConfig config,
    required String source,
    required AgentModelCatalogLoader refreshLoader,
    bool forceRefresh = false,
  });
}

import 'package:meta/meta.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/features/agent/application/agent_model_catalog_repository.dart';

/// Riverpod 模型目录投影的安全查询键。
///
/// 键中只保留稳定 Provider ID、可见性和仓储生成的脱敏配置指纹；环境变量值与
/// Provider 原始配置都不会进入 family 参数或 Observer。
@immutable
final class AgentModelCatalogQuery {
  const AgentModelCatalogQuery({
    required this.providerId,
    required this.configFingerprint,
    required this.includeHidden,
  });

  final String providerId;
  final String configFingerprint;
  final bool includeHidden;

  @override
  bool operator ==(Object other) =>
      other is AgentModelCatalogQuery &&
      other.providerId == providerId &&
      other.configFingerprint == configFingerprint &&
      other.includeHidden == includeHidden;

  @override
  int get hashCode => Object.hash(providerId, configFingerprint, includeHidden);
}

/// 查询被 app 组合层拒绝的稳定原因。
enum AgentModelCatalogQueryRejectionReason { unknownProvider, configChanged }

/// 查询键不再对应当前 Provider 配置。
///
/// 异常只携带稳定 ID 与分类，不携带配置内容或环境变量。
final class AgentModelCatalogQueryRejected implements Exception {
  const AgentModelCatalogQueryRejected({
    required this.providerId,
    required this.reason,
  });

  final String providerId;
  final AgentModelCatalogQueryRejectionReason reason;

  @override
  String toString() => 'Model catalog query rejected for $providerId: $reason';
}

/// 模型目录投影可公开给 UI 的脱敏失败分类。
enum AgentModelCatalogProjectionFailureKind {
  sourceUnavailable,
  invalidQuery,
  unsupported,
  load,
  refresh,
}

/// Repository 结果的不可变、只读 UI 投影。
///
/// 本对象不是缓存 owner：它只在 Riverpod family 有订阅时存在，且不参与 TTL、
/// single-flight、generation 或持久化判断。原始异常只在映射时判断是否存在，绝不
/// 保存在 state 中。
@immutable
final class AgentModelCatalogProjectionState {
  const AgentModelCatalogProjectionState._({
    this.catalog,
    this.fetchedAt,
    this.fromCache = false,
    this.isRefreshing = false,
    this.isStale = false,
    this.failure,
  });

  /// 已确认的完整目录；null 表示从未获得过成功快照，空目录仍是有效结果。
  final AgentModelList? catalog;
  final DateTime? fetchedAt;
  final bool fromCache;
  final bool isRefreshing;
  final bool isStale;
  final AgentModelCatalogProjectionFailureKind? failure;

  bool get hasCatalog => catalog != null;

  List<AgentModelInfo> get models =>
      catalog?.models ?? const <AgentModelInfo>[];

  /// 仓储先发布 last-known-good 时的短暂投影。
  factory AgentModelCatalogProjectionState.cacheHit(
    AgentModelCatalogSnapshot snapshot,
  ) {
    return AgentModelCatalogProjectionState._(
      catalog: _freezeCatalog(snapshot.models),
      fetchedAt: snapshot.fetchedAt,
      fromCache: true,
      isRefreshing: true,
    );
  }

  /// 仓储完成读取后的最终投影。
  factory AgentModelCatalogProjectionState.loaded(
    AgentModelCatalogLoadResult result,
  ) {
    return AgentModelCatalogProjectionState._(
      catalog: _freezeCatalog(result.models),
      fetchedAt: result.fetchedAt,
      fromCache: result.fromCache,
      isStale: result.isStale,
      failure: result.refreshError == null
          ? null
          : AgentModelCatalogProjectionFailureKind.refresh,
    );
  }

  /// 只保留稳定失败分类；刷新失败时保留既有 last-known-good。
  factory AgentModelCatalogProjectionState.failed(
    AgentModelCatalogProjectionFailureKind failure, {
    AgentModelCatalogProjectionState? previous,
  }) {
    final keepPrevious =
        failure == AgentModelCatalogProjectionFailureKind.refresh &&
        previous?.hasCatalog == true;
    return AgentModelCatalogProjectionState._(
      catalog: keepPrevious ? previous!.catalog : null,
      fetchedAt: keepPrevious ? previous!.fetchedAt : null,
      fromCache: keepPrevious && previous!.fromCache,
      isStale: keepPrevious,
      failure: failure,
    );
  }

  /// 显式刷新开始时保留当前目录，避免 UI 闪回空态。
  AgentModelCatalogProjectionState beginRefresh() {
    return AgentModelCatalogProjectionState._(
      catalog: catalog,
      fetchedAt: fetchedAt,
      fromCache: fromCache,
      isRefreshing: true,
      isStale: isStale,
    );
  }
}

/// app 组合层提供的模型目录查询入口。
///
/// presentation 只依赖本端口；唯一 repository、Provider runtime 与 capability
/// 二次校验都留在 app runner。
abstract interface class AgentModelCatalogProjectionSource {
  AgentModelCatalogQuery queryForConfig(
    AgentProviderConfig config, {
    bool includeHidden = false,
  });

  Future<AgentModelCatalogLoadResult> loadModelCatalog(
    AgentModelCatalogQuery query, {
    bool forceRefresh = false,
    void Function(AgentModelCatalogSnapshot snapshot)? onCacheHit,
  });
}

AgentModelList _freezeCatalog(AgentModelList catalog) {
  return AgentModelList(
    models: List<AgentModelInfo>.unmodifiable(catalog.models),
    nextCursor: catalog.nextCursor,
  );
}

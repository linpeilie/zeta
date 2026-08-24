import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zeta/src/features/agent/application/provider_settings_slice/agent_model_catalog_projection.dart';
import 'package:zeta/src/features/agent/presentation/provider_settings_slice/agent_provider_settings_slice_providers.dart';

/// 不含 Provider 配置正文的查询请求。
typedef AgentModelCatalogQueryRequest = ({
  String providerId,
  bool includeHidden,
});

/// app 组合层注入的唯一模型目录查询源；null = 第 2 批 flag 关闭。
final agentModelCatalogProjectionSourceProvider =
    Provider<AgentModelCatalogProjectionSource?>((ref) => null);

/// 把 Provider ID/可见性解析为安全 family key。
final agentModelCatalogQueryProvider =
    Provider.family<AgentModelCatalogQuery?, AgentModelCatalogQueryRequest>(
      (ref, request) {
        final source = ref.watch(agentModelCatalogProjectionSourceProvider);
        if (source == null) {
          return null;
        }
        final settings = ref.watch(agentProviderSettingsValueProvider);
        for (final config in settings.providers) {
          if (config.id == request.providerId) {
            return source.queryForConfig(
              config,
              includeHidden: request.includeHidden,
            );
          }
        }
        return null;
      },
      name: 'agentModelCatalogQuery',
      isAutoDispose: true,
    );

/// keyed、autoDispose 的模型目录只读投影。
///
/// autoDispose 只释放这个短生命周期 UI 快照；repository、runtime registry 与
/// Provider generation 均由 app session owner 管理。
final agentModelCatalogProjectionProvider =
    AsyncNotifierProvider.family<
      AgentModelCatalogProjectionNotifier,
      AgentModelCatalogProjectionState,
      AgentModelCatalogQuery
    >(
      AgentModelCatalogProjectionNotifier.new,
      name: 'agentModelCatalogProjection',
      isAutoDispose: true,
    );

final class AgentModelCatalogProjectionNotifier
    extends AsyncNotifier<AgentModelCatalogProjectionState> {
  AgentModelCatalogProjectionNotifier(this.query);

  final AgentModelCatalogQuery query;
  int _requestRevision = 0;

  @override
  Future<AgentModelCatalogProjectionState> build() {
    // query 的安全指纹不包含环境变量值；监听完整 settings 快照可确保仅环境值
    // 变化时也重新查询。缓存是否仍可用仍只由 repository generation 判断。
    ref.watch(agentProviderSettingsSliceProvider);
    final source = ref.watch(agentModelCatalogProjectionSourceProvider);
    final revision = ++_requestRevision;
    if (source == null) {
      return Future<AgentModelCatalogProjectionState>.value(
        AgentModelCatalogProjectionState.failed(
          AgentModelCatalogProjectionFailureKind.sourceUnavailable,
        ),
      );
    }
    return _load(source, revision: revision, forceRefresh: false);
  }

  /// 显式绕过 fresh cache；single-flight 仍由共享 repository 合并。
  Future<void> refresh() async {
    final source = ref.read(agentModelCatalogProjectionSourceProvider);
    final previous = state.value;
    final revision = ++_requestRevision;
    if (source == null) {
      state = AsyncData<AgentModelCatalogProjectionState>(
        AgentModelCatalogProjectionState.failed(
          AgentModelCatalogProjectionFailureKind.sourceUnavailable,
        ),
      );
      return;
    }
    state = previous == null
        ? const AsyncLoading<AgentModelCatalogProjectionState>()
        : AsyncData<AgentModelCatalogProjectionState>(previous.beginRefresh());
    final result = await _load(
      source,
      revision: revision,
      forceRefresh: true,
      previous: previous,
    );
    if (_accepts(revision)) {
      state = AsyncData<AgentModelCatalogProjectionState>(result);
    }
  }

  Future<AgentModelCatalogProjectionState> _load(
    AgentModelCatalogProjectionSource source, {
    required int revision,
    required bool forceRefresh,
    AgentModelCatalogProjectionState? previous,
  }) async {
    try {
      final result = await source.loadModelCatalog(
        query,
        forceRefresh: forceRefresh,
        onCacheHit: (snapshot) {
          if (_accepts(revision)) {
            state = AsyncData<AgentModelCatalogProjectionState>(
              AgentModelCatalogProjectionState.cacheHit(snapshot),
            );
          }
        },
      );
      return AgentModelCatalogProjectionState.loaded(result);
    } on Object catch (error) {
      return AgentModelCatalogProjectionState.failed(
        _failureKindFor(error, hasPrevious: previous?.hasCatalog == true),
        previous: previous,
      );
    }
  }

  bool _accepts(int revision) => ref.mounted && revision == _requestRevision;
}

/// active Provider 的安全查询键；flag 关闭或配置缺失时为 null。
final activeAgentModelCatalogQueryProvider = Provider<AgentModelCatalogQuery?>((
  ref,
) {
  if (ref.watch(agentModelCatalogProjectionSourceProvider) == null) {
    return null;
  }
  final activeProviderId = ref
      .watch(agentProviderSettingsValueProvider)
      .activeProviderId;
  if (activeProviderId.isEmpty) {
    return null;
  }
  return ref.watch(
    agentModelCatalogQueryProvider((
      providerId: activeProviderId,
      includeHidden: false,
    )),
  );
}, name: 'activeAgentModelCatalogQuery');

/// active Provider 的 async 目录投影；null 表示第 2 批路径未启用。
final activeAgentModelCatalogProjectionProvider =
    Provider<AsyncValue<AgentModelCatalogProjectionState>?>((ref) {
      final query = ref.watch(activeAgentModelCatalogQueryProvider);
      if (query == null) {
        return null;
      }
      return ref.watch(agentModelCatalogProjectionProvider(query));
    }, name: 'activeAgentModelCatalogProjection');

AgentModelCatalogProjectionFailureKind _failureKindFor(
  Object error, {
  required bool hasPrevious,
}) {
  if (error is AgentModelCatalogQueryRejected) {
    return AgentModelCatalogProjectionFailureKind.invalidQuery;
  }
  if (error is UnsupportedError) {
    return AgentModelCatalogProjectionFailureKind.unsupported;
  }
  return hasPrevious
      ? AgentModelCatalogProjectionFailureKind.refresh
      : AgentModelCatalogProjectionFailureKind.load;
}

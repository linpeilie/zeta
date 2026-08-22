import 'dart:async';
import 'dart:collection';

import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/usage_statistics/domain/fallback_usage_statistics_text_catalog.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_token_usage_source.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_query_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_quota_source.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_text_catalog.dart';

typedef EnabledAgentUsageProviderLoader =
    Future<List<AgentProviderConfig>> Function();

/// 统一用量查询的渐进式输出。
sealed class AgentUsageQueryEvent {
  const AgentUsageQueryEvent();
}

/// 本轮所有 Provider 的稳定目录；后续完成事件可以乱序到达。
final class AgentUsageProvidersDiscovered extends AgentUsageQueryEvent {
  AgentUsageProvidersDiscovered({
    required List<AgentUsageProviderDescriptor> providers,
  }) : providers = UnmodifiableListView<AgentUsageProviderDescriptor>(
         List<AgentUsageProviderDescriptor>.of(providers),
       );

  final List<AgentUsageProviderDescriptor> providers;
}

/// 单个 Provider 的 quota/history 都已独立收敛为显式状态。
final class AgentUsageProviderResolved extends AgentUsageQueryEvent {
  const AgentUsageProviderResolved(this.snapshot);

  final AgentUsageProviderSnapshot snapshot;
}

/// 本轮目录中的 Provider 均已完成。
final class AgentUsageQueryCompleted extends AgentUsageQueryEvent {
  const AgentUsageQueryCompleted(this.refreshedAt);

  final DateTime refreshedAt;
}

/// 套餐额度和 Token 历史的 application 级统一查询边界。
///
/// 两种能力保持独立并行；任一失败只影响当前 Provider 的当前能力。Service 不解析
/// Provider raw、不读取私有路径，也不按 Provider kind/id 选择实现。
final class AgentUsageQueryService {
  AgentUsageQueryService(
    this._enabledProviderLoader,
    this._quotaSource,
    this._tokenSourceRegistry, {
    DateTime Function()? clock,
    UsageStatisticsTextCatalog? textCatalog,
  }) : _clock = clock ?? DateTime.now,
       _textCatalog = textCatalog ?? const FallbackUsageStatisticsTextCatalog();

  final EnabledAgentUsageProviderLoader _enabledProviderLoader;
  final AgentUsageQuotaSource _quotaSource;
  final AgentTokenUsageSourceRegistry _tokenSourceRegistry;
  final UsageStatisticsTextCatalog _textCatalog;
  final DateTime Function() _clock;
  final Map<_ProviderQueryKey, Future<AgentUsageProviderSnapshot>> _inFlight =
      <_ProviderQueryKey, Future<AgentUsageProviderSnapshot>>{};

  /// 只返回当前已启用的稳定目录，不启动套餐或 Token 历史查询。
  Future<List<AgentUsageProviderDescriptor>> discoverProviders() async {
    final configs = await _loadEnabledConfigs();
    return List<AgentUsageProviderDescriptor>.unmodifiable(
      configs.map(AgentUsageProviderDescriptor.fromConfig),
    );
  }

  /// 只查询一个 Provider；目录变化导致目标失效时返回 null。
  Future<AgentUsageProviderSnapshot?> loadProvider(
    String providerId,
    AgentUsageQuery query,
  ) async {
    final configs = await _loadEnabledConfigs();
    AgentProviderConfig? target;
    for (final config in configs) {
      if (config.id == providerId) {
        target = config;
        break;
      }
    }
    if (target == null) {
      return null;
    }
    return _loadProviderInFlight(target, query);
  }

  /// 按配置目录顺序发布目录，并按实际完成顺序渐进发布 Provider 快照。
  ///
  /// 完整统计页需要跨 Provider 聚合，因此保留显式全量入口；侧栏不得调用它。
  Stream<AgentUsageQueryEvent> loadAll(AgentUsageQuery query) async* {
    final configs = await _loadEnabledConfigs();
    yield AgentUsageProvidersDiscovered(
      providers: <AgentUsageProviderDescriptor>[
        for (final config in configs)
          AgentUsageProviderDescriptor.fromConfig(config),
      ],
    );
    if (configs.isEmpty) {
      yield AgentUsageQueryCompleted(_clock());
      return;
    }

    final completions = StreamController<AgentUsageProviderSnapshot>();
    var remaining = configs.length;
    for (final config in configs) {
      unawaited(
        _loadProviderInFlight(config, query).then(completions.add).whenComplete(
          () {
            remaining -= 1;
            if (remaining == 0) {
              unawaited(completions.close());
            }
          },
        ),
      );
    }
    await for (final snapshot in completions.stream) {
      yield AgentUsageProviderResolved(snapshot);
    }
    yield AgentUsageQueryCompleted(_clock());
  }

  Future<AgentUsageProviderSnapshot> _loadProviderInFlight(
    AgentProviderConfig config,
    AgentUsageQuery query,
  ) {
    final key = _ProviderQueryKey(
      config: config,
      earliest: query.earliest,
      forceRefresh: query.forceRefresh,
    );
    final existing = _inFlight[key];
    if (existing != null) {
      return existing;
    }
    late final Future<AgentUsageProviderSnapshot> tracked;
    tracked = _loadProvider(config, query).whenComplete(() {
      if (identical(_inFlight[key], tracked)) {
        _inFlight.remove(key);
      }
    });
    _inFlight[key] = tracked;
    return tracked;
  }

  Future<AgentUsageProviderSnapshot> _loadProvider(
    AgentProviderConfig config,
    AgentUsageQuery query,
  ) async {
    final quotaFuture = _loadQuota(config);
    final tokenHistoryFuture = _loadTokenHistory(config, query);
    final quota = await quotaFuture;
    final tokenHistory = await tokenHistoryFuture;
    return AgentUsageProviderSnapshot(
      provider: AgentUsageProviderDescriptor.fromConfig(config),
      quota: quota,
      tokenHistory: tokenHistory,
    );
  }

  Future<AgentUsageCapabilityResult<AgentUsageQuotaSnapshot>> _loadQuota(
    AgentProviderConfig config,
  ) async {
    try {
      return await _quotaSource.loadQuota(config);
    } catch (_) {
      return AgentUsageCapabilityResult<AgentUsageQuotaSnapshot>.unavailable(
        AgentUsageWarning(
          code: 'quota-unavailable',
          message: _textCatalog.quotaUnreadable,
        ),
      );
    }
  }

  Future<AgentUsageCapabilityResult<AgentTokenUsageSourceSnapshot>>
  _loadTokenHistory(AgentProviderConfig config, AgentUsageQuery query) async {
    try {
      final source = _tokenSourceRegistry.createFor(config);
      if (source == null) {
        return const AgentUsageCapabilityResult<
          AgentTokenUsageSourceSnapshot
        >.unsupported();
      }
      if (source.providerId != config.id) {
        return AgentUsageCapabilityResult<
          AgentTokenUsageSourceSnapshot
        >.unavailable(
          AgentUsageWarning(
            code: 'token-source-mismatch',
            message: _textCatalog.tokenSourceMismatch,
          ),
        );
      }
      final snapshot = await source.load(query);
      return AgentUsageCapabilityResult<
        AgentTokenUsageSourceSnapshot
      >.available(snapshot);
    } catch (_) {
      return AgentUsageCapabilityResult<
        AgentTokenUsageSourceSnapshot
      >.unavailable(
        AgentUsageWarning(
          code: 'token-history-unavailable',
          message: _textCatalog.tokenHistoryUnavailable,
        ),
      );
    }
  }

  Future<List<AgentProviderConfig>> _loadEnabledConfigs() async {
    return List<AgentProviderConfig>.unmodifiable(
      (await _enabledProviderLoader()).where((config) => config.enabled),
    );
  }
}

final class _ProviderQueryKey {
  const _ProviderQueryKey({
    required this.config,
    required this.earliest,
    required this.forceRefresh,
  });

  /// 配置对象变化时不得复用旧进程/凭据对应的进行中结果。
  final AgentProviderConfig config;
  final DateTime earliest;
  final bool forceRefresh;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _ProviderQueryKey &&
          identical(config, other.config) &&
          earliest == other.earliest &&
          forceRefresh == other.forceRefresh;

  @override
  int get hashCode =>
      Object.hash(identityHashCode(config), earliest, forceRefresh);
}

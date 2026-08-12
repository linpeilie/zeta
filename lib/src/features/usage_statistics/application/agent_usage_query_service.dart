import 'dart:async';
import 'dart:collection';

import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_token_usage_source.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_query_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_quota_source.dart';

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
  }) : _clock = clock ?? DateTime.now;

  final EnabledAgentUsageProviderLoader _enabledProviderLoader;
  final AgentUsageQuotaSource _quotaSource;
  final AgentTokenUsageSourceRegistry _tokenSourceRegistry;
  final DateTime Function() _clock;
  final Map<_ProviderQueryKey, Future<AgentUsageProviderSnapshot>> _inFlight =
      <_ProviderQueryKey, Future<AgentUsageProviderSnapshot>>{};

  /// 按配置目录顺序发布目录，并按实际完成顺序渐进发布 Provider 快照。
  Stream<AgentUsageQueryEvent> load(AgentUsageQuery query) async* {
    final configs = List<AgentProviderConfig>.unmodifiable(
      (await _enabledProviderLoader()).where((config) => config.enabled),
    );
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
      providerId: config.id,
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
      return const AgentUsageCapabilityResult<
        AgentUsageQuotaSnapshot
      >.unavailable(
        AgentUsageWarning(code: 'quota-unavailable', message: '套餐额度暂时无法读取'),
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
        return const AgentUsageCapabilityResult<
          AgentTokenUsageSourceSnapshot
        >.unavailable(
          AgentUsageWarning(
            code: 'token-source-mismatch',
            message: 'Token 历史数据源配置不匹配',
          ),
        );
      }
      final snapshot = await source.load(query);
      return AgentUsageCapabilityResult<
        AgentTokenUsageSourceSnapshot
      >.available(snapshot);
    } catch (_) {
      return const AgentUsageCapabilityResult<
        AgentTokenUsageSourceSnapshot
      >.unavailable(
        AgentUsageWarning(
          code: 'token-history-unavailable',
          message: 'Token 历史暂时无法读取',
        ),
      );
    }
  }
}

final class _ProviderQueryKey {
  const _ProviderQueryKey({
    required this.providerId,
    required this.earliest,
    required this.forceRefresh,
  });

  final String providerId;
  final DateTime earliest;
  final bool forceRefresh;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _ProviderQueryKey &&
          providerId == other.providerId &&
          earliest == other.earliest &&
          forceRefresh == other.forceRefresh;

  @override
  int get hashCode => Object.hash(providerId, earliest, forceRefresh);
}

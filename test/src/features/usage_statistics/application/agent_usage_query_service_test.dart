import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/usage_statistics/application/agent_usage_query_service.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_token_usage_source.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_query_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_quota_source.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';

void main() {
  test('quota failure does not hide available token history', () async {
    final config = _config('codex', 'Codex');
    final source = _FakeTokenSource(
      providerId: config.id,
      loader: (query) async => _tokenSnapshot(config),
    );
    final service = _service(
      configs: <AgentProviderConfig>[config],
      quotaLoader: (config) => throw StateError('secret quota failure'),
      sources: <String, AgentTokenUsageSource>{config.id: source},
    );

    final resolved = await _singleResolved(service);

    expect(resolved.quota.status, AgentUsageCapabilityStatus.unavailable);
    expect(resolved.quota.warning?.code, 'quota-unavailable');
    expect(resolved.quota.warning?.message, isNot(contains('secret')));
    expect(resolved.tokenHistory.status, AgentUsageCapabilityStatus.available);
    expect(resolved.tokenHistory.value?.records, hasLength(1));
  });

  test('token history failure does not hide available quota', () async {
    final config = _config('codex', 'Codex');
    final source = _FakeTokenSource(
      providerId: config.id,
      loader: (query) => throw StateError('secret history failure'),
    );
    final service = _service(
      configs: <AgentProviderConfig>[config],
      quotaLoader: (config) async => _availableQuota(config),
      sources: <String, AgentTokenUsageSource>{config.id: source},
    );

    final resolved = await _singleResolved(service);

    expect(resolved.quota.status, AgentUsageCapabilityStatus.available);
    expect(resolved.quota.value?.providerId, config.id);
    expect(
      resolved.tokenHistory.status,
      AgentUsageCapabilityStatus.unavailable,
    );
    expect(resolved.tokenHistory.warning?.code, 'token-history-unavailable');
    expect(resolved.tokenHistory.warning?.message, isNot(contains('secret')));
  });

  test('both missing capabilities stay explicitly unsupported', () async {
    final config = _config('plain', 'Plain');
    final service = _service(
      configs: <AgentProviderConfig>[config],
      quotaLoader: (config) async =>
          const AgentUsageCapabilityResult<
            AgentUsageQuotaSnapshot
          >.unsupported(),
      sources: const <String, AgentTokenUsageSource>{},
    );

    final resolved = await _singleResolved(service);

    expect(resolved.quota.status, AgentUsageCapabilityStatus.unsupported);
    expect(
      resolved.tokenHistory.status,
      AgentUsageCapabilityStatus.unsupported,
    );
  });

  test(
    'publishes stable directory while providers resolve out of order',
    () async {
      final first = _config('first', 'First');
      final second = _config('second', 'Second');
      final firstResult = Completer<AgentTokenUsageSourceSnapshot>();
      final secondResult = Completer<AgentTokenUsageSourceSnapshot>();
      final firstSource = _FakeTokenSource(
        providerId: first.id,
        loader: (query) => firstResult.future,
      );
      final secondSource = _FakeTokenSource(
        providerId: second.id,
        loader: (query) => secondResult.future,
      );
      final service = _service(
        configs: <AgentProviderConfig>[first, second],
        quotaLoader: (config) async =>
            const AgentUsageCapabilityResult<
              AgentUsageQuotaSnapshot
            >.unsupported(),
        sources: <String, AgentTokenUsageSource>{
          first.id: firstSource,
          second.id: secondSource,
        },
      );
      final events = <AgentUsageQueryEvent>[];
      final done = service
          .load(AgentUsageQuery(earliest: DateTime.utc(2026, 8, 1)))
          .listen(events.add)
          .asFuture<void>();
      await _waitUntil(
        () => firstSource.loadCount == 1 && secondSource.loadCount == 1,
      );

      secondResult.complete(_tokenSnapshot(second));
      await _waitUntil(
        () => events.whereType<AgentUsageProviderResolved>().length == 1,
      );

      final directory = events
          .whereType<AgentUsageProvidersDiscovered>()
          .single;
      expect(
        directory.providers.map((provider) => provider.providerId),
        <String>['first', 'second'],
      );
      expect(
        events
            .whereType<AgentUsageProviderResolved>()
            .single
            .snapshot
            .provider
            .providerId,
        'second',
      );

      firstResult.complete(_tokenSnapshot(first));
      await done;

      expect(
        events.whereType<AgentUsageProviderResolved>().map(
          (event) => event.snapshot.provider.providerId,
        ),
        <String>['second', 'first'],
      );
      expect(events.last, isA<AgentUsageQueryCompleted>());
    },
  );

  test('same provider query shares one in-flight operation', () async {
    final config = _config('codex', 'Codex');
    final result = Completer<AgentTokenUsageSourceSnapshot>();
    final source = _FakeTokenSource(
      providerId: config.id,
      loader: (query) => result.future,
    );
    final quota = _FakeQuotaSource(
      (config) async =>
          const AgentUsageCapabilityResult<
            AgentUsageQuotaSnapshot
          >.unsupported(),
    );
    final service = AgentUsageQueryService(
      () async => <AgentProviderConfig>[config],
      quota,
      _FakeTokenRegistry(<String, AgentTokenUsageSource>{config.id: source}),
    );
    final query = AgentUsageQuery(earliest: DateTime.utc(2026, 8, 1));

    final first = service.load(query).toList();
    final second = service.load(query).toList();
    await _waitUntil(() => source.loadCount == 1);

    expect(quota.loadCount, 1);
    result.complete(_tokenSnapshot(config));
    await Future.wait(<Future<List<AgentUsageQueryEvent>>>[first, second]);
    expect(source.loadCount, 1);
  });

  test('force refresh never reuses a normal in-flight query', () async {
    final config = _config('codex', 'Codex');
    final results = <Completer<AgentTokenUsageSourceSnapshot>>[];
    final source = _FakeTokenSource(
      providerId: config.id,
      loader: (query) {
        final result = Completer<AgentTokenUsageSourceSnapshot>();
        results.add(result);
        return result.future;
      },
    );
    final service = _service(
      configs: <AgentProviderConfig>[config],
      quotaLoader: (config) async =>
          const AgentUsageCapabilityResult<
            AgentUsageQuotaSnapshot
          >.unsupported(),
      sources: <String, AgentTokenUsageSource>{config.id: source},
    );
    final earliest = DateTime.utc(2026, 8, 1);

    final normal = service.load(AgentUsageQuery(earliest: earliest)).toList();
    await _waitUntil(() => source.loadCount == 1);
    final forced = service
        .load(AgentUsageQuery(earliest: earliest, forceRefresh: true))
        .toList();
    await _waitUntil(() => source.loadCount == 2);

    expect(source.queries.map((query) => query.forceRefresh), <bool>[
      false,
      true,
    ]);
    results[0].complete(_tokenSnapshot(config));
    results[1].complete(_tokenSnapshot(config));
    await Future.wait(<Future<List<AgentUsageQueryEvent>>>[normal, forced]);
  });
}

AgentUsageQueryService _service({
  required List<AgentProviderConfig> configs,
  required Future<AgentUsageCapabilityResult<AgentUsageQuotaSnapshot>> Function(
    AgentProviderConfig config,
  )
  quotaLoader,
  required Map<String, AgentTokenUsageSource> sources,
}) {
  return AgentUsageQueryService(
    () async => configs,
    _FakeQuotaSource(quotaLoader),
    _FakeTokenRegistry(sources),
    clock: () => DateTime.utc(2026, 8, 12, 12),
  );
}

Future<AgentUsageProviderSnapshot> _singleResolved(
  AgentUsageQueryService service,
) async {
  final events = await service
      .load(AgentUsageQuery(earliest: DateTime.utc(2026, 8, 1)))
      .toList();
  return events.whereType<AgentUsageProviderResolved>().single.snapshot;
}

AgentProviderConfig _config(String id, String name) =>
    AgentProviderConfig.defaultCodex.copyWith(id: id, displayName: name);

AgentUsageCapabilityResult<AgentUsageQuotaSnapshot> _availableQuota(
  AgentProviderConfig config,
) {
  return AgentUsageCapabilityResult<AgentUsageQuotaSnapshot>.available(
    AgentUsageQuotaSnapshot(
      providerId: config.id,
      providerName: config.displayName,
      windows: const <AgentUsageWindow>[],
    ),
  );
}

AgentTokenUsageSourceSnapshot _tokenSnapshot(AgentProviderConfig config) {
  return AgentTokenUsageSourceSnapshot(
    providerId: config.id,
    providerName: config.displayName,
    records: <AgentUsageRecord>[
      AgentUsageRecord(
        threadId: 'thread-${config.id}',
        turnId: 'turn-${config.id}',
        providerId: config.id,
        providerName: config.displayName,
        projectPath: '/work',
        sourceKind: 'test',
        startedAt: DateTime.utc(2026, 8, 12),
        status: UsageTaskStatus.completed,
      ),
    ],
    refreshedAt: DateTime.utc(2026, 8, 12, 12),
  );
}

Future<void> _waitUntil(bool Function() predicate) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    if (predicate()) {
      return;
    }
    await Future<void>.delayed(Duration.zero);
  }
  fail('condition was not reached');
}

final class _FakeQuotaSource implements AgentUsageQuotaSource {
  _FakeQuotaSource(this.loader);

  final Future<AgentUsageCapabilityResult<AgentUsageQuotaSnapshot>> Function(
    AgentProviderConfig config,
  )
  loader;
  int loadCount = 0;

  @override
  Future<AgentUsageCapabilityResult<AgentUsageQuotaSnapshot>> loadQuota(
    AgentProviderConfig config,
  ) {
    loadCount += 1;
    return loader(config);
  }
}

final class _FakeTokenRegistry implements AgentTokenUsageSourceRegistry {
  _FakeTokenRegistry(this.sources);

  final Map<String, AgentTokenUsageSource> sources;

  @override
  AgentTokenUsageSource? createFor(AgentProviderConfig config) =>
      sources[config.id];
}

final class _FakeTokenSource implements AgentTokenUsageSource {
  _FakeTokenSource({required this.providerId, required this.loader});

  @override
  final String providerId;

  final Future<AgentTokenUsageSourceSnapshot> Function(AgentUsageQuery query)
  loader;
  final List<AgentUsageQuery> queries = <AgentUsageQuery>[];

  int get loadCount => queries.length;

  @override
  Future<AgentTokenUsageSourceSnapshot> load(AgentUsageQuery query) {
    queries.add(query);
    return loader(query);
  }
}

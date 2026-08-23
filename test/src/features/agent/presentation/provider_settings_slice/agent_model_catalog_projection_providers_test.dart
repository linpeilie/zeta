import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_model_catalog_repository.dart';
import 'package:zeta/src/features/agent/application/provider_settings_slice/agent_model_catalog_projection.dart';
import 'package:zeta/src/features/agent/application/provider_settings_slice/agent_provider_settings_slice_effect.dart';
import 'package:zeta/src/features/agent/application/provider_settings_slice/agent_provider_settings_slice_state.dart';
import 'package:zeta/src/features/agent/application/provider_settings_slice/agent_provider_settings_slice_store.dart';
import 'package:zeta/src/features/agent/data/agent_model_catalog_cache_store.dart';
import 'package:zeta/src/features/agent/presentation/provider_settings_slice/agent_model_catalog_projection_providers.dart';
import 'package:zeta/src/features/agent/presentation/provider_settings_slice/agent_provider_settings_slice_providers.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';

const _query = AgentModelCatalogQuery(
  providerId: defaultAgentProviderId,
  configFingerprint: 'safe-fingerprint',
  includeHidden: false,
);

void main() {
  group('Agent model catalog Riverpod projection', () {
    test('resolves active and visibility-specific safe query keys', () {
      final source = _FakeProjectionSource();
      final container = _container(source);

      expect(container.read(activeAgentModelCatalogQueryProvider), _query);
      expect(
        container.read(
          agentModelCatalogQueryProvider((
            providerId: defaultAgentProviderId,
            includeHidden: true,
          )),
        ),
        const AgentModelCatalogQuery(
          providerId: defaultAgentProviderId,
          configFingerprint: 'safe-fingerprint',
          includeHidden: true,
        ),
      );
    });

    test('publishes last-known-good before refresh completes', () async {
      final releaseRefresh = Completer<void>();
      final loadCompleted = Completer<void>();
      final source = _FakeProjectionSource()
        ..handlers.add((query, forceRefresh, onCacheHit) async {
          await _flushAsync();
          onCacheHit?.call(_snapshot('cached'));
          await releaseRefresh.future;
          loadCompleted.complete();
          return _result('remote');
        });
      final container = _container(source);
      final states = <AsyncValue<AgentModelCatalogProjectionState>>[];
      final subscription = container.listen(
        agentModelCatalogProjectionProvider(_query),
        (_, next) => states.add(next),
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      await _flushAsync();
      await _flushAsync();
      final cached = states.last.requireValue;
      expect(cached.models.single.id, 'cached');
      expect(cached.fromCache, isTrue);
      expect(cached.isRefreshing, isTrue);

      releaseRefresh.complete();
      await loadCompleted.future;
      await _flushAsync();
      final refreshed = container
          .read(agentModelCatalogProjectionProvider(_query))
          .requireValue;
      expect(refreshed.models.single.id, 'remote');
      expect(refreshed.fromCache, isFalse);
      expect(refreshed.isRefreshing, isFalse);
    });

    test('stale refresh failure keeps models and drops raw error', () async {
      final source = _FakeProjectionSource()
        ..handlers.add((query, forceRefresh, onCacheHit) async {
          await _flushAsync();
          onCacheHit?.call(_snapshot('cached'));
          return AgentModelCatalogLoadResult(
            models: _modelList('cached'),
            fetchedAt: _fetchedAt,
            fromCache: true,
            refreshed: false,
            isStale: true,
            refreshError: StateError('sensitive raw error'),
          );
        });
      final container = _container(source);
      final subscription = container.listen(
        agentModelCatalogProjectionProvider(_query),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      final projection = await container.read(
        agentModelCatalogProjectionProvider(_query).future,
      );
      await _flushAsync();
      await _flushAsync();
      final settled = container
          .read(agentModelCatalogProjectionProvider(_query))
          .requireValue;

      expect(projection.hasCatalog, isTrue);
      expect(settled.models.single.id, 'cached');
      expect(settled.isStale, isTrue);
      expect(settled.failure, AgentModelCatalogProjectionFailureKind.refresh);
      expect(settled.toString(), isNot(contains('sensitive raw error')));
    });

    test('unsupported source becomes a typed empty failure', () async {
      final source = _FakeProjectionSource()
        ..handlers.add((query, forceRefresh, onCacheHit) async {
          throw UnsupportedError('sensitive provider detail');
        });
      final container = _container(source);

      final projection = await container.read(
        agentModelCatalogProjectionProvider(_query).future,
      );

      expect(projection.hasCatalog, isFalse);
      expect(
        projection.failure,
        AgentModelCatalogProjectionFailureKind.unsupported,
      );
      expect(
        container.read(agentModelCatalogProjectionProvider(_query)).hasError,
        isFalse,
      );
    });

    test(
      'explicit refresh keeps prior data and forwards forceRefresh',
      () async {
        final releaseRefresh = Completer<void>();
        final source = _FakeProjectionSource()
          ..handlers.add((query, forceRefresh, onCacheHit) async {
            return _result('initial');
          })
          ..handlers.add((query, forceRefresh, onCacheHit) async {
            await releaseRefresh.future;
            return _result('refreshed');
          });
        final container = _container(source);
        final subscription = container.listen(
          agentModelCatalogProjectionProvider(_query),
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(subscription.close);
        await container.read(
          agentModelCatalogProjectionProvider(_query).future,
        );

        final refresh = container
            .read(agentModelCatalogProjectionProvider(_query).notifier)
            .refresh();
        await _flushAsync();
        final pending = container
            .read(agentModelCatalogProjectionProvider(_query))
            .requireValue;
        expect(pending.models.single.id, 'initial');
        expect(pending.isRefreshing, isTrue);

        releaseRefresh.complete();
        await refresh;
        final settled = container
            .read(agentModelCatalogProjectionProvider(_query))
            .requireValue;
        expect(settled.models.single.id, 'refreshed');
        expect(settled.isRefreshing, isFalse);
        expect(source.forceRefreshValues, <bool>[false, true]);
      },
    );

    test('environment value change reloads an unchanged safe key', () async {
      final source = _FakeProjectionSource()
        ..handlers.add((query, forceRefresh, onCacheHit) async {
          return _result('first');
        })
        ..handlers.add((query, forceRefresh, onCacheHit) async {
          return _result('second');
        });
      final settingsRunner = _ManualSettingsRunner();
      final initial = AgentProviderConfig.defaultCodex.copyWith(
        environment: const <String, String>{'ZETA_TOKEN': 'old'},
      );
      final store = _settingsStore(settingsRunner);
      addTearDown(store.close);
      final load = store.loadSettings();
      final loadEffect = settingsRunner.take<ProviderSettingsLoadEffect>();
      store.loaded(
        loadEffect.operationId,
        AgentProviderSettings(providers: <AgentProviderConfig>[initial]),
      );
      await load;
      final container = _container(source, settingsStore: store);
      final subscription = container.listen(
        agentModelCatalogProjectionProvider(_query),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await container.read(agentModelCatalogProjectionProvider(_query).future);

      final update = store.updateProviderConfig(
        initial.copyWith(
          environment: const <String, String>{'ZETA_TOKEN': 'new'},
        ),
      );
      await _flushAsync();
      final persist = settingsRunner.take<ProviderSettingsPersistEffect>();
      store.persisted(persist.operationId);
      await update;
      await _flushAsync();
      await _flushAsync();

      expect(source.forceRefreshValues, <bool>[false, false]);
      expect(
        container
            .read(agentModelCatalogProjectionProvider(_query))
            .requireValue
            .models
            .single
            .id,
        'second',
      );
    });

    test(
      'flag-off source stays unavailable without starting a query',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        expect(container.read(activeAgentModelCatalogQueryProvider), isNull);
        final projection = await container.read(
          agentModelCatalogProjectionProvider(_query).future,
        );
        expect(
          projection.failure,
          AgentModelCatalogProjectionFailureKind.sourceUnavailable,
        );
      },
    );
  });
}

typedef _LoadHandler =
    Future<AgentModelCatalogLoadResult> Function(
      AgentModelCatalogQuery query,
      bool forceRefresh,
      void Function(AgentModelCatalogSnapshot snapshot)? onCacheHit,
    );

final class _FakeProjectionSource implements AgentModelCatalogProjectionSource {
  final List<_LoadHandler> handlers = <_LoadHandler>[];
  final List<bool> forceRefreshValues = <bool>[];

  @override
  AgentModelCatalogQuery queryForConfig(
    AgentProviderConfig config, {
    bool includeHidden = false,
  }) {
    return AgentModelCatalogQuery(
      providerId: config.id,
      configFingerprint: 'safe-fingerprint',
      includeHidden: includeHidden,
    );
  }

  @override
  Future<AgentModelCatalogLoadResult> loadModelCatalog(
    AgentModelCatalogQuery query, {
    bool forceRefresh = false,
    void Function(AgentModelCatalogSnapshot snapshot)? onCacheHit,
  }) {
    forceRefreshValues.add(forceRefresh);
    if (handlers.isEmpty) {
      return Future<AgentModelCatalogLoadResult>.value(_result('default'));
    }
    return handlers.removeAt(0)(query, forceRefresh, onCacheHit);
  }
}

ProviderContainer _container(
  AgentModelCatalogProjectionSource source, {
  AgentProviderSettingsSliceStore? settingsStore,
}) {
  final container = ProviderContainer(
    overrides: [
      agentModelCatalogProjectionSourceProvider.overrideWithValue(source),
      if (settingsStore != null)
        agentProviderSettingsSliceStoreProvider.overrideWithValue(
          settingsStore,
        ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

AgentProviderSettingsSliceStore _settingsStore(
  AgentProviderSettingsSliceEffectRunner runner,
) {
  return AgentProviderSettingsSliceStore(
    initialState: const AgentProviderSettingsSliceState(),
    effectRunner: runner,
    modelCatalogRepository: AgentModelCatalogRepository(
      store: MemoryAgentModelCatalogCacheStore(),
    ),
    staticCapabilitiesFor: AgentProviderStaticCapabilities.forKind,
  );
}

final class _ManualSettingsRunner
    implements AgentProviderSettingsSliceEffectRunner {
  final List<AgentProviderSettingsSliceEffect> effects =
      <AgentProviderSettingsSliceEffect>[];

  @override
  void run(AgentProviderSettingsSliceEffect effect) => effects.add(effect);

  T take<T extends AgentProviderSettingsSliceEffect>() {
    final index = effects.indexWhere((effect) => effect is T);
    expect(index, isNonNegative, reason: 'Expected pending $T effect');
    return effects.removeAt(index) as T;
  }
}

final _fetchedAt = DateTime.utc(2026, 8, 23);

AgentModelCatalogSnapshot _snapshot(String id) {
  return AgentModelCatalogSnapshot(
    providerId: defaultAgentProviderId,
    configFingerprint: _query.configFingerprint,
    includeHidden: false,
    models: _modelList(id),
    fetchedAt: _fetchedAt,
    source: 'test',
  );
}

AgentModelCatalogLoadResult _result(String id) {
  return AgentModelCatalogLoadResult(
    models: _modelList(id),
    fetchedAt: _fetchedAt,
    fromCache: false,
    refreshed: true,
    isStale: false,
  );
}

AgentModelList _modelList(String id) {
  return AgentModelList(
    models: <AgentModelInfo>[
      AgentModelInfo(id: id, model: id, displayName: id),
    ],
  );
}

Future<void> _flushAsync() => Future<void>.delayed(Duration.zero);

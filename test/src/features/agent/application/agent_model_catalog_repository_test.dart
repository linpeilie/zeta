import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_model_catalog_repository.dart';
import 'package:zeta/src/features/agent/data/agent_model_catalog_cache_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  group('AgentModelCatalogRepository', () {
    late DateTime now;
    late MemoryAgentModelCatalogCacheStore store;
    late AgentModelCatalogRepository repository;

    setUp(() {
      now = DateTime.utc(2026, 7, 22, 8);
      store = MemoryAgentModelCatalogCacheStore();
      repository = AgentModelCatalogRepository(store: store, clock: () => now);
    });

    test(
      'returns a fresh persisted catalog without invoking the loader',
      () async {
        await repository.record(
          config: AgentProviderConfig.defaultCodex,
          models: _models('cached'),
          source: 'test',
        );
        var loaderCalls = 0;

        final result =
            await AgentModelCatalogRepository(
              store: store,
              clock: () => now.add(const Duration(minutes: 30)),
            ).load(
              config: AgentProviderConfig.defaultCodex,
              source: 'test',
              refreshLoader: () async {
                loaderCalls += 1;
                return _models('remote');
              },
            );

        expect(result.models.models.single.id, 'cached');
        expect(result.fromCache, isTrue);
        expect(result.isStale, isFalse);
        expect(loaderCalls, 0);
      },
    );

    test(
      'publishes stale cache before replacing it in the background',
      () async {
        await repository.record(
          config: AgentProviderConfig.defaultCodex,
          models: _models('cached'),
          source: 'test',
        );
        now = now.add(const Duration(hours: 2));
        final gate = Completer<AgentModelList>();
        final published = <String>[];
        var loaderCalls = 0;

        final load = repository.load(
          config: AgentProviderConfig.defaultCodex,
          source: 'test',
          onCacheHit: (snapshot) {
            published.add(snapshot.models.models.single.id);
          },
          refreshLoader: () {
            loaderCalls += 1;
            return gate.future;
          },
        );
        await Future<void>.delayed(Duration.zero);

        expect(published, <String>['cached']);
        expect(loaderCalls, 1);

        gate.complete(_models('remote'));
        final result = await load;
        expect(result.models.models.single.id, 'remote');
        expect(result.refreshed, isTrue);
      },
    );

    test('retains stale models when refresh fails', () async {
      await repository.record(
        config: AgentProviderConfig.defaultCodex,
        models: _models('cached'),
        source: 'test',
      );
      now = now.add(const Duration(hours: 2));

      final result = await repository.load(
        config: AgentProviderConfig.defaultCodex,
        source: 'test',
        refreshLoader: () async => throw StateError('offline'),
      );

      expect(result.models.models.single.id, 'cached');
      expect(result.isStale, isTrue);
      expect(result.refreshError, isA<StateError>());
    });

    test('deduplicates concurrent refreshes with single-flight', () async {
      final gate = Completer<AgentModelList>();
      var loaderCalls = 0;
      Future<AgentModelList> loader() {
        loaderCalls += 1;
        return gate.future;
      }

      final first = repository.load(
        config: AgentProviderConfig.defaultCodex,
        source: 'test',
        refreshLoader: loader,
      );
      final second = repository.load(
        config: AgentProviderConfig.defaultCodex,
        source: 'test',
        refreshLoader: loader,
      );
      await Future<void>.delayed(Duration.zero);

      expect(loaderCalls, 1);
      gate.complete(_models('remote'));
      final results = await Future.wait(<Future<AgentModelCatalogLoadResult>>[
        first,
        second,
      ]);
      expect(results.map((result) => result.models.models.single.id), <String>[
        'remote',
        'remote',
      ]);
    });

    test('does not reuse cache after runtime configuration changes', () async {
      await repository.record(
        config: AgentProviderConfig.defaultCodex,
        models: _models('cached'),
        source: 'test',
      );
      var cacheHits = 0;

      final result = await repository.load(
        config: AgentProviderConfig.defaultCodex.copyWith(
          command: 'custom-codex',
        ),
        source: 'test',
        onCacheHit: (_) => cacheHits += 1,
        refreshLoader: () async => _models('remote'),
      );

      expect(cacheHits, 0);
      expect(result.models.models.single.id, 'remote');
    });

    test(
      'does not let an older config refresh overwrite a newer one',
      () async {
        // Arrange
        final oldConfig = AgentProviderConfig.defaultCodex.copyWith(
          command: 'codex-old',
        );
        final newConfig = AgentProviderConfig.defaultCodex.copyWith(
          command: 'codex-new',
        );
        final oldGate = Completer<AgentModelList>();
        final newGate = Completer<AgentModelList>();

        // Act
        final oldLoad = repository.load(
          config: oldConfig,
          source: 'old',
          refreshLoader: () => oldGate.future,
        );
        final oldExpectation = expectLater(
          oldLoad,
          throwsA(
            predicate<Object>(
              (error) => error.toString().contains('superseded'),
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        final newLoad = repository.load(
          config: newConfig,
          source: 'new',
          refreshLoader: () => newGate.future,
        );
        await Future<void>.delayed(Duration.zero);
        newGate.complete(_models('new'));
        final newResult = await newLoad;
        oldGate.complete(_models('old'));
        await oldExpectation;

        // Assert
        var unexpectedRefreshes = 0;
        final cached = await repository.load(
          config: newConfig,
          source: 'new',
          refreshLoader: () async {
            unexpectedRefreshes += 1;
            return _models('unexpected');
          },
        );
        expect(newResult.models.models.single.id, 'new');
        expect(cached.models.models.single.id, 'new');
        expect(unexpectedRefreshes, 0);
      },
    );

    test('invalidating a provider supersedes its in-flight refresh', () async {
      // Arrange
      final oldGate = Completer<AgentModelList>();
      final replacementGate = Completer<AgentModelList>();
      final oldLoad = repository.load(
        config: AgentProviderConfig.defaultCodex,
        source: 'old',
        refreshLoader: () => oldGate.future,
      );
      final oldExpectation = expectLater(
        oldLoad,
        throwsA(
          predicate<Object>((error) => error.toString().contains('superseded')),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      // Act
      await repository.invalidateProvider(defaultAgentProviderId);
      final replacementLoad = repository.load(
        config: AgentProviderConfig.defaultCodex,
        source: 'replacement',
        refreshLoader: () => replacementGate.future,
      );
      await Future<void>.delayed(Duration.zero);
      oldGate.complete(_models('old'));
      replacementGate.complete(_models('replacement'));
      await oldExpectation;
      final replacement = await replacementLoad;

      // Assert
      expect(replacement.models.models.single.id, 'replacement');
    });

    test('does not persist an unchanged runtime catalog twice', () async {
      // Arrange
      final countingStore = _CountingModelCatalogStore();
      final countingRepository = AgentModelCatalogRepository(
        store: countingStore,
        clock: () => now,
      );

      // Act
      await countingRepository.load(
        config: AgentProviderConfig.defaultCodex,
        source: 'refresh',
        refreshLoader: () async => _models('same'),
      );
      await countingRepository.record(
        config: AgentProviderConfig.defaultCodex,
        models: _models('same'),
        source: 'runtime event',
      );

      // Assert
      expect(countingStore.saveCalls, 1);

      await countingRepository.record(
        config: AgentProviderConfig.defaultCodex,
        models: _models('changed'),
        source: 'runtime event',
      );
      expect(countingStore.saveCalls, 2);
    });

    test(
      'persists a successful stale refresh even when models are unchanged',
      () async {
        // Arrange
        final countingStore = _CountingModelCatalogStore();
        final countingRepository = AgentModelCatalogRepository(
          store: countingStore,
          clock: () => now,
        );
        await countingRepository.load(
          config: AgentProviderConfig.defaultCodex,
          source: 'first',
          refreshLoader: () async => _models('same'),
        );

        // Act
        now = now.add(const Duration(hours: 2));
        final refreshed = await countingRepository.load(
          config: AgentProviderConfig.defaultCodex,
          source: 'second',
          refreshLoader: () async => _models('same'),
        );

        // Assert
        expect(refreshed.refreshed, isTrue);
        expect(refreshed.fetchedAt, now);
        expect(countingStore.saveCalls, 2);
      },
    );

    test('does not spin on a persistent cache write failure', () async {
      // Arrange
      final failingStore = _FailingModelCatalogStore();
      final failingRepository = AgentModelCatalogRepository(
        store: failingStore,
        clock: () => now,
      );

      // Act
      await failingRepository.record(
        config: AgentProviderConfig.defaultCodex,
        models: _models('first'),
        source: 'runtime event',
      );
      await Future<void>.delayed(Duration.zero);

      // Assert
      expect(failingStore.saveCalls, 1);

      // 下一次真实状态变化仍会发起一次新的最佳努力保存。
      await failingRepository.record(
        config: AgentProviderConfig.defaultCodex,
        models: _models('second'),
        source: 'runtime event',
      );
      expect(failingStore.saveCalls, 2);
    });
  });
}

class _CountingModelCatalogStore implements AgentModelCatalogCacheStore {
  List<AgentModelCatalogSnapshot> snapshots =
      const <AgentModelCatalogSnapshot>[];
  int saveCalls = 0;

  @override
  Future<List<AgentModelCatalogSnapshot>> load() async => snapshots;

  @override
  Future<void> save(List<AgentModelCatalogSnapshot> snapshots) async {
    saveCalls += 1;
    this.snapshots = List<AgentModelCatalogSnapshot>.from(snapshots);
  }
}

class _FailingModelCatalogStore implements AgentModelCatalogCacheStore {
  int saveCalls = 0;

  @override
  Future<List<AgentModelCatalogSnapshot>> load() async =>
      const <AgentModelCatalogSnapshot>[];

  @override
  Future<void> save(List<AgentModelCatalogSnapshot> snapshots) async {
    saveCalls += 1;
    throw StateError('test write failure');
  }
}

AgentModelList _models(String id) {
  return AgentModelList(
    models: <AgentModelInfo>[
      AgentModelInfo(
        id: id,
        model: id,
        displayName: id,
        raw: const <String, Object?>{'secret': 'must-not-be-persisted'},
      ),
    ],
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_model_catalog_repository.dart';
import 'package:zeta/src/features/agent/application/provider_settings_slice/agent_model_catalog_projection.dart';
import 'package:zeta/src/app/plugins/agent_provider_manifest.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import '../../testing/ide_test_harness.dart';
import '../../testing/provider_settings_test_store.dart';

void main() {
  group('AgentProviderSettingsSliceRunner', () {
    test('environment changes invalidate the shared model catalog', () async {
      final initial = defaultCodexAgentProviderConfig.copyWith(
        environment: const <String, String>{'ZETA_TOKEN': 'old'},
      );
      final updated = initial.copyWith(
        environment: const <String, String>{'ZETA_TOKEN': 'new'},
      );
      final catalog = AgentModelCatalogRepository(
        store: MemoryAgentModelCatalogCacheStore(),
      );
      await catalog.record(
        config: initial,
        models: _modelList('cached'),
        source: 'test',
      );
      final provider = FakeAgentProvider(config: initial);
      final registry = AgentProviderRuntimeRegistry(
        providerFactory: FakeAgentProviderBundleBuilder.fromFake(provider),
      );
      addTearDown(registry.close);
      final composition = createProviderSettingsTestComposition(
        configStore: MemoryAgentProviderConfigStore(
          AgentProviderSettings(providers: <AgentProviderConfig>[initial]),
        ),
        modelCatalogRepository: catalog,
        runtimeRegistry: registry,
        providerDefinitions: zetaAgentProviderDefinitionCatalog,
      );
      addTearDown(composition.dispose);
      await composition.store.loadSettings();
      final initialQuery = composition.queryForConfig(initial);

      await composition.store.updateProviderConfig(updated);
      expect(
        composition.queryForConfig(updated),
        initialQuery,
        reason: 'family key 不得包含环境变量值；失效由 repository generation 保证',
      );
      var refreshCount = 0;
      final result = await catalog.load(
        config: updated,
        source: 'test',
        refreshLoader: () async {
          refreshCount += 1;
          return _modelList('remote');
        },
      );

      expect(refreshCount, 1);
      expect(result.models.models.single.id, 'remote');
    });

    test('serializes full settings writes through one runner', () async {
      final configStore = _SlowConfigStore();
      final provider = FakeAgentProvider();
      final registry = AgentProviderRuntimeRegistry(
        providerFactory: FakeAgentProviderBundleBuilder.fromFake(provider),
      );
      addTearDown(registry.close);
      final composition = createProviderSettingsTestComposition(
        configStore: configStore,
        modelCatalogRepository: AgentModelCatalogRepository(
          store: MemoryAgentModelCatalogCacheStore(),
        ),
        runtimeRegistry: registry,
        providerDefinitions: zetaAgentProviderDefinitionCatalog,
      );
      addTearDown(composition.dispose);
      await composition.store.loadSettings();

      final first = composition.store.updateProviderConfig(
        defaultCodexAgentProviderConfig.copyWith(command: 'first'),
      );
      final second = composition.store.updateProviderConfig(
        defaultCodexAgentProviderConfig.copyWith(command: 'second'),
      );
      await Future.wait<void>(<Future<void>>[first, second]);

      expect(configStore.maxConcurrentSaves, 1);
      expect(configStore.saved, hasLength(2));
      expect(configStore.settings.activeProvider.command, 'second');
    });

    test('keyed load forwards visibility and force refresh', () async {
      final provider = _RecordingModelCatalogProvider();
      final registry = AgentProviderRuntimeRegistry(
        providerFactory: FakeAgentProviderBundleBuilder.fromFake(provider),
      );
      addTearDown(registry.close);
      final composition = createProviderSettingsTestComposition(
        configStore: MemoryAgentProviderConfigStore(),
        modelCatalogRepository: AgentModelCatalogRepository(
          store: MemoryAgentModelCatalogCacheStore(),
        ),
        runtimeRegistry: registry,
        providerDefinitions: zetaAgentProviderDefinitionCatalog,
      );
      addTearDown(composition.dispose);
      await composition.store.loadSettings();

      final result = await composition.loadModelCatalog(
        composition.queryForConfig(
          defaultCodexAgentProviderConfig,
          includeHidden: true,
        ),
        forceRefresh: true,
      );

      expect(result.models.models.single.id, 'recorded');
      expect(provider.includeHiddenValues, <bool>[true]);
      expect(provider.forceRefreshValues, <bool>[true]);
    });

    test('rejects a query whose safe config fingerprint changed', () async {
      final provider = FakeAgentProvider();
      final registry = AgentProviderRuntimeRegistry(
        providerFactory: FakeAgentProviderBundleBuilder.fromFake(provider),
      );
      addTearDown(registry.close);
      final composition = createProviderSettingsTestComposition(
        configStore: MemoryAgentProviderConfigStore(),
        modelCatalogRepository: AgentModelCatalogRepository(
          store: MemoryAgentModelCatalogCacheStore(),
        ),
        runtimeRegistry: registry,
        providerDefinitions: zetaAgentProviderDefinitionCatalog,
      );
      addTearDown(composition.dispose);
      await composition.store.loadSettings();
      final staleQuery = composition.queryForConfig(
        defaultCodexAgentProviderConfig,
      );
      await composition.store.updateProviderConfig(
        defaultCodexAgentProviderConfig.copyWith(command: 'codex-next'),
      );

      await expectLater(
        composition.loadModelCatalog(staleQuery),
        throwsA(
          isA<AgentModelCatalogQueryRejected>().having(
            (error) => error.reason,
            'reason',
            AgentModelCatalogQueryRejectionReason.configChanged,
          ),
        ),
      );
      expect(registry.debugLeaseCount, 0);
    });

    test(
      'missing model catalog port fails closed and releases the lease',
      () async {
        final provider = FakeAgentProvider();
        final registry = AgentProviderRuntimeRegistry(
          providerFactory: FakeAgentProviderBundleBuilder(
            runtime: provider,
            conversation: provider,
          ),
        );
        addTearDown(registry.close);
        final composition = createProviderSettingsTestComposition(
          configStore: MemoryAgentProviderConfigStore(),
          modelCatalogRepository: AgentModelCatalogRepository(
            store: MemoryAgentModelCatalogCacheStore(),
          ),
          runtimeRegistry: registry,
          providerDefinitions: zetaAgentProviderDefinitionCatalog,
        );
        addTearDown(composition.dispose);

        await expectLater(
          composition.loadActiveModelCatalog(forceRefresh: true),
          throwsA(isA<UnsupportedError>()),
        );
        expect(registry.debugLeaseCount, 0);
      },
    );
  });
}

final class _RecordingModelCatalogProvider extends FakeAgentProvider {
  final List<bool> includeHiddenValues = <bool>[];
  final List<bool> forceRefreshValues = <bool>[];

  @override
  Future<AgentModelList> listModels({
    int limit = 20,
    bool includeHidden = false,
    bool forceRefresh = false,
  }) async {
    includeHiddenValues.add(includeHidden);
    forceRefreshValues.add(forceRefresh);
    return _modelList('recorded');
  }
}

final class _SlowConfigStore implements AgentProviderConfigStore {
  AgentProviderSettings settings = const AgentProviderSettings();
  final List<AgentProviderSettings> saved = <AgentProviderSettings>[];
  int concurrentSaves = 0;
  int maxConcurrentSaves = 0;

  @override
  Future<AgentProviderSettings> load() async => settings;

  @override
  Future<void> save(AgentProviderSettings value) async {
    concurrentSaves += 1;
    if (concurrentSaves > maxConcurrentSaves) {
      maxConcurrentSaves = concurrentSaves;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
    saved.add(value);
    settings = value;
    concurrentSaves -= 1;
  }
}

AgentModelList _modelList(String id) {
  return AgentModelList(
    models: <AgentModelInfo>[
      AgentModelInfo(id: id, model: id, displayName: id),
    ],
  );
}

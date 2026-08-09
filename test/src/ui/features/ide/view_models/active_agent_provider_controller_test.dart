import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/agent/application/agent_model_catalog_repository.dart';
import 'package:zeta/src/features/agent/application/agent_provider_runtime_registry.dart';
import 'package:zeta/src/features/agent/data/agent_model_catalog_cache_store.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/ui/features/ide/view_models/active_agent_provider_controller.dart';

import '../../../../testing/ide_test_harness.dart';

void main() {
  group('ActiveAgentProviderController', () {
    test('persists only normalized V2 permission optionId', () async {
      final store = _RecordingConfigStore(const AgentProviderSettings());
      final registry = AgentProviderRuntimeRegistry(
        providerFactory: FakeAgentProviderFactory(_TrackingFakeAgentProvider()),
      );
      addTearDown(registry.close);
      final controller = ActiveAgentProviderController(
        runtimeRegistry: registry,
        configStore: store,
      );
      addTearDown(controller.dispose);
      await controller.loadSettings();

      await controller.persistPermissionOptionId('  team-safe  ');

      final codex = store.settings.providers.singleWhere(
        (provider) => provider.id == defaultAgentProviderId,
      );
      expect(codex.selectedPermissionOptionId, 'team-safe');
      expect(store.saveCount, 1);
      final encoded = codex.toJson();
      expect(encoded['selectedPermissionOptionId'], 'team-safe');
      expect(encoded.keys, isNot(contains('selectedPermissionProfileId')));
      expect(encoded.keys, isNot(contains('selectedPermissionMode')));
    });

    test('disabling another provider does not create a runtime', () async {
      // Arrange
      final activeProvider = _TrackingFakeAgentProvider();
      final registry = AgentProviderRuntimeRegistry(
        providerFactory: FakeAgentProviderFactory(activeProvider),
      );
      addTearDown(registry.close);
      final controller = ActiveAgentProviderController(
        runtimeRegistry: registry,
        configStore: MemoryAgentProviderConfigStore(
          const AgentProviderSettings(),
        ),
      );
      addTearDown(controller.dispose);
      // Act
      await controller.setProviderEnabled(grokAgentProviderId, false);

      // Assert
      expect(activeProvider.disposeCount, 0);
      expect(registry.debugProviderCount, 0);
      expect(controller.activeProviderId, defaultAgentProviderId);
    });

    test('invalidates model cache when an environment value changes', () async {
      // Arrange
      final initial = AgentProviderConfig.defaultCodex.copyWith(
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
      final registry = AgentProviderRuntimeRegistry(
        providerFactory: FakeAgentProviderFactory(
          _TrackingFakeAgentProvider(initial),
        ),
      );
      addTearDown(registry.close);
      final controller = ActiveAgentProviderController(
        runtimeRegistry: registry,
        configStore: MemoryAgentProviderConfigStore(
          AgentProviderSettings(providers: <AgentProviderConfig>[initial]),
        ),
        modelCatalogRepository: catalog,
      );
      addTearDown(controller.dispose);
      var loaderCalls = 0;

      // Act
      await controller.updateProviderConfig(updated);
      final result = await catalog.load(
        config: updated,
        source: 'test',
        refreshLoader: () async {
          loaderCalls += 1;
          return _modelList('remote');
        },
      );

      // Assert
      expect(loaderCalls, 1);
      expect(result.models.models.single.id, 'remote');
    });

    test(
      'moves active provider to an enabled fallback when disabled',
      () async {
        // Arrange
        final activeProvider = _TrackingFakeAgentProvider();
        final registry = AgentProviderRuntimeRegistry(
          providerFactory: FakeAgentProviderFactory(activeProvider),
        );
        addTearDown(registry.close);
        final controller = ActiveAgentProviderController(
          runtimeRegistry: registry,
          configStore: MemoryAgentProviderConfigStore(
            const AgentProviderSettings(),
          ),
        );
        addTearDown(controller.dispose);
        final lease = await registry.acquire(
          controller.activeProviderConfig,
          scope: AgentProviderRuntimeScopeKey.global,
        );
        await lease.release();

        // Act
        await controller.setProviderEnabled(defaultAgentProviderId, false);

        // Assert
        expect(activeProvider.disposeCount, 1);
        expect(controller.activeProviderId, grokAgentProviderId);
        expect(controller.isProviderEnabled(grokAgentProviderId), isTrue);
      },
    );

    test('never chooses Cursor through the fallback list index', () async {
      // Arrange
      final factory = _RuntimePathSpyFactory();
      final registry = AgentProviderRuntimeRegistry(providerFactory: factory);
      addTearDown(registry.close);
      final controller = ActiveAgentProviderController(
        runtimeRegistry: registry,
        configStore: MemoryAgentProviderConfigStore(
          AgentProviderSettings(
            providers: <AgentProviderConfig>[
              AgentProviderConfig.defaultCodex,
              AgentProviderConfig.defaultCursor.copyWith(enabled: true),
              AgentProviderConfig.defaultGrok,
            ],
          ),
        ),
      );
      addTearDown(controller.dispose);

      // Act
      await controller.setProviderEnabled(defaultAgentProviderId, false);

      // Assert
      expect(controller.activeProviderId, grokAgentProviderId);
      expect(factory.createdProviderIds, isEmpty);
      expect(factory.cursorProviderCreations, 0);
    });

    test('loading settings never creates a provider runtime', () async {
      // Arrange
      final mismatchedProvider = _TrackingFakeAgentProvider(
        AgentProviderConfig.defaultGrok,
      );
      final registry = AgentProviderRuntimeRegistry(
        providerFactory: FakeAgentProviderFactory(mismatchedProvider),
      );
      addTearDown(registry.close);
      final controller = ActiveAgentProviderController(
        runtimeRegistry: registry,
        configStore: MemoryAgentProviderConfigStore(
          const AgentProviderSettings(),
        ),
      );
      addTearDown(controller.dispose);

      await controller.loadSettings();

      expect(registry.debugProviderCount, 0);
      expect(mismatchedProvider.disposeCount, 0);
    });

    test(
      'falls back from legacy Cursor without saving or reaching Cursor paths',
      () async {
        // Arrange
        final store = _RecordingConfigStore(
          AgentProviderSettings(
            providers: <AgentProviderConfig>[
              AgentProviderConfig.defaultCodex,
              AgentProviderConfig.defaultGrok,
              AgentProviderConfig.defaultCursor.copyWith(
                enabled: true,
                extra: const <String, Object?>{'legacyMarker': 'keep-me'},
              ),
            ],
            activeProviderId: cursorAgentProviderId,
          ),
        );
        final factory = _RuntimePathSpyFactory();
        final registry = AgentProviderRuntimeRegistry(providerFactory: factory);
        addTearDown(registry.close);
        final controller = ActiveAgentProviderController(
          runtimeRegistry: registry,
          configStore: store,
        );
        addTearDown(controller.dispose);
        final before = store.settings.toJson();

        // Act
        await controller.loadSettings();

        // Assert
        expect(controller.settings.activeProviderId, cursorAgentProviderId);
        expect(controller.activeProviderId, defaultAgentProviderId);
        expect(controller.unavailableSelectionReason, contains('已临时回退'));
        expect(
          controller.enabledProviders.map((provider) => provider.id),
          isNot(contains(cursorAgentProviderId)),
        );
        expect(store.saveCount, 0);
        expect(store.settings.toJson(), before);
        expect(factory.createdProviderIds, isEmpty);
        expect(factory.cursorProviderCreations, 0);
        expect(factory.cursorCliLocatorCalls, 0);
        expect(factory.cursorProcessStarts, 0);
        expect(factory.cursorSessionIndexWrites, 0);
        await expectLater(
          controller.setActiveProvider(cursorAgentProviderId),
          throwsUnsupportedError,
        );
      },
    );

    test(
      'keeps a stable unavailable state when Cursor has no fallback',
      () async {
        // Arrange
        final store = _RecordingConfigStore(
          AgentProviderSettings(
            providers: <AgentProviderConfig>[
              AgentProviderConfig.defaultCodex.copyWith(enabled: false),
              AgentProviderConfig.defaultGrok.copyWith(enabled: false),
              AgentProviderConfig.defaultCursor.copyWith(enabled: true),
            ],
            activeProviderId: cursorAgentProviderId,
          ),
        );
        final factory = _RuntimePathSpyFactory();
        final registry = AgentProviderRuntimeRegistry(providerFactory: factory);
        addTearDown(registry.close);
        final controller = ActiveAgentProviderController(
          runtimeRegistry: registry,
          configStore: store,
        );
        addTearDown(controller.dispose);

        // Act
        await controller.loadSettings();

        // Assert
        expect(controller.hasRuntimeProvider, isFalse);
        expect(controller.enabledProviders, isEmpty);
        expect(controller.unavailableSelectionReason, contains('没有已启用'));
        expect(factory.createdProviderIds, isEmpty);
        expect(factory.cursorCliLocatorCalls, 0);
        expect(factory.cursorProcessStarts, 0);
        expect(factory.cursorSessionIndexWrites, 0);
        expect(store.saveCount, 0);
      },
    );
  });

  // 模型目录是会话建立前的信息，只允许走全局实例。
  group('loadActiveModelCatalog 使用 global runtime', () {
    test('目录刷新结束后释放租约并复用全局实例', () async {
      final factory = _MultiInstanceFakeProviderFactory();
      final registry = AgentProviderRuntimeRegistry(providerFactory: factory);
      addTearDown(registry.close);
      final controller = ActiveAgentProviderController(
        configStore: MemoryAgentProviderConfigStore(),
        runtimeRegistry: registry,
      );
      addTearDown(controller.dispose);

      await controller.loadActiveModelCatalog(forceRefresh: true);

      expect(registry.debugLeaseCount, 0, reason: '借了要还，不能残留租约');
      expect(factory.providers, hasLength(1));
      final globalLease = await registry.acquire(
        controller.activeProviderConfig,
        scope: AgentProviderRuntimeScopeKey.global,
      );
      expect(globalLease.provider, same(factory.providers.single));
      globalLease.release();
    });
  });
}

class _TrackingFakeAgentProvider extends FakeAgentProvider {
  _TrackingFakeAgentProvider([
    AgentProviderConfig config = AgentProviderConfig.defaultCodex,
  ]) : super(config: config);

  int disposeCount = 0;

  @override
  Future<void> dispose() async {
    disposeCount += 1;
    await super.dispose();
  }
}

class _RecordingConfigStore implements AgentProviderConfigStore {
  _RecordingConfigStore(this.settings);

  AgentProviderSettings settings;
  int saveCount = 0;

  @override
  Future<AgentProviderSettings> load() async => settings;

  @override
  Future<void> save(AgentProviderSettings settings) async {
    saveCount += 1;
    this.settings = settings;
  }
}

class _RuntimePathSpyFactory implements AgentProviderFactory {
  final List<String> createdProviderIds = <String>[];
  int cursorProviderCreations = 0;
  int cursorCliLocatorCalls = 0;
  int cursorProcessStarts = 0;
  int cursorSessionIndexWrites = 0;

  @override
  AgentProvider create(AgentProviderConfig config) {
    createdProviderIds.add(config.id);
    if (CursorRetirementPolicy.isRetiredProvider(config)) {
      cursorProviderCreations += 1;
      cursorCliLocatorCalls += 1;
      cursorProcessStarts += 1;
      cursorSessionIndexWrites += 1;
      throw StateError('Cursor runtime path must remain unreachable');
    }
    return _TrackingFakeAgentProvider(config);
  }
}

/// 与 [FakeAgentProviderFactory] 不同：每次 create 返回**新**实例，用于证明
/// 不同 scope 拿到的是可区分的对象。
class _MultiInstanceFakeProviderFactory implements AgentProviderFactory {
  final List<AgentProvider> providers = <AgentProvider>[];

  @override
  AgentProvider create(AgentProviderConfig config) {
    final provider = _TrackingFakeAgentProvider(config);
    providers.add(provider);
    return provider;
  }
}

AgentModelList _modelList(String id) {
  return AgentModelList(
    models: <AgentModelInfo>[
      AgentModelInfo(id: id, model: id, displayName: id),
    ],
  );
}

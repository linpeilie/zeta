import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/agent/application/agent_model_catalog_repository.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/agent/data/agent_model_catalog_cache_store.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/application/agent_provider_settings_controller.dart';

import '../../../testing/ide_test_harness.dart';
import '../../../testing/legacy_bundle_factory_mixin.dart';

void main() {
  group('AgentProviderSettingsController', () {
    test('persists only normalized V2 permission optionId', () async {
      final store = _RecordingConfigStore(const AgentProviderSettings());
      final registry = AgentProviderRuntimeRegistry(
        providerFactory: FakeAgentProviderBundleBuilder.fromFake(
          _TrackingFakeAgentProvider(),
        ),
      );
      addTearDown(registry.close);
      final controller = AgentProviderSettingsController(
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
        providerFactory: FakeAgentProviderBundleBuilder.fromFake(
          activeProvider,
        ),
      );
      addTearDown(registry.close);
      final controller = AgentProviderSettingsController(
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
        providerFactory: FakeAgentProviderBundleBuilder.fromFake(
          _TrackingFakeAgentProvider(initial),
        ),
      );
      addTearDown(registry.close);
      final controller = AgentProviderSettingsController(
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

    test('model-related settings rebuild only the global runtime', () async {
      // Arrange
      final initial = AgentProviderConfig.defaultClaudeCode;
      final updated = initial.copyWith(
        extra: const <String, Object?>{
          claudeCodeAccountDataEnrichmentKey: false,
        },
      );
      final factory = _MultiInstanceFakeProviderFactory();
      final registry = AgentProviderRuntimeRegistry(providerFactory: factory);
      addTearDown(registry.close);
      final controller = AgentProviderSettingsController(
        runtimeRegistry: registry,
        configStore: MemoryAgentProviderConfigStore(
          AgentProviderSettings(providers: <AgentProviderConfig>[initial]),
        ),
      );
      addTearDown(controller.dispose);
      const sessionScope = AgentProviderRuntimeScopeKey.session(
        'claude-session-1',
      );
      final globalLease = await registry.acquire(
        initial,
        scope: AgentProviderRuntimeScopeKey.global,
      );
      final sessionLease = await registry.acquire(initial, scope: sessionScope);
      final oldGlobal = factory.providers[0] as _TrackingFakeAgentProvider;
      final oldSession = factory.providers[1] as _TrackingFakeAgentProvider;
      await globalLease.release();
      await sessionLease.release();

      // Act
      await controller.updateProviderConfig(updated);

      // Assert
      expect(oldGlobal.disposeCount, 1);
      expect(oldSession.disposeCount, 0);
      expect(registry.debugProviderCount, 1);
      final replacementGlobal = await registry.acquire(
        updated,
        scope: AgentProviderRuntimeScopeKey.global,
      );
      final retainedSession = await registry.acquire(
        updated,
        scope: sessionScope,
      );
      expect(factory.providers.last, isNot(same(oldGlobal)));
      expect(factory.providers[1], same(oldSession));
      await replacementGlobal.release();
      await retainedSession.release();
    });

    test(
      'moves active provider to an enabled fallback when disabled',
      () async {
        // Arrange
        final activeProvider = _TrackingFakeAgentProvider();
        final registry = AgentProviderRuntimeRegistry(
          providerFactory: FakeAgentProviderBundleBuilder.fromFake(
            activeProvider,
          ),
        );
        addTearDown(registry.close);
        final controller = AgentProviderSettingsController(
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

    test('loading settings never creates a provider runtime', () async {
      // Arrange
      final mismatchedProvider = _TrackingFakeAgentProvider(
        AgentProviderConfig.defaultGrok,
      );
      final registry = AgentProviderRuntimeRegistry(
        providerFactory: FakeAgentProviderBundleBuilder.fromFake(
          mismatchedProvider,
        ),
      );
      addTearDown(registry.close);
      final controller = AgentProviderSettingsController(
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
  });

  // 模型目录是会话建立前的信息，只允许走全局实例。
  group('loadActiveModelCatalog 使用 global runtime', () {
    test('目录刷新结束后释放租约并复用全局实例', () async {
      final factory = _MultiInstanceFakeProviderFactory();
      final registry = AgentProviderRuntimeRegistry(providerFactory: factory);
      addTearDown(registry.close);
      final controller = AgentProviderSettingsController(
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
      expect(factory.providers, hasLength(1));
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

/// 与 [FakeAgentProviderBundleBuilder.fromFake] 不同：每次 create 返回**新**实例，用于证明
/// 不同 scope 拿到的是可区分的对象。
class _MultiInstanceFakeProviderFactory with LegacyBundleFactoryMixin {
  final List<Object> providers = <Object>[];

  @override
  Object create(AgentProviderConfig config) {
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

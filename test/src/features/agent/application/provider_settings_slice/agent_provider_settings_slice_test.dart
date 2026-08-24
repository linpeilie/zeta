import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_model_catalog_repository.dart';
import 'package:zeta/src/features/agent/application/provider_settings_slice/agent_provider_settings_slice_effect.dart';
import 'package:zeta/src/features/agent/application/provider_settings_slice/agent_provider_settings_slice_state.dart';
import 'package:zeta/src/features/agent/application/provider_settings_slice/agent_provider_settings_slice_store.dart';
import 'package:zeta/src/features/agent/data/agent_model_catalog_cache_store.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';

void main() {
  group('AgentProviderSettingsSliceStore', () {
    test('loads once and publishes one confirmed snapshot', () async {
      final runner = _ManualRunner();
      final store = _createStore(runner);
      addTearDown(store.close);
      var notifications = 0;
      store.addListener(() => notifications += 1);

      final first = store.loadSettings();
      final second = store.loadSettings();
      final effect = runner.take<ProviderSettingsLoadEffect>();
      final settings = builtInAgentProviderSettings.copyWith(
        activeProviderId: grokAgentProviderId,
      );
      store.loaded(effect.operationId, settings);

      expect(await first, same(settings));
      expect(await second, same(settings));
      expect(runner.effects, isEmpty);
      expect(store.activeProviderId, grokAgentProviderId);
      expect(notifications, 1);
    });

    test(
      'late persist success settles its Future without publishing',
      () async {
        final runner = _ManualRunner();
        final store = _createStore(runner);
        addTearDown(store.close);
        await _loadDefaults(store, runner);
        var notifications = 0;
        store.addListener(() => notifications += 1);

        final firstFuture = store.updateProviderConfig(
          defaultCodexAgentProviderConfig.copyWith(command: 'codex-first'),
        );
        await _flushAsync();
        final first = runner.take<ProviderSettingsPersistEffect>();
        final secondFuture = store.updateProviderConfig(
          defaultCodexAgentProviderConfig.copyWith(command: 'codex-second'),
        );
        await _flushAsync();
        final second = runner.take<ProviderSettingsPersistEffect>();

        store.persisted(first.operationId);
        await firstFuture;
        expect(store.activeProviderConfig.command, 'codex-second');
        expect(notifications, 0, reason: '迟到回执不得发布旧快照');

        store.persisted(second.operationId);
        await secondFuture;
        expect(store.activeProviderConfig.command, 'codex-second');
        expect(notifications, 1);
      },
    );

    test(
      'disabling active Provider persists an enabled fallback atomically',
      () async {
        final runner = _ManualRunner();
        final store = _createStore(runner);
        addTearDown(store.close);
        await _loadDefaults(store, runner);

        final operation = store.setProviderEnabled(
          defaultAgentProviderId,
          false,
        );
        await _flushAsync();
        final effect = runner.take<ProviderSettingsPersistEffect>();

        expect(effect.restartProvider, isTrue);
        expect(effect.updatedConfig?.id, defaultAgentProviderId);
        expect(effect.updatedConfig?.enabled, isFalse);
        expect(effect.settings.activeProviderId, grokAgentProviderId);
        store.persisted(effect.operationId);
        await operation;
        expect(store.activeProviderId, grokAgentProviderId);
      },
    );

    test('normalizes the V2 permission option before persistence', () async {
      final runner = _ManualRunner();
      final store = _createStore(runner);
      addTearDown(store.close);
      await _loadDefaults(store, runner);

      final operation = store.persistPermissionOptionId('  team-safe  ');
      final effect = runner.take<ProviderSettingsPersistEffect>();
      final codex = effect.settings.providers.singleWhere(
        (provider) => provider.id == defaultAgentProviderId,
      );

      expect(codex.selectedPermissionOptionId, 'team-safe');
      expect(
        codex.toJson().keys,
        isNot(contains('selectedPermissionProfileId')),
      );
      store.persisted(effect.operationId);
      await operation;
    });

    test(
      'failure keeps the candidate and exposes only a typed category',
      () async {
        final runner = _ManualRunner();
        final store = _createStore(runner);
        addTearDown(store.close);
        await _loadDefaults(store, runner);
        final operation = store.updateProviderConfig(
          defaultCodexAgentProviderConfig.copyWith(command: 'candidate'),
        );
        await _flushAsync();
        final effect = runner.take<ProviderSettingsPersistEffect>();
        final expectation = expectLater(operation, throwsA(isA<StateError>()));

        store.persistFailed(
          effect.operationId,
          StateError('sensitive raw detail'),
          StackTrace.current,
        );
        await expectation;

        expect(store.activeProviderConfig.command, 'candidate');
        expect(
          store.state.lastFailure?.kind,
          AgentProviderSettingsFailureKind.persist,
        );
      },
    );

    test('close settles a pending compatibility Future', () async {
      final runner = _ManualRunner();
      final store = _createStore(runner);
      await _loadDefaults(store, runner);
      final operation = store.updateProviderConfig(
        defaultCodexAgentProviderConfig.copyWith(command: 'pending'),
      );
      await _flushAsync();
      runner.take<ProviderSettingsPersistEffect>();
      final expectation = expectLater(operation, throwsA(isA<StateError>()));

      store.close();

      await expectation;
      expect(store.isClosed, isTrue);
    });
  });
}

AgentProviderSettingsSliceStore _createStore(_ManualRunner runner) {
  return AgentProviderSettingsSliceStore(
    initialState: const AgentProviderSettingsSliceState(),
    effectRunner: runner,
    modelCatalogRepository: AgentModelCatalogRepository(
      store: MemoryAgentModelCatalogCacheStore(),
    ),
    staticCapabilitiesFor:
        builtInAgentProviderDefinitionCatalog.staticCapabilitiesFor,
  );
}

Future<void> _loadDefaults(
  AgentProviderSettingsSliceStore store,
  _ManualRunner runner,
) async {
  final operation = store.loadSettings();
  final effect = runner.take<ProviderSettingsLoadEffect>();
  store.loaded(effect.operationId, builtInAgentProviderSettings);
  await operation;
}

Future<void> _flushAsync() => Future<void>.delayed(Duration.zero);

final class _ManualRunner implements AgentProviderSettingsSliceEffectRunner {
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

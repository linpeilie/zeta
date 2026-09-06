import '../../../testing/management_detection_test_support.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../testing/agent_management_test_container.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_dependencies.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_runtime_facts.dart';
import '../../../testing/agent_management_test_definitions.dart';
import 'package:zeta/src/app/plugins/agent_provider_manifest.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_effect.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_notifier.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';

void main() {
  group('AgentManagementSliceNotifier', () {
    test(
      'all async ingress preserves current session facts and exact instance summaries',
      () async {
        final runner = _RecordingRunner();
        final store = _createStore(runner: runner, initialized: false);

        final facts = AgentManagementRuntimeFacts([
          AgentManagementRuntimeFact(
            observationKey: Object(),
            providerId: defaultAgentProviderId,
            runtimeIdentity: const AgentProviderRuntimeIdentity(
              providerId: defaultAgentProviderId,
              generation: 1,
            ),
            lifecycle: AgentConversationRuntimeLifecyclePhase.attached,
            connected: true,
            activeTurn: true,
          ),
          AgentManagementRuntimeFact(
            observationKey: Object(),
            providerId: 'custom',
            lifecycle: AgentConversationRuntimeLifecyclePhase.dormant,
            currentError: true,
          ),
        ]);
        final init = store.initialize();
        final initialEffect = runner.take<ManagementInitializeEffect>();
        store.runtimeFactsReplaced(facts);
        final before = store.current.runtimeByProviderId;
        store.initializationSucceeded(
          initialEffect.operationId,
          store.current.providerSettings,
          store.current.detection.confirmedByProviderId,
        );
        await init;
        void expectFacts() {
          expect(store.current.runtimeFacts, same(facts));
          expect(store.agent.runtimeState, AgentRuntimeState.running);
          expect(store.current.runtimeByProviderId, before);
          expect(store.current.agentsById.containsKey('custom'), isFalse);
        }

        expectFacts();
        final detection = store.detect();
        await Future<void>.delayed(Duration.zero);
        final effect = runner.take<DetectAgentsEffect>();
        store.testDetectionStarted(effect.operationId, defaultAgentProviderId);
        final detected = fixtureForView(
          store.agent,
        ).copyWith(runtimeState: AgentRuntimeState.error);
        store.testDetectionProgress(
          effect.operationId,
          defaultAgentProviderId,
          const AgentDetectionProgress(completed: 1, total: 1, message: ''),
          detected,
        );
        expectFacts();
        store.testAgentDetected(
          effect.operationId,
          defaultAgentProviderId,
          detected,
        );
        completeTestDetection(effect.operationId);
        await detection;
        expectFacts();
        for (final success in [true, false]) {
          final pending = store.testConnection();
          final effect = runner.take<TestAgentConnectionEffect>();
          store.connectionTestSucceeded(
            operationId: effect.operationId,
            agentId: defaultAgentProviderId,
            result: AgentManagementConnectionCheckSummary(
              success: success,
              testedAt: DateTime(2026),
              elapsed: Duration.zero,
              cliCallable: success,
              accountValid: success,
              protocolReady: success,
            ),
            models: [],
            modelSource: '',
            modelsUpdatedAt: DateTime(2026),
          );
          await pending;
          expectFacts();
        }
        store.providerSettingsChanged(
          store.current.providerSettings.copyWith(
            providers: [
              for (final config in store.current.providerSettings.providers)
                config.copyWith(enabled: false),
            ],
          ),
        );
        expect(store.agent.enabled, isFalse);
        expect(store.agent.runtimeState, AgentRuntimeState.running);
        expect(
          store
              .current
              .runtimeByProviderId[defaultAgentProviderId]!
              .connectedRuntimeCount,
          1,
        );
        store.runtimeFactsReplaced(AgentManagementRuntimeFacts.empty);
        expect(store.agent.runtimeState, AgentRuntimeState.disabled);
        expect(
          store.current.runtimeByProviderId.containsKey('custom'),
          isFalse,
        );
      },
    );

    test(
      'synchronous result ingress settles once and publishes immediately',
      () async {
        final runner = _RecordingRunner();
        final container = _createContainer(runner: runner, initialized: false);
        final owner = container.read(agentManagementSliceProvider.notifier);
        runner.execute = (effect) {
          final initialize = effect as ManagementInitializeEffect;
          owner.initializationSucceeded(
            initialize.operationId,
            owner.current.providerSettings,
            owner.current.detection.confirmedByProviderId,
          );
          owner.initializationSucceeded(
            initialize.operationId,
            owner.current.providerSettings,
            owner.current.detection.confirmedByProviderId,
          );
          return Future<void>.value();
        };
        final pending = owner.initialize();
        expect(
          container.read(agentManagementSliceProvider).initialized,
          isTrue,
        );
        await pending;
        expect(runner.effects, hasLength(1));
      },
    );

    test(
      'initialization and save failures preserve error and stack for retry',
      () async {
        final runner = _RecordingRunner();
        final owner = _createStore(runner: runner, initialized: false);
        final error = StateError('original error');
        final trace = StackTrace.fromString('original trace');
        Future<void> checkFailure(
          Future<Object?> pending,
          void Function() fail,
        ) async {
          final checked = pending.then<void>(
            (_) => throw TestFailure('expected failure'),
            onError: (Object actual, StackTrace actualTrace) {
              expect(actual, same(error));
              expect(actualTrace.toString(), trace.toString());
            },
          );
          fail();
          await checked;
        }

        final initialize = owner.initialize();
        final effect = runner.take<ManagementInitializeEffect>();
        expect(owner.initialize(), same(initialize));
        await checkFailure(
          initialize,
          () => owner.initializationFailed(effect.operationId, error, trace),
        );
        final retry = owner.initialize();
        final next = runner.take<ManagementInitializeEffect>();
        owner.initializationFailed(effect.operationId, error, trace);
        owner.initializationSucceeded(
          next.operationId,
          owner.current.providerSettings,
          owner.current.detection.confirmedByProviderId,
        );
        await retry;
        expect(() => owner.saveConfiguration('before load'), throwsStateError);
        final load = owner.loadConfiguration();
        final loading = runner.take<LoadAgentConfigurationEffect>();
        owner.configurationLoaded(
          loading.operationId,
          defaultAgentProviderId,
          _document(signature: 'base', content: 'base'),
        );
        await load;
        final saving = owner.saveConfiguration('updated');
        final save = runner.take<SaveAgentConfigurationEffect>();
        await checkFailure(
          saving,
          () => owner.configurationSaveFailed(
            save.operationId,
            defaultAgentProviderId,
            error,
            trace,
          ),
        );
        expect(owner.configuration!.content, 'base');
        expect(owner.savingConfiguration, isFalse);
      },
    );

    test(
      'typed fallback results and duplicate short circuits remain distinct',
      () async {
        final runner = _RecordingRunner();
        final owner = _createStore(runner: runner);
        final connection = owner.testConnection();
        final testing = runner.take<TestAgentConnectionEffect>();
        expect(await owner.testConnection(), isNull);
        owner.connectionTestFailed(
          testing.operationId,
          defaultAgentProviderId,
          'connection failed',
        );
        expect(await connection, isNull);
        expect(owner.operationError, 'connection failed');
        final load = owner.loadConfiguration();
        final loading = runner.take<LoadAgentConfigurationEffect>();
        expect(await owner.loadConfiguration(), isNull);
        owner.configurationLoadFailed(
          loading.operationId,
          defaultAgentProviderId,
          'load failed',
        );
        expect(await load, isNull);
        final logs = owner.loadLogs();
        final logging = runner.take<LoadAgentLogsEffect>();
        expect(await owner.loadLogs(), isEmpty);
        owner.logsLoadFailed(
          logging.operationId,
          defaultAgentProviderId,
          'logs failed',
        );
        expect(await logs, isEmpty);
        final detection = owner.detect();
        await Future<void>.delayed(Duration.zero);
        final detecting = runner.take<DetectAgentsEffect>();
        final joinedDetection = owner.detect();
        owner.testDetectionFailed(detecting.operationId, 'detection failed');
        await detection;
        await joinedDetection;
        final enabling = owner.setEnabled(false);
        final toggling = runner.take<UpdateProviderEnabledEffect>();
        owner.providerEnabledUpdateFailed(
          toggling.operationId,
          defaultAgentProviderId,
          'enable failed',
        );
        await enabling;
        expect(owner.operationError, 'enable failed');
        expect(runner.effects, isEmpty);
      },
    );

    test(
      'settings, runtime inputs and UI unsubscribe keep owner and pending identity',
      () async {
        final runner = _RecordingRunner();
        final container = _createContainer(runner: runner);
        final owner = container.read(agentManagementSliceProvider.notifier);
        final subscription = container.listen(
          agentManagementSliceProvider,
          (_, _) {},
        );
        final pending = owner.testConnection();
        final effect = runner.take<TestAgentConnectionEffect>();
        owner.providerSettingsChanged(
          owner.current.providerSettings.copyWith(
            activeProviderId: grokAgentProviderId,
          ),
        );
        owner.runtimeFactsReplaced(AgentManagementRuntimeFacts.empty);
        subscription.close();
        container.invalidate(agentManagementSliceDependenciesProvider);
        container.invalidate(agentManagementRunnerFactoryProvider);
        await container.pump();
        expect(
          container.read(agentManagementSliceProvider.notifier),
          same(owner),
        );
        expect(owner.testing, isTrue);
        owner.connectionTestFailed(
          effect.operationId,
          defaultAgentProviderId,
          'failure',
        );
        expect(await pending, isNull);
        expect(owner.isClosed, isFalse);
      },
    );

    test(
      'close settles every typed waiter and ignores old sink after new session',
      () async {
        final runner = _RecordingRunner();
        final oldContainer = _createContainer(
          runner: runner,
          registerTearDown: false,
        );
        final old = oldContainer.read(agentManagementSliceProvider.notifier);
        final load = old.loadConfiguration();
        final loading = runner.take<LoadAgentConfigurationEffect>();
        old.configurationLoaded(
          loading.operationId,
          defaultAgentProviderId,
          _document(signature: 'base', content: 'base'),
        );
        await load;
        final detection = old.refreshDetection();
        final waiters = <Future<Object?>>[
          old.testConnection(),
          old.loadConfiguration(),
          old.saveConfiguration('write'),
          old.loadLogs(),
          old.setEnabled(false),
        ];
        await Future<void>.delayed(Duration.zero);
        final checks = [
          for (final waiter in waiters)
            expectLater(
              waiter,
              throwsA(
                isA<StateError>().having(
                  (e) => e.message,
                  'message',
                  'AgentManagementSliceStore is closed',
                ),
              ),
            ),
        ];
        final lateEffect = runner.take<TestAgentConnectionEffect>();
        old.stopAcceptingCommandsAndSettleWaiters();
        await Future.wait(checks);
        expect((await detection).status, DetectionRunStatus.closed);
        completeAllTestDetections();
        await old.drainExecutions();
        oldContainer.dispose();
        final freshRunner = _RecordingRunner();
        final fresh = _createStore(runner: freshRunner);
        final freshPending = fresh.testConnection();
        final freshEffect = freshRunner.take<TestAgentConnectionEffect>();
        expect(freshEffect.operationId, lateEffect.operationId);
        old.connectionTestFailed(
          lateEffect.operationId,
          defaultAgentProviderId,
          'late',
        );
        old.providerSettingsChanged(fresh.current.providerSettings);
        old.runtimeFactsReplaced(AgentManagementRuntimeFacts.empty);
        expect(fresh.testing, isTrue);
        expect(fresh.operationError, isNull);
        fresh.connectionTestFailed(
          freshEffect.operationId,
          defaultAgentProviderId,
          'fresh',
        );
        await freshPending;
        expect(() => old.selectAgent(defaultAgentProviderId), throwsStateError);
        expect(() => old.validateConfiguration('data'), throwsStateError);
        await expectLater(old.initialize(), throwsStateError);
        expect(() => old.testConnection(), throwsStateError);
        expect(() => old.loadLogs(), throwsStateError);
      },
    );

    test(
      'enrichment failures settle void and close rejects its pending caller',
      () async {
        final runner = _RecordingRunner();
        final container = _createContainer(
          runner: runner,
          supportsEnrichment: true,
        );
        final owner = container.read(agentManagementSliceProvider.notifier);
        final pending = owner.setAccountDataEnrichmentEnabled(false);
        await Future<void>.delayed(Duration.zero);
        final effect = runner.take<UpdateAccountDataEnrichmentEffect>();
        await owner.setAccountDataEnrichmentEnabled(false);
        owner.accountDataEnrichmentUpdateFailed(
          effect.operationId,
          defaultAgentProviderId,
          'enrichment failed',
        );
        await pending;
        expect(owner.accountDataEnrichmentEnabled, isTrue);
        expect(owner.operationError, 'enrichment failed');
        final waiting = expectLater(
          owner.setAccountDataEnrichmentEnabled(false),
          throwsStateError,
        );
        await Future<void>.delayed(Duration.zero);
        owner.stopAcceptingCommandsAndSettleWaiters();
        await waiting;
      },
    );

    test(
      'close settles cold initialization and available-provider callers',
      () async {
        final owner = _createStore(
          runner: _RecordingRunner(),
          initialized: false,
        );
        final init = expectLater(owner.initialize(), throwsStateError);
        final directory = expectLater(
          owner.loadAvailableThreadProviders(),
          throwsStateError,
        );
        owner.stopAcceptingCommandsAndSettleWaiters();
        await Future.wait([init, directory]);
      },
    );

    test(
      'drain waits physical execution after synchronous sink closes owner',
      () async {
        final runner = _RecordingRunner();
        final owner = _createStore(runner: runner);
        final physical = Completer<void>();
        late Future<void> drain;
        runner.execute = (_) {
          owner.stopAcceptingCommandsAndSettleWaiters();
          drain = owner.drainExecutions();
          return physical.future;
        };
        await expectLater(owner.testConnection(), throwsStateError);
        var drained = false;
        unawaited(drain.then((_) => drained = true));
        await Future<void>.delayed(Duration.zero);
        expect(drained, isFalse);
        expect(owner.drainExecutions(), same(drain));
        physical.complete();
        await drain;
        expect(drained, isTrue);
      },
    );

    test('drain failure is cached and waits all physical work', () async {
      final runner = _RecordingRunner();
      final container = _createContainer(
        runner: runner,
        registerTearDown: false,
      );
      addTearDown(container.dispose);
      final owner = container.read(agentManagementSliceProvider.notifier);
      final first = Completer<void>();
      final second = Completer<void>();
      runner.execute = (effect) =>
          effect is TestAgentConnectionEffect ? first.future : second.future;
      final connection = expectLater(owner.testConnection(), throwsStateError);
      final logs = expectLater(owner.loadLogs(), throwsStateError);
      owner.stopAcceptingCommandsAndSettleWaiters();
      final drain = owner.drainExecutions();
      final error = StateError('execution failure');
      var finished = false;
      final checked = drain.then<void>(
        (_) => throw TestFailure('expected drain failure'),
        onError: (Object actual, StackTrace _) {
          finished = true;
          expect(actual, same(error));
        },
      );
      first.completeError(error);
      await Future<void>.delayed(Duration.zero);
      expect(finished, isFalse);
      second.complete();
      await checked;
      await Future.wait([connection, logs]);
      expect(owner.drainExecutions(), same(drain));
      await expectLater(owner.drainExecutions(), throwsA(same(error)));
      // The test deliberately failed the physical runner; teardown must observe it too.
    });
    test(
      'listener errors do not suppress initialization or dispatch twice',
      () async {
        final errors = <Object>[];
        final runner = _RecordingRunner();
        await runZonedGuarded(() async {
          final container = _createContainer(
            runner: runner,
            initialized: false,
          );
          final store = container.read(agentManagementSliceProvider.notifier);
          final subscription = container.listen(agentManagementSliceProvider, (
            _,
            _,
          ) {
            throw StateError('listener failed');
          });
          final pending = store.initialize();
          expect(store.initialize(), same(pending));
          final effect = runner.take<ManagementInitializeEffect>();
          store.initializationSucceeded(
            effect.operationId,
            store.current.providerSettings,
            store.current.detection.confirmedByProviderId,
          );
          await pending;
          expect(store.initialized, isTrue);
          expect(runner.effects, isEmpty);
          expect(errors, isNotEmpty);
          subscription.close();
        }, (error, _) => errors.add(error));
      },
    );

    test(
      'accepts only matching detection progress and completes the request',
      () async {
        // Arrange
        final runner = _RecordingRunner();
        final store = _createStore(runner: runner);

        // Act
        final detection = store.detect();
        await Future<void>.delayed(Duration.zero);
        final effect = runner.take<DetectAgentsEffect>();
        store.testDetectionStarted(effect.operationId, defaultAgentProviderId);
        store.testDetectionProgress(
          effect.operationId,
          grokAgentProviderId,
          const AgentDetectionProgress(
            completed: 1,
            total: 2,
            message: 'stale',
          ),
          ManagedAgent.forDefinition(
            definition: grokAgentManagementDefinition,
            enabled: true,
          ),
        );

        // Assert
        expect(store.detectionProgress, isNull);

        // Act
        final detected =
            ManagedAgent.forDefinition(
              definition: codexAgentManagementDefinition,
              enabled: true,
            ).copyWith(
              installationState: AgentInstallationState.installed,
              currentVersion: '1.0.0',
            );
        store.testDetectionProgress(
          effect.operationId,
          defaultAgentProviderId,
          const AgentDetectionProgress(
            completed: 1,
            total: 2,
            message: 'accepted',
          ),
          detected,
        );
        store.testAgentDetected(
          effect.operationId,
          defaultAgentProviderId,
          detected,
        );
        completeTestDetection(effect.operationId);
        await detection;

        // Assert
        expect(store.detecting, isFalse);
        expect(store.detectionProgress, isNull);
        expect(
          store.current.agentsById[defaultAgentProviderId]?.installed,
          isTrue,
        );
      },
    );

    test(
      'late selected-agent result updates its entity, not current selection',
      () async {
        // Arrange
        final runner = _RecordingRunner();
        final store = _createStore(runner: runner);

        // Act
        final pending = store.testConnection();
        final effect = runner.take<TestAgentConnectionEffect>();
        store.selectAgent(grokAgentProviderId);
        final result = AgentManagementConnectionCheckSummary(
          success: true,
          testedAt: DateTime.utc(2026, 8, 23),
          elapsed: const Duration(milliseconds: 4),
          cliCallable: true,
          accountValid: true,
          protocolReady: true,
        );
        store.connectionTestSucceeded(
          operationId: effect.operationId,
          agentId: defaultAgentProviderId,
          result: result,
          models: const <AgentModelInfo>[],
          modelSource: 'Codex app-server',
          modelsUpdatedAt: DateTime.utc(2026, 8, 23),
        );

        // Assert
        expect(await pending, same(result));
        expect(store.selectedAgentId, grokAgentProviderId);
        expect(store.agent.definition.id, grokAgentProviderId);
        expect(
          store.current.agentsById[defaultAgentProviderId]?.connectionTest,
          same(result),
        );
        expect(
          store.current.agentsById[grokAgentProviderId]?.connectionTest,
          isNull,
        );
      },
    );

    test(
      'configuration save requires matching operation and document signature',
      () async {
        // Arrange
        final runner = _RecordingRunner();
        final store = _createStore(runner: runner);

        final first = _document(signature: 'first', content: 'one');
        final firstLoad = store.loadConfiguration();
        final firstLoadEffect = runner.take<LoadAgentConfigurationEffect>();
        store.configurationLoaded(
          firstLoadEffect.operationId,
          defaultAgentProviderId,
          first,
        );
        await firstLoad;

        // Act
        final save = store.saveConfiguration('saved');
        final saveEffect = runner.take<SaveAgentConfigurationEffect>();
        final second = _document(signature: 'second', content: 'external');
        final secondLoad = store.loadConfiguration();
        final secondLoadEffect = runner.take<LoadAgentConfigurationEffect>();
        store.configurationLoaded(
          secondLoadEffect.operationId,
          defaultAgentProviderId,
          second,
        );
        await secondLoad;
        final saved = AgentConfigurationSaveResult(
          document: _document(signature: 'saved', content: 'saved'),
        );
        store.configurationSaved(
          saveEffect.operationId,
          defaultAgentProviderId,
          saveEffect.original.signature,
          saved,
        );

        // Assert
        expect(await save, same(saved));
        expect(store.configuration?.signature, 'second');
        expect(store.configuration?.content, 'external');
        expect(store.savingConfiguration, isFalse);
      },
    );

    test('close rejects every pending compatibility future', () async {
      // Arrange
      final runner = _RecordingRunner();
      final store = _createStore(runner: runner);
      final pending = store.testConnection();
      final expectation = expectLater(pending, throwsStateError);

      // Act
      store.stopAcceptingCommandsAndSettleWaiters();

      // Assert
      await expectation;
      expect(store.isClosed, isTrue);
    });

    test(
      'unsupported account enrichment fails closed before an effect',
      () async {
        // Arrange
        final runner = _RecordingRunner();
        final store = _createStore(runner: runner);

        // Act / Assert
        await expectLater(
          store.setAccountDataEnrichmentEnabled(false),
          throwsUnsupportedError,
        );
        expect(runner.effects, isEmpty);
      },
    );
  });
}

ProviderContainer _createContainer({
  bool supportsEnrichment = false,
  bool registerTearDown = true,
  required _RecordingRunner runner,
  bool initialized = true,
}) {
  final settings = AgentProviderSettings(
    providers: <AgentProviderConfig>[
      defaultCodexAgentProviderConfig,
      defaultGrokAgentProviderConfig,
    ],
  );
  final container = managementTestContainer(
    registerTearDown: registerTearDown,
    initialState: managementFixtureState(
      agentsById: <String, ManagedAgent>{
        defaultAgentProviderId: ManagedAgent.forDefinition(
          definition: codexAgentManagementDefinition,
          enabled: true,
        ),
        grokAgentProviderId: ManagedAgent.forDefinition(
          definition: grokAgentManagementDefinition,
          enabled: true,
        ),
      },
      orderedAgentIds: const <String>[
        defaultAgentProviderId,
        grokAgentProviderId,
      ],
      selectedAgentId: defaultAgentProviderId,
      capabilitiesByAgentId: <String, AgentCliManagementCapabilities>{
        defaultAgentProviderId: supportsEnrichment
            ? const AgentCliManagementCapabilities(
                accountDataEnrichmentExtraKey: testAccountDataEnrichmentKey,
              )
            : AgentCliManagementCapabilities.none,
        grokAgentProviderId: AgentCliManagementCapabilities.none,
      },
      providerSettings: settings,
      initialized: initialized,
    ),
    effectRunner: runner,
    configurationNotLoadedMessage: 'not loaded',
    accountDataEnrichmentEnabledFor: (config) =>
        config.extra[testAccountDataEnrichmentKey] != false,
  );
  return container;
}

AgentConfigurationDocument _document({
  required String signature,
  required String content,
}) {
  return AgentConfigurationDocument(
    path: '/tmp/config.toml',
    format: 'TOML',
    content: content,
    maskedContent: content,
    exists: true,
    loadedAt: DateTime.utc(2026, 8, 23),
    signature: signature,
  );
}

final class _RecordingRunner implements AgentManagementSliceEffectRunner {
  Future<void> Function(AgentManagementSliceEffect)? execute;
  final List<AgentManagementSliceEffect> effects =
      <AgentManagementSliceEffect>[];

  @override
  Future<void> run(AgentManagementSliceEffect effect) async {
    effects.add(effect);
    if (execute != null) {
      await execute!(effect);
    } else if (effect is DetectAgentsEffect) {
      await holdTestDetection(effect);
    }
  }

  T take<T extends AgentManagementSliceEffect>() {
    final index = effects.indexWhere((effect) => effect is T);
    if (index < 0) {
      throw StateError('No $T effect recorded');
    }
    return effects.removeAt(index) as T;
  }

  @override
  String? validateConfiguration(String agentId, String content) => null;
}

AgentManagementSliceNotifier _createStore({
  required _RecordingRunner runner,
  bool initialized = true,
}) => _createContainer(
  runner: runner,
  initialized: initialized,
).read(agentManagementSliceProvider.notifier);

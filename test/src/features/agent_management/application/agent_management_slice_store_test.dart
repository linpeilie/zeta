import '../../../testing/agent_management_test_definitions.dart';
import 'package:zeta/src/app/plugins/agent_provider_manifest.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_effect.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_state.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_store.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';

void main() {
  group('AgentManagementSliceStore', () {
    test('cold initialization can retry after a listener throws', () async {
      // Arrange
      final runner = _RecordingRunner();
      final store = _createStore(runner: runner, initialized: false);
      addTearDown(store.close);
      var throwOnNextNotification = true;
      store.addListener(() {
        if (throwOnNextNotification) {
          throwOnNextNotification = false;
          throw StateError('listener failed during build');
        }
      });

      // Act / Assert
      await expectLater(store.initialize(), throwsStateError);
      expect(runner.effects, isEmpty);

      // Act
      final retry = store.initialize();
      final effect = runner.take<ManagementInitializeEffect>();
      store.initializationSucceeded(
        effect.operationId,
        store.state.providerSettings,
        store.state.agentsById,
      );

      // Assert
      await retry.timeout(const Duration(milliseconds: 100));
      expect(store.initialized, isTrue);
    });

    test(
      'accepts only matching detection progress and completes the request',
      () async {
        // Arrange
        final runner = _RecordingRunner();
        final store = _createStore(runner: runner);
        addTearDown(store.close);

        // Act
        final detection = store.detect();
        await Future<void>.delayed(Duration.zero);
        final effect = runner.take<DetectAgentsEffect>();
        store.detectionStarted(effect.operationId, defaultAgentProviderId);
        store.detectionProgressReported(
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
        store.detectionProgressReported(
          effect.operationId,
          defaultAgentProviderId,
          const AgentDetectionProgress(
            completed: 1,
            total: 2,
            message: 'accepted',
          ),
          detected,
        );
        store.agentDetected(
          effect.operationId,
          defaultAgentProviderId,
          detected,
        );
        store.detectionCompleted(effect.operationId);
        await detection;

        // Assert
        expect(store.detecting, isFalse);
        expect(store.detectionProgress, isNull);
        expect(
          store.state.agentsById[defaultAgentProviderId]?.installed,
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
        addTearDown(store.close);

        // Act
        final pending = store.testConnection();
        final effect = runner.take<TestAgentConnectionEffect>();
        store.selectAgent(grokAgentProviderId);
        final result = AgentConnectionTestResult(
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
          store.state.agentsById[defaultAgentProviderId]?.connectionTest,
          same(result),
        );
        expect(
          store.state.agentsById[grokAgentProviderId]?.connectionTest,
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
        addTearDown(store.close);
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
      store.close();

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
        addTearDown(store.close);

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

AgentManagementSliceStore _createStore({
  required _RecordingRunner runner,
  bool initialized = true,
}) {
  final settings = AgentProviderSettings(
    providers: <AgentProviderConfig>[
      defaultCodexAgentProviderConfig,
      defaultGrokAgentProviderConfig,
    ],
  );
  return AgentManagementSliceStore(
    initialState: AgentManagementSliceState(
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
      capabilitiesByAgentId: const <String, AgentCliManagementCapabilities>{
        defaultAgentProviderId: AgentCliManagementCapabilities.none,
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
  final List<AgentManagementSliceEffect> effects =
      <AgentManagementSliceEffect>[];

  @override
  void run(AgentManagementSliceEffect effect) => effects.add(effect);

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

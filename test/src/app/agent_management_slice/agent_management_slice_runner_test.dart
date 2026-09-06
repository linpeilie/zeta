import '../../testing/management_detection_test_support.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta/src/app/plugins/zeta_plugin_providers.dart';
import '../../testing/zeta_test_app.dart';
import '../../testing/ide_test_harness.dart'
    show FakeAgentProvider, FakeAgentProviderBundleBuilder;
import '../../testing/agent_management_test_container.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_notifier.dart';
import '../../testing/memory_agent_runtime_fact_source.dart';
import '../../testing/agent_management_test_definitions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/app/plugins/agent_provider_manifest.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/app/agent_management_slice/agent_management_slice_composition.dart';
import 'package:zeta/src/features/agent/application/agent_model_catalog_repository.dart';
import 'package:zeta/src/features/agent/application/agent_provider_settings_port.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import '../../testing/memory_feature_stores.dart';

void main() {
  test(
    'runner preserves management behavior through typed result intents',
    () async {
      // Arrange
      final settingsPort = _SettingsPort(
        AgentProviderSettings(
          providers: <AgentProviderConfig>[
            defaultClaudeCodeAgentProviderConfig.copyWith(
              extra: const <String, Object?>{
                'cliPath': '/opt/claude',
                'detectedCurrentVersion': '2.1.0',
                'detectedAccountState': 'loggedIn',
              },
            ),
          ],
          activeProviderId: defaultClaudeCodeProviderId,
        ),
      );
      final runtimeSource = MemoryAgentRuntimeFactSource();
      final repository = _RunnerRepository();
      final composition = managementAppTestContainer(
        AgentManagementCompositionInputs(
          definitions: testAgentManagementDefinitions,
          repositories: <String, AgentCliManagementRepository>{
            defaultClaudeCodeProviderId: repository,
          },
          providerSettings: settingsPort,
          textCatalog: const FallbackAgentManagementTextCatalog(),
        ),
      );
      final store = composition.read(agentManagementSliceProvider.notifier);
      final subscription = composition.listen(
        agentManagementRuntimeIngressProvider(runtimeSource),
        (_, _) {},
      );
      subscription.read().start();
      addTearDown(() async {
        subscription.close();
        await closeManagementTestContainer(composition);
        expect(runtimeSource.listenerCount, 0);
        settingsPort.dispose();
      });

      // Act
      await store.initialize();

      // Assert
      expect(store.initialized, isTrue);
      expect(store.agent.installed, isTrue);
      expect(store.supportsAccountDataEnrichment, isTrue);

      // Act
      await store.detect();
      final connection = await store.testConnection();
      await store.setAccountDataEnrichmentEnabled(false);
      final document = await store.loadConfiguration();
      final saved = await store.saveConfiguration('{"saved":true}');
      final logs = await store.loadLogs();
      runtimeSource.replace(
        AgentManagementRuntimeFacts([
          AgentManagementRuntimeFact(
            observationKey: Object(),
            providerId: defaultClaudeCodeProviderId,
            lifecycle: AgentConversationRuntimeLifecyclePhase.attached,
            activeTurn: true,
          ),
        ]),
      );

      // Assert
      expect(repository.detectionCalls, 1);
      expect(connection?.success, isTrue);
      expect(store.accountDataEnrichmentEnabled, isFalse);
      expect(document?.signature, 'loaded');
      expect(saved.document.content, '{"saved":true}');
      expect(store.configuration?.signature, 'saved');
      expect(logs.single.message, 'safe log');
      expect(store.agent.availableLogFileCount, 1);
      expect(store.agent.runtimeState, AgentRuntimeState.running);
      expect(
        settingsPort
            .providerConfigById(defaultClaudeCodeProviderId)
            ?.extra['detectedCurrentVersion'],
        '2.2.0',
      );
    },
  );
  test('detection drain includes persistence already in progress', () async {
    final settings = _SettingsPort(
      AgentProviderSettings(providers: [defaultClaudeCodeAgentProviderConfig]),
    );
    final write = Completer<void>();
    settings.updateGate = write;
    final repository = _RunnerRepository();
    final container = managementAppTestContainer(_inputs(repository, settings));
    addTearDown(() async {
      await closeManagementTestContainer(container);
      settings.dispose();
    });
    final owner = container.read(agentManagementSliceProvider.notifier);
    await owner.initialize();
    final detection = owner.refreshDetection();
    await Future<void>.delayed(Duration.zero);
    expect(settings.updateCalls, 1);
    owner.stopAcceptingCommandsAndSettleWaiters();
    expect((await detection).status, DetectionRunStatus.closed);
    var drained = false;
    final drain = owner.drainExecutions().then((_) => drained = true);
    await Future<void>.delayed(Duration.zero);
    expect(drained, isFalse);
    write.complete();
    await drain;
    expect(repository.detectionCalls, 1);
  });

  for (final stopDuringRead in [false, true]) {
    test(
      'logs drain includes ${stopDuringRead ? 'read' : 'discover'} and stops later steps',
      () async {
        final settings = _SettingsPort(
          AgentProviderSettings(
            providers: [defaultClaudeCodeAgentProviderConfig],
          ),
        );
        final repository = _RunnerRepository();
        final gate = Completer<void>();
        if (stopDuringRead) {
          repository.logsGate = gate;
        } else {
          repository.discoverGate = gate;
        }
        final container = managementAppTestContainer(
          _inputs(repository, settings),
        );
        addTearDown(() async {
          await closeManagementTestContainer(container);
          settings.dispose();
        });
        final owner = container.read(agentManagementSliceProvider.notifier);
        await owner.initialize();
        final logs = expectLater(owner.loadLogs(), throwsStateError);
        await Future<void>.delayed(Duration.zero);
        expect(repository.logCalls, stopDuringRead ? 1 : 0);
        owner.stopAcceptingCommandsAndSettleWaiters();
        await logs;
        var drained = false;
        final drain = owner.drainExecutions().then((_) => drained = true);
        await Future<void>.delayed(Duration.zero);
        expect(drained, isFalse);
        gate.complete();
        await drain;
        expect(repository.logCalls, stopDuringRead ? 1 : 0);
        expect(owner.logs, isEmpty);
      },
    );
  }

  test(
    'app builds management without Widgets and close waits save before registry and container',
    () async {
      final settings = _SettingsPort(
        AgentProviderSettings(
          providers: [defaultClaudeCodeAgentProviderConfig],
        ),
      );
      final repository = _RunnerRepository();
      final saveGate = Completer<void>();
      repository.saveGate = saveGate;
      final registry = _RecordingRegistry();
      final app = zetaTestComposition(
        overrides: [
          agentManagementCompositionInputsProvider.overrideWithValue(
            _inputs(repository, settings),
          ),
          agentProviderRuntimeRegistryProvider.overrideWithValue(registry),
          agentProviderBundleFactoryProvider.overrideWithValue(
            registry.providerFactory,
          ),
        ],
      );
      final owner = app.container.read(agentManagementSliceProvider.notifier);
      await owner.initialize();
      expect(owner.initialized, isTrue);
      final facts = MemoryAgentRuntimeFactSource();
      final factsSubscription = app.container.listen(
        agentManagementRuntimeIngressProvider(facts),
        (_, _) {},
      );
      addTearDown(factsSubscription.close);
      final detach = app.container
          .read(agentManagementRuntimeIngressProvider(facts))
          .borrow();
      expect(facts.listenerCount, 1);
      detach();
      expect(facts.listenerCount, 0);
      expect(owner.isClosed, isFalse);
      final detachAgain = app.container
          .read(agentManagementRuntimeIngressProvider(facts))
          .borrow();
      expect(facts.listenerCount, 1);
      final anotherBorrow = app.container
          .read(agentManagementRuntimeIngressProvider(facts))
          .borrow();
      detachAgain();
      expect(facts.listenerCount, 1);
      await owner.loadConfiguration();
      final saved = expectLater(
        owner.saveConfiguration('new config'),
        throwsStateError,
      );
      expect(repository.saveCalls, 1);
      var containerDisposed = false;
      app.container.listen(
        agentManagementSliceProvider,
        (_, _) {},
        onError: (_, _) {},
      );
      app.container.read(
        _disposalProbeProvider(() => containerDisposed = true),
      );
      final close = app.close();
      expect(app.close(), same(close));
      app.dispose();
      await saved;
      expect(registry.closeCalls, 0);
      anotherBorrow();
      expect(facts.listenerCount, 0);
      expect(containerDisposed, isFalse);
      saveGate.complete();
      await close;
      expect(registry.closeCalls, 1);
      expect(containerDisposed, isTrue);
      settings.dispose();
    },
  );
}

final class _RunnerRepository
    implements AgentCliManagementRepository, AgentCliManagementDescriptor {
  int detectionCalls = 0;
  int saveCalls = 0;
  int logCalls = 0;
  Completer<void>? saveGate, discoverGate, logsGate;

  @override
  String get agentId => defaultClaudeCodeProviderId;

  @override
  AgentCliManagementCapabilities get managementCapabilities =>
      testClaudeManagementCapabilities;

  @override
  AgentProviderConfig get defaultProviderConfig =>
      defaultClaudeCodeAgentProviderConfig;

  @override
  bool acceptsExecutablePath(String path) => path.endsWith('claude');

  @override
  String get connectionModelSourceLabel => 'Claude Code';

  @override
  String get configPath => '/tmp/settings.json';

  @override
  Future<ManagedAgent> detect({
    required AgentProviderConfig providerConfig,
    required bool enabled,
    AgentDetectionProgressCallback? onProgress,
  }) async {
    detectionCalls += 1;
    final detected =
        ManagedAgent.forDefinition(
          definition: claudeCodeAgentManagementDefinition,
          enabled: enabled,
        ).copyWith(
          installationState: AgentInstallationState.installed,
          executablePath: '/opt/claude',
          currentVersion: '2.2.0',
          latestVersion: '2.2.0',
          accountState: AgentAccountState.loggedIn,
          lastDetectedAt: DateTime.utc(2026, 8, 23),
          logPaths: const <String>['/tmp/claude.log'],
        );
    onProgress?.call(
      const AgentDetectionProgress(completed: 1, total: 1, message: 'done'),
      detected,
    );
    return detected;
  }

  @override
  Future<(AgentConnectionTestResult, List<AgentModelInfo>)> testConnection({
    required AgentProviderConfig providerConfig,
  }) async {
    return (
      AgentConnectionTestResult(
        success: true,
        testedAt: DateTime.utc(2026, 8, 23),
        elapsed: const Duration(milliseconds: 2),
        cliCallable: true,
        accountValid: true,
        protocolReady: true,
      ),
      const <AgentModelInfo>[],
    );
  }

  @override
  Future<AgentProviderConfig> providerConfigForPath({
    required AgentProviderConfig current,
    required String path,
  }) async => current.copyWith(command: path);

  @override
  Future<AgentConfigurationDocument> readConfiguration() async =>
      AgentConfigurationDocument(
        path: configPath,
        format: 'JSON',
        content: '{}',
        maskedContent: '{}',
        exists: true,
        loadedAt: DateTime.utc(2026, 8, 23),
        signature: 'loaded',
      );

  @override
  String? validateConfiguration(String content) => null;

  @override
  Future<AgentConfigurationSaveResult> saveConfiguration({
    required AgentConfigurationDocument original,
    required String content,
    bool overwriteExternalChanges = false,
  }) async {
    saveCalls += 1;
    await saveGate?.future;
    return AgentConfigurationSaveResult(
      document: AgentConfigurationDocument(
        path: original.path,
        format: original.format,
        content: content,
        maskedContent: content,
        exists: true,
        loadedAt: DateTime.utc(2026, 8, 23),
        signature: 'saved',
      ),
    );
  }

  @override
  Future<List<String>> discoverLogPaths() async {
    await discoverGate?.future;
    return const ['/tmp/claude.log'];
  }

  @override
  Future<List<AgentLogEntry>> readLogs(
    List<String> paths, {
    int maxLines = 1000,
  }) async {
    logCalls += 1;
    await logsGate?.future;
    return [
      AgentLogEntry(
        id: 'log',
        sourcePath: paths.single,
        message: 'safe log',
        level: AgentLogLevel.info,
        timestamp: DateTime.utc(2026, 8, 23),
      ),
    ];
  }
}

final class _SettingsPort extends ChangeNotifier
    implements AgentProviderSettingsPort {
  _SettingsPort(this._settings)
    : modelCatalogRepository = AgentModelCatalogRepository(
        store: MemoryAgentModelCatalogCacheStore(),
      );

  AgentProviderSettings _settings;
  Completer<void>? updateGate;
  int updateCalls = 0;

  final AgentModelCatalogRepository modelCatalogRepository;

  @override
  Future<void> recordModelCatalog({
    required AgentProviderConfig config,
    required AgentModelList models,
    required String source,
  }) {
    return modelCatalogRepository.record(
      config: config,
      models: models,
      source: source,
    );
  }

  @override
  Future<AgentModelCatalogLoadResult> loadModelCatalog({
    required AgentProviderConfig config,
    required AgentModelCatalogLoader refreshLoader,
    bool forceRefresh = false,
    void Function(AgentModelCatalogSnapshot snapshot)? onCacheHit,
  }) {
    return modelCatalogRepository.load(
      config: config,
      source: modelCatalogSourceFor(config),
      refreshLoader: refreshLoader,
      forceRefresh: forceRefresh,
      onCacheHit: onCacheHit,
    );
  }

  @override
  AgentProviderSettings get settings => _settings;

  @override
  String get activeProviderId => _settings.activeProvider.id;

  @override
  String get activeProviderName => _settings.activeProvider.displayName;

  @override
  AgentProviderConfig get activeProviderConfig => _settings.activeProvider;

  @override
  List<AgentProviderConfig> get enabledProviders => List.unmodifiable(
    _settings.providers.where((provider) => provider.enabled),
  );

  @override
  bool isProviderEnabled(String providerId) =>
      providerConfigById(providerId)?.enabled ?? false;

  @override
  AgentProviderConfig? providerConfigById(String providerId) {
    for (final provider in _settings.providers) {
      if (provider.id == providerId) {
        return provider;
      }
    }
    return null;
  }

  @override
  AgentProviderCapabilities capabilitiesForProviderId(String providerId) =>
      AgentProviderCapabilities.unsupported;

  @override
  String modelCatalogSourceFor(AgentProviderConfig config) =>
      config.displayName;

  @override
  Future<AgentProviderSettings> loadSettings() async => _settings;

  @override
  Future<void> updateProviderConfig(
    AgentProviderConfig updated, {
    bool restartProvider = false,
  }) async {
    updateCalls += 1;
    await updateGate?.future;
    _settings = AgentProviderSettings(
      providers: <AgentProviderConfig>[
        for (final provider in _settings.providers)
          if (provider.id == updated.id) updated else provider,
      ],
      activeProviderId: _settings.activeProviderId,
    );
    notifyListeners();
  }

  @override
  Future<void> setProviderEnabled(String providerId, bool enabled) async {
    final current = providerConfigById(providerId);
    if (current != null) {
      await updateProviderConfig(current.copyWith(enabled: enabled));
    }
  }

  @override
  Future<void> setActiveProvider(String providerId) async {
    _settings = _settings.copyWith(activeProviderId: providerId);
    notifyListeners();
  }

  @override
  Future<void> persistModelSelection(
    AgentModelSelection selection,
    Map<String, AgentModelPreference> preferences,
  ) async {}

  @override
  Future<void> persistPermissionOptionId(String optionId) async {}

  @override
  Future<void> persistPermissionOptionIdForProvider(
    String providerId,
    String optionId,
  ) async {}

  @override
  void Function() subscribe(void Function() listener) {
    addListener(listener);
    return () => removeListener(listener);
  }
}

AgentManagementCompositionInputs _inputs(
  _RunnerRepository repository,
  _SettingsPort settings,
) => AgentManagementCompositionInputs(
  repositories: {defaultClaudeCodeProviderId: repository},
  definitions: testAgentManagementDefinitions,
  providerSettings: settings,
  textCatalog: const FallbackAgentManagementTextCatalog(),
);
final _disposalProbeProvider = Provider.family<void, void Function()>((
  ref,
  callback,
) {
  ref.onDispose(callback);
});

final class _RecordingRegistry extends AgentProviderRuntimeRegistry {
  _RecordingRegistry()
    : super(
        providerFactory: FakeAgentProviderBundleBuilder.fromFake(
          FakeAgentProvider(),
        ),
      );
  int closeCalls = 0;
  @override
  Future<void> close() {
    closeCalls += 1;
    return super.close();
  }
}

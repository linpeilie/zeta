import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/app/agent_management_slice/agent_management_slice_composition.dart';
import 'package:zeta/src/features/agent/application/agent_model_catalog_repository.dart';
import 'package:zeta/src/features/agent/application/agent_provider_settings_port.dart';
import 'package:zeta/src/features/agent/data/agent_model_catalog_cache_store.dart';
import 'package:zeta/src/features/agent_management/domain/agent_cli_management_repository.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';
import 'package:zeta/src/features/agent_management/domain/fallback_agent_management_text_catalog.dart';

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
      final runtimeSignal = ChangeNotifier();
      var runtimeState = AgentRuntimeState.notRunning;
      final repository = _RunnerRepository();
      final composition = AgentManagementSliceComposition.create(
        repositories: <String, AgentCliManagementRepository>{
          defaultClaudeCodeProviderId: repository,
        },
        providerSettings: settingsPort,
        runtimeListenable: runtimeSignal,
        runtimeSnapshotProvider: () => (
          activeAgentId: defaultClaudeCodeProviderId,
          runtimeState: runtimeState,
        ),
        textCatalog: const FallbackAgentManagementTextCatalog(),
      );
      final store = composition.store;
      addTearDown(() {
        composition.close();
        runtimeSignal.dispose();
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
      runtimeState = AgentRuntimeState.running;
      runtimeSignal.notifyListeners();

      // Assert
      expect(repository.detectionCalls, 1);
      expect(connection?.success, isTrue);
      expect(store.accountDataEnrichmentEnabled, isFalse);
      expect(document?.signature, 'loaded');
      expect(saved.document.content, '{"saved":true}');
      expect(store.configuration?.signature, 'saved');
      expect(logs.single.message, 'safe log');
      expect(store.agent.logPaths, const <String>['/tmp/claude.log']);
      expect(store.agent.runtimeState, AgentRuntimeState.running);
      expect(
        settingsPort
            .providerConfigById(defaultClaudeCodeProviderId)
            ?.extra['detectedCurrentVersion'],
        '2.2.0',
      );
    },
  );
}

final class _RunnerRepository
    implements AgentCliManagementRepository, AgentCliManagementDescriptor {
  int detectionCalls = 0;

  @override
  String get agentId => defaultClaudeCodeProviderId;

  @override
  AgentCliManagementCapabilities get managementCapabilities =>
      const AgentCliManagementCapabilities(supportsAccountDataEnrichment: true);

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
    final detected = ManagedAgent.claudeCode(enabled: enabled).copyWith(
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
  Future<List<String>> discoverLogPaths() async => const <String>[
    '/tmp/claude.log',
  ];

  @override
  Future<List<AgentLogEntry>> readLogs(
    List<String> paths, {
    int maxLines = 1000,
  }) async => <AgentLogEntry>[
    AgentLogEntry(
      id: 'log',
      sourcePath: paths.single,
      message: 'safe log',
      level: AgentLogLevel.info,
      timestamp: DateTime.utc(2026, 8, 23),
    ),
  ];
}

final class _SettingsPort extends ChangeNotifier
    implements AgentProviderSettingsPort {
  _SettingsPort(this._settings)
    : modelCatalogRepository = AgentModelCatalogRepository(
        store: MemoryAgentModelCatalogCacheStore(),
      );

  AgentProviderSettings _settings;

  @override
  final AgentModelCatalogRepository modelCatalogRepository;

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
}

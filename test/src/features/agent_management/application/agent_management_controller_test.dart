import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_provider_runtime_registry.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_controller.dart';
import 'package:zeta/src/features/agent_management/data/codex_agent_management_repository.dart';
import 'package:zeta/src/features/agent_management/domain/agent_cli_management_repository.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';
import 'package:zeta/src/features/agent/application/agent_provider_settings_controller.dart';

import '../../../testing/ide_test_harness.dart';

void main() {
  group('AgentManagementController.loadAvailableThreadProviders', () {
    test(
      'returns enabled supported providers without detecting CLI state',
      () async {
        // Arrange
        final harness = _ManagementHarness.create(
          codexConfig: AgentProviderConfig.defaultCodex,
        );
        addTearDown(harness.dispose);

        // Act
        final providers = await harness.controller
            .loadAvailableThreadProviders();

        // Assert
        expect(providers.map((provider) => provider.id), <String>[
          defaultAgentProviderId,
        ]);
        expect(
          harness.controller.agent.installationState,
          AgentInstallationState.unknown,
        );
        expect(harness.controller.detecting, isFalse);
      },
    );

    test('does not offer an explicitly disabled provider', () async {
      // Arrange
      final harness = _ManagementHarness.create(
        codexConfig: AgentProviderConfig.defaultCodex.copyWith(enabled: false),
      );
      addTearDown(harness.dispose);

      // Act
      final providers = await harness.controller.loadAvailableThreadProviders();

      // Assert
      expect(providers, isEmpty);
    });
  });

  test('filters Cursor before Agent management auto detection', () async {
    // Arrange
    final provider = FakeAgentProvider();
    final providerFactory = FakeAgentProviderBundleBuilder.fromFake(provider);
    final registry = AgentProviderRuntimeRegistry(
      providerFactory: providerFactory,
    );
    final cursorRepository = _FakeCursorManagementRepository();
    final providerController = AgentProviderSettingsController(
      runtimeRegistry: registry,
      configStore: MemoryAgentProviderConfigStore(
        const AgentProviderSettings(
          providers: <AgentProviderConfig>[
            AgentProviderConfig.defaultCodex,
            AgentProviderConfig.defaultCursor,
          ],
        ),
      ),
    );
    final controller = AgentManagementController(
      repositories: <String, AgentCliManagementRepository>{
        cursorAgentProviderId: cursorRepository,
      },
      providerController: providerController,
    );
    addTearDown(controller.dispose);
    addTearDown(providerController.dispose);
    addTearDown(registry.close);

    // Act
    await controller.initialize(autoDetect: true);
    await Future<void>.delayed(Duration.zero);
    final available = await controller.loadAvailableThreadProviders();

    // Assert
    expect(controller.agents, isEmpty);
    expect(available, isEmpty);
    expect(cursorRepository.detectCalls, 0);
    expect(
      providerController.providerConfigById(cursorAgentProviderId),
      isNotNull,
    );
    expect(
      providerController.isProviderEnabled(cursorAgentProviderId),
      isFalse,
    );
  });
}

class _ManagementHarness {
  _ManagementHarness({
    required this.root,
    required this.providerController,
    required this.controller,
    required this._registry,
  });

  final Directory root;
  final AgentProviderSettingsController providerController;
  final AgentManagementController controller;
  final AgentProviderRuntimeRegistry _registry;

  static _ManagementHarness create({required AgentProviderConfig codexConfig}) {
    final root = Directory.systemTemp.createTempSync(
      'zeta-thread-provider-test-',
    );
    final provider = FakeAgentProvider();
    final providerFactory = FakeAgentProviderBundleBuilder.fromFake(provider);
    final registry = AgentProviderRuntimeRegistry(
      providerFactory: providerFactory,
    );
    final providerController = AgentProviderSettingsController(
      runtimeRegistry: registry,
      configStore: MemoryAgentProviderConfigStore(
        AgentProviderSettings(
          providers: <AgentProviderConfig>[
            codexConfig,
            AgentProviderConfig.defaultGrok,
          ],
        ),
      ),
    );
    final repository = CodexAgentManagementRepository(
      runtimeRegistry: registry,
      codexHomeProvider: () => root.path,
    );
    final controller = AgentManagementController(
      repositories: <String, AgentCliManagementRepository>{
        AgentDefinition.codex.id: repository,
      },
      providerController: providerController,
    );
    return _ManagementHarness(
      root: root,
      providerController: providerController,
      controller: controller,
      registry: registry,
    );
  }

  Future<void> dispose() async {
    controller.dispose();
    providerController.dispose();
    await _registry.close();
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  }
}

class _FakeCursorManagementRepository implements AgentCliManagementRepository {
  int detectCalls = 0;

  @override
  String get agentId => cursorAgentProviderId;

  @override
  String get configPath => 'cursor-config.json';

  @override
  Future<ManagedAgent> detect({
    required AgentProviderConfig providerConfig,
    required bool enabled,
    AgentDetectionProgressCallback? onProgress,
  }) async {
    detectCalls += 1;
    return ManagedAgent.forDefinition(
      definition: _retiredCursorDefinition,
      enabled: enabled,
    ).copyWith(
      installationState: AgentInstallationState.installed,
      accountState: AgentAccountState.loggedIn,
      connectionTest: AgentConnectionTestResult(
        success: true,
        testedAt: DateTime(2026),
        elapsed: const Duration(milliseconds: 1),
        cliCallable: true,
        accountValid: true,
        protocolReady: true,
      ),
    );
  }

  @override
  Future<(AgentConnectionTestResult, List<AgentModelInfo>)> testConnection({
    required AgentProviderConfig providerConfig,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<AgentProviderConfig> providerConfigForPath({
    required AgentProviderConfig current,
    required String path,
  }) async => current;

  @override
  Future<AgentConfigurationDocument> readConfiguration() async {
    throw UnimplementedError();
  }

  @override
  String? validateConfiguration(String content) => null;

  @override
  Future<AgentConfigurationSaveResult> saveConfiguration({
    required AgentConfigurationDocument original,
    required String content,
    bool overwriteExternalChanges = false,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<List<String>> discoverLogPaths() async => const <String>[];

  @override
  Future<List<AgentLogEntry>> readLogs(
    List<String> paths, {
    int maxLines = 1000,
  }) async => const <AgentLogEntry>[];
}

const _retiredCursorDefinition = AgentDefinition(
  id: cursorAgentProviderId,
  displayName: 'Retired Cursor Agent',
  vendor: 'Retired',
  commandName: '',
  protocol: 'unsupported',
  transport: 'none',
  configFormat: 'none',
  defaultConfigRelativePath: '',
  npmPackage: '',
);

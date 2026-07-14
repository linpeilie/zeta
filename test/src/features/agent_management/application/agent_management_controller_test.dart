import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_controller.dart';
import 'package:zeta/src/features/agent_management/data/codex_agent_management_repository.dart';
import 'package:zeta/src/features/agent_management/domain/agent_cli_management_repository.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';
import 'package:zeta/src/ui/features/ide/view_models/active_agent_provider_controller.dart';

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

  test(
    'Cursor can only be enabled after a successful connection test',
    () async {
      // Arrange
      final provider = FakeAgentProvider();
      final providerFactory = FakeAgentProviderFactory(provider);
      final providerController = ActiveAgentProviderController(
        providerFactory: providerFactory,
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
          cursorAgentProviderId: _FakeCursorManagementRepository(),
        },
        providerController: providerController,
      );
      addTearDown(controller.dispose);
      addTearDown(providerController.dispose);
      await controller.initialize();

      // Act / Assert: 未测试时拒绝启用。
      await controller.setEnabled(true);
      expect(controller.agent.enabled, isFalse);
      expect(controller.operationError, contains('连接测试'));

      // Act / Assert: 检测中的无计费握手成功后允许启用。
      await controller.detect();
      await controller.setEnabled(true);
      expect(controller.agent.enabled, isTrue);
      expect(
        providerController.isProviderEnabled(cursorAgentProviderId),
        isTrue,
      );
    },
  );
}

class _ManagementHarness {
  _ManagementHarness({
    required this.root,
    required this.providerController,
    required this.controller,
  });

  final Directory root;
  final ActiveAgentProviderController providerController;
  final AgentManagementController controller;

  static _ManagementHarness create({required AgentProviderConfig codexConfig}) {
    final root = Directory.systemTemp.createTempSync(
      'zeta-thread-provider-test-',
    );
    final provider = FakeAgentProvider();
    final providerFactory = FakeAgentProviderFactory(provider);
    final providerController = ActiveAgentProviderController(
      providerFactory: providerFactory,
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
      providerFactory: providerFactory,
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
    );
  }

  Future<void> dispose() async {
    controller.dispose();
    providerController.dispose();
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  }
}

class _FakeCursorManagementRepository implements AgentCliManagementRepository {
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
    return ManagedAgent.cursor(enabled: enabled).copyWith(
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
    required int timeoutSeconds,
  }) async => current;

  @override
  AgentProviderConfig providerConfigWithTimeout(
    AgentProviderConfig current,
    int timeoutSeconds,
  ) => current;

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

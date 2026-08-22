import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
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

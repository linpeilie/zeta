import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/app/project_threads_slice/project_threads_slice_composition.dart';
import 'package:zeta/src/features/agent/application/agent_provider_settings_controller.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';

import '../../testing/ide_test_harness.dart';

void main() {
  test(
    'runner queries Provider and returns typed page state to the store',
    () async {
      final provider = FakeAgentProvider(
        threadPages: <AgentThreadPage>[
          AgentThreadPage(
            threads: <AgentThreadSummary>[
              agentThread(
                id: 'thread-1',
                projectPath: '/repo',
                title: 'Runner thread',
              ),
            ],
            nextCursor: null,
          ),
        ],
      );
      final registry = AgentProviderRuntimeRegistry(
        providerFactory: FakeAgentProviderBundleBuilder.fromFake(provider),
      );
      final settings = AgentProviderSettingsController(
        runtimeRegistry: registry,
        configStore: MemoryAgentProviderConfigStore(
          const AgentProviderSettings(
            providers: <AgentProviderConfig>[AgentProviderConfig.defaultCodex],
            activeProviderId: defaultAgentProviderId,
          ),
        ),
      );
      final bindingManager = AgentConversationBindingManager(
        runtimeRegistry: registry,
      );
      final composition = ProjectThreadsSliceComposition.create(
        providerController: settings,
        globalRuntime: AgentProviderGlobalRuntime(runtimeRegistry: registry),
        bindingManager: bindingManager,
        textCatalog: const FallbackAgentUiTextCatalog(),
      );
      addTearDown(() async {
        composition.store.dispose();
        settings.dispose();
        await bindingManager.close();
        await registry.close();
      });

      await composition.store.loadInitial('/repo');

      expect(composition.store.stateFor('/repo').threads.single.id, 'thread-1');
      expect(composition.store.stateFor('/repo').hasLoaded, isTrue);
      expect(provider.listQueries.single.projectPath, '/repo');
    },
  );

  test(
    'search debounce stays in runner and publishes only after delay',
    () async {
      final provider = FakeAgentProvider(
        threadPages: <AgentThreadPage>[
          const AgentThreadPage(
            threads: <AgentThreadSummary>[],
            nextCursor: null,
          ),
        ],
      );
      final registry = AgentProviderRuntimeRegistry(
        providerFactory: FakeAgentProviderBundleBuilder.fromFake(provider),
      );
      final settings = AgentProviderSettingsController(
        runtimeRegistry: registry,
        configStore: MemoryAgentProviderConfigStore(
          const AgentProviderSettings(
            providers: <AgentProviderConfig>[AgentProviderConfig.defaultCodex],
            activeProviderId: defaultAgentProviderId,
          ),
        ),
      );
      final bindingManager = AgentConversationBindingManager(
        runtimeRegistry: registry,
      );
      final composition = ProjectThreadsSliceComposition.create(
        providerController: settings,
        globalRuntime: AgentProviderGlobalRuntime(runtimeRegistry: registry),
        bindingManager: bindingManager,
        textCatalog: const FallbackAgentUiTextCatalog(),
      );
      addTearDown(() async {
        composition.store.dispose();
        settings.dispose();
        await bindingManager.close();
        await registry.close();
      });

      composition.store.setSearchTerm(
        projectPath: '/repo',
        searchTerm: 'needle',
      );
      expect(provider.listQueries, isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(provider.listQueries.single.searchTerm, 'needle');
    },
  );
}

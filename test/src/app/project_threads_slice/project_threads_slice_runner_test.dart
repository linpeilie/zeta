import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/app/project_threads_slice/project_threads_slice_composition.dart';
import '../../testing/provider_settings_test_store.dart';

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
      final settings = createProviderSettingsTestStore(
        runtimeRegistry: registry,
        configStore: MemoryAgentProviderConfigStore(
          const AgentProviderSettings(
            providers: <AgentProviderConfig>[defaultCodexAgentProviderConfig],
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
      final settings = createProviderSettingsTestStore(
        runtimeRegistry: registry,
        configStore: MemoryAgentProviderConfigStore(
          const AgentProviderSettings(
            providers: <AgentProviderConfig>[defaultCodexAgentProviderConfig],
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

  test(
    'runner forwards every thread lifecycle effect and settles its Future',
    () async {
      final provider = FakeAgentProvider(
        threadPages: <AgentThreadPage>[
          AgentThreadPage(
            threads: <AgentThreadSummary>[
              for (final id in const <String>[
                'rename',
                'archive',
                'unarchive',
                'delete',
                'fork',
              ])
                agentThread(id: id, projectPath: '/repo', title: '$id thread'),
            ],
            nextCursor: null,
          ),
        ],
      );
      final registry = AgentProviderRuntimeRegistry(
        providerFactory: FakeAgentProviderBundleBuilder.fromFake(provider),
      );
      final settings = createProviderSettingsTestStore(
        runtimeRegistry: registry,
        configStore: MemoryAgentProviderConfigStore(
          const AgentProviderSettings(
            providers: <AgentProviderConfig>[defaultCodexAgentProviderConfig],
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
      await composition.store.renameThread(
        projectPath: '/repo',
        threadId: 'rename',
        name: 'Renamed',
      );
      await composition.store.archiveThread(
        projectPath: '/repo',
        threadId: 'archive',
      );
      await composition.store.unarchiveThread(
        projectPath: '/repo',
        threadId: 'unarchive',
      );
      await composition.store.deleteThread(
        projectPath: '/repo',
        threadId: 'delete',
      );
      final forked = await composition.store.forkThread(
        projectPath: '/repo',
        threadId: 'fork',
      );

      expect(provider.renamedThreads, <({String threadId, String name})>[
        (threadId: 'rename', name: 'Renamed'),
      ]);
      expect(provider.archivedThreads, <String>['archive']);
      expect(provider.unarchivedThreads, <String>['unarchive']);
      expect(provider.deletedThreads, <String>['delete']);
      expect(provider.forkedThreads, <String>['fork']);
      expect(forked?.id, 'forked-fork');
      expect(
        composition.store
            .stateFor('/repo')
            .threads
            .where((thread) => thread.id == 'rename')
            .single
            .title,
        'Renamed',
      );
      final remainingIds = composition.store
          .stateFor('/repo')
          .threads
          .map((thread) => thread.id)
          .toSet();
      expect(
        remainingIds.intersection(const <String>{
          'archive',
          'unarchive',
          'delete',
        }),
        isEmpty,
      );
    },
  );
}

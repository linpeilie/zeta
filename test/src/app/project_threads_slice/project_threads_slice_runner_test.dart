import 'package:zeta/src/app/plugins/agent_provider_manifest.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import '../../testing/agent_provider_implementations.dart';
import 'package:zeta/src/app/project_threads_slice/project_threads_slice_runner.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_slice/project_threads_slice_store.dart';
import 'package:zeta/src/features/project_threads/domain/project_threads_session_snapshot.dart';
import '../../testing/provider_settings_test_store.dart';
import '../../testing/agent_provider_stub_base.dart';
import '../../testing/test_agent_provider_bundle_factory.dart';
import 'package:zeta/src/app/project_threads_slice/project_threads_slice_composition.dart';
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
  group('production Project Threads operations', () {
    test(
      'restores expanded active project and loads first 5 threads',
      () async {
        final provider = _FakeAgentProvider(
          // 聚合后客户端分页：共 10 条时首屏 5 条，游标 agg:5。
          pages: <AgentThreadPage>[_page(_threads(10), nextCursor: null)],
        );
        final controller = _createController(provider);

        controller.restoreSession(
          projectPaths: const <String>['/repo', '/other'],
          activeProjectPath: '/repo',
          snapshot: const ProjectThreadsSessionSnapshot(),
        );
        await _flushAsync();

        final state = controller.stateFor('/repo');
        expect(state.isExpanded, isTrue);
        expect(state.threads, hasLength(5));
        expect(state.nextCursor, 'agg:5');
        expect(controller.stateFor('/other').isExpanded, isFalse);
        expect(provider.listQueries.single.projectPath, '/repo');
      },
    );

    test(
      'loads more with aggregate cursor and appends unique threads',
      () async {
        final provider = _FakeAgentProvider(
          pages: <AgentThreadPage>[
            // 首轮聚合拉取：先 5 条再 10 条，共 15 条缓存后客户端分页。
            _page(_threads(5), nextCursor: 'next'),
            _page(_threads(10, start: 5), nextCursor: null),
            // loadMore 会重新聚合拉取。
            _page(_threads(5), nextCursor: 'next'),
            _page(_threads(10, start: 5), nextCursor: null),
          ],
        );
        final controller = _createController(provider);

        controller.activateProject('/repo');
        await _flushAsync();
        expect(controller.stateFor('/repo').threads, hasLength(5));
        expect(controller.stateFor('/repo').nextCursor, 'agg:5');

        await controller.loadMore('/repo');

        expect(controller.stateFor('/repo').threads, hasLength(15));
        expect(controller.stateFor('/repo').nextCursor, isNull);
      },
    );

    test('keeps cached threads when reload fails', () async {
      final provider = _FakeAgentProvider(
        pages: <AgentThreadPage>[
          _page(_threads(1), nextCursor: null),
          // 失败路径通过 failNextList 抛错；此处不预置第二页。
        ],
      );
      final controller = _createController(provider);

      controller.activateProject('/repo');
      await _flushAsync();
      expect(controller.stateFor('/repo').threads, hasLength(1));

      provider.failNextList = true;
      await controller.loadInitial('/repo');
      await _flushAsync();

      final state = controller.stateFor('/repo');
      expect(state.threads, hasLength(1));
      expect(state.errorMessage, 'Could not load threads');
      expect(state.isLoadingInitial, isFalse);
    });

    test(
      'keeps a current session when an earlier initial load omits it',
      () async {
        final pendingPage = Completer<AgentThreadPage>();
        final provider = _FakeAgentProvider(pages: const <AgentThreadPage>[])
          ..nextListCompleter = pendingPage;
        final controller = _createController(provider);

        final loading = controller.loadInitial('/repo');
        controller.registerSession(
          '/repo',
          const AgentSession(
            id: 'current-thread',
            providerId: grokAgentProviderId,
            title: 'Current Grok thread',
          ),
          preview: '刚刚活跃的会话',
          markRunning: true,
        );
        pendingPage.complete(
          const AgentThreadPage(
            threads: <AgentThreadSummary>[],
            nextCursor: null,
          ),
        );
        await loading;

        final state = controller.stateFor('/repo');
        expect(state.threads.map((thread) => thread.id), <String>[
          'current-thread',
        ]);
        expect(state.selectedThreadId, 'current-thread');
        expect(state.runningThreadIds, <String>{'current-thread'});
        expect(state.hasLoaded, isTrue);
      },
    );

    test(
      'keeps local provisional title when Grok list returns same id without title',
      () async {
        // Grok 新 session 乐观写入 title/preview 后，首屏 list 可能先返回无
        // generated_title 的弱摘要；不得冲掉本地展示名。
        final provider = _FakeAgentProvider(
          pages: <AgentThreadPage>[
            _page(<AgentThreadSummary>[
              AgentThreadSummary(
                id: 'grok-new',
                providerId: grokAgentProviderId,
                projectPath: '/repo',
                title: null,
                preview: 'grok-new',
                createdAt: DateTime.utc(2026, 8, 1),
                updatedAt: DateTime.utc(2026, 8, 1),
                recencyAt: DateTime.utc(2026, 8, 1),
                status: AgentThreadRuntimeStatus.idle,
              ),
            ], nextCursor: null),
          ],
        );
        final controller = _createController(provider);

        controller.registerSession(
          '/repo',
          const AgentSession(id: 'grok-new', providerId: grokAgentProviderId),
          preview: '帮我解释这段代码',
        );
        controller.updateThreadTitle(
          projectPath: '/repo',
          threadId: 'grok-new',
          title: '帮我解释这段代码',
        );
        expect(controller.stateFor('/repo').threads.single.title, '帮我解释这段代码');
        expect(controller.stateFor('/repo').threads.single.preview, '帮我解释这段代码');

        await controller.loadInitial('/repo');
        await _flushAsync();

        final thread = controller.stateFor('/repo').threads.single;
        expect(thread.id, 'grok-new');
        expect(thread.title, '帮我解释这段代码');
        expect(thread.preview, '帮我解释这段代码');
        expect(thread.displayName, '帮我解释这段代码');
      },
    );

    test(
      'ignores duplicate loads while a project is already loading',
      () async {
        final provider = _FakeAgentProvider(
          pages: <AgentThreadPage>[_page(_threads(1), nextCursor: null)],
        );
        final controller = _createController(provider);

        final firstLoad = controller.loadInitial('/repo');
        final secondLoad = controller.loadInitial('/repo');
        await Future.wait(<Future<void>>[firstLoad, secondLoad]);

        expect(provider.listQueries, hasLength(1));
      },
    );

    test('sorts all provider threads by global recency', () async {
      final codex = _FakeAgentProvider(
        config: defaultCodexAgentProviderConfig,
        pages: <AgentThreadPage>[
          _page(<AgentThreadSummary>[
            _thread(
              id: 'codex-new',
              providerId: defaultAgentProviderId,
              updatedAt: DateTime.utc(2026, 6, 1),
            ),
            _thread(
              id: 'codex-middle',
              providerId: defaultAgentProviderId,
              updatedAt: DateTime.utc(2026, 5, 1),
            ),
          ], nextCursor: null),
        ],
      );
      final grok = _FakeAgentProvider(
        config: defaultGrokAgentProviderConfig,
        pages: <AgentThreadPage>[
          _page(<AgentThreadSummary>[
            _thread(
              id: 'grok-old',
              providerId: grokAgentProviderId,
              updatedAt: DateTime.utc(2026, 1, 1),
            ),
          ], nextCursor: null),
        ],
      );
      final controller = _createMultiProviderController(
        codex: codex,
        grok: grok,
      );

      controller.activateProject('/repo');
      await _flushAsync();

      final ids = controller
          .stateFor('/repo')
          .threads
          .map((thread) => thread.id)
          .toList();
      expect(ids, <String>['codex-new', 'codex-middle', 'grok-old']);
      expect(codex.listQueries, isNotEmpty);
      expect(grok.listQueries, isNotEmpty);
    });

    test('passes archived and searchTerm to listThreads', () async {
      final provider = _FakeAgentProvider(
        pages: <AgentThreadPage>[_page(_threads(1), nextCursor: null)],
      );
      final controller = _createController(provider);

      controller.activateProject('/repo');
      await _flushAsync();
      await controller.setArchivedView(projectPath: '/repo', archived: true);
      await _flushAsync();

      expect(provider.listQueries.last.archived, isTrue);
      expect(controller.stateFor('/repo').archived, isTrue);

      controller.setSearchTerm(projectPath: '/repo', searchTerm: 'foo');
      await Future<void>.delayed(projectThreadSearchDebounce);
      await _flushAsync();

      expect(provider.listQueries.last.searchTerm, 'foo');
      expect(controller.stateFor('/repo').searchTerm, 'foo');
    });

    test(
      'renames thread through global runtime and updates cached title',
      () async {
        final provider = _FakeAgentProvider(
          pages: <AgentThreadPage>[_page(_threads(1), nextCursor: null)],
        );
        final controller = _createController(provider);
        controller.activateProject('/repo');
        await _flushAsync();

        await controller.renameThread(
          projectPath: '/repo',
          threadId: 'thread-0',
          name: 'Renamed',
        );
        expect(provider.renamedThreads.single.name, 'Renamed');
        expect(controller.stateFor('/repo').threads.single.title, 'Renamed');
      },
    );

    test('removes archived thread and notifies active clear', () async {
      final provider = _FakeAgentProvider(
        pages: <AgentThreadPage>[_page(_threads(1), nextCursor: null)],
      );
      final cleared = <(String, String)>[];
      final controller = _createController(provider);
      controller.onActiveThreadCleared = (projectPath, threadId) {
        cleared.add((projectPath, threadId));
      };
      controller.activateProject('/repo');
      await _flushAsync();
      controller.selectThreadId('/repo', 'thread-0');

      await controller.archiveThread(
        projectPath: '/repo',
        threadId: 'thread-0',
      );
      expect(provider.archivedThreads, <String>['thread-0']);
      expect(controller.stateFor('/repo').threads, isEmpty);
      expect(cleared, <(String, String)>[('/repo', 'thread-0')]);
    });

    test('caches provider ownership when a session is created', () async {
      final codex = _FakeAgentProvider(pages: []);
      final grok = _FakeAgentProvider(
        pages: [],
        config: defaultGrokAgentProviderConfig,
      );
      final controller = _createMultiProviderController(
        codex: codex,
        grok: grok,
      );

      controller.registerSession(
        '/repo',
        const AgentSession(
          id: 'new-thread',
          providerId: grokAgentProviderId,
          title: 'New Grok thread',
        ),
      );

      final state = controller.stateFor('/repo');
      expect(state.selectedThreadId, 'new-thread');
      expect(state.threads, hasLength(1));
      expect(state.threads.single.providerId, grokAgentProviderId);
      expect(
        controller
            .sessionSnapshot
            .cachedThreadsByProject['/repo']
            ?.single
            .providerId,
        grokAgentProviderId,
      );
      await controller.renameThread(
        projectPath: '/repo',
        threadId: 'new-thread',
        name: 'Renamed Grok',
      );
      expect(grok.renamedThreads, [
        (threadId: 'new-thread', name: 'Renamed Grok'),
      ]);
      expect(codex.renamedThreads, isEmpty);
    });

    test(
      'fork makes provider default source explicit when no pane is open',
      () async {
        final provider = _FakeAgentProvider(
          pages: const <AgentThreadPage>[],
          config: defaultCodexAgentProviderConfig.withPermissionPreference(
            ':workspace',
          ),
        );
        final controller = _createController(provider);
        controller.registerSession(
          '/repo',
          const AgentSession(
            id: 'source-thread',
            providerId: defaultAgentProviderId,
          ),
        );

        final session = await controller.forkThread(
          projectPath: '/repo',
          threadId: 'source-thread',
        );

        expect(session?.id, 'forked-source-thread');
        expect(provider.forkPermissionSnapshots, hasLength(1));
        expect(
          provider.forkPermissionSnapshots.single.source,
          AgentPermissionRequestSource.providerDefault,
        );
        expect(
          provider.forkPermissionSnapshots.single.selection?.optionId,
          ':workspace',
        );
      },
    );

    test('fork without Binding uses the persisted provider default', () async {
      final provider = _FakeAgentProvider(
        pages: const <AgentThreadPage>[],
        config: defaultCodexAgentProviderConfig.withPermissionPreference(
          ':workspace',
        ),
      );
      final registry = AgentProviderRuntimeRegistry(
        providerFactory: _FakeAgentProviderFactory(provider),
      );
      final providerController = createProviderSettingsTestStore(
        runtimeRegistry: registry,
        configStore: MemoryAgentProviderConfigStore(
          AgentProviderSettings(
            providers: <AgentProviderConfig>[provider.config],
            activeProviderId: provider.config.id,
          ),
        ),
      );
      final bindingManager = AgentConversationBindingManager(
        runtimeRegistry: registry,
      );
      final controller = ProjectThreadsSliceComposition.create(
        providerController: providerController,
        globalRuntime: AgentProviderGlobalRuntime(runtimeRegistry: registry),
        textCatalog: const FallbackAgentUiTextCatalog(),
        bindingManager: bindingManager,
      ).store;
      addTearDown(() async {
        controller.dispose();
        providerController.dispose();
        await bindingManager.close();
        await registry.close();
      });
      controller.registerSession(
        '/repo',
        const AgentSession(
          id: 'source-thread',
          providerId: defaultAgentProviderId,
        ),
      );

      await controller.forkThread(
        projectPath: '/repo',
        threadId: 'source-thread',
      );

      expect(provider.forkPermissionSnapshots, hasLength(1));
      expect(
        provider.forkPermissionSnapshots.single.source,
        AgentPermissionRequestSource.providerDefault,
      );
      expect(
        provider.forkPermissionSnapshots.single.selection?.optionId,
        ':workspace',
      );
    });

    test('fork 优先使用已存在 Binding 的 thread 权限快照', () async {
      final provider = _FakeAgentProvider(
        pages: const <AgentThreadPage>[],
        config: defaultCodexAgentProviderConfig.withPermissionPreference(
          ':workspace',
        ),
      );
      final registry = AgentProviderRuntimeRegistry(
        providerFactory: _FakeAgentProviderFactory(provider),
      );
      final providerController = createProviderSettingsTestStore(
        runtimeRegistry: registry,
        configStore: MemoryAgentProviderConfigStore(
          AgentProviderSettings(
            providers: <AgentProviderConfig>[provider.config],
            activeProviderId: provider.config.id,
          ),
        ),
      );
      final bindingManager = AgentConversationBindingManager(
        runtimeRegistry: registry,
      );
      final bindingLease = bindingManager.acquireThread(
        providerId: defaultAgentProviderId,
        threadId: 'source-thread',
        resolveConfig: (_) => provider.config,
        persistPermissionOptionId: (_) async {},
      );
      await bindingLease.binding.permissions.applyEffectiveSelection(
        const AgentPermissionSelection(optionId: ':read-only'),
        syncPort: false,
      );
      final controller = ProjectThreadsSliceComposition.create(
        providerController: providerController,
        globalRuntime: AgentProviderGlobalRuntime(runtimeRegistry: registry),
        bindingManager: bindingManager,
        textCatalog: const FallbackAgentUiTextCatalog(),
      ).store;
      addTearDown(() async {
        controller.dispose();
        await bindingLease.release();
        await bindingManager.close();
        providerController.dispose();
        await registry.close();
      });
      controller.registerSession(
        '/repo',
        const AgentSession(
          id: 'source-thread',
          providerId: defaultAgentProviderId,
        ),
      );

      await controller.forkThread(
        projectPath: '/repo',
        threadId: 'source-thread',
      );

      expect(provider.forkPermissionSnapshots, hasLength(1));
      expect(
        provider.forkPermissionSnapshots.single.source,
        AgentPermissionRequestSource.threadEffective,
      );
      expect(
        provider.forkPermissionSnapshots.single.selection?.optionId,
        ':read-only',
      );
    });
  });
  test(
    'page ingress seeds runtime mapping without clearing an outside mapping',
    () async {
      final provider = _FakeAgentProvider(
        pages: [_page(_threads(1), nextCursor: null)],
      );
      final store = _createController(provider);
      store.registerThreadMapping('/repo', 'outside');
      await store.loadInitial('/repo');
      store.setThreadRunning('thread-0', isRunning: true);
      store.setThreadRunning('outside', isRunning: true);
      expect(store.stateFor('/repo').runningThreadIds, {'thread-0', 'outside'});
    },
  );

  test(
    'restore indexes cached and selected threads through the owner',
    () async {
      final provider = _FakeAgentProvider(pages: [_page([], nextCursor: null)]);
      final store = _createController(provider);
      store.restoreSession(
        projectPaths: ['/repo'],
        activeProjectPath: '/repo',
        snapshot: ProjectThreadsSessionSnapshot(
          cachedThreadsByProject: {'/repo': _threads(1)},
          selectedThreadIdsByProject: {'/repo': 'selected-outside'},
        ),
      );
      store.setThreadRunning('thread-0', isRunning: true);
      store.setThreadRunning('selected-outside', isRunning: true);
      await _flushAsync();
      expect(store.stateFor('/repo').runningThreadIds, {
        'thread-0',
        'selected-outside',
      });
      expect(store.stateFor('/repo').threads.single.id, 'thread-0');
    },
  );

  test(
    'retention cancels removed project search and rejects its pending page',
    () async {
      final page = Completer<AgentThreadPage>();
      final provider = _FakeAgentProvider(pages: [])..nextListCompleter = page;
      final store = _createController(provider);
      final loading = store.loadInitial('/a');
      await _flushAsync();
      store.setSearchTerm(projectPath: '/a', searchTerm: 'pending');
      store.registerSession(
        '/b',
        const AgentSession(id: 'b', providerId: defaultAgentProviderId),
        markRunning: true,
      );
      store.retainProjects(['/b']);
      page.complete(_page(_threads(1), nextCursor: null));
      await loading;
      await Future<void>.delayed(projectThreadSearchDebounce);
      store.setThreadRunning('thread-0', isRunning: true);
      expect(store.states.keys, ['/b']);
      expect(store.stateFor('/b').runningThreadIds, {'b'});
      expect(provider.listQueries, hasLength(1));
    },
  );

  test(
    'dispose settles pending page and cancels search without late state publication',
    () async {
      final page = Completer<AgentThreadPage>();
      final provider = _FakeAgentProvider(pages: [])..nextListCompleter = page;
      final store = _createController(provider);
      final loading = store.loadInitial('/repo');
      await _flushAsync();
      store.setSearchTerm(projectPath: '/repo', searchTerm: 'pending');
      final before = store.state;
      store.dispose();
      await loading;
      page.complete(_page(_threads(1), nextCursor: null));
      await Future<void>.delayed(projectThreadSearchDebounce);
      await _flushAsync();
      expect(store.state, same(before));
      expect(provider.listQueries, hasLength(1));
      expect(store.staleResultCount, 0);
    },
  );

  test(
    'dispose drops late archive callback and fork result after settling callers',
    () async {
      final archive = Completer<void>();
      final fork = Completer<AgentSession>();
      final provider = _FakeAgentProvider(pages: [])
        ..pendingArchive = archive
        ..pendingFork = fork;
      final store = _createController(provider);
      for (final id in ['fork', 'archive']) {
        store.registerSession(
          '/repo',
          AgentSession(id: id, providerId: defaultAgentProviderId),
        );
      }
      var callbacks = 0;
      store.onActiveThreadCleared = (_, _) => callbacks++;
      final archiving = store.archiveThread(
        projectPath: '/repo',
        threadId: 'archive',
      );
      final forking = store.forkThread(projectPath: '/repo', threadId: 'fork');
      await _flushAsync();
      expect(provider.archivedThreads, ['archive']);
      expect(provider.forkedThreads, ['fork']);
      final before = store.state;
      store.dispose();
      await archiving;
      expect(await forking, isNull);
      archive.complete();
      fork.complete(
        const AgentSession(id: 'late', providerId: defaultAgentProviderId),
      );
      await _flushAsync();
      expect(store.state, same(before));
      expect(callbacks, 0);
      expect(store.staleResultCount, 0);
    },
  );

  test(
    'owner closure during removal publication suppresses external callback',
    () async {
      final provider = _FakeAgentProvider(pages: []);
      final store = _createController(provider);
      store.registerSession(
        '/repo',
        const AgentSession(id: 'selected', providerId: defaultAgentProviderId),
      );
      var callbacks = 0;
      store.onActiveThreadCleared = (_, _) => callbacks++;
      store.subscribe(() {
        if (store.threadFor('/repo', 'selected') == null) store.dispose();
      });
      await store.archiveThread(projectPath: '/repo', threadId: 'selected');
      expect(store.stateFor('/repo').threads, isEmpty);
      expect(callbacks, 0);
    },
  );

  test(
    'remote failures settle the Store Future with the original error',
    () async {
      final failure = StateError('rename rejected');
      final provider = _FakeAgentProvider(pages: [])..renameFailure = failure;
      final store = _createController(provider);
      store.registerSession(
        '/repo',
        const AgentSession(id: 'thread', providerId: defaultAgentProviderId),
      );
      await expectLater(
        store.renameThread(
          projectPath: '/repo',
          threadId: 'thread',
          name: 'next',
        ),
        throwsA(same(failure)),
      );
      // Existing optimistic title and error behavior remain intact.
      expect(store.threadFor('/repo', 'thread')?.title, 'next');
      expect(store.staleResultCount, 0);
    },
  );

  test(
    'missing summary does not guess the active Provider for remote work',
    () async {
      final provider = _FakeAgentProvider(pages: []);
      final store = _createController(provider);
      store.registerThreadMapping('/repo', 'outside');
      await store.renameThread(
        projectPath: '/repo',
        threadId: 'outside',
        name: 'name',
      );
      expect(
        await store.forkThread(projectPath: '/repo', threadId: 'missing'),
        isNull,
      );
      expect(provider.renamedThreads, isEmpty);
      expect(provider.forkedThreads, isEmpty);
    },
  );
}

ProjectThreadsSliceStore _createController(_FakeAgentProvider provider) {
  // 单 provider 配置，避免默认 Codex+Grok 下同一 fake 被聚合调用两次。
  final registry = AgentProviderRuntimeRegistry(
    providerFactory: _FakeAgentProviderFactory(provider),
  );
  final providerController = createProviderSettingsTestStore(
    runtimeRegistry: registry,
    configStore: MemoryAgentProviderConfigStore(
      AgentProviderSettings(
        providers: <AgentProviderConfig>[provider.config],
        activeProviderId: provider.config.id,
      ),
    ),
  );
  final bindingManager = AgentConversationBindingManager(
    runtimeRegistry: registry,
  );
  final controller = ProjectThreadsSliceComposition.create(
    providerController: providerController,
    globalRuntime: AgentProviderGlobalRuntime(runtimeRegistry: registry),
    textCatalog: const FallbackAgentUiTextCatalog(),
    bindingManager: bindingManager,
  ).store;
  addTearDown(() async {
    controller.dispose();
    providerController.dispose();
    await bindingManager.close();
    await registry.close();
  });
  return controller;
}

ProjectThreadsSliceStore _createMultiProviderController({
  required _FakeAgentProvider codex,
  required _FakeAgentProvider grok,
  List<String>? createdProviderIds,
}) {
  final registry = AgentProviderRuntimeRegistry(
    providerFactory: _MultiAgentProviderFactory(
      codex: codex,
      grok: grok,
      createdProviderIds: createdProviderIds,
    ),
  );
  final providerController = createProviderSettingsTestStore(
    runtimeRegistry: registry,
    configStore: MemoryAgentProviderConfigStore(
      AgentProviderSettings(
        providers: <AgentProviderConfig>[
          defaultCodexAgentProviderConfig,
          defaultGrokAgentProviderConfig,
        ],
        activeProviderId: defaultAgentProviderId,
      ),
    ),
  );
  final bindingManager = AgentConversationBindingManager(
    runtimeRegistry: registry,
  );
  final controller = ProjectThreadsSliceComposition.create(
    providerController: providerController,
    globalRuntime: AgentProviderGlobalRuntime(runtimeRegistry: registry),
    textCatalog: const FallbackAgentUiTextCatalog(),
    bindingManager: bindingManager,
  ).store;
  addTearDown(() async {
    controller.dispose();
    providerController.dispose();
    await bindingManager.close();
    await registry.close();
  });
  return controller;
}

AgentThreadPage _page(
  List<AgentThreadSummary> threads, {
  required String? nextCursor,
}) {
  return AgentThreadPage(threads: threads, nextCursor: nextCursor);
}

List<AgentThreadSummary> _threads(int count, {int start = 0}) {
  return <AgentThreadSummary>[
    for (var index = start; index < start + count; index += 1)
      _thread(
        id: 'thread-$index',
        providerId: defaultAgentProviderId,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(index),
        title: 'Thread $index',
        preview: 'Preview $index',
      ),
  ];
}

AgentThreadSummary _thread({
  required String id,
  required String providerId,
  required DateTime updatedAt,
  String title = 'Thread',
  String preview = 'Preview',
}) {
  return AgentThreadSummary(
    id: id,
    providerId: providerId,
    projectPath: '/repo',
    title: title,
    preview: preview,
    createdAt: updatedAt,
    updatedAt: updatedAt,
    recencyAt: updatedAt,
    status: AgentThreadRuntimeStatus.idle,
  );
}

Future<void> _flushAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _FakeAgentProviderFactory with TestAgentProviderBundleFactory {
  _FakeAgentProviderFactory(this.provider);

  final _FakeAgentProvider provider;

  @override
  Object create(AgentProviderConfig config) => provider;
}

class _MultiAgentProviderFactory with TestAgentProviderBundleFactory {
  _MultiAgentProviderFactory({
    required this.codex,
    required this.grok,
    List<String>? createdProviderIds,
  }) : createdProviderIds = createdProviderIds ?? <String>[];

  final _FakeAgentProvider codex;
  final _FakeAgentProvider grok;
  final List<String> createdProviderIds;

  @override
  Object create(AgentProviderConfig config) {
    createdProviderIds.add(config.id);
    return switch (config.id) {
      grokAgentProviderId => grok,
      _ => codex,
    };
  }
}

class _FakeAgentProvider
    with AgentProviderThreadLifecycleStub
    implements
        AgentRuntimePort,
        AgentConversationPort,
        AgentThreadCatalogPort,
        AgentLocalThreadListPort {
  _FakeAgentProvider({
    required List<AgentThreadPage> pages,
    this.config = defaultCodexAgentProviderConfig,
  }) : _pages = List<AgentThreadPage>.from(pages);

  final List<AgentThreadPage> _pages;
  final List<AgentThreadListQuery> listQueries = <AgentThreadListQuery>[];
  final StreamController<AgentEvent> _events =
      StreamController<AgentEvent>.broadcast();
  bool failNextList = false;
  Completer<void>? pendingArchive;
  Completer<AgentSession>? pendingFork;
  Object? renameFailure;

  @override
  Future<void> renameThread({
    required String threadId,
    required String name,
  }) async {
    await super.renameThread(threadId: threadId, name: name);
    if (renameFailure case final failure?) throw failure;
  }

  @override
  Future<void> archiveThread(String threadId) async {
    await super.archiveThread(threadId);
    await pendingArchive?.future;
  }

  @override
  Future<AgentSession> forkThread({
    required String threadId,
    required AgentContext context,
    AgentForkBoundary boundary = const AgentForkCurrentHead(),
    AgentPermissionRequestSnapshot permissionSnapshot =
        const AgentPermissionRequestSnapshot.providerFallback(),
  }) async {
    final session = await super.forkThread(
      threadId: threadId,
      context: context,
      boundary: boundary,
      permissionSnapshot: permissionSnapshot,
    );
    return pendingFork == null ? session : await pendingFork!.future;
  }

  Completer<AgentThreadPage>? nextListCompleter;
  final List<String> removedLocalThreads = <String>[];

  @override
  final AgentProviderConfig config;

  @override
  AgentProviderCapabilities get capabilities => codexStaticCapabilities;

  @override
  Stream<AgentEvent> get events => _events.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<AgentThreadPage> listThreads({
    required AgentThreadListQuery query,
  }) async {
    listQueries.add(query);
    if (failNextList) {
      failNextList = false;
      throw StateError('list failed');
    }
    final completer = nextListCompleter;
    if (completer != null) {
      nextListCompleter = null;
      return completer.future;
    }
    return _pages.isEmpty
        ? const AgentThreadPage(
            threads: <AgentThreadSummary>[],
            nextCursor: null,
          )
        : _pages.removeAt(0);
  }

  @override
  Future<AgentThreadHistorySnapshot> readThreadHistory({
    required String threadId,
    String? sessionPath,
    String? projectPath,
  }) async {
    return AgentThreadHistorySnapshot(
      threadId: threadId,
      turns: const <AgentHistoryTurn>[],
    );
  }

  Future<void> unsubscribeThread(String threadId) async {}

  @override
  Future<AgentSession> startSession({
    required AgentContext context,
    AgentPermissionRequestSnapshot permissionSnapshot =
        const AgentPermissionRequestSnapshot.providerFallback(),
  }) async {
    return const AgentSession(
      id: 'thread-0',
      providerId: defaultAgentProviderId,
    );
  }

  @override
  Future<AgentSession> resumeSession(
    String sessionId, {
    required AgentContext context,
    AgentPermissionRequestSnapshot permissionSnapshot =
        const AgentPermissionRequestSnapshot.providerFallback(),
  }) async {
    return AgentSession(id: sessionId, providerId: defaultAgentProviderId);
  }

  @override
  Future<AgentTurn> sendMessage({
    required AgentSession session,
    required AgentContext context,
    String? message,
    List<AgentUserInput>? inputs,
    String? clientUserMessageId,
    AgentTurnConfiguration configuration = const AgentTurnConfiguration(),
  }) async {
    return AgentTurn(id: 'turn-1', sessionId: session.id);
  }

  Future<void> steerTurn({
    required AgentSession session,
    required String expectedTurnId,
    required AgentContext context,
    String? message,
    List<AgentUserInput>? inputs,
    String? clientUserMessageId,
  }) async {}

  @override
  Future<void> cancelTurn(AgentTurn turn) async {}

  Future<AgentModelList> listModels({
    int limit = 20,
    bool includeHidden = false,
    bool forceRefresh = false,
  }) async {
    return const AgentModelList(models: <AgentModelInfo>[]);
  }

  @override
  void updateModelSelection(AgentModelSelection selection) {}

  Future<void> approveGuardianDeniedAction({
    required String threadId,
    required Object event,
  }) async {}

  Future<void> respondToPermission(AgentPermissionDecision decision) async {}

  @override
  Future<void> removeThreadFromList(String threadId) async {
    removedLocalThreads.add(threadId);
  }

  @override
  Future<void> dispose() async {
    await _events.close();
  }

  void emit(AgentEvent event) {
    _events.add(event);
  }
}

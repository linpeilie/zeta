import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta/src/app/agent_management_slice/workspace_agent_runtime_fact_source.dart';
import '../../testing/conversation_workspace_test_container.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_runtime_aggregation.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_runtime_facts.dart';

import '../../testing/provider_settings_test_store.dart';
import '../../testing/ide_test_harness.dart';
import '../../testing/callback_workspace_file_corpus_port.dart';
import '../../testing/fake_agent_frame_scheduler.dart';

void main() {
  test(
    'all providers and background entries; promotion keeps the observation key',
    () async {
      final h = await _Harness.create();
      final a = await h.draft('codex');
      final b = await h.draft('grok');
      final before = h.fact(b).observationKey;
      expect(h.summary('grok').state, AgentRuntimeState.notRunning);
      expect(
        h.summary('grok').connectedRuntimeCount,
        0,
      ); // global prewarm excluded
      await b.controller.sendMessage('work');
      await h.flush();
      expect(h.fact(b).observationKey, same(before));
      expect(b.binding.threadId, isNotNull);
      expect(h.summary('grok').activeTurnCount, 1);
      expect(h.summary('codex').connectedRuntimeCount, 0);
      h.workspace.selectEntry(a.entryId);
      h.workspace.enterProjectHome();
      expect(h.summary('grok').activeTurnCount, 1);
      final disabledPolicy = aggregateManagementRuntime(h.source.current, {
        'grok': false,
      })['grok']!;
      expect(disabledPolicy.enabled, isFalse);
      expect(disabledPolicy.activeTurnCount, 1);
      expect(disabledPolicy.connectedRuntimeCount, 1);
      await h.settings.store.setProviderEnabled('grok', false);
      await h.flush();
      expect(
        b.binding.hasRuntime,
        isFalse,
      ); // real settings invalidates the runtime
      expect(h.summary('grok').state, AgentRuntimeState.disabled);
    },
  );

  test(
    'global catalog failure before any session attempt is not a session startup error',
    () async {
      final h = await _Harness.create();
      h.factory.failure = StateError('catalog failed');
      final a = await h.draft('grok');
      expect(a.controller.runtimeObservationAttemptEpoch, 0);
      expect(a.binding.hasRuntime, isFalse);
      expect(h.summary('grok').state, AgentRuntimeState.notRunning);
      expect(h.summary('grok').hasErrors, isFalse);
    },
  );

  test(
    'same provider concurrent scopes stay distinct; ready and short RPC are not turns',
    () async {
      final h = await _Harness.create();
      final a = await h.draft('codex');
      await a.controller.sendMessage('first');
      await h.flush();
      final b = await h.draft('codex');
      await b.controller.sendMessage('second');
      await h.flush();
      expect(h.summary('codex').connectedRuntimeCount, 2);
      expect(h.summary('codex').activeTurnCount, 2);
      h
          .provider(a)
          .emit(
            AgentTurnCompletedEvent(
              sessionId: a.controller.sessionId!,
              turnId: 'turn-1',
            ),
          );
      await h.flush();
      expect(h.summary('codex').activeTurnCount, 1);
      final gate = Completer<void>();
      final rpc = a.binding.runCurrent((_) => gate.future);
      expect(a.binding.runtimeSnapshot!.activeOperationCount, greaterThan(0));
      expect(h.summary('codex').activeTurnCount, 1);
      gate.complete();
      await rpc;
      expect(h.fact(a).connected, isTrue);
      expect(h.fact(a).activeTurn, isFalse);
    },
  );

  test(
    'cleared identity suppresses stale frame; reopen same key ignores old events',
    () async {
      final h = await _Harness.create();
      final a = await h.draft('grok');
      await a.controller.sendMessage('first');
      await h.flush();
      final old = h.provider(a);
      final oldKey = h.fact(a).observationKey;
      final oldIdentity = h.fact(a).runtimeIdentity;
      await h.frames.single.runInBuildPhaseAsync(a.binding.invalidateRuntime);
      expect(h.summary('grok').activeTurnCount, 0);
      expect(h.summary('grok').connectedRuntimeCount, 0);
      await conversationWorkspaceTestLifetimes(
        h.workspace,
      ).closeEntry(a.ownerKey);
      final b = await h.thread(
        'grok',
        'thread-1',
        status: AgentThreadRuntimeStatus.active,
      );
      expect(h.fact(b).observationKey, isNot(same(oldKey)));
      expect(
        h.summary('grok').activeTurnCount,
        0,
      ); // historical active does not connect
      await b.controller.sendMessage('replacement');
      await h.flush();
      expect(h.fact(b).runtimeIdentity, isNot(oldIdentity));
      old.emit(
        const AgentStatusEvent(
          AgentProviderStatus(
            message: '',
            state: AgentProviderConnectionState.error,
          ),
        ),
      );
      await h.flush();
      expect(h.summary('grok').hasErrors, isFalse);
      expect(h.summary('grok').activeTurnCount, 1);
      // Late reap candidate from the removed generation cannot clear the replacement.
      expect(
        await b.binding.reapIfIdle(
          expectedIdentity: oldIdentity!,
          idleCutoff: DateTime.now(),
        ),
        isFalse,
      );
    },
  );

  for (final unavailable in [false, true]) {
    test(
      'startup ${unavailable ? 'unavailable' : 'error'} stays in its attempt and clears before retry',
      () async {
        final h = await _Harness.create();
        final a = await h.draft('grok');
        h.factory.failure = unavailable
            ? const ProcessException('fake', [], 'missing')
            : StateError('startup failed');
        await a.controller.sendMessage('fail');
        await h.flush();
        expect(h.fact(a).runtimeIdentity, isNull);
        expect(
          h.summary('grok').state,
          unavailable ? AgentRuntimeState.unavailable : AgentRuntimeState.error,
        );
        final attempt = a.controller.runtimeObservationAttemptEpoch;
        final gate = Completer<void>();
        h.factory.initializationGate = gate;
        final retry = a.controller.sendMessage('retry');
        await h.flush();
        expect(a.controller.runtimeObservationAttemptEpoch, attempt + 1);
        expect(h.summary('grok').state, AgentRuntimeState.starting);
        expect(h.summary('grok').errorBindingCount, 0);
        expect(h.summary('grok').unavailableBindingCount, 0);
        gate.complete();
        await retry;
        await h.flush();
        expect(h.summary('grok').activeTurnCount, 1);
        expect(h.summary('grok').hasErrors, isFalse);
      },
    );
  }

  test(
    'connection-only errors and waiting facts publish without reading history or payload',
    () async {
      final h = await _Harness.create();
      final a = await h.draft('grok');
      await a.controller.sendMessage('work');
      await h.flush();
      final provider = h.provider(a);
      provider.emit(
        AgentTurnCompletedEvent(
          sessionId: a.controller.sessionId!,
          turnId: 'turn-1',
        ),
      );
      await h.flush();
      expect(h.summary('grok').state, AgentRuntimeState.idle);
      provider.emit(
        const AgentStatusEvent(
          AgentProviderStatus(
            message: '',
            state: AgentProviderConnectionState.error,
          ),
        ),
      );
      await h.flush();
      expect(h.summary('grok').state, AgentRuntimeState.error);
      provider.emit(
        const AgentStatusEvent(
          AgentProviderStatus(
            message: '',
            state: AgentProviderConnectionState.ready,
          ),
        ),
      );
      await h.flush();
      expect(h.summary('grok').hasErrors, isFalse);
      provider.emit(
        AgentThreadStatusChangedEvent(
          threadId: a.controller.sessionId!,
          status: AgentThreadRuntimeStatus.active,
          waitingOnApproval: true,
          waitingOnUserInput: true,
        ),
      );
      await h.flush();
      expect(h.fact(a).waitingOnApproval, isTrue);
      expect(h.fact(a).waitingOnUserInput, isTrue);
      expect(h.summary('grok').activeTurnCount, 1);
    },
  );

  test('connection epoch change never relabels old live facts', () async {
    final h = await _Harness.create();
    final a = await h.draft('grok');
    await a.controller.sendMessage('work');
    await h.flush();
    final provider = h.provider(a);
    provider.epoch++;
    await a.binding.runCurrent((_) async {});
    await h.flush();
    expect(h.summary('grok').activeTurnCount, 0);
    expect(h.summary('grok').unobservedTurnRuntimeCount, 1);
    expect(h.summary('grok').connectedRuntimeCount, 1);
  });

  test(
    'orphan runtime reports connection and unknown turn; source close is observational',
    () async {
      final h = await _Harness.create();
      final a = await h.draft('grok');
      await a.controller.sendMessage('work');
      await h.flush();
      final key = h.fact(a).observationKey;
      final provider = h.provider(a);
      await conversationWorkspaceTestLifetimes(
        h.workspace,
      ).closeEntry(a.ownerKey);
      expect(h.source.current.bindings.single.observationKey, same(key));
      expect(h.summary('grok').connectedRuntimeCount, 1);
      expect(h.summary('grok').unobservedTurnRuntimeCount, 1);
      expect(h.summary('grok').activeTurnCount, 0);
      provider.lifecycle = AgentProviderLifecycleState.closing;
      provider.emit(
        const AgentStatusEvent(
          AgentProviderStatus(
            message: '',
            state: AgentProviderConnectionState.idle,
          ),
        ),
      );
      await h.flush();
      expect(h.summary('grok').connectedRuntimeCount, 0);
      var publications = 0;
      final unsubscribe = h.source.subscribe((_) => publications++);
      expect(publications, 0); // subscribe does not call current
      final created = h.factory.created.length;
      final disposed = h.factory.created.fold(
        0,
        (sum, p) => sum + p.disposeCalls,
      );
      h.source.start();
      h.source.close();
      h.source.close();
      unsubscribe();
      expect(h.factory.created.length, created);
      expect(
        h.factory.created.fold(0, (sum, p) => sum + p.disposeCalls),
        disposed,
      );
      expect(a.binding.hasRuntime, isTrue);
      expect(h.source.start, throwsStateError);
      expect(() => h.source.subscribe((_) {}), throwsStateError);
      provider.emit(
        const AgentStatusEvent(
          AgentProviderStatus(
            message: '',
            state: AgentProviderConnectionState.error,
          ),
        ),
      );
      await h.flush();
      expect(publications, 0);
    },
  );

  test(
    'structural equality suppresses navigation; reentrant membership reconciles again',
    () async {
      final h = await _Harness.create();
      final a = await h.draft('grok');
      var publications = 0;
      final unsubscribe = h.source.subscribe((_) {
        publications++;
        if (publications == 1) {
          h.workspace.ensureDraftEntry(
            callbacks: conversationWorkspaceTestCallbacks(h.workspace),
            projectPath: '/other',
            providerId: 'codex',
          );
        }
      });
      h.workspace.selectEntry(a.entryId);
      h.workspace.enterProjectHome();
      expect(publications, 0);
      await a.controller.sendMessage('work');
      await h.flush();
      expect(
        h.source.current.bindings.map((f) => f.providerId),
        containsAll(['codex', 'grok']),
      );
      unsubscribe();
      final before = publications;
      h.workspace.enterProjectHome();
      expect(publications, before);
    },
  );
}

final class _Harness {
  _Harness() {
    registry = AgentProviderRuntimeRegistry(providerFactory: factory);
    settings = createProviderSettingsTestComposition(
      configStore: MemoryAgentProviderConfigStore(),
      runtimeRegistry: registry,
    );
    bindingManager = AgentConversationBindingManager(runtimeRegistry: registry)
      ..start();
    workspace = createConversationWorkspaceTestOwner(
      bindingManager: bindingManager,
      providerController: settings.store,
      runtimeRegistry: registry,
      workspaceFileCorpus: CallbackWorkspaceFileCorpusPort(
        filesProvider: () => [],
        isReadyProvider: () => true,
        addListenerCallback: (_) {},
        removeListenerCallback: (_) {},
      ),
      uiFrameSchedulerFactory: () {
        final f = FakeAgentFrameScheduler();
        frames.add(f);
        return f;
      },
    );
    source = WorkspaceAgentRuntimeFactSource(
      workspace,
      subscribeWorkspace: conversationWorkspaceTestChanges(workspace),
    )..start();
  }
  static Future<_Harness> create() async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.settings.store.loadSettings();
    return h;
  }

  final factory = _Factory();
  final frames = <FakeAgentFrameScheduler>[];
  late final AgentProviderRuntimeRegistry registry;
  late final AgentConversationBindingManager bindingManager;
  late final ProviderSettingsTestComposition settings;
  late final AgentConversationWorkspaceNotifier workspace;
  late final WorkspaceAgentRuntimeFactSource source;

  Future<AgentConversationEntryResources> draft(String id) async {
    final entry = workspace.ensureDraftEntry(
      callbacks: conversationWorkspaceTestCallbacks(workspace),
      projectPath: '/repo',
      providerId: id,
    );
    await entry.controller.loadSettings();
    await flush();
    return entry;
  }

  Future<AgentConversationEntryResources> thread(
    String provider,
    String id, {
    required AgentThreadRuntimeStatus status,
  }) async {
    final entry = workspace.ensureThreadEntry(
      callbacks: conversationWorkspaceTestCallbacks(workspace),
      projectPath: '/repo',
      thread: AgentThreadSummary(
        id: id,
        providerId: provider,
        projectPath: '/repo',
        title: 'history',
        preview: '',
        sessionPath: '/repo/history',
        status: status,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );
    await entry.controller.initialization;
    await flush();
    return entry;
  }

  _Provider provider(AgentConversationEntryResources e) =>
      e.binding.currentRuntime!.bundle.runtime as _Provider;
  AgentManagementRuntimeFact fact(AgentConversationEntryResources e) =>
      source.current.bindings.singleWhere(
        (f) => e.binding.currentRuntime == null
            ? f.providerId == e.providerId
            : f.runtimeIdentity == e.binding.currentRuntime!.runtimeIdentity,
      );
  AgentManagementProviderRuntimeSummary summary(String id) =>
      aggregateManagementRuntime(source.current, {
        for (final config in settings.store.settings.providers)
          config.id: config.enabled,
      })[id]!;
  Future<void> flush() async {
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(Duration.zero);
      for (final f in frames) {
        f.drainFrames();
      }
    }
  }

  Future<void> dispose() async {
    source.close();
    await closeConversationWorkspaceTestOwner(workspace);
    await bindingManager.close();
    await settings.dispose();
    await registry.close();
    for (final provider in factory.created) {
      await provider.closeEvents();
    }
  }
}

final class _Factory implements AgentProviderBundleFactory {
  final created = <_Provider>[];
  Object? failure;
  Completer<void>? initializationGate;
  @override
  AgentProviderBundle createBundle(AgentProviderConfig config) {
    final provider = _Provider(
      config,
      created.length,
      failure,
      initializationGate,
    );
    failure = null;
    initializationGate = null;
    created.add(provider);
    return FakeAgentProviderBundleBuilder.fromFake(
      provider,
    ).createBundle(config);
  }
}

final class _Provider extends FakeAgentProvider {
  _Provider(AgentProviderConfig config, this.id, this.failure, this.gate)
    : super(config: config, completeTurns: false);
  final int id;
  final Object? failure;
  final Completer<void>? gate;
  int epoch = 1;
  int disposeCalls = 0;
  AgentProviderLifecycleState lifecycle = AgentProviderLifecycleState.stopped;
  @override
  AgentProviderLifecycleState get lifecycleState => lifecycle;
  @override
  AgentRuntimeScope get runtimeScope =>
      AgentRuntimeScope(runtimeId: 'runtime-$id', connectionEpoch: epoch);
  @override
  Future<void> initialize() async {
    lifecycle = AgentProviderLifecycleState.initializing;
    await gate?.future;
    if (failure case final error?) {
      lifecycle = AgentProviderLifecycleState.failed;
      throw error;
    }
    lifecycle = AgentProviderLifecycleState.ready;
  }

  @override
  Future<AgentSession> startSession({
    required AgentContext context,
    AgentPermissionRequestSnapshot permissionSnapshot =
        const AgentPermissionRequestSnapshot.providerFallback(),
  }) async {
    await initialize();
    return AgentSession(id: 'thread-$id', providerId: config.id);
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    lifecycle = AgentProviderLifecycleState.closed;
  }

  Future<void> closeEvents() => super.dispose();
}

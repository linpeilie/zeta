import 'package:zeta/src/app/composition/agent_session_resource_providers.dart';
import 'package:zeta/src/app/plugins/zeta_plugin_catalog.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/app/composition/workbench_session_providers.dart';
import 'package:zeta/src/app/conversation_workspace_slice/agent_conversation_workspace_notifier.dart';
import 'package:zeta/src/app/plugins/zeta_plugin_providers.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_owner_key.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_session_dependencies.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_notifier.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_state.dart';
import 'package:zeta/src/features/agent/presentation/conversation_slice/agent_conversation_slice_providers.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_notifier.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_slice/project_threads_slice_notifier.dart';
import '../../testing/ide_test_harness.dart';
import '../../testing/test_agent_provider_bundle_factory.dart';
import '../../testing/zeta_test_app.dart';

void main() {
  test(
    'ready without Widgets has one workbench and all owners, no session runtime',
    () async {
      final factory = _Factory();
      final app = zetaTestComposition(
        overrides: [
          agentProviderBundleFactoryProvider.overrideWithValue(factory),
        ],
      );
      await app.ready;
      final c = app.container;
      final workbench = c.read(workbenchSessionProvider);
      final workspace = c.read(agentConversationWorkspaceProvider.notifier);
      final owner = c.read(
        agentConversationSliceOwnerProvider(
          workspace.entries.single.ownerKey,
        ).notifier,
      );
      expect(c.read(workbenchSessionProvider), same(workbench));
      workbench.shell.start();
      expect(workspace.entries, hasLength(1));
      expect(workspace.entries.single.binding.hasRuntime, isFalse);
      expect(c.read(agentManagementSliceProvider), isNotNull);
      expect(c.read(projectThreadsSliceProvider), isNotNull);
      expect(
        c.read(agentConversationSliceOwnerProvider(owner.ownerKey).notifier),
        same(owner),
      );
      expect(app.takeStateSnapshot().shell.orderedConversationEntryIds, [
        owner.ownerKey.entryId,
      ]);
      expect(
        factory.created.every(
          (p) => p.startPermissionSnapshots.isEmpty && p.sentMessages.isEmpty,
        ),
        isTrue,
      );
    },
  );

  test(
    'runtime restart and input invalidation keep the same conversation owner',
    () async {
      final app = zetaTestComposition(
        overrides: [
          agentProviderBundleFactoryProvider.overrideWithValue(_Factory()),
        ],
      );
      final c = app.container;
      final entry = c
          .read(workbenchSessionProvider)
          .shell
          .agentWorkspaceEntries
          .single;
      await entry.controller.loadSettings();
      final key = entry.ownerKey;
      final owner = c.read(agentConversationSliceOwnerProvider(key).notifier);
      final first = owner.sendMessage(text: 'first');
      await _until(() => !owner.current.pendingOperations.contains(first));
      final previousRuntime = entry.binding.currentRuntime!.runtimeIdentity;
      await entry.binding.invalidateRuntime();
      c.invalidate(agentConversationWorkspaceInputsProvider);
      c.invalidate(agentConversationSessionDependenciesProvider(key));
      final next = owner.sendMessage(text: 'after restart');
      await _until(() => !owner.current.pendingOperations.contains(next));
      expect(
        entry.binding.currentRuntime!.runtimeIdentity,
        isNot(previousRuntime),
      );
      expect(
        c.read(agentConversationSliceOwnerProvider(key).notifier),
        same(owner),
      );
      expect(entry.ownerKey, same(key));
      expect(owner.current.pendingOperations, isEmpty);
    },
  );

  test(
    'reentrant entry and application close reuse futures before notifying',
    () async {
      final app = zetaTestComposition(
        overrides: [
          agentProviderBundleFactoryProvider.overrideWithValue(_Factory()),
        ],
      );
      final c = app.container;
      final w = c.read(workbenchSessionProvider);
      final key = w.shell.agentWorkspaceEntries.single.ownerKey;
      Future<void>? nestedEntry;
      Future<void>? nestedApp;
      final sub = c.listen(agentConversationWorkspaceProvider, (_, state) {
        if (state.aliases.values.any(
          (value) => value is AgentConversationOwnerClosing,
        )) {
          nestedEntry ??= w.lifetimes.closeEntry(key);
          nestedApp ??= app.close();
        }
      });
      final closing = app.close();
      await closing;
      expect(nestedApp, same(closing));
      expect(nestedEntry, isNotNull);
      await nestedEntry;
      sub.close();
    },
  );

  test(
    'draft promotion preserves owner, pending settlement, and both aliases',
    () async {
      final factory = _Factory();
      final app = zetaTestComposition(
        overrides: [
          agentProviderBundleFactoryProvider.overrideWithValue(factory),
        ],
      );
      await app.ready;
      final c = app.container;
      final w = c.read(workbenchSessionProvider);
      final entry = w.shell.agentWorkspaceEntries.single;
      await entry.controller.loadSettings();
      final draft = entry.binding.key;
      final key = entry.ownerKey;
      final owner = c.read(agentConversationSliceOwnerProvider(key).notifier);
      final command = owner.sendMessage(text: 'first message');
      await _until(() => !owner.current.pendingOperations.contains(command));
      expect(entry.binding.key, isNot(draft));
      expect(entry.ownerKey, same(key));
      expect(
        c.read(agentConversationSliceOwnerProvider(key).notifier),
        same(owner),
      );
      expect(
        (c.read(agentConversationOwnerResolutionProvider(draft))
                as AgentConversationOwnerLive)
            .ownerKey,
        key,
      );
      expect(
        (c.read(agentConversationOwnerResolutionProvider(entry.binding.key))
                as AgentConversationOwnerLive)
            .ownerKey,
        key,
      );
      expect(
        c.read(agentConversationSliceProvider(draft)),
        same(c.read(agentConversationSliceProvider(entry.binding.key))),
      );
      expect(owner.current.pendingOperations, isEmpty);
    },
  );

  test(
    'close is one awaitable release; retired same-frame selector is empty without runtime recreation',
    () async {
      final gate = Completer<void>();
      var releases = 0;
      final factory = _Factory();
      final app = zetaTestComposition(
        overrides: [
          agentProviderBundleFactoryProvider.overrideWithValue(factory),
          conversationEntryLeaseReleaseProvider.overrideWithValue((
            entry,
          ) async {
            releases++;
            await gate.future;
            await entry.bindingLease.release();
          }),
        ],
      );
      final c = app.container;
      final w = c.read(workbenchSessionProvider);
      final entry = w.shell.agentWorkspaceEntries.single;
      await entry.controller.loadSettings();
      final key = entry.ownerKey;
      final bindingKey = entry.binding.key;
      final owner = c.read(agentConversationSliceOwnerProvider(key).notifier);
      final subscriber = c.listen(
        agentConversationSliceProvider(bindingKey),
        (_, _) {},
      );
      final closing = w.lifetimes.closeEntry(key);
      expect(w.lifetimes.closeEntry(key), same(closing));
      expect(releases, 1);
      expect(owner.isClosed, isTrue);
      expect(owner.current.pendingOperations, isEmpty);
      expect(owner.current.history.visibleTurns, isEmpty);
      expect(
        c.read(agentConversationSliceProvider(bindingKey)).projectionStatus,
        AgentConversationProjectionStatus.closed,
      );
      expect(w.lifetimes.releaseMarkerCount, 0);
      expect(
        c
            .read(agentConversationWorkspaceProvider.notifier)
            .retainedResourceCount,
        1,
      );
      final sessionCreations = factory.created.fold<int>(
        0,
        (count, p) => count + p.startPermissionSnapshots.length,
      );
      gate.complete();
      await closing;
      await c.pump();
      expect(
        factory.created.fold<int>(
          0,
          (count, p) => count + p.startPermissionSnapshots.length,
        ),
        sessionCreations,
      );
      expect(entry.binding.hasRuntime, isFalse);
      expect(
        c
            .read(agentConversationWorkspaceProvider.notifier)
            .retainedResourceCount,
        0,
      );
      subscriber.close();
      await c.pump();
      await Future<void>.delayed(Duration.zero);
      expect(w.lifetimes.retainedOwnerCount, 0);
      expect(w.lifetimes.releaseMarkerCount, 0);
      expect(
        c.read(agentConversationSliceProvider(bindingKey)).projectionStatus,
        AgentConversationProjectionStatus.unavailable,
      );
    },
  );

  test(
    'same thread reopen receives new token and late old results cannot modify it',
    () async {
      final factory = _Factory();
      final app = zetaTestComposition(
        overrides: [
          agentProviderBundleFactoryProvider.overrideWithValue(factory),
        ],
      );
      final c = app.container;
      final w = c.read(workbenchSessionProvider);
      final workspace = c.read(agentConversationWorkspaceProvider.notifier);
      final thread = _thread();
      final old = workspace.ensureThreadEntry(
        projectPath: '/repo',
        thread: thread,
        callbacks: w.shell.entryCallbacks,
      );
      await old.controller.initialization;
      final oldOwner = c.read(
        agentConversationSliceOwnerProvider(old.ownerKey).notifier,
      );
      final subscription = c.listen(
        agentConversationSliceOwnerProvider(old.ownerKey),
        (_, _) {},
      );
      final operation = oldOwner.sendMessage(text: 'old');
      await w.lifetimes.closeEntry(old.ownerKey);
      final next = workspace.ensureThreadEntry(
        projectPath: '/repo',
        thread: thread,
        callbacks: w.shell.entryCallbacks,
      );
      final nextOwner = c.read(
        agentConversationSliceOwnerProvider(next.ownerKey).notifier,
      );
      final before = nextOwner.current;
      expect(
        next.ownerKey.lifetimeToken,
        isNot(same(old.ownerKey.lifetimeToken)),
      );
      expect(nextOwner, isNot(same(oldOwner)));
      oldOwner.completeCommand(operation);
      expect(oldOwner.current.pendingOperations, isEmpty);
      expect(nextOwner.current, same(before));
      subscription.close();
      await c.pump();
      await Future<void>.delayed(Duration.zero);
      final resolution =
          c.read(agentConversationOwnerResolutionProvider(next.binding.key))
              as AgentConversationOwnerLive;
      expect(resolution.ownerKey, next.ownerKey);
      await next.controller.initialization;
    },
  );

  test(
    'unobserved entries reclaim owners, aliases, and markers without a Widget frame',
    () async {
      final factory = _Factory();
      final app = zetaTestComposition(
        overrides: [
          agentProviderBundleFactoryProvider.overrideWithValue(factory),
        ],
      );
      final c = app.container;
      final w = c.read(workbenchSessionProvider);
      final workspace = c.read(agentConversationWorkspaceProvider.notifier);
      final baselineOwners = w.lifetimes.retainedOwnerCount;
      final baselineAliases = workspace.current.aliases.length;
      for (var i = 0; i < 25; i++) {
        final entry = workspace.ensureThreadEntry(
          projectPath: '/repo',
          thread: _thread(),
          callbacks: w.shell.entryCallbacks,
        );
        await entry.controller.initialization;
        final key = entry.ownerKey;
        await w.lifetimes.closeEntry(key);
        await c.pump();
        await Future<void>.delayed(Duration.zero);
        expect(c.exists(agentConversationSliceOwnerProvider(key)), isFalse);
        expect(w.lifetimes.retainedOwnerCount, baselineOwners);
        expect(workspace.current.aliases.length, baselineAliases);
        expect(w.lifetimes.closeFutureCount, 0);
        expect(w.lifetimes.releaseMarkerCount, 0);
      }
      expect(workspace.retainedResourceCount, 1);
    },
  );

  test(
    'failed entry release is cached, all entries attempted, app remains inspectable',
    () async {
      final error = StateError('release failed');
      final factory = _Factory();
      final attempts = <AgentConversationOwnerKey>[];
      AgentConversationOwnerKey? failing;
      final app = zetaTestComposition(
        overrides: [
          agentProviderBundleFactoryProvider.overrideWithValue(factory),
          conversationEntryLeaseReleaseProvider.overrideWithValue((
            entry,
          ) async {
            attempts.add(entry.ownerKey);
            if (entry.ownerKey == failing) throw error;
            await entry.bindingLease.release();
          }),
        ],
        verifyClose: (closing) => expectLater(closing, throwsA(same(error))),
      );
      final c = app.container;
      final w = c.read(workbenchSessionProvider);
      final workspace = c.read(agentConversationWorkspaceProvider.notifier);
      final entry = workspace.ensureThreadEntry(
        projectPath: '/repo',
        thread: _thread(),
        callbacks: w.shell.entryCallbacks,
      );
      await entry.controller.initialization;
      failing = entry.ownerKey;
      final close = app.close();
      await expectLater(close, throwsA(same(error)));
      expect(app.close(), same(close));
      expect(attempts, contains(failing));
      expect(attempts.length, 2);
      expect(workspace.retainedResourceCount, 1);
      expect(
        c.read(agentConversationOwnerResolutionProvider(entry.binding.key)),
        isA<AgentConversationOwnerClosing>(),
      );
      final retry = w.lifetimes.closeEntry(entry.ownerKey);
      await expectLater(retry, throwsA(same(error)));
      expect(w.lifetimes.closeEntry(entry.ownerKey), same(retry));
      expect(attempts.length, 2);
      expect(w.lifetimes.releaseMarkerCount, 0);
      // Explicit fixture cleanup follows assertions that production did not report release.
      await entry.bindingLease.release();
      await c.read(agentConversationBindingManagerProvider).close();
      await c.read(agentProviderRuntimeRegistryProvider).close();
    },
  );

  test(
    'registry failure retains the same failed app future and does not close plugin or container',
    () async {
      final error = StateError('registry failed');
      final factory = _Factory();
      final registry = _Registry(factory)..closeFailure = error;
      final catalog = ZetaPluginCatalog.forTesting(factories: []);
      var disposed = false;
      final app = zetaTestComposition(
        overrides: [
          agentProviderBundleFactoryProvider.overrideWithValue(factory),
          agentProviderRuntimeRegistryProvider.overrideWithValue(registry),
          zetaPluginCatalogProvider.overrideWithValue(catalog),
        ],
        verifyClose: (closing) => expectLater(closing, throwsA(same(error))),
      );
      final c = app.container;
      c.read(zetaPluginCatalogProvider);
      c.read(
        Provider((ref) {
          ref.onDispose(() => disposed = true);
          return 0;
        }),
      );
      final closing = app.close();
      await expectLater(closing, throwsA(same(error)));
      expect(app.close(), same(closing));
      expect(registry.closeCalls, 1);
      expect(disposed, isFalse);
      expect(catalog.activate, returnsNormally);
      await catalog.close();
    },
  );

  test(
    'app shutdown waits delayed entry release before registry and container',
    () async {
      final gate = Completer<void>();
      final factory = _Factory();
      final registry = _Registry(factory);
      var releaseStarted = false;
      var disposed = false;
      final app = zetaTestComposition(
        overrides: [
          agentProviderBundleFactoryProvider.overrideWithValue(factory),
          agentProviderRuntimeRegistryProvider.overrideWithValue(registry),
          conversationEntryLeaseReleaseProvider.overrideWithValue((
            entry,
          ) async {
            releaseStarted = true;
            await gate.future;
            await entry.bindingLease.release();
          }),
        ],
      );
      final probe = Provider((ref) {
        ref.onDispose(() => disposed = true);
        return 0;
      });
      app.container.read(probe);
      final closing = app.close();
      expect(app.close(), same(closing));
      await _until(() => releaseStarted);
      expect(registry.closeCalls, 0);
      expect(disposed, isFalse);
      gate.complete();
      await closing;
      expect(registry.closeCalls, 1);
      expect(disposed, isTrue);
    },
  );
}

AgentThreadSummary _thread() => AgentThreadSummary(
  id: 'same-thread',
  providerId: 'codex',
  projectPath: '/repo',
  title: 'Thread',
  preview: '',
  sessionPath: '',
  status: AgentThreadRuntimeStatus.idle,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);
Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 100; i++) {
    if (done()) return;
    await Future<void>.delayed(Duration.zero);
  }
  expect(done(), isTrue);
}

final class _Factory with TestAgentProviderBundleFactory {
  final created = <FakeAgentProvider>[];
  @override
  Object create(AgentProviderConfig config) {
    final p = FakeAgentProvider(config: config);
    created.add(p);
    return p;
  }
}

final class _Registry extends AgentProviderRuntimeRegistry {
  _Registry(AgentProviderBundleFactory factory)
    : super(providerFactory: factory);
  int closeCalls = 0;
  Object? closeFailure;
  @override
  Future<void> close() async {
    closeCalls++;
    await super.close();
    if (closeFailure != null) throw closeFailure!;
  }
}

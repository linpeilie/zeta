import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/agent/application/agent_conversation_binding.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_binding_manager.dart';
import 'package:zeta/src/features/agent/application/agent_provider_runtime_registry.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

import '../../../testing/legacy_bundle_factory_mixin.dart';
import '../presentation/harness/agent_pane_test_harness.dart';

void main() {
  group('AgentConversationBindingManager', () {
    late DateTime now;
    late _BindingProviderFactory factory;
    late AgentProviderRuntimeRegistry registry;
    late AgentConversationBindingManager manager;

    setUp(() {
      now = DateTime.utc(2026, 8, 9, 10);
      factory = _BindingProviderFactory();
      registry = AgentProviderRuntimeRegistry(providerFactory: factory);
      manager = AgentConversationBindingManager(
        runtimeRegistry: registry,
        clock: () => now,
      );
    });

    tearDown(() async {
      await manager.close();
      await registry.close();
    });

    AgentConversationBindingLease acquireDraft() {
      return manager.acquireDraft(
        providerId: defaultAgentProviderId,
        entryId: 'entry-1',
        resolveConfig: (_) => AgentProviderConfig.defaultCodex,
        persistPermissionOptionId: (_) async {},
      );
    }

    test('创建和打开 Binding 不会立即创建 session Provider', () {
      final lease = acquireDraft();

      expect(factory.providers, isEmpty);
      expect(lease.binding.hasRuntime, isFalse);
      expect(
        lease.binding.runtimeLifecycle.phase,
        AgentConversationRuntimeLifecyclePhase.dormant,
      );
    });

    test('beginTurn 明确区分 starting、attached 与 cleared', () async {
      final lease = acquireDraft();

      final activityFuture = lease.binding.beginTurn();

      expect(
        lease.binding.runtimeLifecycle.phase,
        AgentConversationRuntimeLifecyclePhase.starting,
      );

      final activity = await activityFuture;
      final identity = activity.runtime.runtimeIdentity;
      expect(
        lease.binding.runtimeLifecycle.phase,
        AgentConversationRuntimeLifecyclePhase.attached,
      );
      expect(lease.binding.runtimeLifecycle.runtimeIdentity, identity);

      await activity.release();
      await lease.binding.invalidateRuntime();

      expect(
        lease.binding.runtimeLifecycle.phase,
        AgentConversationRuntimeLifecyclePhase.cleared,
      );
      expect(lease.binding.runtimeLifecycle.runtimeIdentity, identity);
      expect(
        lease.binding.runtimeLifecycle.clearReason,
        AgentConversationRuntimeClearReason.explicitInvalidation,
      );
    });

    test('runtime 初始化失败回到 dormant，不伪造 cleared', () async {
      final lease = acquireDraft();
      factory.failNextInitialize = true;
      final observedPhases = <AgentConversationRuntimeLifecyclePhase>[];
      lease.binding.addListener(
        () => observedPhases.add(lease.binding.runtimeLifecycle.phase),
      );

      await expectLater(lease.binding.beginTurn(), throwsStateError);

      expect(
        observedPhases,
        contains(AgentConversationRuntimeLifecyclePhase.starting),
      );
      expect(
        observedPhases,
        isNot(contains(AgentConversationRuntimeLifecyclePhase.cleared)),
      );
      expect(
        lease.binding.runtimeLifecycle.phase,
        AgentConversationRuntimeLifecyclePhase.dormant,
      );
    });

    test('dormant 权限选择只更新下次请求，不创建 session Provider', () async {
      var config = AgentProviderConfig.defaultCodex.withPermissionPreference(
        ':workspace',
      );
      String? persistedOptionId;
      final lease = manager.acquireDraft(
        providerId: defaultAgentProviderId,
        entryId: 'permission-draft',
        resolveConfig: (_) => config,
        persistPermissionOptionId: (optionId) async {
          persistedOptionId = optionId;
          config = config.withPermissionPreference(optionId);
        },
      );
      final catalogProvider = AgentPaneFakeProvider();
      await lease.binding.bindPermissionCatalog(
        port: catalogProvider.permissionPolicy,
        persistedOptionId: config.resolvedPermissionOptionId,
      );

      await lease.binding.permissions.selectOption(
        lease.binding.permissions.options.first,
      );

      expect(factory.providers, isEmpty);
      expect(catalogProvider.permissionApplyCount, 0);
      expect(persistedOptionId, ':read-only');
      expect(
        lease.binding.permissions.snapshotForRequest().selection?.optionId,
        ':read-only',
      );
      expect(lease.binding.permissions.applyScopeHint, isNull);
    });

    test('dormant 权限持久化失败后创建 runtime 仍保留选择且不重复 apply', () async {
      final lease = manager.acquireDraft(
        providerId: defaultAgentProviderId,
        entryId: 'permission-persist-failure',
        resolveConfig: (_) => AgentProviderConfig.defaultCodex,
        persistPermissionOptionId: (_) async {
          throw StateError('disk unavailable');
        },
      );
      final catalogProvider = AgentPaneFakeProvider();
      await lease.binding.bindPermissionCatalog(
        port: catalogProvider.permissionPolicy,
        persistedOptionId: ':workspace',
      );
      await lease.binding.permissions.selectOption(
        const AgentPermissionOption(id: ':read-only', label: 'Read only'),
      );

      final activity = await lease.binding.beginTurn();

      expect(lease.binding.permissions.selectedOptionId, ':read-only');
      expect(lease.binding.permissions.canRetryPersistence, isTrue);
      expect(
        lease.binding.permissions.snapshotForRequest().selection?.optionId,
        ':read-only',
      );
      expect(factory.providers.single.permissionApplyCount, 0);
      await activity.release();
    });

    test('首次 beginTurn 创建实例，同一 Binding 后续复用', () async {
      final lease = acquireDraft();

      final first = await lease.binding.beginTurn();
      await first.release();
      final second = await lease.binding.beginTurn();

      expect(factory.providers, hasLength(1));
      expect(second.runtime.runtimeIdentity, first.runtime.runtimeIdentity);
      await second.release();
    });

    test('首次 beginTurn 切换到 session Provider 后保留并刷新权限目录', () async {
      final config = AgentProviderConfig.defaultCodex.withPermissionPreference(
        ':danger-full-access',
      );
      final lease = manager.acquireDraft(
        providerId: defaultAgentProviderId,
        entryId: 'permission-catalog-rebind',
        resolveConfig: (_) => config,
        persistPermissionOptionId: (_) async {},
      );
      final globalProvider = AgentPaneFakeProvider();
      await lease.binding.bindPermissionCatalog(
        port: globalProvider.permissionPolicy,
        persistedOptionId: config.resolvedPermissionOptionId,
      );

      expect(globalProvider.permissionCatalogListCount, 1);
      expect(lease.binding.permissions.displayLabel, 'Full access');

      final activity = await lease.binding.beginTurn();

      expect(factory.providers.single.permissionCatalogListCount, 1);
      expect(
        lease.binding.permissions.options.map((option) => option.id),
        contains(':danger-full-access'),
      );
      expect(lease.binding.permissions.displayLabel, 'Full access');
      await activity.release();
    });

    test('草稿晋升后关闭再打开按 thread key 复用 Binding', () async {
      final draftLease = acquireDraft();
      final activity = await draftLease.binding.beginTurn();
      await activity.release();
      draftLease.binding.promoteToThread('thread-1');
      await draftLease.release();

      final reopened = manager.acquireThread(
        providerId: defaultAgentProviderId,
        threadId: 'thread-1',
        resolveConfig: (_) => AgentProviderConfig.defaultCodex,
        persistPermissionOptionId: (_) async {},
      );

      expect(reopened.binding, same(draftLease.binding));
      expect(reopened.binding.hasRuntime, isTrue);
      expect(factory.providers, hasLength(1));
      await reopened.release();
    });

    test('运行中 turn 不回收，终态十分钟后回收并按需重建', () async {
      final lease = acquireDraft();
      final activity = await lease.binding.beginTurn();
      final firstIdentity = activity.runtime.runtimeIdentity;
      now = now.add(const Duration(hours: 1));

      await manager.sweepNow();

      expect(lease.binding.hasRuntime, isTrue);
      expect(factory.providers, hasLength(1));

      await activity.release();
      now = now.add(const Duration(minutes: 10));
      await manager.sweepNow();

      expect(lease.binding.hasRuntime, isFalse);
      expect(
        lease.binding.runtimeLifecycle.phase,
        AgentConversationRuntimeLifecyclePhase.cleared,
      );
      expect(lease.binding.runtimeLifecycle.runtimeIdentity, firstIdentity);
      expect(
        lease.binding.runtimeLifecycle.clearReason,
        AgentConversationRuntimeClearReason.idleTimeout,
      );
      final replacement = await lease.binding.beginTurn();
      expect(factory.providers, hasLength(2));
      expect(replacement.runtime.runtimeIdentity, isNot(firstIdentity));
      await replacement.release();
    });

    test('重叠 sweep 共享同一次扫描且不会重复 dispose', () async {
      final lease = acquireDraft();
      final activity = await lease.binding.beginTurn();
      await activity.release();
      now = now.add(const Duration(minutes: 10));

      await Future.wait(<Future<void>>[manager.sweepNow(), manager.sweepNow()]);

      expect(factory.providers.single.disposeCount, 1);
      expect(lease.binding.hasRuntime, isFalse);
    });

    test('回收 dispose 期间 beginTurn 等待旧进程退出后再创建', () async {
      final lease = acquireDraft();
      final firstTurn = await lease.binding.beginTurn();
      await firstTurn.release();
      final firstProvider = factory.providers.single;
      final disposeGate = Completer<void>();
      firstProvider.disposeGate = disposeGate;
      now = now.add(const Duration(minutes: 10));

      final sweep = manager.sweepNow();
      while (firstProvider.disposeCount == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      final nextTurn = lease.binding.beginTurn();
      await Future<void>.delayed(Duration.zero);

      expect(factory.providers, hasLength(1));
      disposeGate.complete();
      await sweep;
      final replacement = await nextTurn;

      expect(factory.providers, hasLength(2));
      expect(
        replacement.runtime.runtimeIdentity,
        isNot(firstTurn.runtime.runtimeIdentity),
      );
      await replacement.release();
    });

    test('短 RPC 执行期间不回收，完成时间重新开始计算 TTL', () async {
      final lease = acquireDraft();
      final turn = await lease.binding.beginTurn();
      await turn.release();
      final rpcGate = Completer<void>();
      final rpc = lease.binding.runCurrent((_) => rpcGate.future);
      now = now.add(const Duration(hours: 1));

      await manager.sweepNow();
      expect(lease.binding.hasRuntime, isTrue);

      rpcGate.complete();
      await rpc;
      now = now.add(const Duration(minutes: 9, seconds: 59));
      await manager.sweepNow();
      expect(lease.binding.hasRuntime, isTrue);

      now = now.add(const Duration(seconds: 1));
      await manager.sweepNow();
      expect(lease.binding.hasRuntime, isFalse);
    });

    test('两个 thread 的事件与权限状态互不污染', () async {
      final first = manager.acquireThread(
        providerId: defaultAgentProviderId,
        threadId: 'thread-a',
        resolveConfig: (_) => AgentProviderConfig.defaultCodex,
        persistPermissionOptionId: (_) async {},
      );
      final second = manager.acquireThread(
        providerId: defaultAgentProviderId,
        threadId: 'thread-b',
        resolveConfig: (_) => AgentProviderConfig.defaultCodex,
        persistPermissionOptionId: (_) async {},
      );
      final firstEvents = <AgentEvent>[];
      final secondEvents = <AgentEvent>[];
      final firstSubscription = first.binding.events.listen(firstEvents.add);
      final secondSubscription = second.binding.events.listen(secondEvents.add);
      addTearDown(firstSubscription.cancel);
      addTearDown(secondSubscription.cancel);

      final firstTurn = await first.binding.beginTurn();
      final secondTurn = await second.binding.beginTurn();
      await first.binding.permissions.refreshOptions();
      await second.binding.permissions.refreshOptions();
      await first.binding.permissions.selectOption(
        const AgentPermissionOption(id: ':read-only', label: 'Read only'),
      );
      await second.binding.permissions.selectOption(
        const AgentPermissionOption(id: ':workspace', label: 'Workspace'),
      );
      factory.providers[0].emitEvent(
        const AgentStatusEvent(
          AgentProviderStatus(
            state: AgentProviderConnectionState.running,
            message: 'Running',
          ),
        ),
      );
      factory.providers[1].emitEvent(
        const AgentStatusEvent(AgentProviderStatus.idle()),
      );
      await Future<void>.delayed(Duration.zero);

      expect(factory.providers, hasLength(2));
      expect(firstEvents, hasLength(1));
      expect(secondEvents, hasLength(1));
      expect(first.binding.permissions.selectedOptionId, ':read-only');
      expect(second.binding.permissions.selectedOptionId, ':workspace');
      expect(factory.providers[0].lastAppliedPermissionOptionId, ':read-only');
      expect(factory.providers[1].lastAppliedPermissionOptionId, ':workspace');
      await firstTurn.release();
      await secondTurn.release();
    });

    test('配置失效会清除全部 session runtime，下一次 beginTurn 才重建', () async {
      final lease = acquireDraft();
      final first = await lease.binding.beginTurn();
      final firstIdentity = first.runtime.runtimeIdentity;
      await first.release();

      await registry.invalidateProvider(defaultAgentProviderId);

      expect(lease.binding.hasRuntime, isFalse);
      expect(lease.binding.permissions.isRuntimeAttached, isFalse);
      expect(factory.providers, hasLength(1));
      expect(manager.bindings.values, contains(lease.binding));

      final replacement = await lease.binding.beginTurn();
      expect(factory.providers, hasLength(2));
      expect(replacement.runtime.runtimeIdentity, isNot(firstIdentity));
      await replacement.release();
    });

    test('无消费者 Binding 在外部 invalidate 后立即从映射移除', () async {
      final lease = acquireDraft();
      final activity = await lease.binding.beginTurn();
      await activity.release();
      final binding = lease.binding;
      await lease.release();

      expect(binding.consumerCount, 0);
      expect(binding.hasRuntime, isTrue);
      expect(manager.bindings.values, contains(binding));

      await registry.invalidateProvider(defaultAgentProviderId);

      expect(binding.hasRuntime, isFalse);
      expect(manager.bindings.values, isNot(contains(binding)));
      expect(manager.bindings, isEmpty);
    });

    test('global runtime 不参与 Binding 空闲回收', () async {
      final global = await registry.acquire(
        AgentProviderConfig.defaultCodex,
        scope: AgentProviderRuntimeScopeKey.global,
      );
      await global.bundle.runtime.initialize();
      await global.release();
      now = now.add(const Duration(days: 1));

      await manager.sweepNow();

      expect(registry.debugProviderCount, 1);
      expect(factory.providers.single.disposeCount, 0);
    });

    test('草稿晋升碰到已存在 thread Binding 时 fail-closed', () {
      final draft = acquireDraft();
      final existing = manager.acquireThread(
        providerId: defaultAgentProviderId,
        threadId: 'thread-1',
        resolveConfig: (_) => AgentProviderConfig.defaultCodex,
        persistPermissionOptionId: (_) async {},
      );

      expect(() => draft.binding.promoteToThread('thread-1'), throwsStateError);
      expect(
        manager.bindingForThread(
          providerId: defaultAgentProviderId,
          threadId: 'thread-1',
        ),
        same(existing.binding),
      );
      expect(draft.binding.key, isA<AgentConversationDraftBindingKey>());
    });

    test('草稿晋升在 Manager 通知时 key 与映射已同步提交', () {
      final lease = acquireDraft();
      final binding = lease.binding;
      final draftKey = binding.key;
      AgentConversationBindingKey? keySeenByManagerListener;
      AgentConversationBinding? mappedSeenByManagerListener;
      var draftKeyPresentDuringNotify = false;

      manager.addListener(() {
        keySeenByManagerListener = binding.key;
        mappedSeenByManagerListener = manager.bindingForThread(
          providerId: defaultAgentProviderId,
          threadId: 'thread-1',
        );
        draftKeyPresentDuringNotify = manager.bindings.containsKey(draftKey);
      });

      binding.promoteToThread('thread-1');

      expect(
        keySeenByManagerListener,
        isA<AgentConversationThreadBindingKey>(),
      );
      expect(
        (keySeenByManagerListener! as AgentConversationThreadBindingKey)
            .threadId,
        'thread-1',
      );
      expect(mappedSeenByManagerListener, same(binding));
      expect(draftKeyPresentDuringNotify, isFalse);
      expect(manager.bindings.containsKey(draftKey), isFalse);
      expect(binding.permissions.state.threadId, 'thread-1');
    });
  });
}

final class _BindingProviderFactory with LegacyBundleFactoryMixin {
  final List<_BindingProvider> providers = <_BindingProvider>[];
  bool failNextInitialize = false;

  @override
  Object create(AgentProviderConfig config) {
    final provider = _BindingProvider(failInitialize: failNextInitialize);
    failNextInitialize = false;
    providers.add(provider);
    return provider;
  }
}

final class _BindingProvider extends AgentPaneFakeProvider {
  _BindingProvider({required this.failInitialize});

  final bool failInitialize;
  int disposeCount = 0;
  Completer<void>? disposeGate;

  @override
  Future<void> initialize() async {
    if (failInitialize) {
      throw StateError('initialize failed');
    }
    await super.initialize();
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
    await disposeGate?.future;
    await super.dispose();
  }
}

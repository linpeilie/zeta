import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/agent/application/agent_provider_runtime_registry.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';

void main() {
  group('AgentProviderRuntimeRegistry', () {
    test('并发获取同一 Provider 时只创建一个实例', () async {
      final factory = _CountingProviderFactory();
      final registry = AgentProviderRuntimeRegistry(providerFactory: factory);

      final leases = await Future.wait(
        List<Future<AgentProviderRuntimeLease>>.generate(
          12,
          (_) => registry.acquire(
            AgentProviderConfig.defaultCodex,
            scope: AgentProviderRuntimeScopeKey.global,
          ),
        ),
      );

      expect(factory.createCount, 1);
      expect(leases.map((lease) => lease.provider).toSet(), hasLength(1));
      expect(registry.debugProviderCount, 1);
      expect(registry.debugLeaseCount, 12);

      await Future.wait(leases.map((lease) => lease.release()));
      expect(registry.debugLeaseCount, 0);
      expect(factory.providers.single.disposeCount, 0);

      await registry.close();
      expect(factory.providers.single.disposeCount, 1);
    });

    test('每个 Provider ID 各自只维护一个实例', () async {
      final factory = _CountingProviderFactory();
      final registry = AgentProviderRuntimeRegistry(providerFactory: factory);

      final codexA = await registry.acquire(
        AgentProviderConfig.defaultCodex,
        scope: AgentProviderRuntimeScopeKey.global,
      );
      final grokA = await registry.acquire(
        AgentProviderConfig.defaultGrok,
        scope: AgentProviderRuntimeScopeKey.global,
      );
      final codexB = await registry.acquire(
        AgentProviderConfig.defaultCodex,
        scope: AgentProviderRuntimeScopeKey.global,
      );
      final grokB = await registry.acquire(
        AgentProviderConfig.defaultGrok,
        scope: AgentProviderRuntimeScopeKey.global,
      );

      expect(factory.createCount, 2);
      expect(identical(codexA.provider, codexB.provider), isTrue);
      expect(identical(grokA.provider, grokB.provider), isTrue);
      expect(identical(codexA.provider, grokA.provider), isFalse);

      await registry.close();
      expect(
        factory.providers.every((provider) => provider.disposeCount == 1),
        isTrue,
      );
    });

    test('影响启动的配置变化会先关闭旧实例再创建新实例', () async {
      final factory = _CountingProviderFactory();
      final registry = AgentProviderRuntimeRegistry(providerFactory: factory);
      final first = await registry.acquire(
        AgentProviderConfig.defaultCodex,
        scope: AgentProviderRuntimeScopeKey.global,
      );
      final firstProvider = first.provider as _FakeProvider;
      final changed = AgentProviderConfig.defaultCodex.copyWith(
        command: 'codex-next',
      );

      final second = await registry.acquire(
        changed,
        scope: AgentProviderRuntimeScopeKey.global,
      );

      expect(factory.createCount, 2);
      expect(first.isCurrent, isFalse);
      expect(firstProvider.disposeCount, 1);
      expect(identical(first.provider, second.provider), isFalse);

      await first.release();
      await second.release();
      await registry.close();
      expect((second.provider as _FakeProvider).disposeCount, 1);
    });

    test('重建 Provider 时递增 runtime generation', () async {
      final factory = _CountingProviderFactory();
      final registry = AgentProviderRuntimeRegistry(providerFactory: factory);
      final first = await registry.acquire(
        AgentProviderConfig.defaultGrok,
        scope: AgentProviderRuntimeScopeKey.global,
      );
      final firstIdentity = first.runtimeIdentity;

      await registry.invalidateProvider(AgentProviderConfig.defaultGrok.id);
      final second = await registry.acquire(
        AgentProviderConfig.defaultGrok,
        scope: AgentProviderRuntimeScopeKey.global,
      );

      expect(first.isCurrent, isFalse);
      expect(second.runtimeIdentity.providerId, firstIdentity.providerId);
      expect(second.runtimeIdentity.generation, firstIdentity.generation + 1);

      await first.release();
      await second.release();
      await registry.close();
    });

    test('关闭后拒绝创建新运行时且 close 幂等', () async {
      final factory = _CountingProviderFactory();
      final registry = AgentProviderRuntimeRegistry(providerFactory: factory);
      await registry.acquire(
        AgentProviderConfig.defaultCodex,
        scope: AgentProviderRuntimeScopeKey.global,
      );

      await Future.wait(<Future<void>>[registry.close(), registry.close()]);

      expect(factory.providers.single.disposeCount, 1);
      expect(
        () => registry.acquire(
          AgentProviderConfig.defaultCodex,
          scope: AgentProviderRuntimeScopeKey.global,
        ),
        throwsStateError,
      );
    });

    test('身份错配不得关闭已被其他 entry 持有的实例', () async {
      final shared = _FakeProvider(AgentProviderConfig.defaultCodex);
      final registry = AgentProviderRuntimeRegistry(
        providerFactory: _SingleProviderFactory(shared),
      );
      final codex = await registry.acquire(
        AgentProviderConfig.defaultCodex,
        scope: AgentProviderRuntimeScopeKey.global,
      );

      await expectLater(
        registry.acquire(
          AgentProviderConfig.defaultGrok,
          scope: AgentProviderRuntimeScopeKey.global,
        ),
        throwsStateError,
      );

      expect(codex.isCurrent, isTrue);
      expect(shared.disposeCount, 0);

      await registry.close();
      expect(shared.disposeCount, 1);
    });
  });

  group('global runtime 保温与销毁语义', () {
    test('同一 Provider 的多个消费者共享同一实例与同一 runtime identity', () async {
      final factory = _CountingProviderFactory();
      final registry = AgentProviderRuntimeRegistry(providerFactory: factory);
      addTearDown(registry.close);

      final sessionA = await registry.acquire(
        AgentProviderConfig.defaultGrok,
        scope: AgentProviderRuntimeScopeKey.global,
      );
      final sessionB = await registry.acquire(
        AgentProviderConfig.defaultGrok,
        scope: AgentProviderRuntimeScopeKey.global,
      );

      expect(factory.createCount, 1);
      expect(identical(sessionA.provider, sessionB.provider), isTrue);
      expect(sessionA.runtimeIdentity, sessionB.runtimeIdentity);

      await sessionA.release();
      await sessionB.release();
    });

    test('全部租约释放后实例仍被保温，再次获取复用同一实例与同一 generation', () async {
      final factory = _CountingProviderFactory();
      final registry = AgentProviderRuntimeRegistry(providerFactory: factory);
      addTearDown(registry.close);
      final first = await registry.acquire(
        AgentProviderConfig.defaultCodex,
        scope: AgentProviderRuntimeScopeKey.global,
      );
      final firstIdentity = first.runtimeIdentity;

      await first.release();

      expect(registry.debugLeaseCount, 0);
      expect(registry.debugProviderCount, 1);
      expect(factory.providers.single.disposeCount, 0);

      final second = await registry.acquire(
        AgentProviderConfig.defaultCodex,
        scope: AgentProviderRuntimeScopeKey.global,
      );

      expect(factory.createCount, 1);
      expect(identical(second.provider, first.provider), isTrue);
      expect(second.runtimeIdentity, firstIdentity);
      await second.release();
    });

    test('仍有活跃租约时 invalidateProvider 照样销毁实例', () async {
      final factory = _CountingProviderFactory();
      final registry = AgentProviderRuntimeRegistry(providerFactory: factory);
      addTearDown(registry.close);
      final lease = await registry.acquire(
        AgentProviderConfig.defaultCodex,
        scope: AgentProviderRuntimeScopeKey.global,
      );
      expect(registry.debugLeaseCount, 1);

      await registry.invalidateProvider(AgentProviderConfig.defaultCodex.id);

      expect(factory.providers.single.disposeCount, 1);
      expect(lease.isCurrent, isFalse);
      expect(registry.debugProviderCount, 0);
    });

    test('重复释放同一租约不会让计数变负，也不会误伤其他租约', () async {
      final factory = _CountingProviderFactory();
      final registry = AgentProviderRuntimeRegistry(providerFactory: factory);
      addTearDown(registry.close);
      final first = await registry.acquire(
        AgentProviderConfig.defaultCodex,
        scope: AgentProviderRuntimeScopeKey.global,
      );
      final second = await registry.acquire(
        AgentProviderConfig.defaultCodex,
        scope: AgentProviderRuntimeScopeKey.global,
      );

      await first.release();
      await first.release();
      await first.release();

      expect(registry.debugLeaseCount, 1);
      expect(factory.providers.single.disposeCount, 0);

      await second.release();

      expect(registry.debugLeaseCount, 0);
      expect(factory.providers.single.disposeCount, 0);
    });

    test('实例 dispose 抛错时 invalidateProvider 不外泄异常且可立即重建', () async {
      final factory = _CountingProviderFactory(disposeThrows: true);
      final registry = AgentProviderRuntimeRegistry(providerFactory: factory);
      addTearDown(registry.close);
      final first = await registry.acquire(
        AgentProviderConfig.defaultCodex,
        scope: AgentProviderRuntimeScopeKey.global,
      );

      await registry.invalidateProvider(AgentProviderConfig.defaultCodex.id);
      final second = await registry.acquire(
        AgentProviderConfig.defaultCodex,
        scope: AgentProviderRuntimeScopeKey.global,
      );

      expect(factory.createCount, 2);
      expect(identical(second.provider, first.provider), isFalse);
      expect(
        second.runtimeIdentity.generation,
        first.runtimeIdentity.generation + 1,
      );
      await second.release();
    });
  });

  group('scope 复合键（S2）', () {
    test('显式 global scope 的多个调用复用同一个实例', () async {
      final factory = _CountingProviderFactory();
      final registry = AgentProviderRuntimeRegistry(providerFactory: factory);
      addTearDown(registry.close);

      final first = await registry.acquire(
        AgentProviderConfig.defaultCodex,
        scope: AgentProviderRuntimeScopeKey.global,
      );
      final second = await registry.acquire(
        AgentProviderConfig.defaultCodex,
        scope: AgentProviderRuntimeScopeKey.global,
      );

      expect(factory.createCount, 1);
      expect(identical(first.provider, second.provider), isTrue);

      await first.release();
      await second.release();
    });

    test('两个不同 session scope 各自拿到独立实例', () async {
      final factory = _CountingProviderFactory();
      final registry = AgentProviderRuntimeRegistry(providerFactory: factory);
      addTearDown(registry.close);

      final sessionA = await registry.acquire(
        AgentProviderConfig.defaultCodex,
        scope: const AgentProviderRuntimeScopeKey.session('entry-a'),
      );
      final sessionB = await registry.acquire(
        AgentProviderConfig.defaultCodex,
        scope: const AgentProviderRuntimeScopeKey.session('entry-b'),
      );
      // 同一个 session id 再次获取应复用同一个实例。
      final sessionAAgain = await registry.acquire(
        AgentProviderConfig.defaultCodex,
        scope: const AgentProviderRuntimeScopeKey.session('entry-a'),
      );

      expect(factory.createCount, 2);
      expect(identical(sessionA.provider, sessionB.provider), isFalse);
      expect(identical(sessionA.provider, sessionAAgain.provider), isTrue);

      await sessionA.release();
      await sessionB.release();
      await sessionAAgain.release();
    });

    test('global 与 session scope 互不干扰：各自独立实例，互相失效不影响对方', () async {
      final factory = _CountingProviderFactory();
      final registry = AgentProviderRuntimeRegistry(providerFactory: factory);
      addTearDown(registry.close);
      const sessionScope = AgentProviderRuntimeScopeKey.session('entry-a');

      final global = await registry.acquire(
        AgentProviderConfig.defaultCodex,
        scope: AgentProviderRuntimeScopeKey.global,
      );
      final session = await registry.acquire(
        AgentProviderConfig.defaultCodex,
        scope: sessionScope,
      );

      expect(factory.createCount, 2);
      expect(identical(global.provider, session.provider), isFalse);

      await registry.invalidateScope(
        AgentProviderConfig.defaultCodex.id,
        sessionScope,
      );

      expect(global.isCurrent, isTrue);
      expect(session.isCurrent, isFalse);
      expect(registry.debugProviderCount, 1);

      await global.release();
    });

    test('invalidateScope 只关闭指定 scope 的实例，其余 scope 不受影响', () async {
      final factory = _CountingProviderFactory();
      final registry = AgentProviderRuntimeRegistry(providerFactory: factory);
      addTearDown(registry.close);
      const scopeA = AgentProviderRuntimeScopeKey.session('entry-a');
      const scopeB = AgentProviderRuntimeScopeKey.session('entry-b');

      final leaseA = await registry.acquire(
        AgentProviderConfig.defaultCodex,
        scope: scopeA,
      );
      final leaseB = await registry.acquire(
        AgentProviderConfig.defaultCodex,
        scope: scopeB,
      );

      await registry.invalidateScope(
        AgentProviderConfig.defaultCodex.id,
        scopeA,
      );

      expect(leaseA.isCurrent, isFalse);
      expect(leaseB.isCurrent, isTrue);
      expect(registry.debugProviderCount, 1);
      expect(
        factory.providers
            .firstWhere((provider) => identical(provider, leaseA.provider))
            .disposeCount,
        1,
      );
      expect(
        factory.providers
            .firstWhere((provider) => identical(provider, leaseB.provider))
            .disposeCount,
        0,
      );

      await leaseB.release();
    });

    test('invalidateProvider 仍会关闭该 Provider 在全部 scope 下的实例', () async {
      final factory = _CountingProviderFactory();
      final registry = AgentProviderRuntimeRegistry(providerFactory: factory);
      addTearDown(registry.close);

      final global = await registry.acquire(
        AgentProviderConfig.defaultCodex,
        scope: AgentProviderRuntimeScopeKey.global,
      );
      final sessionA = await registry.acquire(
        AgentProviderConfig.defaultCodex,
        scope: const AgentProviderRuntimeScopeKey.session('entry-a'),
      );
      final sessionB = await registry.acquire(
        AgentProviderConfig.defaultCodex,
        scope: const AgentProviderRuntimeScopeKey.session('entry-b'),
      );
      // 不同 Provider 的实例不应被误伤。
      final grok = await registry.acquire(
        AgentProviderConfig.defaultGrok,
        scope: AgentProviderRuntimeScopeKey.global,
      );

      await registry.invalidateProvider(AgentProviderConfig.defaultCodex.id);

      expect(global.isCurrent, isFalse);
      expect(sessionA.isCurrent, isFalse);
      expect(sessionB.isCurrent, isFalse);
      expect(grok.isCurrent, isTrue);
      expect(registry.debugProviderCount, 1);

      await grok.release();
    });

    test('不同 session scope 各自维护独立的 runtime generation，identity 不会撞车', () async {
      final factory = _CountingProviderFactory();
      final registry = AgentProviderRuntimeRegistry(providerFactory: factory);
      addTearDown(registry.close);

      final global = await registry.acquire(
        AgentProviderConfig.defaultCodex,
        scope: AgentProviderRuntimeScopeKey.global,
      );
      final session = await registry.acquire(
        AgentProviderConfig.defaultCodex,
        scope: const AgentProviderRuntimeScopeKey.session('entry-a'),
      );

      expect(global.runtimeIdentity, isNot(session.runtimeIdentity));
      expect(
        global.runtimeIdentity.generation,
        isNot(session.runtimeIdentity.generation),
      );

      await global.release();
      await session.release();
    });
  });

  group('Binding runtime 隔离', () {
    test('session runtime 与 global runtime 使用不同 identity', () async {
      final registry = AgentProviderRuntimeRegistry(
        providerFactory: _CountingProviderFactory(),
      );
      addTearDown(registry.close);

      final global = await registry.acquire(
        AgentProviderConfig.defaultCodex,
        scope: AgentProviderRuntimeScopeKey.global,
      );
      final session = await registry.acquire(
        AgentProviderConfig.defaultCodex,
        scope: const AgentProviderRuntimeScopeKey.session('binding-1'),
      );

      expect(session.runtimeIdentity, isNot(global.runtimeIdentity));
      expect(
        session.runtimeIdentity.providerId,
        global.runtimeIdentity.providerId,
      );
      await global.release();
      await session.release();
    });

    test('同 scope 重建会等待旧进程 dispose，旧 identity 不能误杀新实例', () async {
      const scope = AgentProviderRuntimeScopeKey.session('binding-1');
      final factory = _GatedDisposeProviderFactory();
      final registry = AgentProviderRuntimeRegistry(providerFactory: factory);
      addTearDown(registry.close);
      final first = await registry.acquire(
        AgentProviderConfig.defaultCodex,
        scope: scope,
      );

      final invalidating = registry.invalidateScopeIfCurrent(
        providerId: defaultAgentProviderId,
        scope: scope,
        expectedIdentity: first.runtimeIdentity,
      );
      await factory.disposeStarted.future;
      var acquiredReplacement = false;
      final replacementFuture = registry
          .acquire(AgentProviderConfig.defaultCodex, scope: scope)
          .then((lease) {
            acquiredReplacement = true;
            return lease;
          });
      await Future<void>.delayed(Duration.zero);

      expect(acquiredReplacement, isFalse);
      expect(factory.providers, hasLength(1));

      factory.allowDispose.complete();
      await invalidating;
      final replacement = await replacementFuture;
      expect(factory.providers, hasLength(2));
      expect(
        await registry.invalidateScopeIfCurrent(
          providerId: defaultAgentProviderId,
          scope: scope,
          expectedIdentity: first.runtimeIdentity,
        ),
        isFalse,
      );
      expect(replacement.isCurrent, isTrue);
    });
  });
}

final class _CountingProviderFactory extends AgentProviderFactory {
  _CountingProviderFactory({this.disposeThrows = false});

  final bool disposeThrows;
  final List<_FakeProvider> providers = <_FakeProvider>[];

  int get createCount => providers.length;

  @override
  AgentProvider create(AgentProviderConfig config) {
    final provider = _FakeProvider(config, disposeThrows: disposeThrows);
    providers.add(provider);
    return provider;
  }
}

final class _FakeProvider extends Fake implements AgentProvider {
  _FakeProvider(this.config, {this.disposeThrows = false});

  @override
  final AgentProviderConfig config;

  final bool disposeThrows;

  int disposeCount = 0;

  @override
  Future<void> dispose() async {
    disposeCount += 1;
    if (disposeThrows) {
      throw StateError('dispose failed');
    }
  }
}

final class _SingleProviderFactory extends AgentProviderFactory {
  _SingleProviderFactory(this.provider);

  final AgentProvider provider;

  @override
  AgentProvider create(AgentProviderConfig config) => provider;
}

final class _GatedDisposeProviderFactory implements AgentProviderFactory {
  final List<_GatedDisposeProvider> providers = <_GatedDisposeProvider>[];
  final Completer<void> disposeStarted = Completer<void>();
  final Completer<void> allowDispose = Completer<void>();

  @override
  AgentProvider create(AgentProviderConfig config) {
    final provider = _GatedDisposeProvider(
      config,
      isFirst: providers.isEmpty,
      disposeStarted: disposeStarted,
      allowDispose: allowDispose,
    );
    providers.add(provider);
    return provider;
  }
}

final class _GatedDisposeProvider extends Fake implements AgentProvider {
  _GatedDisposeProvider(
    this.config, {
    required this.isFirst,
    required this.disposeStarted,
    required this.allowDispose,
  });

  @override
  final AgentProviderConfig config;
  final bool isFirst;
  final Completer<void> disposeStarted;
  final Completer<void> allowDispose;

  @override
  Future<void> dispose() async {
    if (!isFirst) {
      return;
    }
    if (!disposeStarted.isCompleted) {
      disposeStarted.complete();
    }
    await allowDispose.future;
  }
}

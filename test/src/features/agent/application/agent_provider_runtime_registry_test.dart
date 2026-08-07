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
          (_) => registry.acquire(AgentProviderConfig.defaultCodex),
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

      final codexA = await registry.acquire(AgentProviderConfig.defaultCodex);
      final grokA = await registry.acquire(AgentProviderConfig.defaultGrok);
      final codexB = await registry.acquire(AgentProviderConfig.defaultCodex);
      final grokB = await registry.acquire(AgentProviderConfig.defaultGrok);

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
      final first = await registry.acquire(AgentProviderConfig.defaultCodex);
      final firstProvider = first.provider as _FakeProvider;
      final changed = AgentProviderConfig.defaultCodex.copyWith(
        command: 'codex-next',
      );

      final second = await registry.acquire(changed);

      expect(factory.createCount, 2);
      expect(first.isCurrent, isFalse);
      expect(firstProvider.disposeCount, 1);
      expect(identical(first.provider, second.provider), isFalse);

      await first.release();
      await second.release();
      await registry.close();
      expect((second.provider as _FakeProvider).disposeCount, 1);
    });

    test('重建 Provider 时递增 runtime generation 并退役旧状态', () async {
      final factory = _CountingProviderFactory();
      final registry = AgentProviderRuntimeRegistry(providerFactory: factory);
      final first = await registry.acquire(AgentProviderConfig.defaultGrok);
      final firstIdentity = first.runtimeIdentity;

      await registry.invalidateProvider(AgentProviderConfig.defaultGrok.id);
      final second = await registry.acquire(AgentProviderConfig.defaultGrok);

      expect(first.isCurrent, isFalse);
      expect(second.runtimeIdentity.providerId, firstIdentity.providerId);
      expect(second.runtimeIdentity.generation, firstIdentity.generation + 1);
      expect(registry.permissionStateStore.isCurrent(firstIdentity), isFalse);
      expect(
        registry.permissionStateStore.isCurrent(second.runtimeIdentity),
        isTrue,
      );

      await first.release();
      await second.release();
      await registry.close();
    });

    test('关闭后拒绝创建新运行时且 close 幂等', () async {
      final factory = _CountingProviderFactory();
      final registry = AgentProviderRuntimeRegistry(providerFactory: factory);
      await registry.acquire(AgentProviderConfig.defaultCodex);

      await Future.wait(<Future<void>>[registry.close(), registry.close()]);

      expect(factory.providers.single.disposeCount, 1);
      expect(
        () => registry.acquire(AgentProviderConfig.defaultCodex),
        throwsStateError,
      );
    });

    test('身份错配不得关闭已被其他 entry 持有的实例', () async {
      final shared = _FakeProvider(AgentProviderConfig.defaultCodex);
      final registry = AgentProviderRuntimeRegistry(
        providerFactory: _SingleProviderFactory(shared),
      );
      final codex = await registry.acquire(AgentProviderConfig.defaultCodex);

      await expectLater(
        registry.acquire(AgentProviderConfig.defaultGrok),
        throwsStateError,
      );

      expect(codex.isCurrent, isTrue);
      expect(shared.disposeCount, 0);

      await registry.close();
      expect(shared.disposeCount, 1);
    });
  });

  // 会话级 Provider 实例改造的安全网。这些用例钉住的是**当前**语义：实例按
  // providerId 共享、租约计数归零后继续保温、销毁只由 invalidate/close 触发。
  // 改造后它们的断言会变，那正是行为变更的可见证据（见 01-动机与止损线.md）。
  group('实例保温与销毁语义（会话级改造前的 characterization）', () {
    test('同一 Provider 的多个消费者共享同一实例与同一 runtime identity', () async {
      final factory = _CountingProviderFactory();
      final registry = AgentProviderRuntimeRegistry(providerFactory: factory);
      addTearDown(registry.close);

      final sessionA = await registry.acquire(AgentProviderConfig.defaultGrok);
      final sessionB = await registry.acquire(AgentProviderConfig.defaultGrok);

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
      final first = await registry.acquire(AgentProviderConfig.defaultCodex);
      final firstIdentity = first.runtimeIdentity;

      await first.release();

      expect(registry.debugLeaseCount, 0);
      expect(registry.debugProviderCount, 1);
      expect(factory.providers.single.disposeCount, 0);

      final second = await registry.acquire(AgentProviderConfig.defaultCodex);

      expect(factory.createCount, 1);
      expect(identical(second.provider, first.provider), isTrue);
      expect(second.runtimeIdentity, firstIdentity);
      await second.release();
    });

    test('仍有活跃租约时 invalidateProvider 照样销毁实例', () async {
      final factory = _CountingProviderFactory();
      final registry = AgentProviderRuntimeRegistry(providerFactory: factory);
      addTearDown(registry.close);
      final lease = await registry.acquire(AgentProviderConfig.defaultCodex);
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
      final first = await registry.acquire(AgentProviderConfig.defaultCodex);
      final second = await registry.acquire(AgentProviderConfig.defaultCodex);

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
      final first = await registry.acquire(AgentProviderConfig.defaultCodex);

      await registry.invalidateProvider(AgentProviderConfig.defaultCodex.id);
      final second = await registry.acquire(AgentProviderConfig.defaultCodex);

      expect(factory.createCount, 2);
      expect(identical(second.provider, first.provider), isFalse);
      expect(
        second.runtimeIdentity.generation,
        first.runtimeIdentity.generation + 1,
      );
      await second.release();
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

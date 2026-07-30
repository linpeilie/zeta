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
}

final class _CountingProviderFactory extends AgentProviderFactory {
  final List<_FakeProvider> providers = <_FakeProvider>[];

  int get createCount => providers.length;

  @override
  AgentProvider create(AgentProviderConfig config) {
    final provider = _FakeProvider(config);
    providers.add(provider);
    return provider;
  }
}

final class _FakeProvider extends Fake implements AgentProvider {
  _FakeProvider(this.config);

  @override
  final AgentProviderConfig config;

  int disposeCount = 0;

  @override
  Future<void> dispose() async {
    disposeCount += 1;
  }
}

final class _SingleProviderFactory extends AgentProviderFactory {
  _SingleProviderFactory(this.provider);

  final AgentProvider provider;

  @override
  AgentProvider create(AgentProviderConfig config) => provider;
}

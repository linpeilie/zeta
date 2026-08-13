import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/agent/data/default_agent_provider_factory.dart';
import 'package:zeta/src/features/agent/data/legacy_agent_provider_factory_bundle_adapter.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';

import '../../../testing/ide_test_harness.dart';

void main() {
  group('LegacyAgentProviderFactoryBundleAdapter', () {
    test('adapt 旧 Factory 后只通过 createBundle 发布端口', () {
      final provider = FakeAgentProvider();
      final factory = _LegacyOnlyFactory(provider);
      final adapter = LegacyAgentProviderFactoryBundleAdapter(factory);

      final bundle = adapter.createBundle(AgentProviderConfig.defaultCodex);

      expect(bundle.runtime.config.id, provider.config.id);
      expect(bundle.conversation, isNotNull);
      expect(factory.createCount, 1);
    });

    test('asAgentProviderBundleFactory 对已实现 Bundle 工厂的对象直接返回', () {
      const factory = DefaultAgentProviderFactory();

      expect(identical(asAgentProviderBundleFactory(factory), factory), isTrue);
    });

    test('asAgentProviderBundleFactory 把纯旧 Factory 包成 adapter', () {
      final factory = _LegacyOnlyFactory(FakeAgentProvider());
      final adapted = asAgentProviderBundleFactory(factory);

      expect(adapted, isA<LegacyAgentProviderFactoryBundleAdapter>());
      final bundle = adapted.createBundle(AgentProviderConfig.defaultCodex);
      expect(bundle.runtime.config.id, defaultAgentProviderId);
    });
  });
}

class _LegacyOnlyFactory extends AgentProviderFactory {
  _LegacyOnlyFactory(this.provider);

  final FakeAgentProvider provider;
  int createCount = 0;

  @override
  AgentProvider create(AgentProviderConfig config) {
    createCount += 1;
    return provider;
  }
}

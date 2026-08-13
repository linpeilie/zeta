import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider_bundle.dart';

import 'ide_test_harness.dart';

void main() {
  group('FakeAgentProviderBundleBuilder', () {
    test('默认只发布 runtime 与 conversation', () {
      final provider = FakeAgentProvider();
      final factory = FakeAgentProviderBundleBuilder(
        runtime: AgentProviderBundle.adapt(provider).runtime,
        conversation: AgentProviderBundle.adapt(provider).conversation,
      );

      final bundle = factory.createBundle(AgentProviderConfig.defaultCodex);

      expect(bundle.runtime, isNotNull);
      expect(bundle.conversation, isNotNull);
      expect(bundle.threadCatalog, isNull);
      expect(bundle.threadSubscription, isNull);
      expect(bundle.threadNaming, isNull);
      expect(bundle.threadArchival, isNull);
      expect(bundle.threadDeletion, isNull);
      expect(bundle.threadCompaction, isNull);
      expect(bundle.threadBranching, isNull);
      expect(bundle.turnSteering, isNull);
      expect(bundle.permissionResponses, isNull);
      expect(bundle.questions, isNull);
      expect(bundle.deniedActionOverride, isNull);
      expect(bundle.modelCatalog, isNull);
      expect(bundle.conversationModes, isNull);
      expect(bundle.skills, isNull);
      expect(bundle.localThreadList, isNull);
      expect(bundle.sessionConfiguration, isNull);
      expect(bundle.planApproval, isNull);
      expect(bundle.permissionPolicy, isNull);
      expect(bundle.usageQuota, isNull);
    });

    test('fromFake 按 Fake 已实现接口发布可选端口', () {
      final provider = FakeAgentProvider();
      final factory = FakeAgentProviderBundleBuilder.fromFake(provider);
      final bundle = factory.createBundle(AgentProviderConfig.defaultCodex);
      final adapted = AgentProviderBundle.adapt(provider);

      expect(bundle.threadCatalog != null, adapted.threadCatalog != null);
      expect(bundle.localThreadList, isNotNull);
      expect(bundle.questions, isNotNull);
      expect(bundle.permissionPolicy, isNotNull);
    });

    test('createBundle 复用同一 Bundle 实例', () {
      final factory = FakeAgentProviderBundleBuilder.fromFake(
        FakeAgentProvider(),
      );

      final first = factory.createBundle(AgentProviderConfig.defaultCodex);
      final second = factory.createBundle(AgentProviderConfig.defaultGrok);

      expect(identical(first, second), isTrue);
    });
  });
}

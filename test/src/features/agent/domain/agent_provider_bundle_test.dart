import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/app/plugins/agent_provider_manifest.dart';

import '../../../testing/ide_test_harness.dart';
import '../../../testing/test_agent_provider_bundle_factory.dart';

void main() {
  group('native test bundle assembly', () {
    test('FakeAgentProvider publishes the ports it implements', () {
      final provider = FakeAgentProvider();
      final bundle = testAgentProviderBundle(provider);

      expect(identical(bundle.runtime, provider), isTrue);
      expect(identical(bundle.conversation, provider), isTrue);
      expect(bundle.threadCatalog, isNotNull);
      expect(bundle.localThreadList, isNotNull);
      expect(bundle.questions, isNotNull);
      expect(bundle.permissionPolicy, isNotNull);
      expect(bundle.sessionConfiguration, isNull);
      expect(bundle.planApproval, isNull);
    });

    test(
      'explicit builder still defaults to runtime and conversation only',
      () {
        final provider = FakeAgentProvider();
        final bundle = FakeAgentProviderBundleBuilder(
          runtime: provider,
          conversation: provider,
        ).createBundle(defaultCodexAgentProviderConfig);

        expect(bundle.threadCatalog, isNull);
        expect(bundle.permissionPolicy, isNull);
      },
    );
  });
}

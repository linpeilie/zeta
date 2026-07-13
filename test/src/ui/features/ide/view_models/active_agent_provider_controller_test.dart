import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/ui/features/ide/view_models/active_agent_provider_controller.dart';

import '../../../../testing/ide_test_harness.dart';

void main() {
  group('ActiveAgentProviderController', () {
    test(
      'does not dispose the active provider when disabling another one',
      () async {
        // Arrange
        final activeProvider = _TrackingFakeAgentProvider();
        final controller = ActiveAgentProviderController(
          providerFactory: FakeAgentProviderFactory(activeProvider),
          configStore: MemoryAgentProviderConfigStore(
            const AgentProviderSettings(),
          ),
        );
        addTearDown(controller.dispose);
        await controller.activeProvider();

        // Act
        await controller.setProviderEnabled(grokAgentProviderId, false);

        // Assert
        expect(activeProvider.disposeCount, 0);
        expect(controller.activeProviderId, defaultAgentProviderId);
      },
    );

    test(
      'moves active provider to an enabled fallback when disabled',
      () async {
        // Arrange
        final activeProvider = _TrackingFakeAgentProvider();
        final controller = ActiveAgentProviderController(
          providerFactory: FakeAgentProviderFactory(activeProvider),
          configStore: MemoryAgentProviderConfigStore(
            const AgentProviderSettings(),
          ),
        );
        addTearDown(controller.dispose);
        await controller.activeProvider();

        // Act
        await controller.setProviderEnabled(defaultAgentProviderId, false);

        // Assert
        expect(activeProvider.disposeCount, 1);
        expect(controller.activeProviderId, grokAgentProviderId);
        expect(controller.isProviderEnabled(grokAgentProviderId), isTrue);
      },
    );
  });
}

class _TrackingFakeAgentProvider extends FakeAgentProvider {
  int disposeCount = 0;

  @override
  Future<void> dispose() async {
    disposeCount += 1;
    await super.dispose();
  }
}

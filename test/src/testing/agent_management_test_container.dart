import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/app/agent_management_slice/agent_management_slice_composition.dart';
import 'package:zeta/src/app/plugins/agent_provider_icon_overrides.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_dependencies.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_notifier.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_state.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

/// Test lifetime only; production Notifier/runner and app input seams own behavior.
ProviderContainer managementTestContainer({
  bool registerTearDown = true,
  required AgentManagementSliceState initialState,
  required AgentManagementSliceEffectRunner effectRunner,
  required String configurationNotLoadedMessage,
  required bool Function(AgentProviderConfig) accountDataEnrichmentEnabledFor,
}) {
  final container = ProviderContainer(
    overrides: [
      agentProviderIconsOverride(),
      agentManagementSliceDependenciesProvider.overrideWithValue(
        AgentManagementSliceDependencies(
          initialState: initialState,
          configurationNotLoadedMessage: configurationNotLoadedMessage,
          accountDataEnrichmentEnabledFor: accountDataEnrichmentEnabledFor,
        ),
      ),
      agentManagementRunnerFactoryProvider.overrideWithValue(
        (_) => effectRunner,
      ),
    ],
  );
  if (registerTearDown) {
    addTearDown(() => closeManagementTestContainer(container));
  }
  return container;
}

ProviderContainer managementAppTestContainer(
  AgentManagementCompositionInputs inputs,
) {
  final container = ProviderContainer(
    overrides: [
      agentProviderIconsOverride(),
      ...agentManagementSliceOverrides(),
      agentManagementCompositionInputsProvider.overrideWithValue(inputs),
    ],
  );
  container.read(agentManagementSliceProvider.notifier);
  container.read(agentManagementSettingsIngressProvider).start();
  return container;
}

Future<void> closeManagementTestContainer(ProviderContainer container) async {
  final owner = container.read(agentManagementSliceProvider.notifier);
  owner.stopAcceptingCommandsAndSettleWaiters();
  await owner.drainExecutions();
  container.dispose();
}

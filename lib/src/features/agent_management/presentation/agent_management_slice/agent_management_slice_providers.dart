import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_state.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_notifier.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';

/// Read-only projections of the app-session owner.
final agentManagementAgentsProvider = Provider<List<ManagedAgent>>(
  (ref) => ref.watch(
    agentManagementSliceProvider.select(AgentManagementSliceSelectors.agents),
  ),
);
final agentManagementSelectedAgentProvider = Provider<ManagedAgent>(
  (ref) => ref.watch(
    agentManagementSliceProvider.select(
      AgentManagementSliceSelectors.selectedAgent,
    ),
  ),
);
final agentManagementDetectionProgressProvider =
    Provider<AgentDetectionProgress?>(
      (ref) => ref.watch(
        agentManagementSliceProvider.select((state) => state.detectionProgress),
      ),
    );

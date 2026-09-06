import '../agent_management_detection_port.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';

sealed class AgentManagementSliceEffect {
  const AgentManagementSliceEffect();
}

final class ManagementInitializeEffect extends AgentManagementSliceEffect {
  const ManagementInitializeEffect(this.operationId);

  final OperationId operationId;
}

final class DetectAgentsEffect extends AgentManagementSliceEffect {
  const DetectAgentsEffect(
    this.operationId, {
    required this.providerIds,
    required this.catalogGeneration,
    required this.ownerGeneration,
    required this.cancellation,
  });
  final List<String> providerIds;
  final int catalogGeneration;
  final int ownerGeneration;
  final AgentManagementCancellation cancellation;

  final OperationId operationId;
}

final class UpdateProviderEnabledEffect extends AgentManagementSliceEffect {
  const UpdateProviderEnabledEffect({
    required this.operationId,
    required this.agentId,
    required this.enabled,
  });

  final OperationId operationId;
  final String agentId;
  final bool enabled;
}

final class UpdateAccountDataEnrichmentEffect
    extends AgentManagementSliceEffect {
  const UpdateAccountDataEnrichmentEffect({
    required this.operationId,
    required this.agentId,
    required this.enabled,
  });

  final OperationId operationId;
  final String agentId;
  final bool enabled;
}

final class TestAgentConnectionEffect extends AgentManagementSliceEffect {
  const TestAgentConnectionEffect({
    required this.operationId,
    required this.agentId,
  });

  final OperationId operationId;
  final String agentId;
}

final class LoadAgentConfigurationEffect extends AgentManagementSliceEffect {
  const LoadAgentConfigurationEffect({
    required this.operationId,
    required this.agentId,
  });

  final OperationId operationId;
  final String agentId;
}

final class SaveAgentConfigurationEffect extends AgentManagementSliceEffect {
  const SaveAgentConfigurationEffect({
    required this.operationId,
    required this.agentId,
    required this.original,
    required this.content,
    required this.overwriteExternalChanges,
  });

  final OperationId operationId;
  final String agentId;
  final AgentConfigurationDocument original;
  final String content;
  final bool overwriteExternalChanges;
}

final class LoadAgentLogsEffect extends AgentManagementSliceEffect {
  const LoadAgentLogsEffect({required this.operationId, required this.agentId});

  final OperationId operationId;
  final String agentId;
}

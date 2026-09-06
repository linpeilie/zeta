import '../agent_management_agent_view.dart';
import '../agent_management_detection_state.dart';
import '../agent_management_detection_port.dart';
import '../agent_management_runtime_facts.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';

sealed class AgentManagementSliceIntent {
  const AgentManagementSliceIntent();
}

final class ManagementInitializeRequested extends AgentManagementSliceIntent {
  const ManagementInitializeRequested(this.operationId);

  final OperationId operationId;
}

final class ManagementInitialized extends AgentManagementSliceIntent {
  const ManagementInitialized({
    required this.operationId,
    required this.providerSettings,
    required this.confirmedByProviderId,
  });

  final OperationId operationId;
  final AgentProviderSettings providerSettings;
  final Map<String, AgentDetectionConfirmedRecord> confirmedByProviderId;
}

final class ManagementInitializationFailed extends AgentManagementSliceIntent {
  const ManagementInitializationFailed(this.operationId);

  final OperationId operationId;
}

final class AgentSelected extends AgentManagementSliceIntent {
  const AgentSelected(this.agentId);

  final String agentId;
}

/// owner 生命周期 intent 不触发第二次探测 effect。
final class DetectionRequested extends AgentManagementSliceIntent {
  const DetectionRequested(this.operationId);
  final OperationId operationId;
}

final class DetectionRunStarted extends AgentManagementSliceIntent {
  const DetectionRunStarted(this.operationId, this.providerIds);
  final OperationId operationId;
  final List<String> providerIds;
}

final class DetectionResultAccepted extends AgentManagementSliceIntent {
  const DetectionResultAccepted(this.operationId, this.event);
  final OperationId operationId;
  final AgentManagementDetectionEvent event;
}

final class DetectionRunFinished extends AgentManagementSliceIntent {
  const DetectionRunFinished(this.operationId, this.result);
  final OperationId operationId;
  final AgentManagementDetectionRunResult result;
}

final class ManagementCatalogReplaced extends AgentManagementSliceIntent {
  const ManagementCatalogReplaced(this.generation, this.definitions);
  final int generation;
  final Map<String, AgentManagementDisplayDefinition> definitions;
}

final class ProviderEnabledToggled extends AgentManagementSliceIntent {
  const ProviderEnabledToggled({
    required this.operationId,
    required this.agentId,
    required this.enabled,
  });

  final OperationId operationId;
  final String agentId;
  final bool enabled;
}

final class ProviderEnabledUpdated extends AgentManagementSliceIntent {
  const ProviderEnabledUpdated({
    required this.operationId,
    required this.agentId,
    required this.enabled,
    required this.providerSettings,
  });

  final OperationId operationId;
  final String agentId;
  final bool enabled;
  final AgentProviderSettings providerSettings;
}

final class ProviderEnabledUpdateFailed extends AgentManagementSliceIntent {
  const ProviderEnabledUpdateFailed({
    required this.operationId,
    required this.agentId,
    required this.message,
  });

  final OperationId operationId;
  final String agentId;
  final String message;
}

final class AccountDataEnrichmentToggled extends AgentManagementSliceIntent {
  const AccountDataEnrichmentToggled({
    required this.operationId,
    required this.agentId,
    required this.enabled,
  });

  final OperationId operationId;
  final String agentId;
  final bool enabled;
}

final class AccountDataEnrichmentUpdated extends AgentManagementSliceIntent {
  const AccountDataEnrichmentUpdated({
    required this.operationId,
    required this.agentId,
    required this.providerSettings,
  });

  final OperationId operationId;
  final String agentId;
  final AgentProviderSettings providerSettings;
}

final class AccountDataEnrichmentUpdateFailed
    extends AgentManagementSliceIntent {
  const AccountDataEnrichmentUpdateFailed({
    required this.operationId,
    required this.agentId,
    required this.message,
  });

  final OperationId operationId;
  final String agentId;
  final String message;
}

final class ConnectionTestRequested extends AgentManagementSliceIntent {
  const ConnectionTestRequested({
    required this.operationId,
    required this.agentId,
  });

  final OperationId operationId;
  final String agentId;
}

final class ConnectionTestSucceeded extends AgentManagementSliceIntent {
  const ConnectionTestSucceeded({
    required this.operationId,
    required this.agentId,
    required this.result,
    required this.models,
    required this.modelSource,
    required this.modelsUpdatedAt,
  });

  final OperationId operationId;
  final String agentId;
  final AgentManagementConnectionCheckSummary result;
  final List<AgentModelInfo> models;
  final String modelSource;
  final DateTime modelsUpdatedAt;
}

final class ConnectionTestFailed extends AgentManagementSliceIntent {
  const ConnectionTestFailed({
    required this.operationId,
    required this.agentId,
    required this.message,
  });

  final OperationId operationId;
  final String agentId;
  final String message;
}

final class ConfigurationLoadRequested extends AgentManagementSliceIntent {
  const ConfigurationLoadRequested({
    required this.operationId,
    required this.agentId,
  });

  final OperationId operationId;
  final String agentId;
}

final class ConfigurationLoadSucceeded extends AgentManagementSliceIntent {
  const ConfigurationLoadSucceeded({
    required this.operationId,
    required this.agentId,
    required this.document,
  });

  final OperationId operationId;
  final String agentId;
  final AgentConfigurationDocument document;
}

final class ConfigurationLoadFailed extends AgentManagementSliceIntent {
  const ConfigurationLoadFailed({
    required this.operationId,
    required this.agentId,
    required this.message,
  });

  final OperationId operationId;
  final String agentId;
  final String message;
}

final class ConfigurationSaveRequested extends AgentManagementSliceIntent {
  const ConfigurationSaveRequested({
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

final class ConfigurationSaveSucceeded extends AgentManagementSliceIntent {
  const ConfigurationSaveSucceeded({
    required this.operationId,
    required this.agentId,
    required this.originalSignature,
    required this.result,
  });

  final OperationId operationId;
  final String agentId;
  final String originalSignature;
  final AgentConfigurationSaveResult result;
}

final class ConfigurationSaveFailed extends AgentManagementSliceIntent {
  const ConfigurationSaveFailed({
    required this.operationId,
    required this.agentId,
  });

  final OperationId operationId;
  final String agentId;
}

final class LogsLoadRequested extends AgentManagementSliceIntent {
  const LogsLoadRequested({required this.operationId, required this.agentId});

  final OperationId operationId;
  final String agentId;
}

final class LogsLoadSucceeded extends AgentManagementSliceIntent {
  const LogsLoadSucceeded({
    required this.operationId,
    required this.agentId,
    required this.fileCount,
    required this.logs,
  });

  final OperationId operationId;
  final String agentId;
  final int fileCount;
  final List<AgentLogEntry> logs;
}

final class LogsLoadFailed extends AgentManagementSliceIntent {
  const LogsLoadFailed({
    required this.operationId,
    required this.agentId,
    required this.message,
  });

  final OperationId operationId;
  final String agentId;
  final String message;
}

/// Provider settings store 的只读 ingress 快照。
final class ProviderSettingsSnapshotChanged extends AgentManagementSliceIntent {
  const ProviderSettingsSnapshotChanged(this.providerSettings);

  final AgentProviderSettings providerSettings;
}

/// Shell session 事实源的全量替换。
final class RuntimeFactsReplaced extends AgentManagementSliceIntent {
  const RuntimeFactsReplaced(this.facts);
  final AgentManagementRuntimeFacts facts;
}

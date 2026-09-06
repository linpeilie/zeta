import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_agent_view.dart';
import 'agent_management_details_catalog.dart';

AgentManagementDisplayDefinition managementDisplayDefinition(
  AgentDefinition definition,
) => AgentManagementDisplayDefinition(
  id: definition.id,
  displayName: definition.displayName,
  vendor: definition.vendor,
  commandName: definition.commandName,
  protocol: definition.protocol,
  transport: definition.transport,
  configFormat: definition.configFormat,
  isBeta: definition.isBeta,
);

AgentManagementConnectionCheckSummary managementConnectionSummary(
  AgentConnectionTestResult result, {
  AgentManagementDetailsHandle? handle,
}) => AgentManagementConnectionCheckSummary(
  success: result.success,
  testedAt: result.testedAt,
  elapsed: result.elapsed,
  cliCallable: result.cliCallable,
  accountValid: result.accountValid,
  protocolReady: result.protocolReady,
  failureStage: result.failureStage,
  message: safeManagementText(result.message),
  detailsHandle: handle,
  protocolVersion: safeManagementText(result.protocolVersion),
  agentName: safeManagementText(result.agentName),
  agentVersion: safeManagementText(result.agentVersion),
  capabilitySummary: result.capabilitySummary
      .map((v) => safeManagementText(v)!)
      .toList(),
  capabilityFingerprint: safeManagementText(result.capabilityFingerprint),
  compatibilitySummary: safeManagementText(result.compatibilitySummary),
  exitReason: safeManagementText(result.exitReason),
);

AgentDetectionDetails managementDetectionDetails(
  ManagedAgent agent, {
  AgentManagementDetailsHandle? handle,
}) => AgentDetectionDetails(
  installationState: agent.installationState,
  executableLocated: agent.executablePath != null,
  currentVersion: safeManagementText(agent.currentVersion),
  latestVersion: safeManagementText(agent.latestVersion),
  accountState: agent.accountState,
  accountLabel: safeManagementText(agent.accountLabel),
  versionState: agent.versionState,
  lastDetectedAt: agent.lastDetectedAt,
  errorStage: agent.errorStage,
  safeErrorMessage: safeManagementText(agent.errorMessage),
  safeSuggestion: safeManagementText(agent.suggestion),
  configExists: agent.configExists,
  configModifiedAt: agent.configModifiedAt,
  availableLogFileCount: agent.logPaths.length,
  detectedModels: agent.models,
  modelsUpdatedAt: agent.modelsUpdatedAt,
  modelSource: safeManagementText(agent.modelSource),
  connectionTest: agent.connectionTest == null
      ? null
      : managementConnectionSummary(agent.connectionTest!),
  detailsHandle: handle,
);
AgentDetectionPartial managementDetectionPartial(ManagedAgent agent) =>
    AgentDetectionPartial(
      installationState: agent.installationState,
      currentVersion: safeManagementText(agent.currentVersion),
      accountState: agent.accountState,
      versionState: agent.versionState,
    );

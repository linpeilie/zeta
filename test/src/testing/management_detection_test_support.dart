import 'dart:async';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta/src/app/agent_management_slice/agent_management_detection_projection.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_agent_view.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_detection_port.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_detection_state.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_state.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_notifier.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_effect.dart';
import 'agent_management_test_definitions.dart';
export 'package:zeta/src/features/agent_management/application/agent_management_agent_view.dart';
export 'package:zeta/src/features/agent_management/application/agent_management_detection_port.dart';
export 'package:zeta/src/features/agent_management/application/agent_management_detection_state.dart';

/// 旧 fixture 只在测试边界转换；生产 application 不接受 ManagedAgent。
AgentManagementSliceState managementFixtureState({
  required Map<String, ManagedAgent> agentsById,
  required List<String> orderedAgentIds,
  required String selectedAgentId,
  required Map<String, AgentCliManagementCapabilities> capabilitiesByAgentId,
  AgentProviderSettings providerSettings = const AgentProviderSettings(),
  bool initialized = false,
  Map<String, AgentConfigurationDocument>? confirmedConfigurationsByAgentId,
  Map<String, List<AgentLogEntry>>? logsByAgentId,
  Map<AgentManagementOperationKey, OperationId>? pendingOperations,
  AgentManagementFailure? failure,
}) => AgentManagementSliceState(
  definitionsByProviderId: {
    for (final e in agentsById.entries)
      e.key: managementDisplayDefinition(e.value.definition),
  },
  detection: AgentManagementDetectionState(
    confirmedByProviderId: {
      for (final e in agentsById.entries)
        e.key: AgentDetectionConfirmedRecord(
          details: managementDetectionDetails(e.value),
          freshness: DetectionFreshness.restoredCache,
        ),
    },
  ),
  orderedAgentIds: orderedAgentIds,
  selectedAgentId: selectedAgentId,
  capabilitiesByAgentId: capabilitiesByAgentId,
  providerSettings: providerSettings,
  initialized: initialized,
  confirmedConfigurationsByAgentId: confirmedConfigurationsByAgentId,
  logsByAgentId: logsByAgentId,
  pendingOperations: pendingOperations,
  failure: failure,
);
AgentManagementAgentView managementFixtureView(ManagedAgent agent) =>
    AgentManagementAgentView(
      definition: managementDisplayDefinition(agent.definition),
      details: managementDetectionDetails(agent),
      enabled: agent.enabled,
      runtimeState: agent.runtimeState,
    );
ManagedAgent fixtureForView(AgentManagementAgentView view) =>
    ManagedAgent.forDefinition(
      definition: testAgentManagementDefinitions[view.definition.id]!,
      enabled: view.enabled,
    ).copyWith(
      installationState: view.installationState,
      currentVersion: view.currentVersion,
      runtimeState: view.runtimeState,
    );

final _recorded = <OperationId, (DetectAgentsEffect, Completer<void>)>{};
Future<void> holdTestDetection(DetectAgentsEffect effect) {
  final gate = Completer<void>();
  _recorded[effect.operationId] = (effect, gate);
  return gate.future.whenComplete(() => _recorded.remove(effect.operationId));
}

void completeTestDetection(OperationId id) {
  final gate = _recorded[id]?.$2;
  if (gate != null && !gate.isCompleted) gate.complete();
}

void completeAllTestDetections() {
  for (final id in _recorded.keys.toList()) {
    completeTestDetection(id);
  }
}

extension ManagementDetectionTestIngress on AgentManagementSliceNotifier {
  void testDetectionStarted(OperationId id, String providerId) =>
      _report(id, DetectionProviderStarted(providerId));
  void testDetectionProgress(
    OperationId id,
    String providerId,
    AgentDetectionProgress progress,
    ManagedAgent partial,
  ) => _report(
    id,
    DetectionProviderProgress(
      providerId,
      progress,
      managementDetectionPartial(partial),
    ),
  );
  void testAgentDetected(
    OperationId id,
    String providerId,
    ManagedAgent agent,
  ) => _report(
    id,
    DetectionProviderSucceeded(providerId, managementDetectionDetails(agent)),
  );
  void testDetectionFailed(OperationId id, String message) {
    for (final e in current.detection.outcomesByProviderId.entries) {
      if (e.value == ProviderDetectionOutcome.pending) {
        _report(
          id,
          DetectionProviderFailed(
            e.key,
            AgentManagementFailure(
              kind: AgentManagementFailureKind.detection,
              operationId: id,
              agentId: e.key,
              message: message,
            ),
          ),
        );
      }
    }
    completeTestDetection(id);
  }

  void _report(OperationId id, AgentManagementDetectionEvent event) {
    final effect = _recorded[id]?.$1;
    if (effect == null) return;
    acceptDetectionResult(
      id,
      effect.ownerGeneration,
      effect.catalogGeneration,
      event,
    );
  }
}

/// 测试与生产共用事件端口；异步列表仅作为旧 fixture 输入转换成逐 Provider 事件。
final class FixtureManagementDetectionPort
    implements AgentManagementDetectionPort {
  FixtureManagementDetectionPort(this.load);
  final Future<List<ManagedAgent>> Function() load;
  int calls = 0;
  @override
  Future<void> detect({
    required OperationId operationId,
    required List<String> providerIds,
    required int catalogGeneration,
    required AgentManagementCancellation cancellation,
    required bool Function(AgentManagementDetectionEvent) emit,
  }) async {
    calls++;
    final agents = await load();
    cancellation.throwIfCanceled();
    for (final id in providerIds) {
      cancellation.throwIfCanceled();
      if (!emit(DetectionProviderStarted(id))) {
        throw const AgentManagementDetectionCanceled();
      }
      final agent = agents.where((a) => a.definition.id == id).firstOrNull;
      final details = agent == null
          ? AgentDetectionDetails(
              installationState: AgentInstallationState.notInstalled,
            )
          : managementDetectionDetails(agent);
      if (!emit(DetectionProviderSucceeded(id, details))) {
        throw const AgentManagementDetectionCanceled();
      }
    }
  }
}

import '../agent_management_agent_view.dart';
import '../agent_management_detection_state.dart';
import '../agent_management_detection_port.dart';
import '../agent_management_runtime_aggregation.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_effect.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_intent.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_state.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';

/// 所有 ingress 共用出口；探测/初始化/连接测试不得覆盖 session 运行事实。
Transition<AgentManagementSliceState, AgentManagementSliceEffect>
agentManagementSliceReduce(
  AgentManagementSliceState state,
  AgentManagementSliceIntent intent,
) {
  final transition = _reduce(state, intent);
  return Transition(
    projectManagementRuntimeState(transition.state),
    transition.effects,
  );
}

AgentManagementSliceState projectManagementRuntimeState(
  AgentManagementSliceState state,
) {
  final enabled = <String, bool>{
    for (final agent in state.agentsById.entries)
      agent.key: agent.value.enabled,
    for (final config in state.providerSettings.providers)
      config.id: config.enabled,
  };
  final summaries = aggregateManagementRuntime(state.runtimeFacts, enabled);
  return zetaMapEquals(summaries, state.runtimeByProviderId)
      ? state
      : state.copyWith(runtimeByProviderId: summaries);
}

/// Agent 管理页的纯同步 reducer。
Transition<AgentManagementSliceState, AgentManagementSliceEffect> _reduce(
  AgentManagementSliceState state,
  AgentManagementSliceIntent intent,
) {
  switch (intent) {
    case ManagementInitializeRequested():
      final key = _globalKey(AgentManagementOperationKind.initialize);
      return Transition(
        state.copyWith(
          pendingOperations: _putPending(
            state.pendingOperations,
            key,
            intent.operationId,
          ),
          failure: null,
        ),
        <AgentManagementSliceEffect>[
          ManagementInitializeEffect(intent.operationId),
        ],
      );

    case ManagementInitialized():
      final key = _globalKey(AgentManagementOperationKind.initialize);
      if (!_accepts(state, key, intent.operationId)) {
        return Transition.none(state);
      }
      return Transition.stateOnly(
        state.copyWith(
          detection: state.detection.copyWith(
            confirmedByProviderId: {
              ...intent.confirmedByProviderId,
              ...state.detection.confirmedByProviderId,
            },
          ),
          providerSettings: intent.providerSettings,
          pendingOperations: _removePending(state.pendingOperations, key),
          initialized: true,
          failure: null,
        ),
      );

    case ManagementInitializationFailed():
      final key = _globalKey(AgentManagementOperationKind.initialize);
      if (!_accepts(state, key, intent.operationId)) {
        return Transition.none(state);
      }
      return Transition.stateOnly(
        state.copyWith(
          pendingOperations: _removePending(state.pendingOperations, key),
          failure: AgentManagementFailure(
            kind: AgentManagementFailureKind.initialization,
            operationId: intent.operationId,
          ),
        ),
      );

    case AgentSelected():
      if (state.selectedAgentId == intent.agentId ||
          !state.agentsById.containsKey(intent.agentId)) {
        return Transition.none(state);
      }
      return Transition.stateOnly(
        state.copyWith(selectedAgentId: intent.agentId, failure: null),
      );

    case DetectionRequested():
      return Transition.stateOnly(
        state.copyWith(
          detection: AgentManagementDetectionState(
            phase: ManagementDetectionPhase.initializing,
            operationId: intent.operationId,
            automaticAttemptConsumed: true,
            confirmedByProviderId: {
              for (final e in state.detection.confirmedByProviderId.entries)
                e.key: e.value.stale(),
            },
          ),
        ),
      );
    case DetectionRunStarted():
      if (state.detection.operationId != intent.operationId ||
          !state.detection.isLoading) {
        return Transition.none(state);
      }
      return Transition.stateOnly(
        state.copyWith(
          detection: state.detection.copyWith(
            phase: ManagementDetectionPhase.running,
            outcomesByProviderId: {
              for (final id in intent.providerIds)
                id: ProviderDetectionOutcome.pending,
            },
          ),
        ),
      );
    case DetectionResultAccepted():
      return Transition.stateOnly(_acceptDetectionEvent(state, intent));
    case DetectionRunFinished():
      if (state.detection.operationId != intent.operationId ||
          !state.detection.isLoading) {
        return Transition.none(state);
      }
      final canceled =
          intent.result.status == DetectionRunStatus.canceled ||
          intent.result.status == DetectionRunStatus.closed;
      return Transition.stateOnly(
        state.copyWith(
          detection: state.detection.copyWith(
            phase: switch (intent.result.status) {
              DetectionRunStatus.succeeded =>
                ManagementDetectionPhase.succeeded,
              DetectionRunStatus.partialFailure =>
                ManagementDetectionPhase.partialFailure,
              DetectionRunStatus.failed => ManagementDetectionPhase.failed,
              _ => ManagementDetectionPhase.canceled,
            },
            outcomesByProviderId: {
              for (final e in state.detection.outcomesByProviderId.entries)
                e.key: e.value == ProviderDetectionOutcome.pending
                    ? (canceled
                          ? ProviderDetectionOutcome.canceled
                          : ProviderDetectionOutcome.failed)
                    : e.value,
            },
            pendingPartialByProviderId: {},
            progressByProviderId: {},
            lastResult: intent.result,
          ),
          detectionProgress: null,
          detectingAgentId: null,
        ),
      );
    case ManagementCatalogReplaced():
      return Transition.stateOnly(
        state.copyWith(
          catalogGeneration: intent.generation,
          definitionsByProviderId: intent.definitions,
          orderedAgentIds: intent.definitions.keys.toList(),
          detection: AgentManagementDetectionState(
            automaticAttemptConsumed: state.detection.automaticAttemptConsumed,
            phase: ManagementDetectionPhase.canceled,
            lastResult: AgentManagementDetectionRunResult.canceled,
          ),
          confirmedConnectionChecksByProviderId: {},
        ),
      );

    case ProviderEnabledToggled():
      final key = _agentKey(
        AgentManagementOperationKind.providerEnabledUpdate,
        intent.agentId,
      );
      return Transition(
        state.copyWith(
          pendingOperations: _putPending(
            state.pendingOperations,
            key,
            intent.operationId,
          ),
          failure: null,
        ),
        <AgentManagementSliceEffect>[
          UpdateProviderEnabledEffect(
            operationId: intent.operationId,
            agentId: intent.agentId,
            enabled: intent.enabled,
          ),
        ],
      );

    case ProviderEnabledUpdated():
      final key = _agentKey(
        AgentManagementOperationKind.providerEnabledUpdate,
        intent.agentId,
      );
      if (!_accepts(state, key, intent.operationId)) {
        return Transition.none(state);
      }
      return Transition.stateOnly(
        state.copyWith(
          providerSettings: intent.providerSettings,
          pendingOperations: _removePending(state.pendingOperations, key),
          failure: null,
        ),
      );

    case ProviderEnabledUpdateFailed():
      return _operationFailed(
        state,
        operationId: intent.operationId,
        key: _agentKey(
          AgentManagementOperationKind.providerEnabledUpdate,
          intent.agentId,
        ),
        kind: AgentManagementFailureKind.providerEnabledUpdate,
        agentId: intent.agentId,
        message: intent.message,
      );

    case AccountDataEnrichmentToggled():
      final key = _agentKey(
        AgentManagementOperationKind.accountDataEnrichmentUpdate,
        intent.agentId,
      );
      return Transition(
        state.copyWith(
          pendingOperations: _putPending(
            state.pendingOperations,
            key,
            intent.operationId,
          ),
          failure: null,
        ),
        <AgentManagementSliceEffect>[
          UpdateAccountDataEnrichmentEffect(
            operationId: intent.operationId,
            agentId: intent.agentId,
            enabled: intent.enabled,
          ),
        ],
      );

    case AccountDataEnrichmentUpdated():
      final key = _agentKey(
        AgentManagementOperationKind.accountDataEnrichmentUpdate,
        intent.agentId,
      );
      if (!_accepts(state, key, intent.operationId)) {
        return Transition.none(state);
      }
      return Transition.stateOnly(
        state.copyWith(
          providerSettings: intent.providerSettings,
          pendingOperations: _removePending(state.pendingOperations, key),
          failure: null,
        ),
      );

    case AccountDataEnrichmentUpdateFailed():
      return _operationFailed(
        state,
        operationId: intent.operationId,
        key: _agentKey(
          AgentManagementOperationKind.accountDataEnrichmentUpdate,
          intent.agentId,
        ),
        kind: AgentManagementFailureKind.accountDataEnrichmentUpdate,
        agentId: intent.agentId,
        message: intent.message,
      );

    case ConnectionTestRequested():
      final key = _agentKey(
        AgentManagementOperationKind.connectionTest,
        intent.agentId,
      );
      return Transition(
        state.copyWith(
          pendingOperations: _putPending(
            state.pendingOperations,
            key,
            intent.operationId,
          ),
          failure: null,
        ),
        <AgentManagementSliceEffect>[
          TestAgentConnectionEffect(
            operationId: intent.operationId,
            agentId: intent.agentId,
          ),
        ],
      );

    case ConnectionTestSucceeded():
      final key = _agentKey(
        AgentManagementOperationKind.connectionTest,
        intent.agentId,
      );
      if (!_accepts(state, key, intent.operationId)) {
        return Transition.none(state);
      }
      return Transition.stateOnly(
        state.copyWith(
          confirmedConnectionChecksByProviderId: {
            ...state.confirmedConnectionChecksByProviderId,
            intent.agentId: AgentManagementConnectionCheckState(
              result: intent.result,
              models: intent.models,
              modelsUpdatedAt: intent.modelsUpdatedAt,
              modelSource: intent.modelSource,
            ),
          },
          pendingOperations: _removePending(state.pendingOperations, key),
          failure: null,
        ),
      );

    case ConnectionTestFailed():
      return _operationFailed(
        state,
        operationId: intent.operationId,
        key: _agentKey(
          AgentManagementOperationKind.connectionTest,
          intent.agentId,
        ),
        kind: AgentManagementFailureKind.connectionTest,
        agentId: intent.agentId,
        message: intent.message,
      );

    case ConfigurationLoadRequested():
      final key = _agentKey(
        AgentManagementOperationKind.configurationLoad,
        intent.agentId,
      );
      return Transition(
        state.copyWith(
          pendingOperations: _putPending(
            state.pendingOperations,
            key,
            intent.operationId,
          ),
          failure: null,
        ),
        <AgentManagementSliceEffect>[
          LoadAgentConfigurationEffect(
            operationId: intent.operationId,
            agentId: intent.agentId,
          ),
        ],
      );

    case ConfigurationLoadSucceeded():
      final key = _agentKey(
        AgentManagementOperationKind.configurationLoad,
        intent.agentId,
      );
      if (!_accepts(state, key, intent.operationId)) {
        return Transition.none(state);
      }
      return Transition.stateOnly(
        state.copyWith(
          confirmedConfigurationsByAgentId:
              <String, AgentConfigurationDocument>{
                ...state.confirmedConfigurationsByAgentId,
                intent.agentId: intent.document,
              },
          pendingOperations: _removePending(state.pendingOperations, key),
          failure: null,
        ),
      );

    case ConfigurationLoadFailed():
      return _operationFailed(
        state,
        operationId: intent.operationId,
        key: _agentKey(
          AgentManagementOperationKind.configurationLoad,
          intent.agentId,
        ),
        kind: AgentManagementFailureKind.configurationRead,
        agentId: intent.agentId,
        message: intent.message,
      );

    case ConfigurationSaveRequested():
      final key = _agentKey(
        AgentManagementOperationKind.configurationSave,
        intent.agentId,
      );
      return Transition(
        state.copyWith(
          pendingOperations: _putPending(
            state.pendingOperations,
            key,
            intent.operationId,
          ),
          failure: null,
        ),
        <AgentManagementSliceEffect>[
          SaveAgentConfigurationEffect(
            operationId: intent.operationId,
            agentId: intent.agentId,
            original: intent.original,
            content: intent.content,
            overwriteExternalChanges: intent.overwriteExternalChanges,
          ),
        ],
      );

    case ConfigurationSaveSucceeded():
      final key = _agentKey(
        AgentManagementOperationKind.configurationSave,
        intent.agentId,
      );
      if (!_accepts(state, key, intent.operationId)) {
        return Transition.none(state);
      }
      final pendingRemoved = _removePending(state.pendingOperations, key);
      final currentDocument =
          state.confirmedConfigurationsByAgentId[intent.agentId];
      if (currentDocument?.signature != intent.originalSignature) {
        return Transition.stateOnly(
          state.copyWith(pendingOperations: pendingRemoved),
        );
      }
      return Transition.stateOnly(
        state.copyWith(
          confirmedConfigurationsByAgentId:
              <String, AgentConfigurationDocument>{
                ...state.confirmedConfigurationsByAgentId,
                intent.agentId: intent.result.document,
              },
          pendingOperations: pendingRemoved,
          failure: null,
        ),
      );

    case ConfigurationSaveFailed():
      return _operationFailed(
        state,
        operationId: intent.operationId,
        key: _agentKey(
          AgentManagementOperationKind.configurationSave,
          intent.agentId,
        ),
        kind: AgentManagementFailureKind.configurationSave,
        agentId: intent.agentId,
      );

    case LogsLoadRequested():
      final key = _agentKey(
        AgentManagementOperationKind.logsLoad,
        intent.agentId,
      );
      return Transition(
        state.copyWith(
          pendingOperations: _putPending(
            state.pendingOperations,
            key,
            intent.operationId,
          ),
          failure: null,
        ),
        <AgentManagementSliceEffect>[
          LoadAgentLogsEffect(
            operationId: intent.operationId,
            agentId: intent.agentId,
          ),
        ],
      );

    case LogsLoadSucceeded():
      final key = _agentKey(
        AgentManagementOperationKind.logsLoad,
        intent.agentId,
      );
      if (!_accepts(state, key, intent.operationId)) {
        return Transition.none(state);
      }
      return Transition.stateOnly(
        state.copyWith(
          logFileCountsByProviderId: {
            ...state.logFileCountsByProviderId,
            intent.agentId: intent.fileCount,
          },
          logsByAgentId: <String, List<AgentLogEntry>>{
            ...state.logsByAgentId,
            intent.agentId: intent.logs,
          },
          pendingOperations: _removePending(state.pendingOperations, key),
          failure: null,
        ),
      );

    case LogsLoadFailed():
      return _operationFailed(
        state,
        operationId: intent.operationId,
        key: _agentKey(AgentManagementOperationKind.logsLoad, intent.agentId),
        kind: AgentManagementFailureKind.logsRead,
        agentId: intent.agentId,
        message: intent.message,
      );

    case ProviderSettingsSnapshotChanged():
      final checks = {...state.confirmedConnectionChecksByProviderId};
      final pending = {...state.pendingOperations};
      for (final old in state.providerSettings.providers) {
        final updated = intent.providerSettings.providers
            .where((p) => p.id == old.id)
            .firstOrNull;
        if (updated == null ||
            old.kind != updated.kind ||
            old.command != updated.command ||
            !zetaMapEquals(old.environment, updated.environment) ||
            old.selectedPermissionOptionId !=
                updated.selectedPermissionOptionId ||
            !zetaListEquals(old.arguments, updated.arguments) ||
            !zetaMapEquals(
              _processExtra(old.extra),
              _processExtra(updated.extra),
            )) {
          checks.remove(old.id);
          pending.remove(
            _agentKey(AgentManagementOperationKind.connectionTest, old.id),
          );
        }
      }
      return Transition.stateOnly(
        state.copyWith(
          providerSettings: intent.providerSettings,
          confirmedConnectionChecksByProviderId: checks,
          pendingOperations: pending,
        ),
      );

    case RuntimeFactsReplaced():
      return intent.facts == state.runtimeFacts
          ? Transition.none(state)
          : Transition.stateOnly(state.copyWith(runtimeFacts: intent.facts));
  }
}

Transition<AgentManagementSliceState, AgentManagementSliceEffect>
_operationFailed(
  AgentManagementSliceState state, {
  required OperationId operationId,
  required AgentManagementOperationKey key,
  required AgentManagementFailureKind kind,
  String? agentId,
  String? message,
}) {
  if (!_accepts(state, key, operationId)) {
    return Transition.none(state);
  }
  return Transition.stateOnly(
    state.copyWith(
      pendingOperations: _removePending(state.pendingOperations, key),
      failure: AgentManagementFailure(
        kind: kind,
        operationId: operationId,
        agentId: agentId,
        message: message,
      ),
    ),
  );
}

AgentManagementOperationKey _globalKey(AgentManagementOperationKind kind) =>
    AgentManagementOperationKey(kind);

AgentManagementOperationKey _agentKey(
  AgentManagementOperationKind kind,
  String agentId,
) => AgentManagementOperationKey(kind, agentId);

bool _accepts(
  AgentManagementSliceState state,
  AgentManagementOperationKey key,
  OperationId operationId,
) => state.pendingOperations[key] == operationId;

Map<AgentManagementOperationKey, OperationId> _putPending(
  Map<AgentManagementOperationKey, OperationId> source,
  AgentManagementOperationKey key,
  OperationId operationId,
) => <AgentManagementOperationKey, OperationId>{...source, key: operationId};

Map<AgentManagementOperationKey, OperationId> _removePending(
  Map<AgentManagementOperationKey, OperationId> source,
  AgentManagementOperationKey key,
) => <AgentManagementOperationKey, OperationId>{
  for (final entry in source.entries)
    if (entry.key != key) entry.key: entry.value,
};

Map<String, Object?> _processExtra(Map<String, Object?> extra) => {
  for (final e in extra.entries)
    if (!e.key.startsWith('detected') && e.key != 'lastDetectedAt')
      e.key: e.value,
};

AgentManagementSliceState _acceptDetectionEvent(
  AgentManagementSliceState state,
  DetectionResultAccepted intent,
) {
  final d = state.detection;
  final event = intent.event;
  final id = event.providerId;
  if (d.operationId != intent.operationId ||
      d.phase != ManagementDetectionPhase.running ||
      !d.outcomesByProviderId.containsKey(id)) {
    return state;
  }
  if (event is DetectionCacheWriteWarning) {
    return state.copyWith(
      detection: d.copyWith(
        cacheWriteWarningProviderIds: {...d.cacheWriteWarningProviderIds, id},
      ),
    );
  }
  if (d.outcomesByProviderId[id] != ProviderDetectionOutcome.pending) {
    return state;
  }
  switch (event) {
    case DetectionProviderStarted():
      return state.copyWith(detectingAgentId: id, detectionProgress: null);
    case DetectionProviderProgress():
      if (state.detectingAgentId != id) return state;
      return state.copyWith(
        detection: d.copyWith(
          pendingPartialByProviderId: {
            ...d.pendingPartialByProviderId,
            id: event.partial,
          },
          progressByProviderId: {...d.progressByProviderId, id: event.progress},
        ),
        detectingAgentId: id,
        detectionProgress: event.progress,
      );
    case DetectionProviderSucceeded():
      if (state.detectingAgentId != id) return state;
      return state.copyWith(
        detection: d.copyWith(
          confirmedByProviderId: {
            ...d.confirmedByProviderId,
            id: AgentDetectionConfirmedRecord(
              details: event.details,
              confirmedAt: event.confirmedAt ?? event.details.lastDetectedAt,
              freshness: DetectionFreshness.confirmedThisRun,
            ),
          },
          pendingPartialByProviderId: {...d.pendingPartialByProviderId}
            ..remove(id),
          progressByProviderId: {...d.progressByProviderId}..remove(id),
          outcomesByProviderId: {
            ...d.outcomesByProviderId,
            id: ProviderDetectionOutcome.succeeded,
          },
        ),
        detectingAgentId: null,
        detectionProgress: null,
      );
    case DetectionProviderFailed():
      return state.copyWith(
        detection: d.copyWith(
          pendingPartialByProviderId: {...d.pendingPartialByProviderId}
            ..remove(id),
          progressByProviderId: {...d.progressByProviderId}..remove(id),
          outcomesByProviderId: {
            ...d.outcomesByProviderId,
            id: ProviderDetectionOutcome.failed,
          },
          failuresByProviderId: {...d.failuresByProviderId, id: event.failure},
        ),
        detectingAgentId: null,
        detectionProgress: null,
      );
    case DetectionCacheWriteWarning():
      return state;
  }
}

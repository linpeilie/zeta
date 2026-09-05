import '../agent_management_runtime_aggregation.dart';
import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

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
  var changed = false;
  final agents = <String, ManagedAgent>{};
  for (final entry in state.agentsById.entries) {
    final summary = summaries[entry.key]!;
    final agent = entry.value;
    if (agent.runtimeState != summary.state ||
        agent.enabled != summary.enabled) {
      changed = true;
      agents[entry.key] = agent.copyWith(
        runtimeState: summary.state,
        enabled: summary.enabled,
      );
    } else {
      agents[entry.key] = agent;
    }
  }
  if (!changed && zetaMapEquals(summaries, state.runtimeByProviderId)) {
    return state;
  }
  return state.copyWith(agentsById: agents, runtimeByProviderId: summaries);
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
          agentsById: intent.agentsById,
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
      final key = _globalKey(AgentManagementOperationKind.detection);
      return Transition(
        state.copyWith(
          pendingOperations: _putPending(
            state.pendingOperations,
            key,
            intent.operationId,
          ),
          detectionProgress: null,
          detectingAgentId: null,
          failure: null,
        ),
        <AgentManagementSliceEffect>[DetectAgentsEffect(intent.operationId)],
      );

    case AgentDetectionStarted():
      final key = _globalKey(AgentManagementOperationKind.detection);
      if (!_accepts(state, key, intent.operationId) ||
          !state.agentsById.containsKey(intent.agentId)) {
        return Transition.none(state);
      }
      return Transition.stateOnly(
        state.copyWith(
          detectingAgentId: intent.agentId,
          detectionProgress: null,
        ),
      );

    case AgentDetectionProgressReported():
      final key = _globalKey(AgentManagementOperationKind.detection);
      if (!_accepts(state, key, intent.operationId) ||
          state.detectingAgentId != intent.agentId) {
        return Transition.none(state);
      }
      return Transition.stateOnly(
        state.copyWith(
          agentsById: _replaceAgent(
            state.agentsById,
            intent.agentId,
            intent.partial,
          ),
          detectionProgress: intent.progress,
        ),
      );

    case AgentDetectionSucceeded():
      final key = _globalKey(AgentManagementOperationKind.detection);
      if (!_accepts(state, key, intent.operationId) ||
          state.detectingAgentId != intent.agentId) {
        return Transition.none(state);
      }
      return Transition.stateOnly(
        state.copyWith(
          agentsById: _replaceAgent(
            state.agentsById,
            intent.agentId,
            intent.agent,
          ),
          detectingAgentId: null,
        ),
      );

    case DetectionCompleted():
      final key = _globalKey(AgentManagementOperationKind.detection);
      if (!_accepts(state, key, intent.operationId)) {
        return Transition.none(state);
      }
      return Transition.stateOnly(
        state.copyWith(
          pendingOperations: _removePending(state.pendingOperations, key),
          detectionProgress: null,
          detectingAgentId: null,
          failure: null,
        ),
      );

    case DetectionFailed():
      final key = _globalKey(AgentManagementOperationKind.detection);
      if (!_accepts(state, key, intent.operationId)) {
        return Transition.none(state);
      }
      return Transition.stateOnly(
        state.copyWith(
          pendingOperations: _removePending(state.pendingOperations, key),
          detectingAgentId: null,
          failure: AgentManagementFailure(
            kind: AgentManagementFailureKind.detection,
            operationId: intent.operationId,
            message: intent.message,
          ),
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
      final current = state.agentsById[intent.agentId];
      return Transition.stateOnly(
        state.copyWith(
          agentsById: current == null
              ? state.agentsById
              : _replaceAgent(
                  state.agentsById,
                  intent.agentId,
                  current.copyWith(enabled: intent.enabled),
                ),
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
      final current = state.agentsById[intent.agentId];
      final tested = current?.copyWith(
        connectionTest: intent.result,
        models: intent.models,
        modelsUpdatedAt: intent.models.isEmpty
            ? current.modelsUpdatedAt
            : intent.modelsUpdatedAt,
        modelSource: intent.models.isEmpty
            ? current.modelSource
            : intent.modelSource,
        errorStage: intent.result.success ? null : intent.result.failureStage,
        errorMessage: intent.result.success ? null : intent.result.message,
        errorDetails: intent.result.success
            ? null
            : intent.result.rawErrorSummary,
      );
      return Transition.stateOnly(
        state.copyWith(
          agentsById: tested == null
              ? state.agentsById
              : _replaceAgent(state.agentsById, intent.agentId, tested),
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
      final currentAgent = state.agentsById[intent.agentId];
      return Transition.stateOnly(
        state.copyWith(
          confirmedConfigurationsByAgentId:
              <String, AgentConfigurationDocument>{
                ...state.confirmedConfigurationsByAgentId,
                intent.agentId: intent.result.document,
              },
          agentsById: currentAgent == null
              ? state.agentsById
              : _replaceAgent(
                  state.agentsById,
                  intent.agentId,
                  currentAgent.copyWith(
                    configExists: true,
                    configModifiedAt: intent.result.document.modifiedAt,
                  ),
                ),
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
      final current = state.agentsById[intent.agentId];
      return Transition.stateOnly(
        state.copyWith(
          agentsById: current == null
              ? state.agentsById
              : _replaceAgent(
                  state.agentsById,
                  intent.agentId,
                  current.copyWith(logPaths: intent.paths),
                ),
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
      var changed = false;
      final agents = Map<String, ManagedAgent>.from(state.agentsById);
      for (final entry in agents.entries.toList(growable: false)) {
        final enabled = _providerEnabled(
          intent.providerSettings,
          entry.key,
          fallback: entry.value.enabled,
        );
        if (entry.value.enabled == enabled) {
          continue;
        }
        changed = true;
        agents[entry.key] = entry.value.copyWith(enabled: enabled);
      }
      if (!changed &&
          identical(state.providerSettings, intent.providerSettings)) {
        return Transition.none(state);
      }
      return Transition.stateOnly(
        state.copyWith(
          agentsById: agents,
          providerSettings: intent.providerSettings,
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

Map<String, ManagedAgent> _replaceAgent(
  Map<String, ManagedAgent> source,
  String agentId,
  ManagedAgent agent,
) => <String, ManagedAgent>{...source, agentId: agent};

bool _providerEnabled(
  AgentProviderSettings settings,
  String agentId, {
  required bool fallback,
}) {
  for (final provider in settings.providers) {
    if (provider.id == agentId) {
      return provider.enabled;
    }
  }
  return fallback;
}

import 'dart:collection';

import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';

import 'agent_management_runtime_facts.dart';

/// 仅聚合已校验的 session 事实；默认/选中 Provider、历史状态和 RPC 计数不参与。
Map<String, AgentManagementProviderRuntimeSummary> aggregateManagementRuntime(
  AgentManagementRuntimeFacts facts,
  Map<String, bool> enabledByProviderId,
) {
  final grouped = <String, List<AgentManagementRuntimeFact>>{
    for (final id in enabledByProviderId.keys) id: [],
  };
  final seenBindings = HashSet<Object>.identity();
  for (final fact in facts.bindings) {
    if (seenBindings.add(fact.observationKey)) {
      (grouped[fact.providerId] ??= []).add(fact);
    }
  }
  return Map.unmodifiable({
    for (final entry in grouped.entries)
      entry.key: _aggregate(
        entry.key,
        enabledByProviderId[entry.key] ?? false,
        entry.value,
      ),
  });
}

AgentManagementProviderRuntimeSummary _aggregate(
  String id,
  bool enabled,
  List<AgentManagementRuntimeFact> facts,
) {
  final connected = <AgentProviderRuntimeIdentity>{};
  final unobserved = <AgentProviderRuntimeIdentity>{};
  final observed = <AgentProviderRuntimeIdentity>{};
  var active = 0;
  var starting = 0;
  var errors = 0;
  var unavailable = 0;
  for (final fact in facts) {
    if (fact.activeTurn) active++;
    if (fact.lifecycle == AgentConversationRuntimeLifecyclePhase.starting ||
        fact.connectionState == AgentProviderConnectionState.connecting) {
      starting++;
    }
    if (fact.currentError) errors++;
    if (fact.unavailable) unavailable++;
    final identity = fact.runtimeIdentity;
    if (identity != null) {
      if (fact.connected) connected.add(identity);
      if (fact.hasCurrentThreadObservation) {
        observed.add(identity);
      } else if (fact.lifecycle ==
          AgentConversationRuntimeLifecyclePhase.attached) {
        unobserved.add(identity);
      }
    }
  }
  unobserved.removeAll(observed);
  final state = active > 0
      ? AgentRuntimeState.running
      : errors > 0
      ? AgentRuntimeState.error
      : starting > 0
      ? AgentRuntimeState.starting
      : unavailable > 0
      ? AgentRuntimeState.unavailable
      : connected.isNotEmpty
      ? AgentRuntimeState.idle
      : !enabled
      ? AgentRuntimeState.disabled
      : AgentRuntimeState.notRunning;
  return AgentManagementProviderRuntimeSummary(
    providerId: id,
    enabled: enabled,
    activeTurnCount: active,
    connectedRuntimeCount: connected.length,
    startingBindingCount: starting,
    errorBindingCount: errors,
    unavailableBindingCount: unavailable,
    unobservedTurnRuntimeCount: unobserved.length,
    state: state,
  );
}

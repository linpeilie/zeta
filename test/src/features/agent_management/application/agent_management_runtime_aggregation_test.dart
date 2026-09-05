import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_runtime_aggregation.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_runtime_facts.dart';

void main() {
  test('exact instance ids and all settings participate independently', () {
    final summaries = aggregateManagementRuntime(
      AgentManagementRuntimeFacts([
        fact('grok', generation: 1, active: true),
        fact('codex', generation: 2),
        fact('custom-codex', generation: 3, active: true),
      ]),
      {'codex': true, 'grok': true, 'disabled': false, 'dormant': true},
    );
    expect(summaries['codex']!.state, AgentRuntimeState.idle);
    expect(summaries['grok']!.state, AgentRuntimeState.running);
    expect(summaries['custom-codex']!.activeTurnCount, 1);
    expect(summaries['custom-codex']!.enabled, isFalse);
    expect(summaries['disabled']!.state, AgentRuntimeState.disabled);
    expect(summaries['dormant']!.state, AgentRuntimeState.notRunning);
    expect(() => summaries.clear(), throwsUnsupportedError);
  });

  test(
    'different session generations coexist; duplicate bindings/runtimes count once',
    () {
      final a = fact('p', generation: 1, active: true);
      final b = fact('p', generation: 2);
      final result = aggregateManagementRuntime(
        AgentManagementRuntimeFacts([a, a, b, fact('p', generation: 2)]),
        {'p': true},
      )['p']!;
      expect(result.activeTurnCount, 1);
      expect(result.connectedRuntimeCount, 2);
      expect(result.state, AgentRuntimeState.running);
    },
  );

  test(
    'running keeps independent errors and disabled policy keeps physical facts',
    () {
      final result = aggregateManagementRuntime(
        AgentManagementRuntimeFacts([
          fact('p', generation: 1, active: true),
          AgentManagementRuntimeFact(
            observationKey: Object(),
            providerId: 'p',
            lifecycle: AgentConversationRuntimeLifecyclePhase.dormant,
            currentError: true,
          ),
        ]),
        {'p': false},
      )['p']!;
      expect(result.enabled, isFalse);
      expect(result.state, AgentRuntimeState.running);
      expect(result.activeTurnCount, 1);
      expect(result.connectedRuntimeCount, 1);
      expect(result.errorBindingCount, 1);
      expect(result.hasErrors, isTrue);
    },
  );

  test('unknown turn runtimes are distinct and never imply an active turn', () {
    final result = aggregateManagementRuntime(
      AgentManagementRuntimeFacts([
        fact('p', generation: 1, observed: false),
        fact('p', generation: 1, observed: false),
        fact('p', generation: 2, observed: false),
        fact('p', generation: 2),
      ]),
      {'p': true},
    )['p']!;
    expect(result.connectedRuntimeCount, 2);
    expect(result.unobservedTurnRuntimeCount, 1);
    expect(result.activeTurnCount, 0);
  });

  for (final (connection, lifecycle, error, unavailable, expected) in [
    (
      null,
      AgentConversationRuntimeLifecyclePhase.dormant,
      false,
      false,
      AgentRuntimeState.notRunning,
    ),
    (
      null,
      AgentConversationRuntimeLifecyclePhase.cleared,
      false,
      false,
      AgentRuntimeState.notRunning,
    ),
    (
      null,
      AgentConversationRuntimeLifecyclePhase.starting,
      false,
      false,
      AgentRuntimeState.starting,
    ),
    (
      AgentProviderConnectionState.connecting,
      AgentConversationRuntimeLifecyclePhase.attached,
      false,
      false,
      AgentRuntimeState.starting,
    ),
    (
      null,
      AgentConversationRuntimeLifecyclePhase.starting,
      true,
      false,
      AgentRuntimeState.error,
    ),
    (
      null,
      AgentConversationRuntimeLifecyclePhase.starting,
      false,
      true,
      AgentRuntimeState.starting,
    ),
    (
      null,
      AgentConversationRuntimeLifecyclePhase.dormant,
      false,
      true,
      AgentRuntimeState.unavailable,
    ),
  ]) {
    test(
      'priority $lifecycle/$connection/error=$error/unavailable=$unavailable',
      () {
        final facts = AgentManagementRuntimeFacts([
          AgentManagementRuntimeFact(
            observationKey: Object(),
            providerId: 'p',
            lifecycle: lifecycle,
            connectionState: connection,
            currentError: error,
            unavailable: unavailable,
          ),
        ]);
        final result = aggregateManagementRuntime(facts, {'p': true})['p']!;
        expect(result.state, expected);
        expect(result.connectedRuntimeCount, 0);
        expect(() => facts.bindings.clear(), throwsUnsupportedError);
      },
    );
  }
}

AgentManagementRuntimeFact fact(
  String id, {
  required int generation,
  bool active = false,
  bool observed = true,
}) => AgentManagementRuntimeFact(
  observationKey: Object(),
  providerId: id,
  runtimeIdentity: AgentProviderRuntimeIdentity(
    providerId: id,
    generation: generation,
  ),
  connectionScope: AgentRuntimeScope(
    runtimeId: 'session-$generation',
    connectionEpoch: 1,
  ),
  lifecycle: AgentConversationRuntimeLifecyclePhase.attached,
  connected: true,
  activeTurn: active,
  hasCurrentThreadObservation: observed,
);

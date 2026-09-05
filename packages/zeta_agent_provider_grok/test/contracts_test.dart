import 'package:test/test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta_agent_provider_sdk/zeta_agent_provider_sdk_testing.dart';
import 'package:zeta_agent_provider_grok/zeta_agent_provider_grok_testing.dart';
import 'support/provider_test_files.dart';

void main() {
  runAgentProviderContractTests(() => _GrokContractFixture());
}

final class _GrokContractFixture extends AgentProviderContractFixture {
  @override
  AgentProviderDefinition get definition => grokAgentProviderDefinition;

  @override
  AgentProviderBundle createBundle() =>
      createGrokBundle(defaultGrokAgentProviderConfig);

  @override
  List<Object> get sampleWirePayloads => <Object>[
    providerTestFiles.readFixtureJsonMap(
      'agent_stream_identity/grok_live_text_tool_text.json',
    ),
  ];

  @override
  List<AgentEvent> mapSampleWirePayload(Object payload) {
    const scope = AgentRuntimeScope(runtimeId: 'contract', connectionEpoch: 1);
    final mapper = GrokAcpNotificationMapper();
    addTearDown(mapper.dispose);
    mapper.beginTurn(
      runtimeScope: scope,
      sessionId: 'grok-session-redacted',
      turnId: 'grok-turn-redacted',
    );
    final fixture = payload as Map<String, Object?>;
    return <AgentEvent>[
      for (final value in fixture['events']! as List)
        ...mapper
            .mapSessionUpdate(
              params: Map<String, Object?>.from(
                (value as Map)['params'] as Map,
              ),
              runningTurnId: 'grok-turn-redacted',
              runtimeScope: scope,
            )
            .events,
    ];
  }
}

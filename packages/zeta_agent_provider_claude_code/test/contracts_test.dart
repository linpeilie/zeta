import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta_agent_provider_sdk/zeta_agent_provider_sdk_testing.dart';
import 'package:zeta_agent_provider_claude_code/zeta_agent_provider_claude_code_testing.dart';
import 'support/provider_test_files.dart';

void main() {
  runAgentProviderContractTests(() => _ClaudeCodeContractFixture());
}

final class _ClaudeCodeContractFixture extends AgentProviderContractFixture {
  @override
  AgentProviderDefinition get definition => claudeCodeAgentProviderDefinition;

  @override
  AgentProviderBundle createBundle() =>
      createClaudeCodeBundle(defaultClaudeCodeAgentProviderConfig);

  @override
  List<Object> get sampleWirePayloads => <Object>[
    providerTestFiles.readFixtureJsonMap(
      'agent_file_change_evidence/claude_code_edit_write_2_1_227.json',
    ),
  ];

  @override
  List<AgentEvent> mapSampleWirePayload(Object payload) {
    const scope = AgentRuntimeScope(runtimeId: 'contract', connectionEpoch: 1);
    final fixture = payload as Map<String, Object?>;
    final events = <AgentEvent>[];
    for (final value in fixture['scenarios']! as List) {
      final frames = (value as Map)['frames'] as List;
      final sessionId = (frames.first as Map)['session_id'] as String;
      final mapper = ClaudeCodeEventMapper(
        providerId: defaultClaudeCodeProviderId,
      );
      mapper.beginTurn(
        runtimeScope: scope,
        sessionId: sessionId,
        turnId: 'contract-turn',
      );
      try {
        for (final frame in frames) {
          events.addAll(
            mapper
                .mapFrame(
                  raw: Map<String, Object?>.from(frame as Map),
                  runtimeScope: scope,
                  runningTurnId: 'contract-turn',
                )
                .events,
          );
        }
      } finally {
        mapper.dispose();
      }
    }
    return events;
  }
}

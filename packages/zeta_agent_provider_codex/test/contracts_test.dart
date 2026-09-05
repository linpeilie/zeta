import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta_agent_provider_sdk/zeta_agent_provider_sdk_testing.dart';
import 'package:zeta_agent_provider_codex/zeta_agent_provider_codex_testing.dart';
import 'support/recording_json_rpc_peer.dart';
import 'support/provider_test_files.dart';

void main() {
  runAgentProviderContractTests(() => _CodexContractFixture());
}

final class _CodexContractFixture extends AgentProviderContractFixture {
  @override
  AgentProviderDefinition get definition => codexAgentProviderDefinition;

  @override
  AgentProviderBundle createBundle() =>
      createCodexBundle(defaultCodexAgentProviderConfig);

  @override
  List<Object> get sampleWirePayloads => <Object>[
    providerTestFiles.readFixtureJsonMap(
      'agent_stream_identity/codex_agent_message_lifecycle.json',
    ),
  ];

  @override
  Future<List<AgentEvent>> mapSampleWirePayload(Object payload) async {
    final peer = RecordingJsonRpcPeer();
    final bundle = createCodexBundle(
      defaultCodexAgentProviderConfig,
      peer: peer,
    );
    final events = <AgentEvent>[];
    final subscription = bundle.runtime.events.listen(events.add);
    try {
      await bundle.runtime.initialize();
      final fixture = payload as Map<String, Object?>;
      for (final value in fixture['events']! as List) {
        final envelope = Map<String, Object?>.from(value as Map);
        peer.emitNotification(
          envelope['method']! as String,
          Map<String, Object?>.from(envelope['params']! as Map),
        );
      }
      // 等待 broadcast 通知与中立事件各自完成一次队列投递。
      await Future<void>.delayed(Duration.zero);
      return events;
    } finally {
      await subscription.cancel();
      await bundle.runtime.dispose();
    }
  }
}

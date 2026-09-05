import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/app/plugins/agent_provider_manifest.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_codec.dart';
import '../../../testing/agent_provider_implementations.dart';
import '../../../testing/recording_json_rpc_peer.dart';

void main() {
  test(
    'restores custom team-safe profile from config and encodes permissions',
    () async {
      final config = defaultCodexAgentProviderConfig.withPermissionPreference(
        'team-safe',
      );
      // V2 round-trip 只保留 optionId；自定义 profile 不得变成 :workspace。
      final decoded = AgentProviderSettingsCodec(
        providerDefinitions: zetaAgentProviderDefinitionCatalog,
      ).decodeProvider(config.toJson());
      expect(decoded, isNotNull);
      expect(decoded!.selectedPermissionOptionId, 'team-safe');
      expect(decoded.resolvedPermissionOptionId, 'team-safe');

      final peer = RecordingJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(config: decoded, peer: peer);
      addTearDown(provider.dispose);

      await provider.sendMessage(
        session: const AgentSession(
          id: 'thread-team-safe',
          providerId: defaultAgentProviderId,
        ),
        message: 'hello',
        context: const AgentContext(projectPath: '/repo'),
        clientUserMessageId: 'client-team-safe',
      );

      final turnStartIndex = peer.requestMethods.indexOf('turn/start');
      expect(peer.requestParams[turnStartIndex], <String, Object?>{
        'threadId': 'thread-team-safe',
        'input': <Object?>[
          <String, Object?>{'type': 'text', 'text': 'hello'},
        ],
        'cwd': '/repo',
        'approvalPolicy': 'on-request',
        'permissions': 'team-safe',
        'clientUserMessageId': 'client-team-safe',
      });
    },
  );
}

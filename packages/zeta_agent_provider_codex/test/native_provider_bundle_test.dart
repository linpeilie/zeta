import 'package:test/test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_provider_codex/zeta_agent_provider_codex_testing.dart';
import 'support/activated_plugin.dart';
import 'support/recording_json_rpc_peer.dart';

void main() {
  late AgentProviderBundleFactory factory;
  setUp(() {
    factory = activateBuiltInAgentProviderBundleFactory();
  });
  test('Codex native bundle owns the same runtime', () {
    final native = factory.createBundle(defaultCodexAgentProviderConfig);
    addTearDown(native.runtime.dispose);

    expect(_portPresence(native), _codexPresence);
    expect(identical(native.runtime, native.conversation), isTrue);
    expect(identical(native.deniedActionOverride, native.runtime), isTrue);
  });
  test('createCodexBundle returns a distinct runtime owner each time', () {
    final first = createCodexBundle(defaultCodexAgentProviderConfig);
    final second = createCodexBundle(defaultCodexAgentProviderConfig);
    addTearDown(first.runtime.dispose);
    addTearDown(second.runtime.dispose);

    expect(identical(first.runtime, second.runtime), isFalse);
    expect(_portPresence(first), _codexPresence);
  });
  test(
    'Codex native listModels(forceRefresh) bypasses cache like adapt()',
    () async {
      final peer = RecordingJsonRpcPeer();
      final native = createCodexBundle(
        defaultCodexAgentProviderConfig,
        peer: peer,
      );
      addTearDown(native.runtime.dispose);

      await native.modelCatalog!.listModels();
      await native.modelCatalog!.listModels();
      expect(peer.callsFor('model/list'), hasLength(1));

      await native.modelCatalog!.listModels(forceRefresh: true);
      expect(peer.callsFor('model/list'), hasLength(2));
    },
  );
}

const _codexPresence = <String, bool>{
  'threadCatalog': true,
  'threadSubscription': true,
  'threadNaming': true,
  'threadArchival': true,
  'threadDeletion': true,
  'threadCompaction': true,
  'threadBranching': true,
  'turnSteering': true,
  'permissionResponses': true,
  'questions': true,
  'deniedActionOverride': true,
  'modelCatalog': true,
  'conversationModes': true,
  'skills': true,
  'localThreadList': false,
  'sessionConfiguration': false,
  'planApproval': false,
  'permissionPolicy': true,
  'usageQuota': true,
};

Map<String, bool> _portPresence(AgentProviderBundle bundle) {
  return <String, bool>{
    'threadCatalog': bundle.threadCatalog != null,
    'threadSubscription': bundle.threadSubscription != null,
    'threadNaming': bundle.threadNaming != null,
    'threadArchival': bundle.threadArchival != null,
    'threadDeletion': bundle.threadDeletion != null,
    'threadCompaction': bundle.threadCompaction != null,
    'threadBranching': bundle.threadBranching != null,
    'turnSteering': bundle.turnSteering != null,
    'permissionResponses': bundle.permissionResponses != null,
    'questions': bundle.questions != null,
    'deniedActionOverride': bundle.deniedActionOverride != null,
    'modelCatalog': bundle.modelCatalog != null,
    'conversationModes': bundle.conversationModes != null,
    'skills': bundle.skills != null,
    'localThreadList': bundle.localThreadList != null,
    'sessionConfiguration': bundle.sessionConfiguration != null,
    'planApproval': bundle.planApproval != null,
    'permissionPolicy': bundle.permissionPolicy != null,
    'usageQuota': bundle.usageQuota != null,
  };
}

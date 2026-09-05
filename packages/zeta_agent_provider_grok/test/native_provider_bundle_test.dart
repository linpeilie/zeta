import 'package:test/test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_provider_grok/zeta_agent_provider_grok_testing.dart';
import 'support/activated_plugin.dart';

void main() {
  late AgentProviderBundleFactory factory;
  setUp(() {
    factory = activateBuiltInAgentProviderBundleFactory();
  });
  test('Grok native bundle omits unsupported ports', () {
    final native = factory.createBundle(defaultGrokAgentProviderConfig);
    addTearDown(native.runtime.dispose);

    expect(_portPresence(native), _grokPresence);
    expect(identical(native.runtime, native.conversation), isTrue);
    expect(native.threadSubscription, isNull);
    expect(native.deniedActionOverride, isNull);
    expect(native.threadArchival, isNull);
  });
}

const _grokPresence = <String, bool>{
  'threadCatalog': true,
  'threadSubscription': false,
  'threadNaming': true,
  'threadArchival': false,
  'threadDeletion': true,
  'threadCompaction': false,
  'threadBranching': false,
  'turnSteering': false,
  'permissionResponses': true,
  'questions': true,
  'deniedActionOverride': false,
  'modelCatalog': true,
  'conversationModes': true,
  'skills': true,
  'localThreadList': false,
  'sessionConfiguration': false,
  'planApproval': true,
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

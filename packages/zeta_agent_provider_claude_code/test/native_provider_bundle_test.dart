import 'package:test/test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_provider_claude_code/zeta_agent_provider_claude_code_testing.dart';
import 'support/activated_plugin.dart';

void main() {
  late AgentProviderBundleFactory factory;
  setUp(() {
    factory = activateBuiltInAgentProviderBundleFactory();
  });
  test('Claude Code native bundle omits unsupported ports', () {
    final native = factory.createBundle(defaultClaudeCodeAgentProviderConfig);
    addTearDown(native.runtime.dispose);

    expect(_portPresence(native), _claudePresence);
    expect(identical(native.runtime, native.conversation), isTrue);
    expect(identical(native.questions, native.runtime), isTrue);
    expect(native.deniedActionOverride, isNull);
    expect(native.threadNaming, isNull);
  });
  test('createBundle uses the injected Claude metadata loader', () async {
    var metadataCalls = 0;
    final providerFactory = activateBuiltInAgentProviderBundleFactory(
      claudeCodeMetadataLoader: () async {
        metadataCalls += 1;
        return const ClaudeCodeCliMetadataSnapshot(
          models: AgentModelList(
            models: <AgentModelInfo>[
              AgentModelInfo(
                id: 'native-cli',
                model: 'native-cli',
                displayName: 'Native CLI',
                isDefault: true,
              ),
            ],
          ),
        );
      },
    );
    final bundle = providerFactory.createBundle(
      defaultClaudeCodeAgentProviderConfig,
    );
    addTearDown(bundle.runtime.dispose);

    final models = await bundle.modelCatalog!.listModels(forceRefresh: true);

    expect(models.models.single.id, 'native-cli');
    expect(metadataCalls, 1);
    expect(identical(bundle.modelCatalog, bundle.runtime), isTrue);
  });
}

const _claudePresence = <String, bool>{
  'threadCatalog': true,
  'threadSubscription': false,
  'threadNaming': false,
  'threadArchival': false,
  'threadDeletion': false,
  'threadCompaction': true,
  'threadBranching': false,
  'turnSteering': false,
  'permissionResponses': true,
  'questions': true,
  'deniedActionOverride': false,
  'modelCatalog': true,
  'conversationModes': false,
  'skills': false,
  'localThreadList': true,
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

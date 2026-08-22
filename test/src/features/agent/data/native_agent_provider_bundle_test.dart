import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_cli_metadata.dart';
import 'package:zeta/src/features/agent/data/default_agent_provider_factory.dart';
import 'package:zeta/src/features/agent/data/native_agent_provider_bundles.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import '../../../testing/recording_json_rpc_peer.dart';

void main() {
  const factory = DefaultAgentProviderFactory();

  group('native port presence', () {
    test('Codex native bundle owns the same runtime', () {
      final native = factory.createBundle(AgentProviderConfig.defaultCodex);
      addTearDown(native.runtime.dispose);

      expect(_portPresence(native), _codexPresence);
      expect(identical(native.runtime, native.conversation), isTrue);
      expect(identical(native.deniedActionOverride, native.runtime), isTrue);
    });

    test('Grok native bundle omits unsupported ports', () {
      final native = factory.createBundle(AgentProviderConfig.defaultGrok);
      addTearDown(native.runtime.dispose);

      expect(_portPresence(native), _grokPresence);
      expect(identical(native.runtime, native.conversation), isTrue);
      expect(native.threadSubscription, isNull);
      expect(native.deniedActionOverride, isNull);
      expect(native.threadArchival, isNull);
    });

    test('Claude Code native bundle omits unsupported ports', () {
      final native = factory.createBundle(
        AgentProviderConfig.defaultClaudeCode,
      );
      addTearDown(native.runtime.dispose);

      expect(_portPresence(native), _claudePresence);
      expect(identical(native.runtime, native.conversation), isTrue);
      expect(identical(native.questions, native.runtime), isTrue);
      expect(native.deniedActionOverride, isNull);
      expect(native.threadNaming, isNull);
    });
  });

  group('create*Bundle', () {
    test('createCodexBundle returns a distinct runtime owner each time', () {
      final first = createCodexBundle(AgentProviderConfig.defaultCodex);
      final second = createCodexBundle(AgentProviderConfig.defaultCodex);
      addTearDown(first.runtime.dispose);
      addTearDown(second.runtime.dispose);

      expect(identical(first.runtime, second.runtime), isFalse);
      expect(_portPresence(first), _codexPresence);
    });

    test('createBundle uses the injected Claude metadata loader', () async {
      var metadataCalls = 0;
      final providerFactory = DefaultAgentProviderFactory(
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
        AgentProviderConfig.defaultClaudeCode,
      );
      addTearDown(bundle.runtime.dispose);

      final models = await bundle.modelCatalog!.listModels(forceRefresh: true);

      expect(models.models.single.id, 'native-cli');
      expect(metadataCalls, 1);
      expect(identical(bundle.modelCatalog, bundle.runtime), isTrue);
    });

    test(
      'Codex native listModels(forceRefresh) bypasses cache like adapt()',
      () async {
        final peer = RecordingJsonRpcPeer();
        final native = createCodexBundle(
          AgentProviderConfig.defaultCodex,
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
  });
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

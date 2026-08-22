import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/agent/data/datasources/app_server/codex_app_server_agent_provider.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_cli_metadata.dart';
import 'package:zeta/src/features/agent/data/default_agent_provider_factory.dart';
import 'package:zeta/src/features/agent/data/native_agent_provider_bundles.dart';

import '../../../testing/recording_json_rpc_peer.dart';

/// 三个生产 Provider 原生 Bundle 的细分端口矩阵。
///
/// 不支持的能力必须是端口为 null，不能靠 Bundle 上的 no-op / 抛错方法冒充。
void main() {
  const factory = DefaultAgentProviderFactory();

  group('production Bundle port matrix', () {
    test('Codex exposes the split ports it actually supports', () {
      final bundle = factory.createBundle(AgentProviderConfig.defaultCodex);
      addTearDown(bundle.runtime.dispose);

      _expectRuntimeOwner(bundle);
      expect(bundle.threadCatalog, isNotNull);
      expect(bundle.threadSubscription, isNotNull);
      expect(bundle.threadNaming, isNotNull);
      expect(bundle.threadArchival, isNotNull);
      expect(bundle.threadDeletion, isNotNull);
      expect(bundle.threadCompaction, isNotNull);
      expect(bundle.threadBranching, isNotNull);
      expect(bundle.turnSteering, isNotNull);
      expect(bundle.permissionResponses, isNotNull);
      expect(bundle.questions, isNotNull);
      expect(bundle.deniedActionOverride, isNotNull);
      expect(bundle.modelCatalog, isNotNull);
      expect(bundle.conversationModes, isNotNull);
      expect(bundle.skills, isNotNull);
      expect(bundle.localThreadList, isNull);
      expect(bundle.sessionConfiguration, isNull);
      expect(bundle.planApproval, isNull);
      expect(bundle.permissionPolicy, isNotNull);
      expect(bundle.usageQuota, isNotNull);
      expect(bundle.runtime, isA<AgentThreadSubscriptionPort>());
      expect(bundle.runtime, isA<AgentDeniedActionOverridePort>());
      expect(bundle.runtime, isA<AgentQuestionResponsePort>());
      expect(bundle.runtime, isNot(isA<AgentLocalThreadListPort>()));
      expect(bundle.runtime, isNot(isA<AgentSessionConfigurationPort>()));
      expect(bundle.runtime, isNot(isA<AgentPlanApprovalPort>()));
    });

    test('Grok exposes only the split ports it actually supports', () {
      final bundle = factory.createBundle(AgentProviderConfig.defaultGrok);
      addTearDown(bundle.runtime.dispose);

      _expectRuntimeOwner(bundle);
      expect(bundle.threadCatalog, isNotNull);
      expect(bundle.threadSubscription, isNull);
      expect(bundle.threadNaming, isNotNull);
      expect(bundle.threadArchival, isNull);
      expect(bundle.threadDeletion, isNotNull);
      expect(bundle.threadCompaction, isNull);
      expect(bundle.threadBranching, isNull);
      expect(bundle.turnSteering, isNull);
      expect(bundle.permissionResponses, isNotNull);
      expect(bundle.questions, isNotNull);
      expect(bundle.deniedActionOverride, isNull);
      expect(bundle.modelCatalog, isNotNull);
      expect(bundle.conversationModes, isNotNull);
      expect(bundle.skills, isNotNull);
      expect(bundle.localThreadList, isNull);
      expect(bundle.sessionConfiguration, isNull);
      expect(bundle.planApproval, isNotNull);
      expect(bundle.permissionPolicy, isNotNull);
      expect(bundle.usageQuota, isNotNull);
      expect(bundle.runtime, isA<AgentQuestionResponsePort>());
      expect(bundle.runtime, isA<AgentPlanApprovalPort>());
      expect(bundle.runtime, isNot(isA<AgentThreadSubscriptionPort>()));
      expect(bundle.runtime, isNot(isA<AgentDeniedActionOverridePort>()));
      expect(bundle.runtime, isNot(isA<AgentLocalThreadListPort>()));
      expect(bundle.runtime, isNot(isA<AgentSessionConfigurationPort>()));
    });

    test('Claude Code exposes only the split ports it actually supports', () {
      final bundle = factory.createBundle(
        AgentProviderConfig.defaultClaudeCode,
      );
      addTearDown(bundle.runtime.dispose);

      _expectRuntimeOwner(bundle);
      expect(bundle.threadCatalog, isNotNull);
      expect(bundle.threadSubscription, isNull);
      expect(bundle.threadNaming, isNull);
      expect(bundle.threadArchival, isNull);
      expect(bundle.threadDeletion, isNull);
      expect(bundle.threadCompaction, isNotNull);
      expect(bundle.threadBranching, isNull);
      expect(bundle.turnSteering, isNull);
      expect(bundle.permissionResponses, isNotNull);
      expect(bundle.questions, isNotNull);
      expect(bundle.deniedActionOverride, isNull);
      expect(bundle.modelCatalog, isNotNull);
      expect(bundle.conversationModes, isNull);
      expect(bundle.skills, isNull);
      expect(bundle.localThreadList, isNotNull);
      expect(bundle.sessionConfiguration, isNull);
      expect(bundle.planApproval, isNotNull);
      expect(bundle.permissionPolicy, isNotNull);
      expect(bundle.usageQuota, isNotNull);
      expect(bundle.runtime, isA<AgentLocalThreadListPort>());
      expect(bundle.runtime, isA<AgentPlanApprovalPort>());
      expect(bundle.runtime, isA<AgentQuestionResponsePort>());
      expect(bundle.runtime, isNot(isA<AgentThreadSubscriptionPort>()));
      expect(bundle.runtime, isNot(isA<AgentDeniedActionOverridePort>()));
      expect(bundle.runtime, isNot(isA<AgentSessionConfigurationPort>()));
      expect(bundle.runtime, isNot(isA<AgentSkillsPort>()));
      expect(bundle.runtime, isNot(isA<AgentConversationModeCatalogPort>()));
    });
  });

  group('factory and registry identity', () {
    test('factory createBundle returns a new runtime owner each time', () {
      final first = factory.createBundle(AgentProviderConfig.defaultCodex);
      final second = factory.createBundle(AgentProviderConfig.defaultCodex);
      addTearDown(first.runtime.dispose);
      addTearDown(second.runtime.dispose);

      expect(identical(first.runtime, second.runtime), isFalse);
      expect(identical(first.runtime.config, first.runtime.config), isTrue);
    });

    test(
      'global and two session scopes do not share a production runtime owner',
      () async {
        final registry = AgentProviderRuntimeRegistry(providerFactory: factory);
        addTearDown(registry.close);

        final global = await registry.acquire(
          AgentProviderConfig.defaultGrok,
          scope: AgentProviderRuntimeScopeKey.global,
        );
        final sessionA = await registry.acquire(
          AgentProviderConfig.defaultGrok,
          scope: const AgentProviderRuntimeScopeKey.session('entry-a'),
        );
        final sessionB = await registry.acquire(
          AgentProviderConfig.defaultGrok,
          scope: const AgentProviderRuntimeScopeKey.session('entry-b'),
        );
        final sessionAAgain = await registry.acquire(
          AgentProviderConfig.defaultGrok,
          scope: const AgentProviderRuntimeScopeKey.session('entry-a'),
        );

        expect(
          identical(global.bundle.runtime, sessionA.bundle.runtime),
          isFalse,
        );
        expect(
          identical(sessionA.bundle.runtime, sessionB.bundle.runtime),
          isFalse,
        );
        expect(
          identical(sessionA.bundle.runtime, sessionAAgain.bundle.runtime),
          isTrue,
        );
        expect(global.runtimeIdentity, isNot(sessionA.runtimeIdentity));
        expect(sessionA.runtimeIdentity, isNot(sessionB.runtimeIdentity));
        expect(sessionA.runtimeIdentity, sessionAAgain.runtimeIdentity);
      },
    );
  });

  group('model catalog forceRefresh and reasoning efforts', () {
    test(
      'Codex cache hits until forceRefresh, and capabilities stay live',
      () async {
        final peer = RecordingJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        addTearDown(provider.dispose);
        final bundle = nativeBundleFromCodex(provider);

        final first = await bundle.modelCatalog!.listModels();
        final cached = await bundle.modelCatalog!.listModels();
        expect(identical(first, cached), isTrue);
        expect(peer.callsFor('model/list'), hasLength(1));

        final refreshed = await bundle.modelCatalog!.listModels(
          forceRefresh: true,
        );
        expect(peer.callsFor('model/list'), hasLength(2));
        expect(refreshed.models.single.id, 'gpt-contract');
        expect(
          bundle.runtime.capabilities.canForkThread,
          provider.capabilities.canForkThread,
        );
        expect(bundle.runtime.capabilities.supportsModelSelection, isTrue);
      },
    );

    test(
      'Claude Code forceRefresh keeps model-level reasoning efforts',
      () async {
        var metadataCalls = 0;
        final efforts = <AgentModelReasoningEffort>[
          const AgentModelReasoningEffort(effort: 'low'),
          const AgentModelReasoningEffort(effort: 'high'),
        ];
        final providerFactory = DefaultAgentProviderFactory(
          claudeCodeMetadataLoader: () async {
            metadataCalls += 1;
            return ClaudeCodeCliMetadataSnapshot(
              models: AgentModelList(
                models: <AgentModelInfo>[
                  AgentModelInfo(
                    id: 'cli-opus',
                    model: 'cli-opus',
                    displayName: 'CLI Opus',
                    isDefault: true,
                    supportedReasoningEfforts: efforts,
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
        final catalog = bundle.modelCatalog!;

        final first = await catalog.listModels();
        final cached = await catalog.listModels();
        expect(metadataCalls, 1);
        expect(identical(first, cached), isTrue);
        expect(
          first.models.single.supportedReasoningEfforts.map(
            (item) => item.effort,
          ),
          <String>['low', 'high'],
        );

        final refreshed = await catalog.listModels(forceRefresh: true);
        expect(metadataCalls, 2);
        expect(
          refreshed.models.single.supportedReasoningEfforts.map(
            (item) => item.effort,
          ),
          <String>['low', 'high'],
        );
      },
    );
  });
}

void _expectRuntimeOwner(AgentProviderBundle bundle) {
  expect(bundle.runtime.capabilities.canPrompt, isTrue);
  expect(bundle.runtime.events, isA<Stream<AgentEvent>>());
}

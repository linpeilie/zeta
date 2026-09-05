import 'dart:async';

import 'package:test/test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

/// 被测插件提供的契约夹具。
///
/// 插件包继承本类并提供 definition 与默认 bundle；有脱敏 wire fixture 时再覆盖
/// [sampleWirePayloads] 与 [mapSampleWirePayload]，让同一套契约检查规范化事件。
abstract class AgentProviderContractFixture {
  AgentProviderDefinition get definition;

  AgentProviderBundle createBundle();

  List<Object> get sampleWirePayloads => const <Object>[];

  /// 同步 mapper 与异步 transport 都可回放；只改变测试调度，不修改 Provider。
  FutureOr<List<AgentEvent>> mapSampleWirePayload(Object payload) =>
      const <AgentEvent>[];
}

/// 注册每个 Provider 插件必须复用的中立契约测试。
void runAgentProviderContractTests(
  AgentProviderContractFixture Function() createFixture,
) {
  group('definition 契约', () {
    test('providerId 与 providerType 非空且稳定', () {
      final definition = createFixture().definition;
      expect(definition.providerId, isNotEmpty);
      expect(definition.providerId.trim(), definition.providerId);
      expect(definition.providerType.value, isNotEmpty);
      expect(
        definition.providerType.value.trim(),
        definition.providerType.value,
      );
      expect(definition.defaultConfig.id, definition.providerId);
      expect(definition.defaultConfig.kind, definition.providerType);
    });

    test('staticCapabilities 与默认 bundle 一致', () {
      final fixture = createFixture();
      final bundle = fixture.createBundle();
      addTearDown(bundle.runtime.dispose);

      expect(
        _capabilitySnapshot(bundle.capabilities),
        _capabilitySnapshot(fixture.definition.staticCapabilities),
      );
      expect(bundle.runtime.config.id, fixture.definition.providerId);
      expect(bundle.runtime.config.kind, fixture.definition.providerType);
    });

    test('metricLabel 只含规范化字符', () {
      final value = createFixture().definition.metricLabel.value;
      expect(value, isNotEmpty);
      expect(ZetaMetricLabel.isValidLiteral(value), isTrue);
    });
  });

  group('bundle 端口/能力一致性', () {
    test('可选端口非空时不得谎报对应 capability=false', () {
      final bundle = createFixture().createBundle();
      addTearDown(bundle.runtime.dispose);
      final contracts = _optionalPortContracts(bundle);

      // 唯一真源：zeta_agent_core/src/domain/agent_provider_bundle.dart。
      // 当前 19 个可选端口须逐一镜像；新增端口时同步本清单和自测。
      expect(contracts, hasLength(19));
      expect(
        _portImpliesCapabilityViolations(contracts),
        isEmpty,
        reason: '非空端口必须声明对应能力（G4）',
      );
    });

    test('capability=true 时对应可选端口必须存在', () {
      final bundle = createFixture().createBundle();
      addTearDown(bundle.runtime.dispose);

      expect(
        _capabilityRequiresPortViolations(_optionalPortContracts(bundle)),
        isEmpty,
        reason: '能力不得由 null/no-op 端口伪造（G4）',
      );
    });

    test('必选端口 runtime / conversation 类型完整', () {
      final bundle = createFixture().createBundle();
      addTearDown(bundle.runtime.dispose);

      expect(bundle.runtime, isA<AgentRuntimePort>());
      expect(bundle.conversation, isA<AgentConversationPort>());
    });
  });

  group('事件契约（G1/G2）', () {
    test('适配层输出的时间线与交互 identity 非空', () async {
      final fixture = createFixture();
      if (fixture.sampleWirePayloads.isEmpty) {
        markTestSkipped('该插件尚未提供脱敏 wire fixture');
      }

      final events = <AgentEvent>[
        for (final payload in fixture.sampleWirePayloads)
          ...await fixture.mapSampleWirePayload(payload),
      ];
      expect(events, isNotEmpty, reason: '非空 wire fixture 必须产出规范化事件');
      expect(_eventIdentityViolations(events), isEmpty);
    });

    test('raw payload 保持不透明且可稳定渲染', () async {
      final fixture = createFixture();
      if (fixture.sampleWirePayloads.isEmpty) {
        markTestSkipped('该插件尚未提供脱敏 wire fixture');
      }

      final payloads = <AgentProviderRawPayload>[
        for (final payload in fixture.sampleWirePayloads)
          for (final event in await fixture.mapSampleWirePayload(payload))
            ..._rawPayloads(event),
      ];
      for (final payload in payloads) {
        expect(payload.toPrettyJson(), payload.toPrettyJson());
        expect(payload.toString(), startsWith('AgentProviderRawPayload('));
      }
    });
  });

  group('审批语义（G5）', () {
    test('权限、提问与 Plan 审批 decision 模型互不混用', () {
      const permission = AgentPermissionDecision(
        requestId: 'permission',
        approved: false,
      );
      const question = AgentQuestionResponse(requestId: 'question');
      const plan = AgentPlanApprovalDecision(
        requestId: 'plan',
        kind: AgentPlanApprovalDecisionKind.cancelled,
      );

      expect(permission, isNot(isA<AgentQuestionResponse>()));
      expect(permission, isNot(isA<AgentPlanApprovalDecision>()));
      expect(question, isNot(isA<AgentPermissionDecision>()));
      expect(question, isNot(isA<AgentPlanApprovalDecision>()));
      expect(plan, isNot(isA<AgentPermissionDecision>()));
      expect(plan, isNot(isA<AgentQuestionResponse>()));
    });
  });
}

/// 返回 bundle 的 capability/端口不一致项，供套件自测和插件私有测试复用。
List<String> agentProviderBundleContractViolations(AgentProviderBundle bundle) {
  final contracts = _optionalPortContracts(bundle);
  return List<String>.unmodifiable(<String>[
    ..._portImpliesCapabilityViolations(contracts),
    ..._capabilityRequiresPortViolations(contracts),
  ]);
}

final class _OptionalPortContract {
  const _OptionalPortContract({
    required this.name,
    required this.isPresent,
    this.capability,
    this.discoversCapability = false,
  });

  final String name;
  final bool isPresent;

  /// null 表示 core 没有为该端口声明冗余静态 capability，端口本身即真源。
  final bool? capability;

  /// 目录查询先于能力协商；查询端口存在不代表已有可选项。
  final bool discoversCapability;
}

List<_OptionalPortContract> _optionalPortContracts(AgentProviderBundle bundle) {
  final capabilities = bundle.capabilities;
  return <_OptionalPortContract>[
    _OptionalPortContract(
      name: 'threadCatalog',
      isPresent: bundle.threadCatalog != null,
      capability: capabilities.canListThreads || capabilities.canReadHistory,
    ),
    _OptionalPortContract(
      name: 'threadSubscription',
      isPresent: bundle.threadSubscription != null,
    ),
    _OptionalPortContract(
      name: 'threadNaming',
      isPresent: bundle.threadNaming != null,
      capability: capabilities.canRenameThread,
    ),
    _OptionalPortContract(
      name: 'threadArchival',
      isPresent: bundle.threadArchival != null,
      capability:
          capabilities.canArchiveThread || capabilities.canUnarchiveThread,
    ),
    _OptionalPortContract(
      name: 'threadDeletion',
      isPresent: bundle.threadDeletion != null,
      capability: capabilities.canDeleteThread,
    ),
    _OptionalPortContract(
      name: 'threadCompaction',
      isPresent: bundle.threadCompaction != null,
      capability: capabilities.canCompactThread,
    ),
    _OptionalPortContract(
      name: 'threadBranching',
      isPresent: bundle.threadBranching != null,
      capability: capabilities.canForkThread,
    ),
    _OptionalPortContract(
      name: 'turnSteering',
      isPresent: bundle.turnSteering != null,
      capability: capabilities.canSteerTurn,
    ),
    _OptionalPortContract(
      name: 'permissionResponses',
      isPresent: bundle.permissionResponses != null,
      capability: capabilities.supportsPermissionRequests,
    ),
    _OptionalPortContract(
      name: 'questions',
      isPresent: bundle.questions != null,
      capability: capabilities.supportsUserQuestions,
    ),
    _OptionalPortContract(
      name: 'deniedActionOverride',
      isPresent: bundle.deniedActionOverride != null,
    ),
    _OptionalPortContract(
      name: 'modelCatalog',
      isPresent: bundle.modelCatalog != null,
      capability: capabilities.supportsModelSelection,
    ),
    _OptionalPortContract(
      name: 'conversationModes',
      isPresent: bundle.conversationModes != null,
      capability: capabilities.supportsModeSelection,
      discoversCapability: true,
    ),
    _OptionalPortContract(
      name: 'skills',
      isPresent: bundle.skills != null,
      capability: capabilities.supportsSkillInput,
    ),
    _OptionalPortContract(
      name: 'localThreadList',
      isPresent: bundle.localThreadList != null,
      capability: capabilities.canRemoveThreadFromList,
    ),
    _OptionalPortContract(
      name: 'sessionConfiguration',
      isPresent: bundle.sessionConfiguration != null,
    ),
    _OptionalPortContract(
      name: 'planApproval',
      isPresent: bundle.planApproval != null,
      capability: capabilities.supportsPlanApproval,
    ),
    _OptionalPortContract(
      name: 'permissionPolicy',
      isPresent: bundle.permissionPolicy != null,
    ),
    _OptionalPortContract(
      name: 'usageQuota',
      isPresent: bundle.usageQuota != null,
      capability: capabilities.supportsUsage,
    ),
  ];
}

List<String> _portImpliesCapabilityViolations(
  Iterable<_OptionalPortContract> contracts,
) => <String>[
  for (final contract in contracts)
    if (contract.isPresent &&
        contract.capability == false &&
        !contract.discoversCapability)
      '${contract.name}: port present but capability=false',
];

List<String> _capabilityRequiresPortViolations(
  Iterable<_OptionalPortContract> contracts,
) => <String>[
  for (final contract in contracts)
    if (contract.capability == true && !contract.isPresent)
      '${contract.name}: capability=true but port is null',
];

Map<String, Object> _capabilitySnapshot(
  AgentProviderCapabilities capabilities,
) => <String, Object>{
  'canCreateSession': capabilities.canCreateSession,
  'canResumeSession': capabilities.canResumeSession,
  'canListThreads': capabilities.canListThreads,
  'canReadHistory': capabilities.canReadHistory,
  'canDeleteThread': capabilities.canDeleteThread,
  'canRemoveThreadFromList': capabilities.canRemoveThreadFromList,
  'canPrompt': capabilities.canPrompt,
  'canCancelTurn': capabilities.canCancelTurn,
  'canSteerTurn': capabilities.canSteerTurn,
  'canRenameThread': capabilities.canRenameThread,
  'canArchiveThread': capabilities.canArchiveThread,
  'canUnarchiveThread': capabilities.canUnarchiveThread,
  'canForkThread': capabilities.canForkThread,
  'canForkThreadAtTurn': capabilities.canForkThreadAtTurn,
  'canCompactThread': capabilities.canCompactThread,
  'supportsTextInput': capabilities.supportsTextInput,
  'supportsLocalImageInput': capabilities.supportsLocalImageInput,
  'supportsResourceInput': capabilities.supportsResourceInput,
  'supportsSkillInput': capabilities.supportsSkillInput,
  'supportsPermissionRequests': capabilities.supportsPermissionRequests,
  'supportsUserQuestions': capabilities.supportsUserQuestions,
  'supportsPlanApproval': capabilities.supportsPlanApproval,
  'supportsModelSelection': capabilities.supportsModelSelection,
  'supportsModeSelection': capabilities.supportsModeSelection,
  'supportsReasoningOptions': capabilities.supportsReasoningOptions,
  'supportsServiceTierSelection': capabilities.supportsServiceTierSelection,
  'supportsUsage': capabilities.supportsUsage,
  'requiresWorkspace': capabilities.bootstrapPolicy.requiresWorkspace,
  'allowsEagerModelPreload':
      capabilities.bootstrapPolicy.allowsEagerModelPreload,
};

List<String> _eventIdentityViolations(Iterable<AgentEvent> events) {
  final violations = <String>[];
  for (final event in events) {
    final identity = switch (event) {
      AgentMessageDeltaEvent(:final messageId) => messageId,
      AgentMessageUpdatedEvent(:final messageId) => messageId,
      AgentReasoningDeltaEvent(:final itemId) => itemId,
      AgentToolCallEvent(:final toolCall) => toolCall.id,
      AgentPermissionRequestedEvent(:final request) => request.id,
      AgentQuestionRequestedEvent(:final request) => request.id,
      AgentPlanApprovalRequestedEvent(:final request) => request.id,
      _ => null,
    };
    if (identity != null && identity.trim().isEmpty) {
      violations.add('${event.runtimeType}: empty normalized identity');
    }
  }
  return violations;
}

Iterable<AgentProviderRawPayload> _rawPayloads(AgentEvent event) sync* {
  switch (event) {
    case AgentMessageDeltaEvent(:final raw):
    case AgentMessageUpdatedEvent(:final raw):
    case AgentReasoningDeltaEvent(:final raw):
      yield raw;
    case AgentToolCallEvent(:final toolCall):
      yield toolCall.raw;
      yield toolCall.rawInput;
      yield toolCall.rawOutput;
    case AgentPermissionRequestedEvent(:final request):
      yield request.raw;
    case AgentQuestionRequestedEvent(:final request):
      yield request.raw;
    case AgentPlanApprovalRequestedEvent(:final request):
      yield request.raw;
    default:
      return;
  }
}

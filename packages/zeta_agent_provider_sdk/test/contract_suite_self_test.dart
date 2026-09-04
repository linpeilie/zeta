import 'package:test/test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta_agent_provider_sdk/zeta_agent_provider_sdk.dart';
import 'package:zeta_agent_provider_sdk/zeta_agent_provider_sdk_testing.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

void main() {
  runAgentProviderContractTests(_PassingFixture.new);

  group('contract suite self-test', () {
    test('全绿 fixture 没有端口/能力违规', () {
      final bundle = _PassingFixture().createBundle();
      addTearDown(bundle.runtime.dispose);

      expect(agentProviderBundleContractViolations(bundle), isEmpty);
    });

    test('端口与能力不一致的 fixture 会被抓住', () {
      final bundle = _FailingFixture().createBundle();
      addTearDown(bundle.runtime.dispose);

      expect(
        agentProviderBundleContractViolations(bundle),
        contains('threadCatalog: port present but capability=false'),
      );
    });
  });
}

const _config = AgentProviderConfig(
  id: 'contract',
  displayName: 'Contract',
  kind: AgentProviderTypeId('contract'),
  command: 'contract',
);

const _definition = AgentProviderDefinition(
  providerId: 'contract',
  providerType: AgentProviderTypeId('contract'),
  defaultConfig: _config,
  staticCapabilities: AgentProviderCapabilities.unsupported,
  modelCatalogSourceLabel: 'contract',
  metricLabel: ZetaMetricLabel.constant('contract'),
  isDefault: true,
);

final class _PassingFixture extends AgentProviderContractFixture {
  @override
  AgentProviderDefinition get definition => _definition;

  @override
  List<Object> get sampleWirePayloads => const <Object>[
    <String, Object?>{'text': 'redacted'},
  ];

  @override
  List<AgentEvent> mapSampleWirePayload(Object payload) => <AgentEvent>[
    AgentMessageDeltaEvent(
      messageId: 'entry-1',
      delta: 'redacted',
      role: AgentMessageRole.agent,
      raw: wrapAgentProviderPayload(payload as Map<String, Object?>),
    ),
  ];

  @override
  AgentProviderBundle createBundle() {
    final host = _FakeHost();
    return AgentProviderBundle(runtime: host, conversation: host);
  }
}

final class _FailingFixture extends AgentProviderContractFixture {
  @override
  AgentProviderDefinition get definition => _definition;

  @override
  AgentProviderBundle createBundle() {
    final host = _FakeHost();
    return AgentProviderBundle(
      runtime: host,
      conversation: host,
      threadCatalog: const _FakeThreadCatalog(),
    );
  }
}

final class _FakeHost implements AgentRuntimePort, AgentConversationPort {
  @override
  AgentProviderCapabilities get capabilities =>
      AgentProviderCapabilities.unsupported;

  @override
  AgentProviderConfig get config => _config;

  @override
  Stream<AgentEvent> get events => const Stream<AgentEvent>.empty();

  @override
  AgentProviderLifecycleState get lifecycleState =>
      AgentProviderLifecycleState.stopped;

  @override
  AgentRuntimeInfo? get runtimeInfo => null;

  @override
  AgentRuntimeScope? get runtimeScope => null;

  @override
  Future<void> cancelTurn(AgentTurn turn) async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<AgentSession> resumeSession(
    String sessionId, {
    required AgentContext context,
    AgentPermissionRequestSnapshot permissionSnapshot =
        const AgentPermissionRequestSnapshot.providerFallback(),
  }) => throw UnsupportedError('not used by contract self-test');

  @override
  Future<AgentTurn> sendMessage({
    required AgentSession session,
    required AgentContext context,
    String? message,
    List<AgentUserInput>? inputs,
    String? clientUserMessageId,
    AgentTurnConfiguration configuration = const AgentTurnConfiguration(),
  }) => throw UnsupportedError('not used by contract self-test');

  @override
  Future<AgentSession> startSession({
    required AgentContext context,
    AgentPermissionRequestSnapshot permissionSnapshot =
        const AgentPermissionRequestSnapshot.providerFallback(),
  }) => throw UnsupportedError('not used by contract self-test');

  @override
  void updateModelSelection(AgentModelSelection selection) {}
}

final class _FakeThreadCatalog implements AgentThreadCatalogPort {
  const _FakeThreadCatalog();

  @override
  Future<AgentThreadPage> listThreads({required AgentThreadListQuery query}) =>
      throw UnsupportedError('not used by contract self-test');

  @override
  Future<AgentThreadHistorySnapshot> readThreadHistory({
    required String threadId,
    String? sessionPath,
    String? projectPath,
  }) => throw UnsupportedError('not used by contract self-test');
}

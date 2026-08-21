import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/core/observability/in_memory_zeta_metrics_port.dart';
import 'package:zeta/src/core/observability/zeta_metric.dart';
import 'package:zeta/src/features/agent/application/agent_provider_runtime_registry.dart';
import 'package:zeta/src/features/agent/application/agent_provider_settings_controller.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider_bundle.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_view_model.dart';

import '../../../testing/agent_conversation_binding_test_harness.dart';
import '../../../testing/agent_provider_stub_base.dart';
import '../../../testing/fake_agent_frame_scheduler.dart';
import '../../../testing/legacy_bundle_factory_mixin.dart';

/// 阶段 0 行为快照：发送 / 取消 / 审批的真实 wire 序列与双会话隔离。
///
/// 这些断言刻意写在「Provider 端口调用序列」这一层，而不是 UI 细节上：
/// Phase 2 把 conversation 外壳迁到 Riverpod slice 之后，这里必须**逐字**
/// 复现同一序列，否则说明迁移改变了产品语义。
///
/// 同时验证阶段 0 探针在真实 ViewModel 链路上按 Provider 分序列聚合，
/// 并且不把 prompt、回复正文或路径写进指标。
void main() {
  test('发送与取消的 wire 序列固定，且不预授权任何操作', () async {
    final provider = _RecordingProvider();
    final metrics = InMemoryZetaMetricsPort();
    final viewModel = _createViewModel(provider, metrics: metrics);
    addTearDown(viewModel.dispose);
    await viewModel.loadSettings();

    await viewModel.sendMessage('run the tests');
    provider.emit(
      const AgentTurnStartedEvent(
        AgentTurn(id: 'turn-1', sessionId: 'thread-1'),
      ),
    );
    await _settle();
    await viewModel.cancelActiveTurn();
    await _settle();

    expect(provider.calls, <String>[
      'start',
      'send:thread-1',
      'cancel:thread-1:turn-1',
    ]);
    // 权限快照走 Provider 默认；Zeta 不得在发送/取消路径上替用户提升权限。
    expect(
      provider.startPermissionSnapshots.single.source,
      AgentPermissionRequestSource.providerFallback,
    );
    expect(provider.startPermissionSnapshots.single.selection, isNull);
    expect(provider.permissionDecisions, isEmpty);
  });

  test('权限审批只经 respondToPermission 回写，决策原样传递', () async {
    final provider = _RecordingProvider();
    final viewModel = _createViewModel(provider);
    addTearDown(viewModel.dispose);
    await viewModel.loadSettings();

    await viewModel.sendMessage('touch a file');
    provider.emit(
      const AgentTurnStartedEvent(
        AgentTurn(id: 'turn-1', sessionId: 'thread-1'),
      ),
    );
    provider.emit(
      const AgentPermissionRequestedEvent(
        AgentPermissionRequest(
          id: 'permission-1',
          sessionId: 'thread-1',
          turnId: 'turn-1',
          title: 'Write file',
          kind: AgentPermissionKind.fileChange,
        ),
      ),
    );
    await _settle();

    final request = viewModel.permissionRequests.single;
    await viewModel.respondToPermission(request, approved: true);
    await _settle();

    expect(provider.permissionDecisions, hasLength(1));
    expect(provider.permissionDecisions.single.requestId, 'permission-1');
    expect(provider.permissionDecisions.single.approved, isTrue);
    expect(viewModel.permissionRequests, isEmpty);
    // 审批不得顺带触发新的 turn 或取消。
    expect(provider.calls, <String>['start', 'send:thread-1']);
  });

  test('两个 Binding 的时间线、回合状态与指标序列互不串扰', () async {
    final metrics = InMemoryZetaMetricsPort();
    final firstProvider = _RecordingProvider(threadId: 'thread-1');
    final secondProvider = _RecordingProvider(
      threadId: 'thread-2',
      providerId: grokAgentProviderId,
      config: AgentProviderConfig.defaultGrok,
    );
    final first = _createViewModel(firstProvider, metrics: metrics);
    final second = _createViewModel(secondProvider, metrics: metrics);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await first.loadSettings();
    await second.loadSettings();

    await first.sendMessage('first');
    await second.sendMessage('second');
    firstProvider.emit(
      const AgentTurnStartedEvent(
        AgentTurn(id: 'turn-1', sessionId: 'thread-1'),
      ),
    );
    firstProvider.emit(
      const AgentMessageDeltaEvent(
        messageId: 'message-1',
        delta: 'only for the first thread',
        role: AgentMessageRole.agent,
        sessionId: 'thread-1',
        turnId: 'turn-1',
      ),
    );
    firstProvider.emit(
      const AgentTurnCompletedEvent(sessionId: 'thread-1', turnId: 'turn-1'),
    );
    await _settle();

    expect(first.timelineEntries, isNotEmpty);
    expect(
      second.timelineEntries.whereType<AgentMessageTimelineEntry>().where(
        (entry) => entry.message.text.contains('only for the first thread'),
      ),
      isEmpty,
    );
    // thread-1 的终态事件只结算自己的回合，thread-2 仍在运行。
    expect(first.isTurnRunning, isFalse);
    expect(second.isTurnRunning, isTrue);
    expect(firstProvider.calls, <String>['start', 'send:thread-1']);
    expect(secondProvider.calls, <String>['start', 'send:thread-2']);

    // 指标按 Provider 分序列；正文与路径不出现在任何序列里。
    final firstTags = ZetaMetricTags(providerId: defaultAgentProviderId);
    final secondTags = ZetaMetricTags(providerId: grokAgentProviderId);
    expect(
      metrics.totalOf(ZetaMetric.agentPipelineEventsAccepted, tags: firstTags),
      greaterThan(0),
    );
    expect(
      metrics.totalOf(ZetaMetric.agentPipelineEventsAccepted, tags: secondTags),
      0,
    );
    final text = metrics.snapshot().map((series) => '$series').join('\n');
    expect(text, isNot(contains('only for the first thread')));
    expect(text, isNot(contains('/repo')));
  });
}

AgentConversationViewModel _createViewModel(
  _RecordingProvider provider, {
  InMemoryZetaMetricsPort? metrics,
}) {
  final registry = AgentProviderRuntimeRegistry(
    providerFactory: _RecordingProviderFactory(provider),
    metrics: metrics ?? InMemoryZetaMetricsPort(enabled: false),
  );
  addTearDown(registry.close);
  final controller = AgentProviderSettingsController(
    runtimeRegistry: registry,
    configStore: MemoryAgentProviderConfigStore(
      AgentProviderSettings(
        providers: <AgentProviderConfig>[provider.config],
        activeProviderId: provider.config.id,
      ),
    ),
  );
  addTearDown(controller.dispose);
  final harness = AgentConversationBindingTestHarness(
    registry: registry,
    settings: controller,
  );
  addTearDown(harness.close);
  final lease = harness.acquireDraft(provider.config);
  return AgentConversationViewModel(
    providerController: controller,
    conversationBinding: lease.binding,
    globalRuntime: harness.globalRuntime,
    initialProjectPath: '/repo',
    uiFrameScheduler: FakeAgentFrameScheduler(),
    metrics: metrics ?? InMemoryZetaMetricsPort(enabled: false),
  );
}

Future<void> _settle() async {
  for (var attempt = 0; attempt < 8; attempt += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _RecordingProviderFactory with LegacyBundleFactoryMixin {
  _RecordingProviderFactory(this.provider);

  final _RecordingProvider provider;

  @override
  Object create(AgentProviderConfig config) => provider;
}

/// 只记录端口调用序列的中立 fake；不模拟任何真实 CLI 协议。
class _RecordingProvider
    with AgentProviderThreadLifecycleStub
    implements
        AgentRuntimePort,
        AgentConversationPort,
        AgentPermissionResponsePort {
  _RecordingProvider({
    this.threadId = 'thread-1',
    this.providerId = defaultAgentProviderId,
    AgentProviderConfig? config,
  }) : config = config ?? AgentProviderConfig.defaultCodex;

  final String threadId;
  final String providerId;

  @override
  final AgentProviderConfig config;

  final List<String> calls = <String>[];
  final List<AgentPermissionRequestSnapshot> startPermissionSnapshots =
      <AgentPermissionRequestSnapshot>[];
  final List<AgentPermissionDecision> permissionDecisions =
      <AgentPermissionDecision>[];

  final StreamController<AgentEvent> _events =
      StreamController<AgentEvent>.broadcast();
  bool _disposed = false;

  @override
  String get threadLifecycleProviderId => providerId;

  @override
  Stream<AgentEvent> get events => _events.stream;

  @override
  AgentRuntimeInfo? get runtimeInfo => null;

  @override
  AgentProviderLifecycleState get lifecycleState =>
      AgentProviderLifecycleState.ready;

  @override
  AgentRuntimeScope? get runtimeScope =>
      AgentRuntimeScope(runtimeId: providerId, connectionEpoch: 1);

  @override
  void updateModelSelection(AgentModelSelection selection) {}

  @override
  Future<void> initialize() async {}

  @override
  Future<AgentSession> startSession({
    required AgentContext context,
    AgentPermissionRequestSnapshot permissionSnapshot =
        const AgentPermissionRequestSnapshot.providerFallback(),
  }) async {
    calls.add('start');
    startPermissionSnapshots.add(permissionSnapshot);
    return AgentSession(id: threadId, providerId: providerId);
  }

  @override
  Future<AgentSession> resumeSession(
    String sessionId, {
    required AgentContext context,
    AgentPermissionRequestSnapshot permissionSnapshot =
        const AgentPermissionRequestSnapshot.providerFallback(),
  }) async {
    calls.add('resume:$sessionId');
    return AgentSession(id: sessionId, providerId: providerId);
  }

  @override
  Future<AgentTurn> sendMessage({
    required AgentSession session,
    required AgentContext context,
    String? message,
    List<AgentUserInput>? inputs,
    String? clientUserMessageId,
    AgentTurnConfiguration configuration = const AgentTurnConfiguration(),
  }) async {
    calls.add('send:${session.id}');
    return AgentTurn(id: 'turn-1', sessionId: session.id);
  }

  @override
  Future<void> cancelTurn(AgentTurn turn) async {
    calls.add('cancel:${turn.sessionId}:${turn.id}');
  }

  @override
  Future<void> respondToPermission(AgentPermissionDecision decision) async {
    permissionDecisions.add(decision);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _events.close();
  }

  void emit(AgentEvent event) {
    if (!_disposed) {
      _events.add(event);
    }
  }
}

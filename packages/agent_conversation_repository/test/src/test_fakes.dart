import 'dart:async';

import 'package:agent_config_client/agent_config_client.dart';
import 'package:agent_provider_contracts/agent_provider_contracts.dart';

final class TestRuntime implements AgentRuntimePort {
  TestRuntime(String providerId)
    : config = AgentProviderConfig(
        id: providerId,
        displayName: 'Test',
        kind: AgentProviderKind.codexAppServer,
        command: 'test',
      );

  final StreamController<AgentEvent> eventController =
      StreamController<AgentEvent>.broadcast(sync: true);
  @override
  final AgentProviderConfig config;
  @override
  AgentProviderCapabilities capabilities = const AgentProviderCapabilities(
    canCreateSession: true,
    canResumeSession: true,
    canPrompt: true,
    canCancelTurn: true,
  );
  @override
  AgentProviderLifecycleState lifecycleState =
      AgentProviderLifecycleState.ready;
  @override
  AgentRuntimeInfo? runtimeInfo;
  @override
  AgentRuntimeScope? runtimeScope = const AgentRuntimeScope(
    runtimeId: 'runtime',
    connectionEpoch: 1,
  );
  int initializeCalls = 0;
  int disposeCalls = 0;
  Exception? initializeError;
  Exception? eventsError;
  Completer<void>? initializeBarrier;

  @override
  Stream<AgentEvent> get events {
    if (eventsError case final error?) throw error;
    return eventController.stream;
  }

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
    if (initializeError case final error?) throw error;
    await initializeBarrier?.future;
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
  }

  @override
  void updateModelSelection(AgentModelSelection selection) {}
}

final class TestConversationPort implements AgentConversationPort {
  AgentSession session = AgentSession(id: 'thread-1', providerId: 'provider');
  AgentTurn turn = AgentTurn(id: 'turn-1', sessionId: 'thread-1');
  int startCalls = 0;
  int resumeCalls = 0;
  int sendCalls = 0;
  int cancelCalls = 0;
  Exception? startError;
  Exception? resumeError;
  Exception? sendError;
  Exception? cancelError;
  AgentContext? lastContext;
  String? lastMessage;
  AgentPermissionRequestSnapshot? lastPermissionSnapshot;

  @override
  Future<AgentSession> startSession({
    required AgentContext context,
    AgentPermissionRequestSnapshot permissionSnapshot =
        const AgentPermissionRequestSnapshot.providerFallback(),
  }) async {
    startCalls += 1;
    lastContext = context;
    lastPermissionSnapshot = permissionSnapshot;
    if (startError case final error?) throw error;
    return session;
  }

  @override
  Future<AgentSession> resumeSession(
    String sessionId, {
    required AgentContext context,
    AgentPermissionRequestSnapshot permissionSnapshot =
        const AgentPermissionRequestSnapshot.providerFallback(),
  }) async {
    resumeCalls += 1;
    lastContext = context;
    lastPermissionSnapshot = permissionSnapshot;
    if (resumeError case final error?) throw error;
    return session;
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
    sendCalls += 1;
    lastContext = context;
    lastMessage = message;
    if (sendError case final error?) throw error;
    return turn;
  }

  @override
  Future<void> cancelTurn(AgentTurn turn) async {
    cancelCalls += 1;
    if (cancelError case final error?) throw error;
  }
}

final class TestThreadCatalog implements AgentThreadCatalogPort {
  AgentThreadHistorySnapshot snapshot = AgentThreadHistorySnapshot(
    threadId: 'thread-1',
    turns: const <AgentHistoryTurn>[],
  );
  Exception? error;
  int calls = 0;

  @override
  Future<AgentThreadPage> listThreads({required AgentThreadListQuery query}) {
    throw UnimplementedError();
  }

  @override
  Future<AgentThreadHistorySnapshot> readThreadHistory({
    required String threadId,
    String? sessionPath,
    String? projectPath,
  }) async {
    calls += 1;
    if (error case final value?) throw value;
    return snapshot;
  }
}

final class TestTurnContextStore implements AgentTurnContextStore {
  final Map<String, AgentThreadTurnContext> values =
      <String, AgentThreadTurnContext>{};
  Exception? loadError;
  Exception? saveError;
  int loadCalls = 0;
  int saveCalls = 0;

  @override
  Future<AgentThreadTurnContext?> load({
    required String providerId,
    required String threadId,
  }) async {
    loadCalls += 1;
    if (loadError case final error?) throw error;
    return values['$providerId\u0000$threadId'];
  }

  @override
  Future<void> save(AgentThreadTurnContext context) async {
    saveCalls += 1;
    if (saveError case final error?) throw error;
    values['${context.providerId}\u0000${context.threadId}'] = context;
  }
}

final class TestResponsePorts
    implements
        AgentPermissionResponsePort,
        AgentQuestionResponsePort,
        AgentPlanApprovalPort,
        AgentTurnSteeringPort,
        AgentThreadSubscriptionPort {
  int permissionCalls = 0;
  int questionCalls = 0;
  int planCalls = 0;
  int steerCalls = 0;
  int unsubscribeCalls = 0;
  Exception? error;

  Future<void> _run(void Function() increment) async {
    increment();
    if (error case final value?) throw value;
  }

  @override
  Future<void> respondToPermission(AgentPermissionDecision decision) =>
      _run(() => permissionCalls += 1);

  @override
  Future<void> respondToQuestion(AgentQuestionResponse response) =>
      _run(() => questionCalls += 1);

  @override
  Future<void> respondToPlanApproval(AgentPlanApprovalDecision decision) =>
      _run(() => planCalls += 1);

  @override
  Future<void> steerTurn({
    required AgentSession session,
    required String expectedTurnId,
    required AgentContext context,
    String? message,
    List<AgentUserInput>? inputs,
    String? clientUserMessageId,
  }) => _run(() => steerCalls += 1);

  @override
  Future<void> unsubscribeThread(String threadId) =>
      _run(() => unsubscribeCalls += 1);
}

AgentProviderBundle testBundle({
  required TestRuntime runtime,
  required TestConversationPort conversation,
  TestThreadCatalog? history,
  TestResponsePorts? ports,
}) => AgentProviderBundle(
  runtime: runtime,
  conversation: conversation,
  threadCatalog: history,
  threadSubscription: ports,
  turnSteering: ports,
  permissionResponses: ports,
  questions: ports,
  planApproval: ports,
);

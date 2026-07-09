import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';

import 'agent_provider_stub_base.dart';

ValueKey<String> fileNodeKey(String label) {
  return ValueKey<String>('file-node-$label');
}

Future<void> waitForIo() {
  return Future<void>.delayed(const Duration(milliseconds: 300));
}

Future<void> pumpSessionSave(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 450));
  await tester.pump();
}

String sessionJson({required String projectPath, String? currentFilePath}) {
  return jsonEncode(<String, Object?>{
    'version': 1,
    'projectPaths': <String>[projectPath],
    'activeProjectPath': projectPath,
    'currentFilePath': currentFilePath,
    'expandedDirectoryPaths': <String>[projectPath],
    'selectedTreeKey': currentFilePath ?? projectPath,
  });
}

String? headerTitleText(WidgetTester tester) {
  return tester
      .widget<Text>(find.byKey(const ValueKey('agent-header-title')))
      .data;
}

String commandGroupId(String turnId, String firstEntryId) {
  return 'command-group-$turnId-$firstEntryId';
}

String fileEditGroupId(String turnId, String toolCallId) {
  return 'file-edit-group-$turnId-$toolCallId';
}

Map<String, Object?> patchApplyChanges(Map<String, String?> diffsByPath) {
  return <String, Object?>{
    'changes': <String, Object?>{
      for (final entry in diffsByPath.entries)
        entry.key: <String, Object?>{
          'type': 'update',
          if (entry.value != null) 'unified_diff': entry.value,
        },
    },
  };
}

AgentThreadSummary agentThread({
  required String id,
  required String projectPath,
  required String title,
  String? preview,
  DateTime? lastActiveAt,
  AgentThreadRuntimeStatus status = AgentThreadRuntimeStatus.idle,
}) {
  final activeAt = lastActiveAt ?? DateTime.fromMillisecondsSinceEpoch(2);
  return AgentThreadSummary(
    id: id,
    providerId: defaultAgentProviderId,
    projectPath: projectPath,
    title: title,
    sessionPath: '$projectPath/$id.jsonl',
    preview: preview ?? title,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1),
    updatedAt: activeAt,
    recencyAt: activeAt,
    status: status,
  );
}

class MemorySessionStore {
  MemorySessionStore([this.value]);

  String? value;

  Future<String?> load() async => value;

  Future<void> save(String newValue) async {
    value = newValue;
  }
}

class FakeAgentProviderFactory implements AgentProviderFactory {
  const FakeAgentProviderFactory(this.provider);

  final FakeAgentProvider provider;

  @override
  AgentProvider create(AgentProviderConfig config) => provider;
}

class FakeAgentProvider
    with AgentProviderThreadLifecycleStub
    implements AgentProvider {
  FakeAgentProvider({
    this.emitToolAndApproval = false,
    this.emitCompletedCommentary = false,
    this.completeTurns = true,
    this.unavailable = false,
    this.sessionTitle,
    this.tokenUsageDuringTurn,
    this.responseText = 'Fake response from provider',
    this.onResumeSession,
    List<AgentThreadPage> threadPages = const <AgentThreadPage>[],
    Map<String, AgentThreadHistorySnapshot> threadHistories =
        const <String, AgentThreadHistorySnapshot>{},
  }) : _threadPages = List<AgentThreadPage>.from(threadPages),
       _threadHistories = Map<String, AgentThreadHistorySnapshot>.from(
         threadHistories,
       );

  final bool emitToolAndApproval;
  final bool emitCompletedCommentary;
  final bool completeTurns;
  final bool unavailable;
  final String? sessionTitle;
  final AgentTokenUsage? tokenUsageDuringTurn;
  final String responseText;
  final Future<AgentSession> Function(String sessionId)? onResumeSession;
  final List<AgentThreadPage> _threadPages;
  final Map<String, AgentThreadHistorySnapshot> _threadHistories;
  final StreamController<AgentEvent> _events =
      StreamController<AgentEvent>.broadcast();
  final List<String> sentMessages = <String>[];
  final List<List<AgentUserInput>> sentInputs = <List<AgentUserInput>>[];
  final List<String> steeredMessages = <String>[];
  final List<List<AgentUserInput>> steeredInputs = <List<AgentUserInput>>[];
  final List<AgentThreadListQuery> listQueries = <AgentThreadListQuery>[];
  final List<String> readHistories = <String>[];
  final List<String?> readHistorySessionPaths = <String?>[];
  final List<String> resumedSessions = <String>[];
  final List<String> unsubscribedThreads = <String>[];
  final List<String> approvedRequests = <String>[];
  final List<String> deniedRequests = <String>[];
  final List<String> cancelledTurns = <String>[];

  @override
  AgentProviderConfig get config => AgentProviderConfig.defaultCodex;

  @override
  Stream<AgentEvent> get events => _events.stream;

  @override
  Future<void> initialize() async {
    if (unavailable) {
      throw const ProcessException('codex', <String>[], 'codex missing');
    }
  }

  @override
  Future<AgentSession> startSession({required AgentContext context}) async {
    await initialize();
    return AgentSession(
      id: 'thread-1',
      providerId: defaultAgentProviderId,
      title: sessionTitle,
    );
  }

  @override
  Future<AgentSession> resumeSession(
    String sessionId, {
    required AgentContext context,
  }) async {
    await initialize();
    resumedSessions.add(sessionId);
    final onResumeSession = this.onResumeSession;
    if (onResumeSession != null) {
      return onResumeSession(sessionId);
    }
    return AgentSession(
      id: sessionId,
      providerId: defaultAgentProviderId,
      title: sessionTitle,
    );
  }

  @override
  Future<AgentThreadPage> listThreads({
    required AgentThreadListQuery query,
  }) async {
    await initialize();
    listQueries.add(query);
    if (_threadPages.isEmpty) {
      return const AgentThreadPage(
        threads: <AgentThreadSummary>[],
        nextCursor: null,
      );
    }
    return _threadPages.removeAt(0);
  }

  @override
  Future<AgentThreadHistorySnapshot> readThreadHistory({
    required String threadId,
    String? sessionPath,
  }) async {
    await initialize();
    readHistories.add(threadId);
    readHistorySessionPaths.add(sessionPath);
    return _threadHistories[threadId] ??
        AgentThreadHistorySnapshot(
          threadId: threadId,
          turns: const <AgentHistoryTurn>[],
        );
  }

  @override
  Future<void> unsubscribeThread(String threadId) async {
    unsubscribedThreads.add(threadId);
  }

  @override
  Future<void> renameThread({
    required String threadId,
    required String name,
  }) async {
    await super.renameThread(threadId: threadId, name: name);
    _events.add(
      AgentThreadNameUpdatedEvent(threadId: threadId, threadName: name),
    );
  }

  @override
  Future<AgentTurn> sendMessage({
    required AgentSession session,
    required AgentContext context,
    String? message,
    List<AgentUserInput>? inputs,
    String? clientUserMessageId,
  }) async {
    final resolved = _resolveInputs(message: message, inputs: inputs);
    sentInputs.add(resolved);
    final text = resolved
        .whereType<AgentTextUserInput>()
        .map((item) => item.text)
        .join('\n');
    sentMessages.add(text);
    final turn = AgentTurn(id: 'turn-1', sessionId: session.id);
    _events
      ..add(AgentTurnStartedEvent(turn))
      ..add(
        AgentMessageDeltaEvent(
          messageId: 'message-1',
          delta: responseText,
          role: AgentMessageRole.agent,
          phase: emitCompletedCommentary
              ? AgentMessagePhase.commentary
              : AgentMessagePhase.response,
          sessionId: session.id,
          turnId: turn.id,
        ),
      );
    if (tokenUsageDuringTurn != null) {
      _events.add(
        AgentTokenUsageEvent(
          sessionId: session.id,
          turnId: turn.id,
          tokenUsage: tokenUsageDuringTurn!,
        ),
      );
    }
    if (emitCompletedCommentary) {
      _events.add(
        AgentMessageUpdatedEvent(
          messageId: 'message-1',
          phase: AgentMessagePhase.commentary,
          status: AgentMessageStatus.completed,
          duration: Duration(seconds: 102),
          sessionId: session.id,
          turnId: turn.id,
        ),
      );
    }
    if (emitToolAndApproval) {
      _events
        ..add(
          AgentToolCallEvent(
            AgentToolCall(
              id: 'tool-1',
              title: 'Run tests',
              kind: AgentToolKind.execute,
              status: AgentToolStatus.inProgress,
              content: 'flutter test',
              sessionId: session.id,
              turnId: turn.id,
            ),
          ),
        )
        ..add(
          AgentPermissionRequestedEvent(
            AgentPermissionRequest(
              id: 'approval-1',
              title: 'Approve command',
              kind: AgentPermissionKind.commandExecution,
              command: 'flutter test',
              sessionId: session.id,
              turnId: turn.id,
            ),
          ),
        );
    }
    if (completeTurns) {
      _events.add(
        AgentTurnCompletedEvent(sessionId: session.id, turnId: turn.id),
      );
    }
    return turn;
  }

  @override
  Future<void> steerTurn({
    required AgentSession session,
    required AgentContext context,
    String? message,
    List<AgentUserInput>? inputs,
    String? clientUserMessageId,
  }) async {
    final resolved = _resolveInputs(message: message, inputs: inputs);
    steeredInputs.add(resolved);
    steeredMessages.add(
      resolved
          .whereType<AgentTextUserInput>()
          .map((item) => item.text)
          .join('\n'),
    );
  }

  List<AgentUserInput> _resolveInputs({
    String? message,
    List<AgentUserInput>? inputs,
  }) {
    if (inputs != null && inputs.isNotEmpty) {
      return List<AgentUserInput>.unmodifiable(inputs);
    }
    return List<AgentUserInput>.unmodifiable(<AgentUserInput>[
      AgentUserInput.text(message ?? ''),
    ]);
  }

  @override
  Future<void> cancelTurn(AgentTurn turn) async {
    cancelledTurns.add(turn.id);
    _events.add(
      AgentTurnCompletedEvent(sessionId: turn.sessionId, turnId: turn.id),
    );
  }

  @override
  Future<AgentModelList> listModels({
    int limit = 20,
    bool includeHidden = false,
  }) async {
    return const AgentModelList(models: <AgentModelInfo>[]);
  }

  @override
  void updateModelSelection(AgentModelSelection selection) {}

  @override
  void updatePermissionSelection(AgentPermissionSelection selection) {}

  @override
  Future<List<AgentPermissionProfileSummary>> listPermissionProfiles() async {
    return const <AgentPermissionProfileSummary>[];
  }

  @override
  Future<void> approveGuardianDeniedAction({
    required String threadId,
    required Object event,
  }) async {}

  @override
  Future<void> respondToPermission(AgentPermissionDecision decision) async {
    if (decision.approved) {
      approvedRequests.add(decision.requestId);
    } else {
      deniedRequests.add(decision.requestId);
    }
  }

  @override
  Future<void> dispose() async {
    await _events.close();
  }

  void emit(AgentEvent event) {
    _events.add(event);
  }
}

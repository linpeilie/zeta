import 'package:agent_conversation_repository/agent_conversation_repository.dart';
import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:test/test.dart';

void main() {
  group('conversation keys and requests', () {
    test(
      'keys have stable value semantics without leaking ids in toString',
      () {
        const draft = ConversationKey.draft(
          providerId: 'provider',
          entryId: 'secret-entry',
        );
        const thread = ConversationKey.thread(
          providerId: 'provider',
          threadId: 'secret-thread',
        );

        expect(
          draft,
          const DraftConversationKey(
            providerId: 'provider',
            entryId: 'secret-entry',
          ),
        );
        expect(draft.toString(), 'draft(provider)');
        expect(thread.toString(), 'thread(provider)');
        expect(draft, isNot(thread));
      },
    );

    test('turn and steer requests retain frozen inputs', () {
      const context = AgentContext(projectPath: 'project');
      const turn = TurnRequest(message: 'hello', context: context);
      const steer = SteerRequest(message: 'next', context: context);

      expect(turn.message, 'hello');
      expect(turn.inputs, isNull);
      expect(turn.clientUserMessageId, isNull);
      expect(turn.configuration, isA<AgentTurnConfiguration>());
      expect(
        turn.permissionSnapshot.source,
        AgentPermissionRequestSource.providerFallback,
      );
      expect(turn.context, context);
      expect(steer.message, 'next');
      expect(steer.inputs, isNull);
      expect(steer.clientUserMessageId, isNull);
      expect(steer.context, context);
    });
  });

  test('timeline entry value objects compare all domain fields', () {
    const message = ConversationMessageEntry(
      id: 'message',
      turnId: 'turn',
      role: AgentMessageRole.agent,
      text: 'a',
      sourceMessageId: 'source',
      messageKind: AgentMessageKind.plan,
      phase: AgentMessagePhase.response,
      status: AgentMessageStatus.streaming,
      duration: Duration(seconds: 1),
    );
    final changed = message.copyWith(
      text: 'b',
      role: AgentMessageRole.system,
      status: AgentMessageStatus.completed,
    );
    final unchanged = message.copyWith();
    const reasoning = ConversationReasoningEntry(
      id: 'reasoning',
      turnId: 'turn',
      text: 'think',
      reasoningKind: AgentReasoningDeltaKind.summaryText,
      sourceItemId: 'source',
    );
    final tool = AgentToolCall(id: 'tool', title: 'Tool');
    final toolEntry = ConversationToolEntry(
      id: 'tool',
      turnId: 'turn',
      toolCall: tool,
    );
    final historyValue = AgentHistoryEventEntry(
      id: 'history',
      kind: AgentHistoryEventKind.system,
      title: 'System',
    );
    final history = ConversationHistoryEntry(
      id: 'history',
      turnId: 'turn',
      entry: historyValue,
    );
    final fileChanges = ConversationFileChangesEntry(
      id: 'files',
      turnId: 'turn',
      snapshot: AgentFileChangeSnapshot(
        revision: 1,
        replayability: AgentFileChangeReplayability.liveOnly,
        changes: const <AgentFileChange>[],
      ),
    );
    final request = AgentPermissionRequest(
      id: 'permission',
      title: 'Permission',
      kind: AgentPermissionKind.other,
    );
    final pending = ConversationPendingEntry(
      id: request.id,
      turnId: 'turn',
      kind: ConversationEntryKind.permission,
      request: request,
    );
    final value = ConversationValueEntry(
      id: 'system',
      turnId: 'turn',
      kind: ConversationEntryKind.system,
      value: request,
    );

    expect(changed.text, 'b');
    expect(changed.role, AgentMessageRole.system);
    expect(changed.status, AgentMessageStatus.completed);
    expect(changed.sourceMessageId, 'source');
    expect(unchanged, message);
    expect(message.props, hasLength(9));
    expect(reasoning.props, hasLength(5));
    expect(toolEntry.props, <Object?>['tool', 'turn', tool]);
    expect(history.props, <Object?>['history', 'turn', historyValue]);
    expect(fileChanges.props, hasLength(3));
    expect(pending.markResolved().resolved, isTrue);
    expect(pending.props, hasLength(5));
    expect(value.props, hasLength(4));
    expect(message.kind, ConversationEntryKind.message);
  });

  test('turn, snapshot, failure and diagnostics are immutable values', () {
    final turn = ConversationTurnSnapshot(
      id: 'turn',
      entries: const <ConversationTimelineEntry>[],
      status: AgentHistoryTurnStatus.completed,
      startedAt: DateTime.utc(2026),
      completedAt: DateTime.utc(2026, 1, 1, 0, 0, 1),
      duration: const Duration(seconds: 1),
      tokenUsage: const AgentTokenUsage(totalTokens: 1),
      contextWindowUsedTokens: 1,
      modelContextWindow: 2,
    );
    const failure = AgentConversationFailure(
      AgentConversationFailureCode.providerOperationFailed,
    );
    final snapshot = ConversationSnapshot(
      key: const ConversationKey.thread(
        providerId: 'provider',
        threadId: 'thread',
      ),
      phase: ConversationPhase.ready,
      generation: 1,
      revision: 2,
      session: AgentSession(id: 'thread', providerId: 'provider'),
      activeTurn: AgentTurn(id: 'turn', sessionId: 'thread'),
      turns: <ConversationTurnSnapshot>[turn],
      threadStatus: AgentThreadRuntimeStatus.active,
      threadName: 'name',
      threadPreview: 'preview',
      isArchived: true,
      waitingOnApproval: true,
      waitingOnUserInput: true,
      pendingPermissions: const <AgentPermissionRequest>[],
      pendingQuestions: const <AgentQuestionRequest>[],
      pendingPlanApprovals: const <AgentPlanApprovalRequest>[],
      autoReviewsByTurnId: const <String, AgentAutoApprovalReviewEvent>{},
      failure: failure,
    );
    const diagnostics = ConversationDiagnostics(
      receivedEvents: 1,
      acceptedEvents: 1,
      coalescedEvents: 0,
      rejectedStaleEvents: 0,
      rejectedOutOfOrderEvents: 0,
      backpressureFlushes: 0,
      maxQueueDepth: 1,
      runtimeLeaseCount: 1,
      reducerInstanceCount: 3,
    );
    final exception = AgentConversationRepositoryException(
      failure: failure,
      cause: StateError('private'),
      stackTrace: StackTrace.current,
    );

    expect(turn.props, hasLength(9));
    expect(snapshot.props, hasLength(22));
    expect(() => snapshot.turns.add(turn), throwsUnsupportedError);
    expect(failure.toString(), contains('providerOperationFailed'));
    expect(failure.props, <Object?>[
      AgentConversationFailureCode.providerOperationFailed,
    ]);
    expect(exception.toString(), isNot(contains('private')));
    expect(exception.cause, isA<StateError>());
    expect(exception.stackTrace, isNotNull);
    expect(diagnostics.props, hasLength(9));
  });
}

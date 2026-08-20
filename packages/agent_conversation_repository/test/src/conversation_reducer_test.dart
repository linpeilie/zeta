import 'package:agent_conversation_repository/src/conversation_models.dart';
import 'package:agent_conversation_repository/src/conversation_reducer.dart';
import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:test/test.dart';

void main() {
  test(
    'history and live reducers build a complete deterministic aggregate',
    () {
      final reducer = ConversationReducer(ConversationReductionScope.live);
      final historyMessage = AgentHistoryMessageEntry(
        id: 'history-message',
        role: AgentMessageRole.user,
        text: 'old',
      );
      final historyTool = AgentToolCall(id: 'history-tool', title: 'Tool');
      final historySystem = AgentHistoryEventEntry(
        id: 'history-system',
        kind: AgentHistoryEventKind.system,
        title: 'System',
      );
      reducer.loadHistory(<AgentHistoryTurn>[
        AgentHistoryTurn(
          id: 'history-turn',
          entries: <AgentHistoryEntry>[
            historyMessage,
            AgentHistoryToolEntry(toolCall: historyTool),
            historySystem,
          ],
          status: AgentHistoryTurnStatus.completed,
          modelContextWindow: 100,
        ),
      ]);
      final session = AgentSession(id: 'thread', providerId: 'provider');
      final turn = AgentTurn(id: 'turn', sessionId: 'thread');
      reducer
        ..reduce(const AgentStatusEvent(AgentProviderStatus.idle()))
        ..reduce(AgentSessionStartedEvent(session))
        ..reduce(
          AgentThreadStatusChangedEvent(
            threadId: 'thread',
            status: AgentThreadRuntimeStatus.active,
            waitingOnApproval: true,
            waitingOnUserInput: true,
          ),
        )
        ..reduce(
          AgentThreadNameUpdatedEvent(threadId: 'thread', threadName: 'Name'),
        )
        ..reduce(
          AgentThreadPreviewUpdatedEvent(
            threadId: 'thread',
            preview: 'Preview',
          ),
        )
        ..reduce(AgentThreadArchivedEvent(threadId: 'thread'))
        ..reduce(AgentThreadUnarchivedEvent(threadId: 'thread'))
        ..reduce(
          AgentThreadSettingsUpdatedEvent(
            threadId: 'thread',
            collaborationMode: AgentConversationModeSelection(
              modeId: AgentConversationModeId.plan,
              effectiveModelId: 'model',
            ),
          ),
        )
        ..reduce(
          AgentAutoApprovalReviewEvent(
            threadId: 'thread',
            turnId: 'turn',
            reviewId: 'review',
            status: 'approved',
          ),
        )
        ..reduce(
          AgentTurnStartedEvent(
            turn,
            startedAt: DateTime.utc(2026),
          ),
        )
        ..reduce(
          AgentMessageDeltaEvent(
            messageId: 'message',
            delta: 'a',
            role: AgentMessageRole.agent,
            sessionId: 'thread',
            turnId: 'turn',
          ),
        )
        ..reduce(
          AgentMessageDeltaEvent(
            messageId: 'message',
            delta: 'c',
            role: AgentMessageRole.agent,
            sessionId: 'thread',
            turnId: 'turn',
          ),
        )
        ..reduce(
          AgentMessageDeltaEvent(
            messageId: 'message',
            delta: 'b',
            role: AgentMessageRole.agent,
            sourceMessageId: 'source',
            sessionId: 'thread',
            turnId: 'turn',
          ),
        )
        ..reduce(
          AgentMessageUpdatedEvent(
            messageId: 'message',
            text: 'final',
            status: AgentMessageStatus.completed,
            sessionId: 'thread',
            turnId: 'turn',
          ),
        )
        ..reduce(
          AgentReasoningDeltaEvent(
            itemId: 'reasoning',
            kind: AgentReasoningDeltaKind.text,
            delta: 'x',
            sessionId: 'thread',
            turnId: 'turn',
          ),
        )
        ..reduce(
          AgentReasoningDeltaEvent(
            itemId: 'reasoning',
            kind: AgentReasoningDeltaKind.summaryText,
            delta: 'z',
            sessionId: 'thread',
            turnId: 'turn',
          ),
        )
        ..reduce(
          AgentReasoningDeltaEvent(
            itemId: 'reasoning',
            kind: AgentReasoningDeltaKind.summaryText,
            delta: 'y',
            sourceItemId: 'source-reasoning',
            sessionId: 'thread',
            turnId: 'turn',
          ),
        )
        ..reduce(
          AgentPlanUpdatedEvent(
            entries: const <AgentPlanEntry>[AgentPlanEntry(content: 'step')],
            sessionId: 'thread',
            turnId: 'turn',
          ),
        )
        ..reduce(
          AgentSessionConfigUpdatedEvent(
            sessionId: 'thread',
            options: const <AgentSessionConfigOption>[],
          ),
        )
        ..reduce(
          AgentConversationModeUpdatedEvent(
            sessionId: 'thread',
            modeId: AgentConversationModeId.defaultMode,
          ),
        );

      final permission = AgentPermissionRequest(
        id: 'permission',
        title: 'Permission',
        kind: AgentPermissionKind.other,
        sessionId: 'thread',
        turnId: 'turn',
      );
      final question = AgentQuestionRequest(
        id: 'question',
        title: 'Question',
        questions: const <AgentUserInputQaPair>[],
        sessionId: 'thread',
        turnId: 'turn',
      );
      final plan = AgentPlanApprovalRequest(
        id: 'plan',
        title: 'Plan',
        markdown: 'plan',
        sessionId: 'thread',
        turnId: 'turn',
      );
      reducer
        ..reduce(AgentPermissionRequestedEvent(permission))
        ..reduce(AgentQuestionRequestedEvent(question))
        ..reduce(AgentPlanApprovalRequestedEvent(plan))
        ..reduce(
          AgentTurnFileChangesEvent(
            sessionId: 'thread',
            turnId: 'turn',
            snapshot: AgentFileChangeSnapshot(
              revision: 1,
              replayability: AgentFileChangeReplayability.liveOnly,
              changes: const <AgentFileChange>[],
            ),
          ),
        )
        ..reduce(
          AgentToolCallEvent(
            AgentToolCall(
              id: 'tool',
              title: 'Tool',
              sessionId: 'thread',
              turnId: 'turn',
            ),
          ),
        )
        ..reduce(
          AgentSystemItemEvent(
            entry: AgentHistoryEventEntry(
              id: 'system',
              kind: AgentHistoryEventKind.system,
              title: 'System',
            ),
            sessionId: 'thread',
            turnId: 'turn',
          ),
        )
        ..reduce(
          AgentTokenUsageEvent(
            tokenUsage: const AgentTokenUsage(totalTokens: 10),
            sessionId: 'thread',
            turnId: 'turn',
          ),
        )
        ..reduce(
          AgentContextWindowUsageEvent(
            usedTokens: 5,
            modelContextWindow: 20,
            sessionId: 'thread',
            turnId: 'turn',
          ),
        )
        ..reduce(
          AgentModelReroutedEvent(
            threadId: 'thread',
            turnId: 'turn',
            fromModel: 'a',
            toModel: 'b',
            reason: 'reason',
          ),
        )
        ..reduce(AgentDeprecationNoticeEvent(summary: 'deprecated'))
        ..reduce(
          AgentErrorEvent(
            message: 'failed',
            sessionId: 'thread',
            turnId: 'turn',
          ),
        )
        ..reduce(
          AgentModelListEvent(AgentModelList(models: <AgentModelInfo>[])),
        );

      expect(reducer.scope, ConversationReductionScope.live);
      expect(reducer.hasTurn('history-turn'), isTrue);
      expect(reducer.session, session);
      expect(reducer.threadName, 'Name');
      expect(reducer.threadPreview, 'Preview');
      expect(reducer.isArchived, isFalse);
      expect(reducer.waitingOnApproval, isTrue);
      expect(reducer.waitingOnUserInput, isTrue);
      expect(reducer.conversationMode, AgentConversationModeId.defaultMode);
      expect(reducer.autoReviewsByTurnId, contains('turn'));
      expect(reducer.pendingPermissions, contains('permission'));
      expect(reducer.pendingQuestions, contains('question'));
      expect(reducer.pendingPlanApprovals, contains('plan'));
      expect(reducer.modelList, isNotNull);
      expect(
        reducer.failure?.code,
        AgentConversationFailureCode.providerOperationFailed,
      );
      final live = reducer.turns.last;
      expect(live.entries, hasLength(greaterThan(8)));
      expect(live.tokenUsage?.totalTokens, 10);
      expect(live.contextWindowUsedTokens, 5);
      expect(live.modelContextWindow, 20);

      reducer
        ..reduce(
          AgentPermissionResolvedEvent(
            requestId: 'permission',
            threadId: 'thread',
          ),
        )
        ..reduce(
          AgentQuestionResolvedEvent(
            requestId: 'question',
            threadId: 'thread',
          ),
        )
        ..reduce(
          const AgentPlanApprovalResolvedEvent(
            requestId: 'plan',
            sessionId: 'thread',
          ),
        )
        ..reduce(AgentThreadCompactedEvent(threadId: 'thread', turnId: 'turn'))
        ..reduce(AgentThreadClosedEvent(threadId: 'thread'))
        ..reduce(AgentThreadDeletedEvent(threadId: 'thread'));
      expect(reducer.pendingPermissions, isEmpty);
      expect(reducer.pendingQuestions, isEmpty);
      expect(reducer.pendingPlanApprovals, isEmpty);
      expect(reducer.activeTurn, isNull);
    },
  );

  test(
    'local turn, token modes, terminal event and missing resolves are safe',
    () {
      final reducer = ConversationReducer(ConversationReductionScope.replay);
      final first = AgentTurn(id: 'first', sessionId: 'thread');
      final second = AgentTurn(id: 'second', sessionId: 'thread');
      reducer
        ..beginLocalTurn(first, message: 'hello', messageId: 'user')
        ..reduce(
          AgentTokenUsageEvent(
            tokenUsage: const AgentTokenUsage(totalTokens: 10),
            turnId: 'first',
          ),
        )
        ..beginLocalTurn(second, message: 'auto id')
        ..reduce(
          AgentTokenUsageEvent(
            tokenUsage: const AgentTokenUsage(totalTokens: 15),
            turnId: 'second',
          ),
        )
        ..reduce(
          AgentTokenUsageEvent(
            tokenUsage: const AgentTokenUsage(totalTokens: 3),
            turnId: 'second',
            isSessionCumulative: false,
          ),
        )
        ..reduce(
          AgentTurnCompletedEvent(
            sessionId: 'thread',
            turnId: 'second',
            status: AgentHistoryTurnStatus.interrupted,
            completedAt: DateTime.utc(2026),
          ),
        );

      expect(
        reducer.turns.first.entries.single,
        isA<ConversationMessageEntry>(),
      );
      expect(reducer.turns.last.tokenUsage?.totalTokens, 3);
      expect(reducer.turns.last.status, AgentHistoryTurnStatus.interrupted);
      expect(reducer.resolvePermission('missing'), isFalse);
      expect(reducer.resolveQuestion('missing'), isFalse);
      expect(reducer.resolvePlanApproval('missing'), isFalse);
    },
  );
}

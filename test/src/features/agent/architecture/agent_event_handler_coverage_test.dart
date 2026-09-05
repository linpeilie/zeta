import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/app/plugins/agent_provider_manifest.dart';

const _threadId = 'thread-1';
const _turnId = 'turn-1';

final List<AgentEvent> allEventSamples = <AgentEvent>[
  const AgentStatusEvent(AgentProviderStatus.idle()),
  const AgentSessionStartedEvent(
    AgentSession(id: _threadId, providerId: defaultAgentProviderId),
  ),
  const AgentThreadStatusChangedEvent(
    threadId: _threadId,
    status: AgentThreadRuntimeStatus.active,
  ),
  const AgentThreadNameUpdatedEvent(threadId: _threadId, threadName: 'Renamed'),
  const AgentThreadPreviewUpdatedEvent(threadId: _threadId, preview: 'preview'),
  const AgentThreadArchivedEvent(threadId: _threadId),
  const AgentThreadUnarchivedEvent(threadId: _threadId),
  const AgentThreadDeletedEvent(threadId: _threadId),
  const AgentThreadClosedEvent(threadId: _threadId),
  const AgentThreadCompactedEvent(threadId: _threadId, turnId: _turnId),
  const AgentThreadSettingsUpdatedEvent(threadId: _threadId),
  const AgentAutoApprovalReviewEvent(
    threadId: _threadId,
    turnId: _turnId,
    reviewId: 'review-1',
    status: 'denied',
  ),
  const AgentTurnStartedEvent(AgentTurn(id: _turnId, sessionId: _threadId)),
  const AgentTurnCompletedEvent(sessionId: _threadId, turnId: _turnId),
  const AgentTokenUsageEvent(
    tokenUsage: AgentTokenUsage(totalTokens: 1),
    sessionId: _threadId,
    turnId: _turnId,
  ),
  const AgentContextWindowUsageEvent(
    usedTokens: 1,
    sessionId: _threadId,
    turnId: _turnId,
  ),
  const AgentMessageDeltaEvent(
    messageId: 'm1',
    delta: 'x',
    role: AgentMessageRole.agent,
    sessionId: _threadId,
    turnId: _turnId,
  ),
  const AgentReasoningDeltaEvent(
    itemId: 'r1',
    kind: AgentReasoningDeltaKind.summaryText,
    delta: 'x',
    sessionId: _threadId,
    turnId: _turnId,
  ),
  const AgentMessageUpdatedEvent(
    messageId: 'm1',
    text: 'done',
    sessionId: _threadId,
    turnId: _turnId,
  ),
  const AgentPlanUpdatedEvent(
    entries: <AgentPlanEntry>[AgentPlanEntry(content: 'Step')],
    sessionId: _threadId,
    turnId: _turnId,
  ),
  const AgentSessionConfigUpdatedEvent(
    sessionId: _threadId,
    options: <AgentSessionConfigOption>[],
  ),
  const AgentConversationModeUpdatedEvent(
    sessionId: _threadId,
    modeId: AgentConversationModeId.plan,
  ),
  AgentPlanApprovalRequestedEvent(
    AgentPlanApprovalRequest(
      id: 'pa1',
      title: 'Plan',
      markdown: 'Do it',
      sessionId: _threadId,
      turnId: _turnId,
    ),
  ),
  const AgentPlanApprovalResolvedEvent(requestId: 'pa1', sessionId: _threadId),
  AgentTurnFileChangesEvent(
    sessionId: _threadId,
    turnId: _turnId,
    snapshot: AgentFileChangeSnapshot(
      revision: 1,
      replayability: AgentFileChangeReplayability.liveOnly,
      changes: <AgentFileChange>[],
    ),
  ),
  const AgentToolCallEvent(
    AgentToolCall(id: 't1', title: 'Run', status: AgentToolStatus.completed),
  ),
  AgentPermissionRequestedEvent(
    AgentPermissionRequest(
      id: 'p1',
      title: 'Run',
      kind: AgentPermissionKind.commandExecution,
      sessionId: _threadId,
      turnId: _turnId,
    ),
  ),
  const AgentPermissionResolvedEvent(requestId: 'p1', threadId: _threadId),
  AgentQuestionRequestedEvent(
    AgentQuestionRequest(
      id: 'q1',
      title: 'Q',
      questions: <AgentUserInputQaPair>[
        AgentUserInputQaPair(questionId: 'q', question: '?'),
      ],
      sessionId: _threadId,
      turnId: _turnId,
    ),
  ),
  const AgentQuestionResolvedEvent(requestId: 'q1', threadId: _threadId),
  const AgentModelReroutedEvent(
    threadId: _threadId,
    turnId: _turnId,
    fromModel: 'a',
    toModel: 'b',
    reason: 'policy',
  ),
  const AgentDeprecationNoticeEvent(summary: 'Deprecated'),
  AgentSystemItemEvent(
    entry: const AgentHistoryEventEntry(
      id: 'sys',
      kind: AgentHistoryEventKind.system,
      title: 'note',
    ),
    sessionId: _threadId,
    turnId: _turnId,
  ),
  const AgentErrorEvent(message: 'boom', sessionId: _threadId, turnId: _turnId),
  const AgentModelListEvent(AgentModelList(models: <AgentModelInfo>[])),
];

String _exhaustivenessGuard(AgentEvent event) => switch (event) {
  AgentStatusEvent() => 'status',
  AgentSessionStartedEvent() => 'sessionStarted',
  AgentThreadStatusChangedEvent() => 'threadStatus',
  AgentThreadNameUpdatedEvent() => 'threadName',
  AgentThreadPreviewUpdatedEvent() => 'threadPreview',
  AgentThreadArchivedEvent() => 'threadArchived',
  AgentThreadUnarchivedEvent() => 'threadUnarchived',
  AgentThreadDeletedEvent() => 'threadDeleted',
  AgentThreadClosedEvent() => 'threadClosed',
  AgentThreadCompactedEvent() => 'threadCompacted',
  AgentThreadSettingsUpdatedEvent() => 'threadSettings',
  AgentAutoApprovalReviewEvent() => 'autoApprovalReview',
  AgentTurnStartedEvent() => 'turnStarted',
  AgentTurnCompletedEvent() => 'turnCompleted',
  AgentTokenUsageEvent() => 'tokenUsage',
  AgentContextWindowUsageEvent() => 'contextUsage',
  AgentMessageDeltaEvent() => 'messageDelta',
  AgentReasoningDeltaEvent() => 'reasoningDelta',
  AgentMessageUpdatedEvent() => 'messageUpdated',
  AgentPlanUpdatedEvent() => 'planUpdated',
  AgentSessionConfigUpdatedEvent() => 'sessionConfig',
  AgentConversationModeUpdatedEvent() => 'conversationMode',
  AgentPlanApprovalRequestedEvent() => 'planApprovalRequested',
  AgentPlanApprovalResolvedEvent() => 'planApprovalResolved',
  AgentTurnFileChangesEvent() => 'turnFileChanges',
  AgentToolCallEvent() => 'toolCall',
  AgentPermissionRequestedEvent() => 'permissionRequested',
  AgentPermissionResolvedEvent() => 'permissionResolved',
  AgentQuestionRequestedEvent() => 'questionRequested',
  AgentQuestionResolvedEvent() => 'questionResolved',
  AgentModelReroutedEvent() => 'modelRerouted',
  AgentDeprecationNoticeEvent() => 'deprecation',
  AgentSystemItemEvent() => 'systemItem',
  AgentErrorEvent() => 'error',
  AgentModelListEvent() => 'modelList',
};

void main() {
  test('每个 AgentEvent 变体都有注册 handler', () {
    final registry = defaultAgentEventHandlerRegistry;
    expect(allEventSamples.length, 35, reason: '样本数必须与事件变体数一致');
    for (final sample in allEventSamples) {
      _exhaustivenessGuard(sample);
      expect(
        registry.hasHandlerFor(sample),
        isTrue,
        reason: '${sample.runtimeType} 未注册 handler',
      );
    }
  });

  test('AgentEvent 子类必须是叶子类（runtimeType 分发的前提）', () {
    final source = File(
      'packages/zeta_agent_core/lib/src/domain/agent_event_models.dart',
    ).readAsStringSync();
    for (final match in RegExp(
      r'class (\w+) extends (\w+)',
    ).allMatches(source)) {
      expect(
        match.group(2),
        'AgentEvent',
        reason:
            '${match.group(1)} 继承了 ${match.group(2)}；'
            'runtimeType 分发要求所有事件类直接继承 AgentEvent',
      );
    }
  });

  test('未注册类型必须抛 UnsupportedError（G4）', () {
    final empty = AgentEventHandlerRegistry.builder().build();
    expect(
      () => empty.dispatch(
        allEventSamples.first,
        const AgentConversationSessionState.initial(
          defaultTitle: agentDefaultThreadTitle,
        ),
        AgentConversationReducerContext(
          scope: AgentConversationReductionScope.live,
          selectedThreadId: _threadId,
          requiresResumedSelectedThread: false,
          pendingTurnGroupId: null,
          hasTurn: (_) => false,
          isHistoryTurnId: (_) => false,
          hasRunningTurnExcluding: (_) => false,
          modelsRefreshing: false,
          activeProviderName: 'Codex',
          activeProviderConfig: defaultCodexAgentProviderConfig,
          effectScope: const AgentConversationEffectScope(
            reductionScope: AgentConversationReductionScope.live,
            providerId: defaultAgentProviderId,
            listenerGeneration: 1,
            threadId: _threadId,
          ),
        ),
        AgentReducerScratch(
          timelineIds: AgentConversationLocalTimelineIdGenerator(),
          textCatalog: const FallbackAgentUiTextCatalog(),
        ),
      ),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('审批语义 handler 不允许被 Provider 覆盖（G5）', () {
    final builder = defaultAgentHandlerRegistryBuilder();
    expect(
      () => builder.register<AgentPermissionRequestedEvent>(
        const PermissionRequestedHandler(),
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      () => builder.register<AgentQuestionResolvedEvent>(
        const QuestionResolvedHandler(),
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      () => builder.register<AgentPlanApprovalRequestedEvent>(
        const PlanApprovalRequestedHandler(),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('非审批 handler 允许覆盖', () {
    final builder = defaultAgentHandlerRegistryBuilder();
    builder.register<AgentMessageDeltaEvent>(const MessageDeltaHandler());
    expect(
      builder.build().hasHandlerFor(
        const AgentMessageDeltaEvent(
          messageId: 'm',
          delta: 'x',
          role: AgentMessageRole.agent,
        ),
      ),
      isTrue,
    );
  });
}

import 'package:zeta_agent_core/src/application/agent_conversation_effect.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_mutation.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_reducer_context.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_session_state.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/_support/reduction_result.dart';
import 'package:zeta_agent_core/src/domain/agent_models.dart';

/// 仅在当前标题仍是占位符时采纳 session 标题。
AgentConversationSessionState adoptSessionTitle(
  AgentConversationSessionState state,
  AgentSession session,
) {
  final title = session.title?.trim();
  if (isAgentThreadTitlePlaceholder(title)) {
    return state;
  }
  if (!isAgentThreadTitlePlaceholder(state.currentThreadTitle)) {
    return state;
  }
  return withThreadTitle(state, title!);
}

AgentConversationSessionState withThreadTitle(
  AgentConversationSessionState state,
  String title,
) {
  final session = state.session;
  return state.copyWith(
    currentThreadTitle: title,
    session: session == null
        ? null
        : AgentSession(
            id: session.id,
            providerId: session.providerId,
            title: title,
          ),
  );
}

AgentConversationSessionState withThreadRuntimeStatus(
  AgentConversationSessionState state, {
  required AgentThreadRuntimeStatus status,
  required bool waitingOnApproval,
  required bool waitingOnUserInput,
}) {
  final isActive = status == AgentThreadRuntimeStatus.active;
  return state.copyWith(
    threadRuntimeStatus: status,
    threadWaitingOnApproval: isActive && waitingOnApproval,
    threadWaitingOnUserInput: isActive && waitingOnUserInput,
  );
}

AgentConversationSessionState withAutoReview(
  AgentConversationSessionState state,
  AgentAutoApprovalReviewEvent event,
) {
  final reviews = Map<String, AgentAutoApprovalReviewEvent>.of(
    state.autoReviewsByTurnId,
  );
  reviews[event.turnId] = event;
  var latest = state.latestDeniedAutoReview;
  if (event.status == 'denied') {
    latest = event;
  } else if (event.status == 'approved' && latest?.reviewId == event.reviewId) {
    latest = null;
  }
  return state.copyWith(
    autoReviewsByTurnId: reviews,
    latestDeniedAutoReview: latest,
  );
}

AgentConversationSessionState finalizeTurnCompleted(
  AgentConversationSessionState state,
  AgentTurnCompletedEvent event,
  AgentConversationReducerContext context, {
  required AgentUiTextCatalog textCatalog,
}) {
  final willBeRunning = context.hasRunningTurnExcluding(event.turnId);
  var next = state.copyWith(modelRerouteNotice: null);
  if (!willBeRunning &&
      state.status.state == AgentProviderConnectionState.running) {
    next = next.copyWith(
      status: AgentProviderStatus(
        state: AgentProviderConnectionState.ready,
        message: textCatalog.providerReady(context.activeProviderName),
      ),
    );
  }
  if (!willBeRunning &&
      state.threadRuntimeStatus == AgentThreadRuntimeStatus.active) {
    next = next.copyWith(
      threadRuntimeStatus: AgentThreadRuntimeStatus.idle,
      threadWaitingOnApproval: false,
      threadWaitingOnUserInput: false,
    );
  }
  return next;
}

/// Provider 断开 / thread closed 共用的中断收尾。
AgentConversationReduction settleInterruptedTurnReduction({
  required String fallbackTurnId,
  required AgentConversationSessionState state,
  required AgentConversationReducerContext context,
}) {
  return acceptedReduction(
    state.copyWith(
      threadRuntimeStatus: null,
      threadWaitingOnApproval: false,
      threadWaitingOnUserInput: false,
    ),
    timelineMutations: <AgentTimelineMutation>[
      AgentSettleInterruptedTimelineMutation(fallbackTurnId),
    ],
    effects: <AgentConversationEffect>[
      AgentClearPlanHandoffEffect(scope: context.effectScope),
      AgentSyncTurnRunningEffect(scope: context.effectScope),
    ],
    threadSnapshot: AgentThreadSnapshotMutation.refresh,
  );
}

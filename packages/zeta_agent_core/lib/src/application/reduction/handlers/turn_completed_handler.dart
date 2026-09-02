import 'package:zeta_agent_core/src/application/agent_conversation_effect.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_mutation.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_reducer_context.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_session_state.dart';
import 'package:zeta_agent_core/src/application/agent_ui_update_request.dart';
import 'package:zeta_agent_core/src/application/reduction/agent_event_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/_support/current_thread_guard.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/_support/reduction_result.dart';
import 'package:zeta_agent_core/src/domain/agent_models.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/_support/session_state_support.dart';

final class TurnCompletedHandler
    implements AgentEventHandler<AgentTurnCompletedEvent> {
  const TurnCompletedHandler();

  @override
  AgentConversationReduction handle(
    AgentTurnCompletedEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
    AgentReducerScratch scratch,
  ) {
    if (!shouldHandleCurrent(
      context,
      sessionId: event.sessionId,
      turnId: event.turnId,
    )) {
      return rejectedReduction(state, 'currentThreadMismatch');
    }
    final timelineMutations = <AgentTimelineMutation>[];
    final errorMessage = event.errorMessage;
    if (event.status == AgentHistoryTurnStatus.failed &&
        errorMessage != null &&
        errorMessage != scratch.lastShownErrorMessage) {
      scratch.lastShownErrorMessage = errorMessage;
      timelineMutations.add(
        AgentAddConversationMessageTimelineMutation(
          AgentConversationMessageMutationData(
            id: scratch.nextLocalTimelineId('turn-failed'),
            role: AgentMessageRole.system,
            text: AgentProviderErrorPresentation.formatUserVisibleText(
              message: errorMessage,
              catalog: scratch.textCatalog,
              code: event.errorCode,
              prefixTurnFailed: true,
            ),
          ),
        ),
      );
    }
    timelineMutations.add(AgentCompleteLiveTurnTimelineMutation(event));
    final turnScope = context.effectScope.forTurn(event.turnId);
    return acceptedReduction(
      finalizeTurnCompleted(
        state,
        event,
        context,
        textCatalog: scratch.textCatalog,
      ),
      timelineMutations: timelineMutations,
      effects: <AgentConversationEffect>[
        AgentPreparePlanHandoffEffect(scope: turnScope, event: event),
        AgentTurnCompletedEffect(
          scope: turnScope,
          turnId: event.turnId,
          attention: AgentAttentionSignal(
            kind: switch (event.status) {
              AgentHistoryTurnStatus.completed =>
                AgentAttentionKind.turnCompleted,
              AgentHistoryTurnStatus.failed => AgentAttentionKind.turnFailed,
              AgentHistoryTurnStatus.interrupted =>
                AgentAttentionKind.turnInterrupted,
              AgentHistoryTurnStatus.running =>
                AgentAttentionKind.turnInterrupted,
              AgentHistoryTurnStatus.unknown =>
                AgentAttentionKind.turnInterrupted,
            },
            phase: AgentAttentionPhase.raised,
            sourceId: event.turnId,
            threadId: event.sessionId,
            turnId: event.turnId,
          ),
        ),
        AgentSyncTurnRunningEffect(scope: turnScope),
        AgentAutoStartPlanExecutionEffect(scope: turnScope),
      ],
      uiEffects: const <AgentUiEffect>[AgentRequestAutoScroll()],
      threadSnapshot: AgentThreadSnapshotMutation.refresh,
    );
  }
}

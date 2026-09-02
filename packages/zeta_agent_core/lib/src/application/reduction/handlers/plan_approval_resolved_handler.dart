import 'package:zeta_agent_core/src/application/agent_conversation_effect.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_mutation.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_reducer_context.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_session_state.dart';
import 'package:zeta_agent_core/src/application/reduction/agent_event_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/_support/current_thread_guard.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/_support/reduction_result.dart';
import 'package:zeta_agent_core/src/domain/agent_models.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/_support/pending_interaction_support.dart';

final class PlanApprovalResolvedHandler
    implements AgentEventHandler<AgentPlanApprovalResolvedEvent> {
  const PlanApprovalResolvedHandler();

  @override
  AgentConversationReduction handle(
    AgentPlanApprovalResolvedEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
    AgentReducerScratch scratch,
  ) {
    if (!shouldHandleCurrent(context, sessionId: event.sessionId)) {
      return rejectedReduction(state, 'currentThreadMismatch');
    }
    return pendingInteractionReduction(
      state,
      AgentRemovePlanApprovalRequestTimelineMutation(event.requestId),
      effect: AgentAttentionEffect(
        scope: context.effectScope,
        signal: AgentAttentionSignal(
          kind: AgentAttentionKind.planApprovalRequired,
          phase: AgentAttentionPhase.resolved,
          sourceId: event.requestId,
          threadId: event.sessionId,
        ),
      ),
    );
  }
}

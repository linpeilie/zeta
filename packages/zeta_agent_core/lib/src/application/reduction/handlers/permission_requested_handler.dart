import 'package:zeta_agent_core/src/application/agent_conversation_effect.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_mutation.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_reducer_context.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_session_state.dart';
import 'package:zeta_agent_core/src/application/reduction/agent_event_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/_support/current_thread_guard.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/_support/reduction_result.dart';
import 'package:zeta_agent_core/src/domain/agent_models.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/_support/pending_interaction_support.dart';

final class PermissionRequestedHandler
    implements AgentEventHandler<AgentPermissionRequestedEvent> {
  const PermissionRequestedHandler();

  @override
  AgentConversationReduction handle(
    AgentPermissionRequestedEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
    AgentReducerScratch scratch,
  ) {
    if (!shouldHandleCurrent(
      context,
      sessionId: event.request.sessionId,
      turnId: event.request.turnId,
    )) {
      return rejectedReduction(state, 'currentThreadMismatch');
    }
    return pendingInteractionReduction(
      state,
      AgentAddPermissionRequestTimelineMutation(event.request),
      effect: AgentAttentionEffect(
        scope: context.effectScope.forTurn(event.request.turnId),
        signal: AgentAttentionSignal(
          kind: AgentAttentionKind.permissionRequired,
          phase: AgentAttentionPhase.raised,
          sourceId: event.request.id,
          threadId: event.request.sessionId,
          turnId: event.request.turnId,
        ),
      ),
    );
  }
}

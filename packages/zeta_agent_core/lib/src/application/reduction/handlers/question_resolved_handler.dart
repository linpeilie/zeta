import 'package:zeta_agent_core/src/application/agent_conversation_effect.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_mutation.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_reducer_context.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_session_state.dart';
import 'package:zeta_agent_core/src/application/reduction/agent_event_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/_support/current_thread_guard.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/_support/reduction_result.dart';
import 'package:zeta_agent_core/src/domain/agent_models.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/_support/pending_interaction_support.dart';

final class QuestionResolvedHandler
    implements AgentEventHandler<AgentQuestionResolvedEvent> {
  const QuestionResolvedHandler();

  @override
  AgentConversationReduction handle(
    AgentQuestionResolvedEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
    AgentReducerScratch scratch,
  ) {
    if (!shouldHandleCurrent(context, sessionId: event.threadId)) {
      return rejectedReduction(state, 'currentThreadMismatch');
    }
    return pendingInteractionReduction(
      state,
      AgentRemoveQuestionRequestTimelineMutation(event.requestId),
      effect: AgentAttentionEffect(
        scope: context.effectScope,
        signal: AgentAttentionSignal(
          kind: AgentAttentionKind.questionRequired,
          phase: AgentAttentionPhase.resolved,
          sourceId: event.requestId,
          threadId: event.threadId,
        ),
      ),
    );
  }
}

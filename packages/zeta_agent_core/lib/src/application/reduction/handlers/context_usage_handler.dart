import 'package:zeta_agent_core/src/application/agent_conversation_mutation.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_reducer_context.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_session_state.dart';
import 'package:zeta_agent_core/src/application/agent_ui_update_request.dart';
import 'package:zeta_agent_core/src/application/reduction/agent_event_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/_support/current_thread_guard.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/_support/reduction_result.dart';
import 'package:zeta_agent_core/src/domain/agent_models.dart';

final class ContextUsageHandler
    implements AgentEventHandler<AgentContextWindowUsageEvent> {
  const ContextUsageHandler();

  @override
  AgentConversationReduction handle(
    AgentContextWindowUsageEvent event,
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
    return acceptedReduction(
      state,
      timelineMutations: <AgentTimelineMutation>[
        AgentUpdateContextWindowUsageTimelineMutation(event),
      ],
      urgency: AgentUiUpdateUrgency.nextFrame,
    );
  }
}

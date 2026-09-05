import 'package:zeta_agent_core/src/application/agent_conversation_mutation.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_reducer_context.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_session_state.dart';
import 'package:zeta_agent_core/src/application/reduction/agent_event_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/_support/current_thread_guard.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/_support/reduction_result.dart';
import 'package:zeta_agent_core/src/domain/agent_models.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/_support/session_state_support.dart';

final class ThreadClosedHandler
    implements AgentEventHandler<AgentThreadClosedEvent> {
  const ThreadClosedHandler();

  @override
  AgentConversationReduction handle(
    AgentThreadClosedEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
    AgentReducerScratch scratch,
  ) {
    if (!shouldHandleCurrent(context, sessionId: event.threadId)) {
      return rejectedReduction(state, 'currentThreadMismatch');
    }
    return settleInterruptedTurnReduction(
      fallbackTurnId: 'closed',
      state: state,
      context: context,
    );
  }
}

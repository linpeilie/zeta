import 'package:zeta_agent_core/src/application/agent_conversation_mutation.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_reducer_context.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_session_state.dart';
import 'package:zeta_agent_core/src/application/reduction/agent_event_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/_support/reduction_result.dart';
import 'package:zeta_agent_core/src/domain/agent_models.dart';

/// 显式不发布 UI 的空 handler（archived / unarchived / deleted）。
final class NoOpHandler<E extends AgentEvent> implements AgentEventHandler<E> {
  const NoOpHandler();

  @override
  AgentConversationReduction handle(
    E event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
    AgentReducerScratch scratch,
  ) {
    return acceptedReduction(state, urgency: null);
  }
}

import 'package:zeta_agent_core/src/application/agent_conversation_effect.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_mutation.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_reducer_context.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_session_state.dart';
import 'package:zeta_agent_core/src/application/reduction/agent_event_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/_support/current_thread_guard.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/_support/reduction_result.dart';
import 'package:zeta_agent_core/src/domain/agent_models.dart';

final class TurnStartedHandler
    implements AgentEventHandler<AgentTurnStartedEvent> {
  const TurnStartedHandler();

  @override
  AgentConversationReduction handle(
    AgentTurnStartedEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
    AgentReducerScratch scratch,
  ) {
    if (!shouldHandleCurrent(
      context,
      sessionId: event.turn.sessionId,
      turnId: event.turn.id,
    )) {
      return rejectedReduction(state, 'currentThreadMismatch');
    }
    scratch.lastShownErrorMessage = null;
    return acceptedReduction(
      state,
      timelineMutations: <AgentTimelineMutation>[
        AgentBeginLiveTurnTimelineMutation(event.turn),
      ],
      effects: <AgentConversationEffect>[
        AgentSyncTurnRunningEffect(
          scope: context.effectScope.forTurn(event.turn.id),
          forceRunning: true,
        ),
      ],
      threadSnapshot: AgentThreadSnapshotMutation.refresh,
    );
  }
}

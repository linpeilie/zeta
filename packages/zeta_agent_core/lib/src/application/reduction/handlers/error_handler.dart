import 'package:zeta_agent_core/src/application/agent_conversation_effect.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_mutation.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_reducer_context.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_session_state.dart';
import 'package:zeta_agent_core/src/application/agent_ui_update_request.dart';
import 'package:zeta_agent_core/src/application/reduction/agent_event_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/_support/current_thread_guard.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/_support/reduction_result.dart';
import 'package:zeta_agent_core/src/domain/agent_models.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/_support/error_text_support.dart';

final class ErrorHandler implements AgentEventHandler<AgentErrorEvent> {
  const ErrorHandler();

  @override
  AgentConversationReduction handle(
    AgentErrorEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
    AgentReducerScratch scratch,
  ) {
    final logEffect = AgentLogProviderErrorEffect(
      scope: context.effectScope.forTurn(event.turnId),
      event: event,
    );
    if (!shouldHandleCurrent(
      context,
      sessionId: event.sessionId,
      turnId: event.turnId,
    )) {
      return rejectedReduction(
        state,
        'currentThreadMismatch',
        effects: <AgentConversationEffect>[logEffect],
      );
    }
    scratch.lastShownErrorMessage = event.message;
    return acceptedReduction(
      state,
      timelineMutations: <AgentTimelineMutation>[
        AgentAddConversationMessageTimelineMutation(
          AgentConversationMessageMutationData(
            id: scratch.nextLocalTimelineId('error'),
            role: AgentMessageRole.system,
            text: errorMessageText(scratch.textCatalog, event),
          ),
        ),
      ],
      uiEffects: const <AgentUiEffect>[AgentRequestAutoScroll()],
      effects: <AgentConversationEffect>[logEffect],
    );
  }
}

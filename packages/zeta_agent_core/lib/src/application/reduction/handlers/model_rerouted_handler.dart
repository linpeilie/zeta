import 'package:zeta_agent_core/src/application/agent_conversation_mutation.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_reducer_context.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_session_state.dart';
import 'package:zeta_agent_core/src/application/agent_ui_update_request.dart';
import 'package:zeta_agent_core/src/application/reduction/agent_event_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/_support/current_thread_guard.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/_support/reduction_result.dart';
import 'package:zeta_agent_core/src/domain/agent_models.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/_support/error_text_support.dart';

final class ModelReroutedHandler
    implements AgentEventHandler<AgentModelReroutedEvent> {
  const ModelReroutedHandler();

  @override
  AgentConversationReduction handle(
    AgentModelReroutedEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
    AgentReducerScratch scratch,
  ) {
    if (!shouldHandleCurrent(
      context,
      sessionId: event.threadId,
      turnId: event.turnId,
    )) {
      return rejectedReduction(state, 'currentThreadMismatch');
    }
    final catalog = scratch.textCatalog;
    return acceptedReduction(
      state.copyWith(
        modelRerouteNotice: catalog.modelReroutedNotice(event.toModel),
      ),
      timelineMutations: <AgentTimelineMutation>[
        AgentAddHistoryEventTimelineMutation(
          AgentHistoryEventEntry(
            id: scratch.nextLocalTimelineId('model-reroute'),
            kind: AgentHistoryEventKind.system,
            title: catalog.modelReroutedTitle,
            description: '${event.fromModel} → ${event.toModel}',
            content: modelRerouteReasonLabel(catalog, event.reason),
          ),
        ),
      ],
      uiEffects: const <AgentUiEffect>[AgentRequestAutoScroll()],
    );
  }
}

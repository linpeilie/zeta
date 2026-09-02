import 'package:zeta_agent_core/src/application/agent_conversation_mutation.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_reducer_context.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_session_state.dart';
import 'package:zeta_agent_core/src/application/agent_ui_update_request.dart';
import 'package:zeta_agent_core/src/application/reduction/agent_event_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/_support/reduction_result.dart';
import 'package:zeta_agent_core/src/domain/agent_models.dart';

final class DeprecationHandler
    implements AgentEventHandler<AgentDeprecationNoticeEvent> {
  const DeprecationHandler();

  @override
  AgentConversationReduction handle(
    AgentDeprecationNoticeEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
    AgentReducerScratch scratch,
  ) {
    if (!scratch.shownDeprecationSummaries.add(event.summary)) {
      return rejectedReduction(state, 'duplicateDeprecation');
    }
    final catalog = scratch.textCatalog;
    return acceptedReduction(
      state,
      timelineMutations: <AgentTimelineMutation>[
        AgentAddHistoryEventTimelineMutation(
          AgentHistoryEventEntry(
            id: scratch.nextLocalTimelineId('deprecation'),
            kind: AgentHistoryEventKind.warning,
            title: catalog.deprecationNoticeTitle,
            description: event.summary,
            content: event.details == null
                ? catalog.deprecationUpgradeHint
                : '${event.details}\n${catalog.deprecationUpgradeHint}',
          ),
        ),
      ],
      uiEffects: const <AgentUiEffect>[AgentRequestAutoScroll()],
    );
  }
}

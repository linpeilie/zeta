import 'package:zeta_agent_core/src/application/agent_conversation_effect.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_mutation.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_reducer_context.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_session_state.dart';
import 'package:zeta_agent_core/src/application/agent_ui_update_request.dart';
import 'package:zeta_agent_core/src/application/reduction/agent_event_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/_support/current_thread_guard.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/_support/reduction_result.dart';
import 'package:zeta_agent_core/src/domain/agent_models.dart';

final class ThreadSettingsHandler
    implements AgentEventHandler<AgentThreadSettingsUpdatedEvent> {
  const ThreadSettingsHandler();

  @override
  AgentConversationReduction handle(
    AgentThreadSettingsUpdatedEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
    AgentReducerScratch scratch,
  ) {
    final permissionSelection = event.permissionSelection;
    final isCurrent = shouldHandleCurrent(context, sessionId: event.threadId);
    if (!isCurrent && permissionSelection == null) {
      return rejectedReduction(state, 'currentThreadMismatch');
    }
    return acceptedReduction(
      state,
      effects: <AgentConversationEffect>[
        if (permissionSelection != null)
          AgentApplyThreadPermissionEffect(
            scope: context.effectScope,
            threadId: event.threadId,
            permissionSelection: permissionSelection,
          ),
        if (isCurrent)
          AgentApplyThreadSettingsEffect(
            scope: context.effectScope,
            event: event,
          ),
      ],
      urgency: isCurrent ? AgentUiUpdateUrgency.immediate : null,
    );
  }
}

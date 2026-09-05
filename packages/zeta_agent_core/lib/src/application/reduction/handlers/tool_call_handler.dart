import 'package:zeta_agent_core/src/application/agent_conversation_mutation.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_reducer_context.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_session_state.dart';
import 'package:zeta_agent_core/src/application/agent_ui_update_request.dart';
import 'package:zeta_agent_core/src/application/reduction/agent_event_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/_support/current_thread_guard.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/_support/reduction_result.dart';
import 'package:zeta_agent_core/src/domain/agent_models.dart';

final class ToolCallHandler implements AgentEventHandler<AgentToolCallEvent> {
  const ToolCallHandler();

  @override
  AgentConversationReduction handle(
    AgentToolCallEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
    AgentReducerScratch scratch,
  ) {
    final toolCall = event.toolCall;
    if (!shouldHandleCurrent(
      context,
      sessionId: toolCall.sessionId,
      turnId: toolCall.turnId,
    )) {
      return rejectedReduction(state, 'currentThreadMismatch');
    }
    final isActive =
        toolCall.status == AgentToolStatus.inProgress ||
        toolCall.status == AgentToolStatus.pending;
    var next = state;
    if (isActive) {
      final title = toolCall.displayTitle(scratch.textCatalog).trim();
      if (title.isNotEmpty) {
        next = next.copyWith(
          status: AgentProviderStatus(
            state: AgentProviderConnectionState.running,
            message: title.length > 80 ? '${title.substring(0, 80)}…' : title,
          ),
        );
      }
    }
    return acceptedReduction(
      next,
      timelineMutations: <AgentTimelineMutation>[
        AgentUpsertToolCallTimelineMutation(toolCall),
      ],
      urgency: isActive
          ? AgentUiUpdateUrgency.nextFrame
          : AgentUiUpdateUrgency.immediate,
      uiEffects: const <AgentUiEffect>[AgentRequestAutoScroll()],
    );
  }
}

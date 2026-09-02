import 'package:zeta_agent_core/src/application/agent_conversation_effect.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_mutation.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_reducer_context.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_session_state.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_timeline_store.dart';
import 'package:zeta_agent_core/src/application/reduction/agent_event_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/_support/reduction_result.dart';
import 'package:zeta_agent_core/src/domain/agent_models.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/_support/session_state_support.dart';

/// 采纳当前 thread 的 session 启动。
final class SessionStartedHandler
    implements AgentEventHandler<AgentSessionStartedEvent> {
  const SessionStartedHandler();

  @override
  AgentConversationReduction handle(
    AgentSessionStartedEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
    AgentReducerScratch scratch,
  ) {
    final selectedThreadId = context.selectedThreadId;
    final accepted = selectedThreadId != null
        ? selectedThreadId == event.session.id
        : !context.requiresResumedSelectedThread;
    if (!accepted) {
      return rejectedReduction(state, 'sessionStartedThreadMismatch');
    }
    var next = state.copyWith(
      session: event.session,
      restoredSessionId: event.session.id,
      threadOpenPhase: AgentThreadOpenPhase.idle,
      requiresResumedSelectedThread: false,
    );
    next = adoptSessionTitle(next, event.session);
    return acceptedReduction(
      next,
      effects: <AgentConversationEffect>[
        if (state.session?.id != event.session.id)
          AgentBindConversationModeThreadEffect(
            scope: context.effectScope,
            threadId: event.session.id,
          ),
      ],
      threadSnapshot: AgentThreadSnapshotMutation.refresh,
    );
  }
}

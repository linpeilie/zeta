import 'package:zeta/agent_chat/bloc/agent_conversation_state.dart';

/// Maps the history slice to the currently visible timeline window.
///
/// Presentation owns this projection so the Bloc State never stores Markdown
/// or render cache, only turn ids.
List<AgentConversationTurnGroup> projectTimelineItems(
  AgentConversationHistoryState history,
) {
  return history.visibleTurns;
}

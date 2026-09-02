import 'package:zeta_agent_core/src/application/agent_conversation_effect.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_mutation.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_session_state.dart';
import 'package:zeta_agent_core/src/application/agent_ui_update_request.dart';

/// 接受本次归约。
AgentConversationReduction acceptedReduction(
  AgentConversationSessionState state, {
  Iterable<AgentTimelineMutation> timelineMutations =
      const <AgentTimelineMutation>[],
  Iterable<AgentConversationEffect> effects = const <AgentConversationEffect>[],
  AgentUiUpdateUrgency? urgency = AgentUiUpdateUrgency.immediate,
  Iterable<AgentUiEffect> uiEffects = const <AgentUiEffect>[],
  AgentThreadSnapshotMutation? threadSnapshot,
}) {
  return AgentConversationReduction(
    accepted: true,
    state: state,
    timelineMutations: timelineMutations,
    effects: effects,
    urgency: urgency,
    uiEffects: uiEffects,
    threadSnapshot: threadSnapshot,
  );
}

/// 拒绝本次归约。
AgentConversationReduction rejectedReduction(
  AgentConversationSessionState state,
  String reason, {
  Iterable<AgentConversationEffect> effects = const <AgentConversationEffect>[],
}) {
  return AgentConversationReduction.rejected(reason, state, effects: effects);
}

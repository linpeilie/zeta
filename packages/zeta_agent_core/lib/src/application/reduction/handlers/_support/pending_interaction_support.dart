import 'package:zeta_agent_core/src/application/agent_conversation_effect.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_mutation.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_session_state.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/_support/reduction_result.dart';

/// permission / question / planApproval 共用的 pending 卡片归约。
AgentConversationReduction pendingInteractionReduction(
  AgentConversationSessionState state,
  AgentTimelineMutation timelineMutation, {
  AgentConversationEffect? effect,
}) {
  return acceptedReduction(
    state,
    timelineMutations: <AgentTimelineMutation>[timelineMutation],
    effects: <AgentConversationEffect>[?effect],
  );
}

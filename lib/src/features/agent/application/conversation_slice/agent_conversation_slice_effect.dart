import 'agent_conversation_command_payload.dart';

sealed class AgentConversationSliceEffect {
  const AgentConversationSliceEffect();
}

final class AgentConversationExecuteCommandEffect
    extends AgentConversationSliceEffect {
  const AgentConversationExecuteCommandEffect(this.command);
  final AgentConversationCommandEnvelope command;
}

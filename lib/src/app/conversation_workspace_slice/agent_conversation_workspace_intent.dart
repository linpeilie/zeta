import 'package:zeta/src/app/conversation_workspace_slice/agent_conversation_workspace_state.dart';

/// Conversation Workspace 的纯状态输入。
sealed class AgentConversationWorkspaceIntent {
  const AgentConversationWorkspaceIntent();
}

final class AgentConversationWorkspaceEntryRegistered
    extends AgentConversationWorkspaceIntent {
  const AgentConversationWorkspaceEntryRegistered(this.entry);

  final AgentConversationWorkspaceEntryState entry;
}

final class AgentConversationWorkspaceEntryUpdated
    extends AgentConversationWorkspaceIntent {
  const AgentConversationWorkspaceEntryUpdated(this.entry);

  final AgentConversationWorkspaceEntryState entry;
}

final class AgentConversationWorkspaceEntryRemoved
    extends AgentConversationWorkspaceIntent {
  const AgentConversationWorkspaceEntryRemoved({
    required this.entryId,
    required this.fallbackEntryId,
  });

  final String entryId;
  final String? fallbackEntryId;
}

final class AgentConversationWorkspaceEntrySelected
    extends AgentConversationWorkspaceIntent {
  const AgentConversationWorkspaceEntrySelected(this.entryId);

  final String entryId;
}

final class AgentConversationWorkspaceHomeEntered
    extends AgentConversationWorkspaceIntent {
  const AgentConversationWorkspaceHomeEntered();
}

final class AgentConversationWorkspaceThreadMappingSet
    extends AgentConversationWorkspaceIntent {
  const AgentConversationWorkspaceThreadMappingSet({
    required this.projectPath,
    required this.threadId,
  });

  final String projectPath;
  final String threadId;
}

final class AgentConversationWorkspaceThreadMappingRemoved
    extends AgentConversationWorkspaceIntent {
  const AgentConversationWorkspaceThreadMappingRemoved(this.projectPath);

  final String projectPath;
}

final class AgentConversationWorkspaceThreadMappingsRestored
    extends AgentConversationWorkspaceIntent {
  const AgentConversationWorkspaceThreadMappingsRestored(this.mappings);

  final Map<String, String> mappings;
}

import 'package:zeta/src/app/conversation_workspace_slice/agent_conversation_workspace_intent.dart';
import 'package:zeta/src/app/conversation_workspace_slice/agent_conversation_workspace_state.dart';

/// Conversation Workspace 的纯同步 reducer。
final class AgentConversationWorkspaceReducer {
  const AgentConversationWorkspaceReducer();

  AgentConversationWorkspaceState reduce(
    AgentConversationWorkspaceState state,
    AgentConversationWorkspaceIntent intent,
  ) {
    return switch (intent) {
      AgentConversationWorkspaceEntryRegistered(:final entry) =>
        AgentConversationWorkspaceState(
          entries: <AgentConversationWorkspaceEntryState>[
            ...state.entries,
            entry,
          ],
          selectedEntryId: state.selectedEntryId,
          projectHomeActive: state.projectHomeActive,
          threadIdsByProject: state.threadIdsByProject,
        ),
      AgentConversationWorkspaceEntryUpdated(:final entry) => _replaceEntry(
        state,
        entry,
      ),
      AgentConversationWorkspaceEntryRemoved(
        :final entryId,
        :final fallbackEntryId,
      ) =>
        AgentConversationWorkspaceState(
          entries: state.entries.where((entry) => entry.entryId != entryId),
          selectedEntryId: state.selectedEntryId == entryId
              ? fallbackEntryId
              : state.selectedEntryId,
          projectHomeActive: state.projectHomeActive,
          threadIdsByProject: state.threadIdsByProject,
        ),
      AgentConversationWorkspaceEntrySelected(:final entryId) =>
        AgentConversationWorkspaceState(
          entries: state.entries,
          selectedEntryId: entryId,
          threadIdsByProject: state.threadIdsByProject,
        ),
      AgentConversationWorkspaceHomeEntered() =>
        AgentConversationWorkspaceState(
          entries: state.entries,
          projectHomeActive: true,
          threadIdsByProject: state.threadIdsByProject,
        ),
      AgentConversationWorkspaceThreadMappingSet(
        :final projectPath,
        :final threadId,
      ) =>
        AgentConversationWorkspaceState(
          entries: state.entries,
          selectedEntryId: state.selectedEntryId,
          projectHomeActive: state.projectHomeActive,
          threadIdsByProject: <String, String>{
            ...state.threadIdsByProject,
            projectPath: threadId,
          },
        ),
      AgentConversationWorkspaceThreadMappingRemoved(:final projectPath) =>
        AgentConversationWorkspaceState(
          entries: state.entries,
          selectedEntryId: state.selectedEntryId,
          projectHomeActive: state.projectHomeActive,
          threadIdsByProject: <String, String>{
            for (final entry in state.threadIdsByProject.entries)
              if (entry.key != projectPath) entry.key: entry.value,
          },
        ),
      AgentConversationWorkspaceThreadMappingsRestored(:final mappings) =>
        AgentConversationWorkspaceState(
          entries: state.entries,
          selectedEntryId: state.selectedEntryId,
          projectHomeActive: state.projectHomeActive,
          threadIdsByProject: mappings,
        ),
    };
  }

  AgentConversationWorkspaceState _replaceEntry(
    AgentConversationWorkspaceState state,
    AgentConversationWorkspaceEntryState replacement,
  ) {
    return AgentConversationWorkspaceState(
      entries: <AgentConversationWorkspaceEntryState>[
        for (final entry in state.entries)
          if (entry.entryId == replacement.entryId) replacement else entry,
      ],
      selectedEntryId: state.selectedEntryId,
      projectHomeActive: state.projectHomeActive,
      threadIdsByProject: state.threadIdsByProject,
    );
  }
}

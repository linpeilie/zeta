import 'package:meta/meta.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

/// Conversation Workspace 中单个常驻运行时的不可变投影。
@immutable
final class AgentConversationWorkspaceEntryState {
  const AgentConversationWorkspaceEntryState({
    required this.entryId,
    required this.projectPath,
    required this.providerId,
    required this.threadId,
    required this.bindingKey,
    required this.threadSnapshot,
  });

  final String entryId;
  final String projectPath;
  final String providerId;
  final String? threadId;
  final AgentConversationBindingKey bindingKey;
  final AgentConversationThreadSnapshot threadSnapshot;

  bool get isDraft => threadId == null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentConversationWorkspaceEntryState &&
          other.entryId == entryId &&
          other.projectPath == projectPath &&
          other.providerId == providerId &&
          other.threadId == threadId &&
          other.bindingKey == bindingKey &&
          other.threadSnapshot == threadSnapshot;

  @override
  int get hashCode => Object.hash(
    entryId,
    projectPath,
    providerId,
    threadId,
    bindingKey,
    threadSnapshot,
  );
}

/// Conversation Workspace 的单一不可变状态。
@immutable
final class AgentConversationWorkspaceState {
  AgentConversationWorkspaceState({
    Iterable<AgentConversationWorkspaceEntryState> entries =
        const <AgentConversationWorkspaceEntryState>[],
    this.selectedEntryId,
    this.projectHomeActive = false,
    Map<String, String> threadIdsByProject = const <String, String>{},
  }) : entries = List<AgentConversationWorkspaceEntryState>.unmodifiable(
         entries,
       ),
       threadIdsByProject = Map<String, String>.unmodifiable(
         threadIdsByProject,
       );

  final List<AgentConversationWorkspaceEntryState> entries;
  final String? selectedEntryId;
  final bool projectHomeActive;
  final Map<String, String> threadIdsByProject;

  AgentConversationWorkspaceEntryState? get selectedEntry {
    final id = selectedEntryId;
    if (id == null) {
      return null;
    }
    for (final entry in entries) {
      if (entry.entryId == id) {
        return entry;
      }
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentConversationWorkspaceState &&
          other.selectedEntryId == selectedEntryId &&
          other.projectHomeActive == projectHomeActive &&
          zetaListEquals(other.entries, entries) &&
          zetaMapEquals(other.threadIdsByProject, threadIdsByProject);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(entries),
    selectedEntryId,
    projectHomeActive,
    Object.hashAllUnordered(threadIdsByProject.entries),
  );
}

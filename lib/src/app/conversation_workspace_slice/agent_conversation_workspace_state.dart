import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_owner_key.dart';
import 'package:meta/meta.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

/// Conversation Workspace 中单个常驻运行时的不可变投影。
@immutable
final class AgentConversationWorkspaceEntryState {
  const AgentConversationWorkspaceEntryState({
    required this.entryId,
    required this.ownerKey,
    required this.projectPath,
    required this.providerId,
    required this.threadId,
    required this.bindingKey,
    required this.threadSnapshot,
  });

  final String entryId;
  final AgentConversationOwnerKey ownerKey;
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
          other.ownerKey == ownerKey &&
          other.projectPath == projectPath &&
          other.providerId == providerId &&
          other.threadId == threadId &&
          other.bindingKey == bindingKey &&
          other.threadSnapshot == threadSnapshot;

  @override
  int get hashCode => Object.hash(
    entryId,
    ownerKey,
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
    Map<AgentConversationBindingKey, AgentConversationOwnerResolution> aliases =
        const {},
    this.selectedEntryId,
    this.projectHomeActive = false,
    Map<String, String> threadIdsByProject = const <String, String>{},
  }) : aliases = Map.unmodifiable(aliases),
       entries = List<AgentConversationWorkspaceEntryState>.unmodifiable(
         entries,
       ),
       threadIdsByProject = Map<String, String>.unmodifiable(
         threadIdsByProject,
       );

  final Map<AgentConversationBindingKey, AgentConversationOwnerResolution>
  aliases;
  AgentConversationWorkspaceState withAliases(
    Map<AgentConversationBindingKey, AgentConversationOwnerResolution> aliases,
  ) => AgentConversationWorkspaceState(
    entries: entries,
    aliases: aliases,
    selectedEntryId: selectedEntryId,
    projectHomeActive: projectHomeActive,
    threadIdsByProject: threadIdsByProject,
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
          zetaMapEquals(other.aliases, aliases) &&
          zetaListEquals(other.entries, entries) &&
          zetaMapEquals(other.threadIdsByProject, threadIdsByProject);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(
      aliases.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    Object.hashAll(entries),
    selectedEntryId,
    projectHomeActive,
    // MapEntry 不覆写 == / hashCode（恒等语义），且 Map.entries 每次迭代都新建
    // 实例：直接聚合 entries 会让同一对象两次读 hashCode 得到不同值。
    Object.hashAllUnordered(<int>[
      for (final entry in threadIdsByProject.entries)
        Object.hash(entry.key, entry.value),
    ]),
  );
}

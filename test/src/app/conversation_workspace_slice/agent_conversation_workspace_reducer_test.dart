import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/app/conversation_workspace_slice/agent_conversation_workspace_intent.dart';
import 'package:zeta/src/app/conversation_workspace_slice/agent_conversation_workspace_reducer.dart';
import 'package:zeta/src/app/conversation_workspace_slice/agent_conversation_workspace_state.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

void main() {
  const reducer = AgentConversationWorkspaceReducer();

  test('register select home and remove are one immutable state sequence', () {
    final registered = reducer.reduce(
      AgentConversationWorkspaceState(),
      AgentConversationWorkspaceEntryRegistered(_entry('entry-1')),
    );
    final selected = reducer.reduce(
      registered,
      const AgentConversationWorkspaceEntrySelected('entry-1'),
    );
    final home = reducer.reduce(
      selected,
      const AgentConversationWorkspaceHomeEntered(),
    );
    final removed = reducer.reduce(
      home,
      const AgentConversationWorkspaceEntryRemoved(
        entryId: 'entry-1',
        fallbackEntryId: null,
      ),
    );

    expect(registered.entries.map((entry) => entry.entryId), <String>[
      'entry-1',
    ]);
    expect(selected.selectedEntryId, 'entry-1');
    expect(selected.projectHomeActive, isFalse);
    expect(home.selectedEntryId, isNull);
    expect(home.projectHomeActive, isTrue);
    expect(removed.entries, isEmpty);
  });

  test('thread mappings restore update and remove without mutable aliases', () {
    final source = <String, String>{'/one': 'thread-1'};
    final restored = reducer.reduce(
      AgentConversationWorkspaceState(),
      AgentConversationWorkspaceThreadMappingsRestored(source),
    );
    source['/two'] = 'outside';
    final updated = reducer.reduce(
      restored,
      const AgentConversationWorkspaceThreadMappingSet(
        projectPath: '/two',
        threadId: 'thread-2',
      ),
    );
    final removed = reducer.reduce(
      updated,
      const AgentConversationWorkspaceThreadMappingRemoved('/one'),
    );

    expect(restored.threadIdsByProject, <String, String>{'/one': 'thread-1'});
    expect(updated.threadIdsByProject['/two'], 'thread-2');
    expect(removed.threadIdsByProject, <String, String>{'/two': 'thread-2'});
  });
}

AgentConversationWorkspaceEntryState _entry(String entryId) {
  return AgentConversationWorkspaceEntryState(
    entryId: entryId,
    projectPath: '/workspace',
    providerId: 'codex',
    threadId: null,
    bindingKey: AgentConversationBindingKey.draft(
      providerId: 'codex',
      entryId: entryId,
    ),
    threadSnapshot: const AgentConversationThreadSnapshot(
      sessionId: null,
      providerId: 'codex',
      threadTitle: 'New thread',
      isTurnRunning: false,
      runtimeStatus: null,
      waitingOnApproval: false,
      waitingOnUserInput: false,
    ),
  );
}

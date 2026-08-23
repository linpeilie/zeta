import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/app/composition/zeta_state_snapshot.dart';
import 'package:zeta/src/features/project_threads/domain/project_thread_list_state.dart';
import 'package:zeta/src/features/workspace/application/workspace_slice/workspace_slice_state.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

void main() {
  test(
    'project thread projection freezes identities and excludes body data',
    () {
      final state = ProjectThreadListState(
        isExpanded: true,
        hasLoaded: true,
        threads: <AgentThreadSummary>[
          AgentThreadSummary(
            id: 'thread-1',
            providerId: 'provider-1',
            projectPath: '/workspace',
            title: 'sensitive title fixture',
            preview: 'sensitive preview fixture',
            createdAt: DateTime.utc(2026, 8, 23),
            updatedAt: DateTime.utc(2026, 8, 23),
            status: AgentThreadRuntimeStatus.active,
          ),
        ],
        runningThreadIds: const <String>{'thread-1'},
        selectedThreadId: 'thread-1',
      );

      final snapshot = ZetaProjectThreadsStateSnapshot.fromState(
        '/workspace',
        state,
      );

      expect(snapshot.orderedThreadIds, const <String>['thread-1']);
      expect(snapshot.runningThreadIds, const <String>{'thread-1'});
      expect(snapshot.selectedThreadId, 'thread-1');
      expect(
        () => snapshot.orderedThreadIds.add('thread-2'),
        throwsUnsupportedError,
      );
      expect(
        () => snapshot.runningThreadIds.add('thread-2'),
        throwsUnsupportedError,
      );
    },
  );

  test('shell snapshot normalizes maps and relay performs on-demand reads', () {
    final projectThreads = <String, ZetaProjectThreadsStateSnapshot>{};
    final orderedEntries = <String>['entry-1'];
    final conversations = <String, ZetaConversationStateSnapshot>{
      'entry-1': const ZetaConversationStateSnapshot(
        entryId: 'entry-1',
        projectPath: '/workspace',
        providerId: 'provider-1',
        threadId: 'thread-1',
        isDraft: false,
        isSelected: true,
        sliceAvailable: true,
        threadOpenPhase: AgentThreadOpenPhase.idle,
        runtimeStatus: AgentThreadRuntimeStatus.active,
        isTurnRunning: true,
        isReadOnly: false,
        visibleTurnCount: 2,
        pendingInteractionCount: 1,
        pendingOperationCount: 0,
      ),
    };
    final snapshot = ZetaShellStateSnapshot(
      workspace: WorkspaceSliceState(projects: const <String>['/workspace']),
      projectThreadsByProjectPath: projectThreads,
      orderedConversationEntryIds: orderedEntries,
      conversationsByEntryId: conversations,
      selectedConversationEntryId: 'entry-1',
      projectHomeActive: false,
    );
    projectThreads['/other'] = ZetaProjectThreadsStateSnapshot.fromState(
      '/other',
      const ProjectThreadListState(),
    );
    orderedEntries.add('entry-2');
    conversations.clear();

    expect(snapshot.projectThreadsByProjectPath, isEmpty);
    expect(snapshot.orderedConversationEntryIds, const <String>['entry-1']);
    expect(snapshot.conversationsByEntryId.keys, const <String>['entry-1']);

    final relay = ZetaShellStateSnapshotRelay();
    ZetaShellStateSnapshot reader() => snapshot;
    relay.bind(reader);
    expect(relay.read(), same(snapshot));
    expect(() => relay.bind(() => snapshot), throwsStateError);
    relay.unbind(reader);
    expect(relay.isBound, isFalse);
    expect(relay.read, throwsStateError);
  });
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta/src/app/conversation_workspace_slice/agent_conversation_workspace_state.dart';
import 'package:zeta/src/app/conversation_workspace_slice/agent_conversation_workspace_store.dart';

/// 根 scope 与 `IdeHome` 之间的同步组合注册表。
final class AgentConversationWorkspaceStoreRegistry {
  AgentConversationWorkspaceStore? _store;

  void bind(AgentConversationWorkspaceStore store) {
    final current = _store;
    if (current != null && !identical(current, store)) {
      throw StateError('Conversation workspace registry is already bound');
    }
    _store = store;
  }

  void unbind(AgentConversationWorkspaceStore store) {
    if (identical(_store, store)) {
      _store = null;
    }
  }

  AgentConversationWorkspaceStore get store =>
      _store ??
      (throw StateError(
        'Conversation workspace store was read before IdeHome binding',
      ));
}

final agentConversationWorkspaceStoreRegistryProvider =
    Provider<AgentConversationWorkspaceStoreRegistry>(
      (ref) => throw StateError(
        'agentConversationWorkspaceStoreRegistryProvider must be overridden',
      ),
      name: 'agentConversationWorkspaceStoreRegistry',
    );

final agentConversationWorkspaceStoreProvider =
    Provider<AgentConversationWorkspaceStore>(
      (ref) => ref.watch(agentConversationWorkspaceStoreRegistryProvider).store,
      name: 'agentConversationWorkspaceStore',
    );

final agentConversationWorkspaceProvider =
    NotifierProvider<
      AgentConversationWorkspaceNotifier,
      AgentConversationWorkspaceState
    >(
      AgentConversationWorkspaceNotifier.new,
      name: 'agentConversationWorkspace',
    );

/// Riverpod 只镜像 app store；Workspace 生命周期仍由 Shell 组合层持有。
final class AgentConversationWorkspaceNotifier
    extends Notifier<AgentConversationWorkspaceState> {
  @override
  AgentConversationWorkspaceState build() {
    final store = ref.watch(agentConversationWorkspaceStoreProvider);
    void listener() => state = store.state;
    store.addListener(listener);
    ref.onDispose(() => store.removeListener(listener));
    return store.state;
  }
}

final agentConversationWorkspaceEntriesProvider =
    Provider<List<AgentConversationWorkspaceEntryState>>(
      (ref) => ref.watch(
        agentConversationWorkspaceProvider.select((state) => state.entries),
      ),
      name: 'agentConversationWorkspaceEntries',
    );

final agentConversationWorkspaceSelectedEntryIdProvider = Provider<String?>(
  (ref) => ref.watch(
    agentConversationWorkspaceProvider.select((state) => state.selectedEntryId),
  ),
  name: 'agentConversationWorkspaceSelectedEntryId',
);

final agentConversationWorkspaceProjectHomeProvider = Provider<bool>(
  (ref) => ref.watch(
    agentConversationWorkspaceProvider.select(
      (state) => state.projectHomeActive,
    ),
  ),
  name: 'agentConversationWorkspaceProjectHome',
);

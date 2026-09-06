import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_actions.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_owner_key.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_notifier.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_state.dart';
import 'agent_conversation_workspace_notifier.dart';
import 'agent_conversation_entry_resources.dart';

/// 应用显式管理资源释放；观察人数仅决定已关闭空投影的回收。
final class ConversationSliceLifetimeCoordinator {
  ConversationSliceLifetimeCoordinator({
    required this.workspace,
    required this.retainOwner,
    required this.readOwner,
    required this.invalidateOwner,
    required this.releaseEntryLease,
  });
  final AgentConversationWorkspaceNotifier workspace;
  final Future<void> Function(AgentConversationEntryResources)
  releaseEntryLease;
  final ProviderSubscription<AgentConversationSliceState> Function(
    AgentConversationOwnerKey,
  )
  retainOwner;
  final AgentConversationSliceNotifier Function(AgentConversationOwnerKey)
  readOwner;
  final void Function(AgentConversationOwnerKey) invalidateOwner;
  final _subscriptions =
      <
        AgentConversationOwnerKey,
        ProviderSubscription<AgentConversationSliceState>
      >{};
  final _owners = <AgentConversationOwnerKey, AgentConversationSliceNotifier>{};
  final _closeFutures = <AgentConversationOwnerKey, Future<void>>{};
  final _releaseCompletionMarkers = <AgentConversationOwnerKey>{};
  Future<void>? _closeAllFuture;
  bool _closing = false;
  int get retainedOwnerCount => _owners.length;
  int get releaseMarkerCount => _releaseCompletionMarkers.length;
  int get closeFutureCount => _closeFutures.length;

  AgentConversationActions actionsForOwner(AgentConversationOwnerKey key) =>
      _owners[key] ?? const AgentClosedConversationActions();

  void ensureSlice(AgentConversationOwnerKey key) {
    if (_closing) throw StateError('Conversation lifetimes are closing');
    if (_owners.containsKey(key)) return;
    final subscription = retainOwner(key);
    _subscriptions[key] = subscription;
    _owners[key] = readOwner(key);
  }

  Future<void> closeEntry(AgentConversationOwnerKey key) {
    final existing = _closeFutures[key];
    if (existing != null) return existing;
    final entry = workspace.resourcesFor(key);
    if (entry == null) return Future<void>.value();
    // Register before synchronous notifications can reenter closeEntry.
    final completion = Completer<void>();
    _closeFutures[key] = completion.future;
    final work = () async {
      workspace.markClosing(key);
      _owners[key]?.closeForEntryRelease();
      workspace.removeVisibleEntry(key);
      entry.detachSnapshotSubscriptions();
      entry.controller.dispose();
      await releaseEntryLease(entry);
      workspace.finishEntryRelease(key);
      if (!_owners.containsKey(key)) {
        workspace.removeReleasedAliases(key);
        _closeFutures.remove(key);
        _subscriptions.remove(key)?.close();
        return;
      }
      _releaseCompletionMarkers.add(key);
      _subscriptions.remove(key)?.close();
    }();
    unawaited(
      work.then(completion.complete, onError: completion.completeError),
    );
    return completion.future;
  }

  Future<void> closeAllEntries() {
    final existing = _closeAllFuture;
    if (existing != null) return existing;
    final completion = Completer<void>();
    _closeAllFuture = completion.future;
    unawaited(
      _closeAllEntries().then(
        completion.complete,
        onError: completion.completeError,
      ),
    );
    return completion.future;
  }

  Future<void> _closeAllEntries() async {
    _closing = true;
    await Future.wait<void>([
      for (final key in workspace.resourceOwnerKeys) closeEntry(key),
    ], eagerError: false);
  }

  void onProjectionUnobserved(AgentConversationOwnerKey key) {
    final owner = _owners[key];
    if (!_releaseCompletionMarkers.contains(key) ||
        owner == null ||
        !owner.isClosed ||
        owner.isProjectionObserved) {
      return;
    }
    owner.releaseClosedProjectionRetention();
    invalidateOwner(key);
    workspace.removeReleasedAliases(key);
    _owners.remove(key);
    _closeFutures.remove(key);
    _releaseCompletionMarkers.remove(key);
  }
}

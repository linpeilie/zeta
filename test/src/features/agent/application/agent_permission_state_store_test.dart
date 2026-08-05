import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_permission_state_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  group('AgentPermissionStateStore', () {
    const firstRuntime = AgentProviderRuntimeIdentity(
      providerId: 'grok',
      generation: 1,
    );

    test('currentTurn is request-only and consumed exactly once', () {
      final store = AgentPermissionStateStore();
      addTearDown(store.dispose);
      store.activateRuntime(
        firstRuntime,
        initialProviderDefault: const AgentPermissionSelection(optionId: 'ask'),
      );
      store.commitApplyResult(
        identity: firstRuntime,
        threadId: 'thread-a',
        result: const AgentPermissionApplyResult(
          normalizedSelection: AgentPermissionSelection(optionId: 'auto'),
          scope: AgentPermissionApplyScope.currentTurn,
        ),
        source: AgentPermissionStateSource.userSelection,
        updateDefault: true,
      );

      final first = store.takeRequestSnapshot(
        identity: firstRuntime,
        threadId: 'thread-a',
        catalogDefault: null,
      );
      final second = store.takeRequestSnapshot(
        identity: firstRuntime,
        threadId: 'thread-a',
        catalogDefault: null,
      );

      expect(first.selection?.optionId, 'auto');
      expect(first.source, AgentPermissionRequestSource.threadEffective);
      expect(second.selection?.optionId, 'ask');
      expect(second.source, AgentPermissionRequestSource.providerDefault);
      expect(
        store.stateFor(firstRuntime).providerDefaultPreference?.optionId,
        'ask',
      );
    });

    test('currentSession changes only the addressed thread', () {
      final store = AgentPermissionStateStore();
      addTearDown(store.dispose);
      store.activateRuntime(
        firstRuntime,
        initialProviderDefault: const AgentPermissionSelection(optionId: 'ask'),
      );
      store.commitApplyResult(
        identity: firstRuntime,
        threadId: 'thread-a',
        result: const AgentPermissionApplyResult(
          normalizedSelection: AgentPermissionSelection(optionId: 'auto'),
          scope: AgentPermissionApplyScope.currentSession,
          warning: 'session only',
        ),
        source: AgentPermissionStateSource.serverSettings,
        updateDefault: false,
      );

      final state = store.stateFor(firstRuntime);
      expect(state.threadStates['thread-a']?.selection.optionId, 'auto');
      expect(
        state.threadStates['thread-a']?.source,
        AgentPermissionStateSource.serverSettings,
      );
      expect(
        state.effectiveStateForThread('thread-b')?.selection.optionId,
        'ask',
      );
      expect(
        () => state.threadStates['thread-b'] = const AgentThreadPermissionState(
          threadId: 'thread-b',
          selection: AgentPermissionSelection(optionId: 'auto'),
          source: AgentPermissionStateSource.userSelection,
        ),
        throwsUnsupportedError,
      );
    });

    test(
      'runtime emits explicit broadcast without rewriting provider default',
      () async {
        final store = AgentPermissionStateStore();
        addTearDown(store.dispose);
        store.activateRuntime(
          firstRuntime,
          initialProviderDefault: const AgentPermissionSelection(
            optionId: 'ask',
          ),
        );
        final eventFuture = store.runtimeStates.first;

        store.commitApplyResult(
          identity: firstRuntime,
          threadId: 'thread-a',
          result: const AgentPermissionApplyResult(
            normalizedSelection: AgentPermissionSelection(
              optionId: 'always-approve',
            ),
            scope: AgentPermissionApplyScope.runtime,
            warning: 'runtime warning',
          ),
          source: AgentPermissionStateSource.userSelection,
          updateDefault: false,
        );

        final event = await eventFuture;
        final state = store.stateFor(firstRuntime);
        expect(event.runtimeIdentity, firstRuntime);
        expect(event.selection.optionId, 'always-approve');
        expect(state.runtimeSelection?.optionId, 'always-approve');
        expect(state.source, AgentPermissionStateSource.runtimeBroadcast);
        expect(state.providerDefaultPreference?.optionId, 'ask');
        expect(
          state.effectiveStateForThread('thread-a')?.selection.optionId,
          'always-approve',
        );
        expect(
          state.effectiveStateForThread('thread-b')?.selection.optionId,
          'always-approve',
        );
      },
    );

    test('nextSession updates preference but preserves current thread', () {
      final store = AgentPermissionStateStore();
      addTearDown(store.dispose);
      store.activateRuntime(
        firstRuntime,
        initialProviderDefault: const AgentPermissionSelection(optionId: 'ask'),
      );
      store.commitApplyResult(
        identity: firstRuntime,
        threadId: 'thread-a',
        result: const AgentPermissionApplyResult(
          normalizedSelection: AgentPermissionSelection(optionId: 'ask'),
          scope: AgentPermissionApplyScope.currentSession,
        ),
        source: AgentPermissionStateSource.serverSettings,
        updateDefault: false,
      );
      store.commitApplyResult(
        identity: firstRuntime,
        threadId: 'thread-a',
        result: const AgentPermissionApplyResult(
          normalizedSelection: AgentPermissionSelection(optionId: 'auto'),
          scope: AgentPermissionApplyScope.nextSession,
          warning: 'restart session',
        ),
        source: AgentPermissionStateSource.userSelection,
        updateDefault: true,
      );

      final state = store.stateFor(firstRuntime);
      expect(state.providerDefaultPreference?.optionId, 'auto');
      expect(state.threadStates['thread-a']?.selection.optionId, 'ask');
      expect(
        state.effectiveStateForThread('thread-a')?.selection.optionId,
        'ask',
      );
      expect(state.warning, 'restart session');
    });

    test('old generation cannot commit or broadcast into new runtime', () {
      final store = AgentPermissionStateStore();
      addTearDown(store.dispose);
      const secondRuntime = AgentProviderRuntimeIdentity(
        providerId: 'grok',
        generation: 2,
      );
      store.activateRuntime(firstRuntime);
      store.retireRuntime(firstRuntime);
      store.activateRuntime(
        secondRuntime,
        initialProviderDefault: const AgentPermissionSelection(optionId: 'ask'),
      );
      final runtimeEvents = <AgentPermissionRuntimeState>[];
      final subscription = store.runtimeStates.listen(runtimeEvents.add);
      addTearDown(subscription.cancel);

      final committed = store.commitApplyResult(
        identity: firstRuntime,
        threadId: 'thread-a',
        result: const AgentPermissionApplyResult(
          normalizedSelection: AgentPermissionSelection(
            optionId: 'always-approve',
          ),
          scope: AgentPermissionApplyScope.runtime,
        ),
        source: AgentPermissionStateSource.runtimeBroadcast,
        updateDefault: false,
      );

      expect(committed, isFalse);
      expect(runtimeEvents, isEmpty);
      expect(store.stateFor(secondRuntime).runtimeSelection, isNull);
      expect(
        store.stateFor(secondRuntime).providerDefaultPreference?.optionId,
        'ask',
      );
    });
  });
}

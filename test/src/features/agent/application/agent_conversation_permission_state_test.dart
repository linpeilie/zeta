import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/agent/application/agent_conversation_permission_state.dart';
import 'package:zeta/src/features/agent/application/agent_provider_runtime_identity.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  group('AgentConversationPermissionState', () {
    const runtime = AgentProviderRuntimeIdentity(
      providerId: 'grok',
      generation: 1,
    );
    const providerDefault = AgentPermissionSelection(optionId: 'ask');

    test('currentTurn is request-only and consumed exactly once', () {
      var state = const AgentConversationPermissionState(
        runtimeIdentity: runtime,
        threadId: 'thread-a',
        providerDefaultPreference: providerDefault,
      );
      state = state.commitApplyResult(
        result: const AgentPermissionApplyResult(
          normalizedSelection: AgentPermissionSelection(optionId: 'auto'),
          scope: AgentPermissionApplyScope.currentTurn,
        ),
        source: AgentPermissionStateSource.userSelection,
        updateDefault: true,
      );

      final first = state.takeRequestSnapshot(
        requestedThreadId: 'thread-a',
        catalogDefault: null,
      );
      final second = first.state.takeRequestSnapshot(
        requestedThreadId: 'thread-a',
        catalogDefault: null,
      );

      expect(first.snapshot.selection?.optionId, 'auto');
      expect(
        first.snapshot.source,
        AgentPermissionRequestSource.threadEffective,
      );
      expect(second.snapshot.selection?.optionId, 'ask');
      expect(
        second.snapshot.source,
        AgentPermissionRequestSource.providerDefault,
      );
      expect(first.state.pendingTurn, isNull);
      expect(first.state.providerDefaultPreference, providerDefault);
    });

    test(
      'session effective belongs to one Binding and rebind fails closed',
      () {
        var state = const AgentConversationPermissionState(
          runtimeIdentity: runtime,
          threadId: 'thread-a',
          providerDefaultPreference: providerDefault,
        );
        state = state.commitApplyResult(
          result: const AgentPermissionApplyResult(
            normalizedSelection: AgentPermissionSelection(optionId: 'auto'),
            scope: AgentPermissionApplyScope.currentSession,
            warning: 'session only',
          ),
          source: AgentPermissionStateSource.serverSettings,
          updateDefault: false,
        );

        expect(state.sessionEffective?.selection.optionId, 'auto');
        expect(
          state.sessionEffective?.source,
          AgentPermissionStateSource.serverSettings,
        );

        expect(() => state.bindThread('thread-b'), throwsA(isA<StateError>()));
        expect(() => state.bindThread(null), throwsA(isA<StateError>()));
        expect(state.threadId, 'thread-a');
        expect(state.runtimeIdentity, runtime);
        expect(state.sessionEffective?.selection.optionId, 'auto');
      },
    );

    test('runtime selection is local and removed when runtime detaches', () {
      var state = const AgentConversationPermissionState(
        runtimeIdentity: runtime,
        threadId: 'thread-a',
        providerDefaultPreference: providerDefault,
      );
      state = state.commitApplyResult(
        result: const AgentPermissionApplyResult(
          normalizedSelection: AgentPermissionSelection(optionId: 'session'),
          scope: AgentPermissionApplyScope.currentSession,
        ),
        source: AgentPermissionStateSource.serverSettings,
        updateDefault: false,
      );
      state = state.commitApplyResult(
        result: const AgentPermissionApplyResult(
          normalizedSelection: AgentPermissionSelection(optionId: 'runtime'),
          scope: AgentPermissionApplyScope.runtime,
        ),
        source: AgentPermissionStateSource.userSelection,
        updateDefault: false,
      );

      expect(state.effectiveValue?.selection.optionId, 'runtime');

      final detached = state.detachRuntime();
      expect(detached.runtimeIdentity, isNull);
      expect(detached.runtimeSelection, isNull);
      expect(detached.sessionEffective?.selection.optionId, 'session');
      expect(detached.providerDefaultPreference, providerDefault);
    });

    test('nextSession changes default but preserves session effective', () {
      var state = const AgentConversationPermissionState(
        runtimeIdentity: runtime,
        threadId: 'thread-a',
        providerDefaultPreference: providerDefault,
      );
      state = state.commitApplyResult(
        result: const AgentPermissionApplyResult(
          normalizedSelection: AgentPermissionSelection(optionId: 'session'),
          scope: AgentPermissionApplyScope.currentSession,
        ),
        source: AgentPermissionStateSource.serverSettings,
        updateDefault: false,
      );
      state = state.commitApplyResult(
        result: const AgentPermissionApplyResult(
          normalizedSelection: AgentPermissionSelection(optionId: 'next'),
          scope: AgentPermissionApplyScope.nextSession,
          warning: 'restart session',
        ),
        source: AgentPermissionStateSource.userSelection,
        updateDefault: true,
      );

      expect(state.providerDefaultPreference?.optionId, 'next');
      expect(state.sessionEffective?.selection.optionId, 'session');
      expect(state.effectiveValue?.selection.optionId, 'session');
      expect(state.warning, 'restart session');
    });

    test('runtime identity is a single exact generation guard', () {
      const replacement = AgentProviderRuntimeIdentity(
        providerId: 'grok',
        generation: 2,
      );
      final state = const AgentConversationPermissionState(
        runtimeIdentity: runtime,
        providerDefaultPreference: providerDefault,
      ).attachRuntime(replacement);

      expect(state.isCurrent(runtime), isFalse);
      expect(state.isCurrent(replacement), isTrue);
    });
  });
}

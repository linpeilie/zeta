import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';

void main() {
  const initial = AgentConversationSessionState.initial(
    defaultTitle: agentDefaultThreadTitle,
  );

  AgentConversationReducerContext context() {
    return AgentConversationReducerContext(
      scope: AgentConversationReductionScope.live,
      selectedThreadId: 'thread-1',
      requiresResumedSelectedThread: false,
      pendingTurnGroupId: null,
      hasTurn: (id) => id == 'turn-1',
      isHistoryTurnId: (_) => false,
      hasRunningTurnExcluding: (_) => false,
      modelsRefreshing: false,
      activeProviderName: 'Codex',
      activeProviderConfig: defaultCodexAgentProviderConfig,
      effectScope: const AgentConversationEffectScope(
        reductionScope: AgentConversationReductionScope.live,
        providerId: 'codex',
        listenerGeneration: 1,
        threadId: 'thread-1',
      ),
    );
  }

  test('copyWith 能把可空字段设回 null', () {
    final filled = initial.copyWith(
      session: const AgentSession(id: 'thread-1', providerId: 'codex'),
      modelRerouteNotice: 'rerouted',
    );
    final cleared = filled.copyWith(session: null, modelRerouteNotice: null);
    expect(cleared.session, isNull);
    expect(cleared.modelRerouteNotice, isNull);
  });

  test('status 事件直接产出 nextState，不经过 VM', () {
    const status = AgentProviderStatus(
      state: AgentProviderConnectionState.running,
      message: 'Working',
    );
    final reduction = AgentConversationReducer.live().reduce(
      const AgentStatusEvent(status),
      initial,
      context(),
    );
    expect(reduction.accepted, isTrue);
    expect(reduction.state.status.state, AgentProviderConnectionState.running);
    expect(reduction.state.status.message, 'Working');
  });

  test('thread preview 写进 currentThreadPreview', () {
    final reduction = AgentConversationReducer.live().reduce(
      const AgentThreadPreviewUpdatedEvent(
        threadId: 'thread-1',
        preview: 'last turn',
      ),
      initial,
      context(),
    );
    expect(reduction.state.currentThreadPreview, 'last turn');
  });
}

import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';

const handlerTestThreadId = 'thread-1';
const handlerTestTurnId = 'turn-1';

const handlerTestInitialState = AgentConversationSessionState.initial(
  defaultTitle: agentDefaultThreadTitle,
);

AgentReducerScratch handlerTestScratch() {
  return AgentReducerScratch(
    timelineIds: AgentConversationLocalTimelineIdGenerator(
      clock: () => DateTime.utc(2026, 1, 2, 3, 4, 5, 6, 7),
    ),
    textCatalog: const FallbackAgentUiTextCatalog(),
  );
}

AgentConversationReducerContext handlerTestContext({
  String? selectedThreadId = handlerTestThreadId,
}) {
  return AgentConversationReducerContext(
    scope: AgentConversationReductionScope.live,
    selectedThreadId: selectedThreadId,
    requiresResumedSelectedThread: false,
    pendingTurnGroupId: null,
    hasTurn: (turnId) => turnId == handlerTestTurnId,
    isHistoryTurnId: (_) => false,
    hasRunningTurnExcluding: (_) => false,
    modelsRefreshing: false,
    activeProviderName: 'Codex',
    activeProviderConfig: defaultCodexAgentProviderConfig,
    effectScope: AgentConversationEffectScope(
      reductionScope: AgentConversationReductionScope.live,
      providerId: defaultAgentProviderId,
      listenerGeneration: 7,
      runtimeId: 'runtime-1',
      connectionEpoch: 3,
      threadId: selectedThreadId,
    ),
  );
}

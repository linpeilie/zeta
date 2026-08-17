import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_effect.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_mutation.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_reducer.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_timeline_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/fallback_agent_ui_text_catalog.dart';

/// 步骤 11 canary：同一中立 fixture 在两种目录下结构相同，仅思考卡标题不同。
const _zhThinkingCatalog = _FixedAgentUiTextCatalog('思考');
const _enThinkingCatalog = _FixedAgentUiTextCatalog('Think');
const _reasoningDelta = AgentReasoningDeltaEvent(
  itemId: 'reasoning-1',
  kind: AgentReasoningDeltaKind.summaryText,
  delta: 'planning next step',
  sessionId: 'thread-1',
  turnId: 'turn-1',
);

void main() {
  group('AgentUiTextCatalog thinking canary', () {
    test('live/history/replay reducers stay independent and share catalog', () {
      final reducers = AgentConversationReducerContexts(
        textCatalog: _enThinkingCatalog,
      );

      expect(identical(reducers.live, reducers.history), isFalse);
      expect(identical(reducers.history, reducers.replay), isFalse);
      expect(
        identical(reducers.live.textCatalog, reducers.history.textCatalog),
        isTrue,
      );
      expect(
        identical(reducers.history.textCatalog, reducers.replay.textCatalog),
        isTrue,
      );
      expect(reducers.live.scope, AgentConversationReductionScope.live);
      expect(reducers.history.scope, AgentConversationReductionScope.history);
      expect(reducers.replay.scope, AgentConversationReductionScope.replay);
    });

    test('reasoning mutations are identical across catalogs', () {
      final zhMutation = AgentConversationReducer.live(
        textCatalog: _zhThinkingCatalog,
      ).reduce(_reasoningDelta, _context());
      final enMutation = AgentConversationReducer.live(
        textCatalog: _enThinkingCatalog,
      ).reduce(_reasoningDelta, _context());

      expect(zhMutation.accepted, isTrue);
      expect(enMutation.accepted, isTrue);
      expect(
        zhMutation.timelineMutations.map((item) => item.runtimeType).toList(),
        enMutation.timelineMutations.map((item) => item.runtimeType).toList(),
      );
      final zhDelta =
          zhMutation.timelineMutations.single
              as AgentAppendReasoningDeltaTimelineMutation;
      final enDelta =
          enMutation.timelineMutations.single
              as AgentAppendReasoningDeltaTimelineMutation;
      expect(zhDelta.event.itemId, enDelta.event.itemId);
      expect(zhDelta.event.delta, enDelta.event.delta);
      expect(zhDelta.event.kind, enDelta.event.kind);
      expect(zhDelta.event.sessionId, enDelta.event.sessionId);
      expect(zhDelta.event.turnId, enDelta.event.turnId);
    });

    test('timeline snapshot matches except the thinking fallback title', () {
      final zhSnap = _runCanary(_zhThinkingCatalog);
      final enSnap = _runCanary(_enThinkingCatalog);

      expect(zhSnap.title, '思考');
      expect(enSnap.title, 'Think');
      expect(zhSnap.toolId, enSnap.toolId);
      expect(zhSnap.kind, enSnap.kind);
      expect(zhSnap.status, enSnap.status);
      expect(zhSnap.content, enSnap.content);
      expect(zhSnap.timelineEntryIds, enSnap.timelineEntryIds);
      expect(zhSnap.phase, enSnap.phase);
      expect(zhSnap.turnId, enSnap.turnId);
      expect(zhSnap.isTerminal, enSnap.isTerminal);
    });
  });
}

({
  String toolId,
  String title,
  AgentToolKind kind,
  AgentToolStatus status,
  String? content,
  List<String> timelineEntryIds,
  AgentTurnActivityPhase phase,
  String? turnId,
  bool isTerminal,
})
_runCanary(AgentUiTextCatalog catalog) {
  final store = AgentConversationTimelineStore(textCatalog: catalog);
  addTearDown(store.dispose);
  store.startPendingLiveTurn();
  store.beginLiveTurnGroup(
    const AgentTurn(id: 'turn-1', sessionId: 'thread-1'),
  );
  store.appendReasoningDelta(_reasoningDelta);
  final tool = store.toolCalls.single;
  return (
    toolId: tool.id,
    title: tool.title,
    kind: tool.kind,
    status: tool.status,
    content: tool.content,
    timelineEntryIds: store.timelineEntries.map((entry) => entry.id).toList(),
    phase: store.currentActivity.phase,
    turnId: store.currentTurnGroupId,
    isTerminal: !store.isTurnRunning,
  );
}

AgentConversationReducerContext _context() {
  const config = AgentProviderConfig(
    id: 'neutral',
    displayName: 'Neutral',
    kind: AgentProviderKind.acp,
    command: 'agent',
  );
  return AgentConversationReducerContext(
    scope: AgentConversationReductionScope.live,
    selectedThreadId: 'thread-1',
    requiresResumedSelectedThread: false,
    pendingTurnGroupId: null,
    hasTurn: (turnId) => turnId == 'turn-1',
    isHistoryTurnId: (_) => false,
    modelsRefreshing: false,
    activeProviderName: 'Neutral',
    activeProviderConfig: config,
    effectScope: const AgentConversationEffectScope(
      reductionScope: AgentConversationReductionScope.live,
      providerId: 'neutral',
      listenerGeneration: 1,
      runtimeId: 'runtime-1',
      connectionEpoch: 1,
      threadId: 'thread-1',
    ),
  );
}

final class _FixedAgentUiTextCatalog extends FallbackAgentUiTextCatalog {
  const _FixedAgentUiTextCatalog(this._thinkingToolTitle);

  final String _thinkingToolTitle;

  @override
  String get thinkingToolTitle => _thinkingToolTitle;
}

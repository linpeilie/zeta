import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_region_state.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';

import '../../../testing/agent_event_storm_fixture.dart';

void main() {
  group('脏区帧预算', () {
    test('1000 个 message delta 不会连带刷新 header/composer', () {
      final fixture = AgentEventStormFixture();
      final timeline = AgentConversationTimelineStore();
      addTearDown(timeline.dispose);
      timeline.startPendingLiveTurn();
      timeline.beginLiveTurnGroup(
        AgentTurn(id: fixture.turnId, sessionId: fixture.sessionId),
      );
      timeline.takeDirtyRegions();

      final published = <AgentUiUpdateRequest>[];
      final processor = _processor(
        timeline: timeline,
        sessionId: fixture.sessionId,
        onPublish: published.add,
      );

      final deltas = fixture.events.whereType<AgentMessageDeltaEvent>().take(
        1000,
      );
      for (final event in deltas) {
        final reduction = processor.process(event);
        expect(reduction.accepted, isTrue);
      }

      final headerPublishes = published.where(
        (request) => request.regions.contains(AgentUiRegion.header),
      );
      expect(headerPublishes.length, lessThanOrEqualTo(2));
      expect(
        published.every(
          (request) => !request.regions.contains(AgentUiRegion.composer),
        ),
        isTrue,
      );
    });

    test('值未变化的写入不点亮脏位', () {
      final store = AgentConversationTimelineStore();
      addTearDown(store.dispose);
      store.appendMessageDelta(
        const AgentMessageDeltaEvent(
          messageId: 'message-1',
          delta: 'hello',
          role: AgentMessageRole.agent,
        ),
      );
      expect(store.takeDirtyRegions(), isNot(isEmpty));

      store.appendMessageDelta(
        const AgentMessageDeltaEvent(
          messageId: 'message-1',
          delta: '',
          role: AgentMessageRole.agent,
        ),
      );
      expect(store.takeDirtyRegions(), isEmpty);
    });

    test('历史 turn 的 token usage 点亮 history 而不是 liveTurn', () {
      final store = AgentConversationTimelineStore();
      addTearDown(store.dispose);
      store.startPendingLiveTurn();
      store.beginLiveTurnGroup(
        const AgentTurn(id: 'turn-1', sessionId: 'thread-1'),
      );
      store.completeLiveTurnGroup('turn-1');
      store.takeDirtyRegions();

      store.updateTurnTokenUsage(
        const AgentTokenUsageEvent(
          tokenUsage: AgentTokenUsage(inputTokens: 10, totalTokens: 12),
          sessionId: 'thread-1',
          turnId: 'turn-1',
          isSessionCumulative: false,
        ),
      );

      final dirty = store.takeDirtyRegions();
      expect(dirty, contains(AgentTimelineDirtyRegion.history));
      expect(dirty, contains(AgentTimelineDirtyRegion.usage));
      expect(dirty, isNot(contains(AgentTimelineDirtyRegion.liveTurn)));
    });
  });

  group('header diff 表覆盖度', () {
    test('header diff 表覆盖 AgentHeaderState 的全部 state 来源字段', () {
      // 构造一遍 AgentHeaderState：新增字段会在这里编译失败，迫使分类来源。
      const AgentHeaderState(
        title: 'Thread',
        threadOpenPhase: AgentThreadOpenPhase.idle,
        systemNoticeLabel: null,
        statusCapsuleLabel: null,
        waitingOnApproval: false,
        waitingOnUserInput: false,
        showRunningIndicator: false,
        runningActivityLabel: null,
        segmentStartedAt: null,
        turnStartedAt: null,
        tokenUsage: null,
        isTurnRunning: false,
        isReadOnly: false,
        canFork: false,
        canRename: false,
        canArchive: false,
        isPlanMode: false,
      );

      const baseline = AgentConversationSessionState.initial(
        defaultTitle: 'Thread',
      );

      final sessionSourcedHeaderMutations =
          <String, AgentConversationSessionState Function()>{
            'status': () => baseline.copyWith(
              status: AgentProviderStatus(
                state: AgentProviderConnectionState.running,
                message: 'working',
              ),
            ),
            'currentThreadTitle': () =>
                baseline.copyWith(currentThreadTitle: 'Renamed'),
            'threadRuntimeStatus': () => baseline.copyWith(
              threadRuntimeStatus: AgentThreadRuntimeStatus.active,
            ),
            'threadWaitingOnApproval': () =>
                baseline.copyWith(threadWaitingOnApproval: true),
            'threadWaitingOnUserInput': () =>
                baseline.copyWith(threadWaitingOnUserInput: true),
            'modelRerouteNotice': () =>
                baseline.copyWith(modelRerouteNotice: 'rerouted'),
            'threadOpenPhase': () => baseline.copyWith(
              threadOpenPhase: AgentThreadOpenPhase.loadingHistory,
            ),
          };

      for (final entry in sessionSourcedHeaderMutations.entries) {
        expect(
          agentUiRegionsFromSessionStateDiff(baseline, entry.value()),
          contains(AgentUiRegion.header),
          reason: '${entry.key} 变化必须点亮 header',
        );
      }

      expect(
        agentUiRegionsFromSessionStateDiff(
          baseline,
          baseline.copyWith(currentThreadPreview: 'preview'),
        ),
        isNot(contains(AgentUiRegion.header)),
      );
      expect(
        agentUiRegionsFromSessionStateDiff(
          baseline,
          baseline.copyWith(
            sessionConfigOptions: const <AgentSessionConfigOption>[
              AgentSessionConfigOption(
                id: 'model',
                name: 'Model',
                kind: AgentSessionConfigOptionKind.select,
              ),
            ],
          ),
        ),
        equals(<AgentUiRegion>{AgentUiRegion.composer}),
      );
    });
  });
}

AgentConversationEventProcessor _processor({
  required AgentConversationTimelineStore timeline,
  required String sessionId,
  required void Function(AgentUiUpdateRequest request) onPublish,
}) {
  return AgentConversationEventProcessor(
    reducer: AgentConversationReducer.live(
      clock: () => DateTime.utc(2026, 7, 31),
    ),
    context: () => AgentConversationReducerContext(
      scope: AgentConversationReductionScope.live,
      selectedThreadId: sessionId,
      requiresResumedSelectedThread: false,
      pendingTurnGroupId: timeline.pendingTurnGroupId,
      hasTurn: timeline.hasTurn,
      isHistoryTurnId: timeline.isHistoryTurnId,
      hasRunningTurnExcluding: (turnId) {
        final running = timeline.selectedRunningTurnId;
        return running != null && running != turnId;
      },
      modelsRefreshing: false,
      activeProviderName: 'Codex',
      activeProviderConfig: defaultCodexAgentProviderConfig,
      effectScope: AgentConversationEffectScope(
        reductionScope: AgentConversationReductionScope.live,
        providerId: 'codex',
        listenerGeneration: 7,
        runtimeId: 'runtime-1',
        connectionEpoch: 3,
        threadId: sessionId,
      ),
    ),
    timeline: timeline,
    stateSink: _Sink(),
    uiUpdates: _Port(onPublish),
    effectRunner: _NoopEffects(),
  );
}

final class _Sink implements AgentConversationStateSink {
  @override
  AgentConversationSessionState sessionState =
      const AgentConversationSessionState.initial(defaultTitle: 'Thread');

  @override
  void applyReducedState(AgentConversationSessionState next) {
    sessionState = next;
  }

  @override
  void requestThreadSnapshotRefresh() {}
}

final class _Port implements AgentUiUpdatePort {
  _Port(this._onPublish);

  final void Function(AgentUiUpdateRequest request) _onPublish;

  @override
  void publish(AgentUiUpdateRequest request) => _onPublish(request);
}

final class _NoopEffects implements AgentConversationEffectRunner {
  @override
  void run(AgentConversationEffect effect) {}

  @override
  void dispose() {}
}

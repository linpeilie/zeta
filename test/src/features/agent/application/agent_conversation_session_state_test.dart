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

  group('hashCode 契约', () {
    // 回归：autoReviewsByTurnId 曾用 Object.hashAll(map.entries) 聚合。
    // MapEntry 不覆写 == / hashCode（恒等语义），且 Map.entries 每次迭代都新建
    // 实例，于是同一个对象两次读 hashCode 都会得到不同值。
    //
    // 注意 AgentAutoApprovalReviewEvent 自身也没有 operator ==（恒等相等），
    // 所以这里刻意复用 **const 实例**：const 规范化保证两处写法拿到同一个对象，
    // zetaMapEquals 才会判等。用两次 `new` 构造出字段相同的事件是**不相等**的，
    // 那属于 P4 state diff 的保守多刷路径，不是本组要验证的契约。
    AgentConversationSessionState reviewsIn(
      List<AgentAutoApprovalReviewEvent> events,
    ) {
      final reducer = AgentConversationReducer.live();
      var state = initial;
      for (final event in events) {
        state = reducer.reduce(event, state, context()).state;
      }
      return state;
    }

    AgentConversationSessionState withReviews() =>
        reviewsIn(const <AgentAutoApprovalReviewEvent>[
          _reviewTurn1,
          _reviewTurn2,
          _reviewTurn3,
        ]);

    test('同一对象重复读 hashCode 保持稳定', () {
      final state = withReviews();
      expect(state.autoReviewsByTurnId, hasLength(3));
      expect(state.hashCode, state.hashCode);
      expect(state.hashCode, state.copyWith().hashCode);
    });

    test('相等的两个 state 必须同 hashCode', () {
      final left = withReviews();
      final right = withReviews();
      expect(left, right);
      expect(left.hashCode, right.hashCode);
    });

    test('插入顺序不同但内容相同的 auto review 仍相等且同 hashCode', () {
      // zetaMapEquals 与顺序无关，hashCode 也必须与顺序无关。
      final reversed = reviewsIn(const <AgentAutoApprovalReviewEvent>[
        _reviewTurn3,
        _reviewTurn2,
        _reviewTurn1,
      ]);
      expect(withReviews(), reversed);
      expect(withReviews().hashCode, reversed.hashCode);
    });

    test('内容不同的 state 不相等', () {
      expect(
        withReviews(),
        isNot(reviewsIn(const <AgentAutoApprovalReviewEvent>[_reviewTurn1])),
      );
    });
  });
}

const _reviewTurn1 = AgentAutoApprovalReviewEvent(
  threadId: 'thread-1',
  turnId: 'turn-1',
  reviewId: 'review-turn-1',
  status: 'approved',
);
const _reviewTurn2 = AgentAutoApprovalReviewEvent(
  threadId: 'thread-1',
  turnId: 'turn-2',
  reviewId: 'review-turn-2',
  status: 'approved',
);
const _reviewTurn3 = AgentAutoApprovalReviewEvent(
  threadId: 'thread-1',
  turnId: 'turn-3',
  reviewId: 'review-turn-3',
  status: 'approved',
);

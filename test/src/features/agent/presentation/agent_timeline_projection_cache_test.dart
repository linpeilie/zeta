import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_timeline_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_projection_cache.dart';

void main() {
  group('AgentTimelineProjectionCache', () {
    test('同一 revision 连续 resolve 只计算 1 次', () {
      var builds = 0;
      final cache = AgentTimelineProjectionCache(
        buildBlocks: ({required turnId, required entries}) {
          builds += 1;
          return const [];
        },
      );
      final turn = _turn(id: 't1', revision: 3);

      for (var i = 0; i < 100; i += 1) {
        cache.resolve(turn);
      }

      expect(builds, 1);
      expect(cache.computeCount, 1);
    });

    test('revision 增加后必须重新计算，不返回旧投影', () {
      final cache = AgentTimelineProjectionCache();
      final v1 = _turn(id: 't1', revision: 1, text: 'hello v1');
      final v2 = _turn(id: 't1', revision: 2, text: 'hello v2 longer content');

      final first = cache.resolve(v1);
      final second = cache.resolve(v2);

      expect(cache.computeCount, 2);
      expect(identical(first, second), isFalse);
      expect(cache.resolveProjection(v2).renderRevision, 2);
    });

    test('只更新 live turn 时历史 turn 不重算', () {
      var builds = 0;
      final cache = AgentTimelineProjectionCache(
        buildBlocks: ({required turnId, required entries}) {
          builds += 1;
          return const [];
        },
      );
      final history = _turn(id: 'history', revision: 1);
      var live = _turn(id: 'live', revision: 1);

      cache.resolve(history);
      cache.resolve(live);
      expect(builds, 2);

      live = _turn(id: 'live', revision: 2, text: 'stream delta');
      cache.resolve(live);
      cache.resolve(history);

      expect(builds, 3);
      expect(cache.computeCount, 3);
    });

    test('retainOnly 与 clear 清理缓存', () {
      final cache = AgentTimelineProjectionCache();
      cache.resolve(_turn(id: 'a', revision: 1));
      cache.resolve(_turn(id: 'b', revision: 1));
      expect(cache.cachedTurnCount, 2);

      cache.retainOnly({'a'});
      expect(cache.containsTurn('a'), isTrue);
      expect(cache.containsTurn('b'), isFalse);

      cache.clear();
      expect(cache.cachedTurnCount, 0);
      expect(cache.computeCount, 0);
    });
  });

  group('AgentConversationTurnState content/meta revision', () {
    test('内容 mutation 推进 contentRevision；metadata 只推进 metaRevision', () {
      final state = AgentConversationTurnState(id: 't1', isStandby: false);
      expect(state.contentRevision, 0);
      expect(state.metaRevision, 0);
      expect(state.snapshot().contentRevision, 0);

      state.appendEntry(
        AgentMessageTimelineEntry(
          message: const AgentConversationMessage(
            id: 'm1',
            role: AgentMessageRole.agent,
            text: 'a',
          ),
        ),
      );
      expect(state.contentRevision, 1);
      expect(state.metaRevision, 0);
      expect(state.snapshot().contentRevision, 1);

      state.replaceEntry(
        AgentMessageTimelineEntry(
          message: const AgentConversationMessage(
            id: 'm1',
            role: AgentMessageRole.agent,
            text: 'ab',
          ),
        ),
      );
      expect(state.contentRevision, 2);

      state.updateMetadata(status: AgentHistoryTurnStatus.completed);
      expect(state.contentRevision, 2, reason: 'meta 不推进 content');
      expect(state.metaRevision, 1);
      expect(state.snapshot().metaRevision, 1);
      expect(state.renderRevision, 2, reason: 'renderRevision 别名 content');
    });

    test('token 元数据更新不使 projection 缓存失效', () {
      final cache = AgentTimelineProjectionCache();
      final state = AgentConversationTurnState(id: 't1', isStandby: false);
      state.appendEntry(
        AgentMessageTimelineEntry(
          message: const AgentConversationMessage(
            id: 'm1',
            role: AgentMessageRole.agent,
            text: 'hello',
          ),
        ),
      );
      final first = cache.resolve(state.snapshot());
      expect(cache.computeCount, 1);

      state.updateMetadata(
        status: state.status,
        tokenUsage: const AgentTokenUsage(totalTokens: 42),
      );
      final second = cache.resolve(state.snapshot());
      expect(cache.computeCount, 1, reason: 'contentRevision 未变');
      expect(identical(first, second), isTrue);
    });

    test('live 与 history turn 各自独立 revision', () {
      final live = AgentConversationTurnState(id: 'live', isStandby: false);
      final history = AgentConversationTurnState(
        id: 'history',
        isStandby: false,
      );

      live.appendEntry(
        AgentMessageTimelineEntry(
          message: const AgentConversationMessage(
            id: 'lm',
            role: AgentMessageRole.agent,
            text: 'live',
          ),
        ),
      );
      expect(live.renderRevision, 1);
      expect(history.renderRevision, 0);

      history.appendEntry(
        AgentMessageTimelineEntry(
          message: const AgentConversationMessage(
            id: 'hm',
            role: AgentMessageRole.agent,
            text: 'hist',
          ),
        ),
      );
      expect(live.renderRevision, 1);
      expect(history.renderRevision, 1);
    });
  });
}

AgentConversationTurnGroup _turn({
  required String id,
  required int revision,
  String text = 'hello',
}) {
  return AgentConversationTurnGroup(
    id: id,
    isStandby: false,
    renderRevision: revision,
    contentRevision: revision,
    entries: <AgentTimelineEntry>[
      AgentMessageTimelineEntry(
        message: AgentConversationMessage(
          id: '$id-msg',
          role: AgentMessageRole.agent,
          text: text,
        ),
      ),
    ],
  );
}

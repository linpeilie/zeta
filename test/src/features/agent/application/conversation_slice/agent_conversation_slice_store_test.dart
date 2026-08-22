import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_effect.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_intent.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_reducer.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_state.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_store.dart';

import '../../presentation/agent_conversation_ui_state_fixtures.dart';

void main() {
  group('AgentConversationSliceStore', () {
    test('命令铸造单调身份，同作用域序号不复用', () {
      final runner = _RecordingRunner();
      final store = _store(runner);
      addTearDown(store.dispose);

      final first = store.sendMessage(text: 'one');
      final second = store.sendMessage(text: 'two');

      expect(first.scope, AgentConversationOperationScopes.send);
      expect(second.sequence, first.sequence + 1);
      expect(store.state.pendingOperations, <Object>{first, second});
      expect(runner.effects, hasLength(2));
    });

    test('不同作用域各自计数，不互相影响', () {
      final runner = _RecordingRunner();
      final store = _store(runner);
      addTearDown(store.dispose);

      final send = store.sendMessage(text: 'one');
      final cancel = store.cancelActiveTurn();

      expect(send.scope, AgentConversationOperationScopes.send);
      expect(cancel.scope, AgentConversationOperationScopes.cancel);
      expect(cancel.sequence, 1);
    });

    test('状态未变时不发布，避免无谓 rebuild', () {
      final runner = _RecordingRunner();
      final store = _store(runner);
      addTearDown(store.dispose);
      var notifications = 0;
      store.addListener(() => notifications += 1);

      store.refreshRegions(const AgentConversationRegionsRefreshed());
      // 同值 region 也不该触发发布。
      store.refreshRegions(
        AgentConversationRegionsRefreshed(header: agentHeaderStateFixture()),
      );

      expect(notifications, 0);
      expect(store.diagnostics.publishCount, 0);
      expect(store.diagnostics.dispatchCount, 2);
    });

    test('region 变化发布一次', () {
      final runner = _RecordingRunner();
      final store = _store(runner);
      addTearDown(store.dispose);
      var notifications = 0;
      store.addListener(() => notifications += 1);

      store.refreshRegions(
        AgentConversationRegionsRefreshed(
          header: agentHeaderStateFixture(title: '新标题'),
        ),
      );

      expect(notifications, 1);
      expect(store.value.header.title, '新标题');
    });

    test('迟到结果被丢弃并计数', () {
      final runner = _RecordingRunner();
      final store = _store(runner);
      addTearDown(store.dispose);

      final first = store.sendMessage(text: 'one');
      store.completeCommand(first);
      // 同一个身份再回一次：已经不在途，必须丢弃。
      store.completeCommand(first);

      expect(store.state.pendingOperations, isEmpty);
      expect(store.diagnostics.staleResultCount, 1);
    });

    test('失败结果记录消息，随下一次命令清空', () {
      final runner = _RecordingRunner();
      final store = _store(runner);
      addTearDown(store.dispose);

      final first = store.sendMessage(text: 'one');
      store.failCommand(first, '发送失败');
      expect(store.state.lastFailure?.message, '发送失败');

      store.sendMessage(text: 'two');
      expect(store.state.lastFailure, isNull);
    });

    test('dispose 后拒绝一切写入', () {
      final runner = _RecordingRunner();
      final store = _store(runner);

      store.dispose();
      store.sendMessage(text: 'ignored');

      expect(store.isClosed, isTrue);
      expect(runner.effects, isEmpty);
      expect(store.diagnostics.dispatchCount, 0);
    });

    test('两个 store 完全隔离：身份、状态、effect 互不影响', () {
      final firstRunner = _RecordingRunner();
      final secondRunner = _RecordingRunner();
      final first = _store(firstRunner);
      final second = _store(secondRunner);
      addTearDown(first.dispose);
      addTearDown(second.dispose);

      final firstOperation = first.sendMessage(text: 'a');
      second.refreshRegions(
        AgentConversationRegionsRefreshed(
          header: agentHeaderStateFixture(title: '第二个会话'),
        ),
      );

      expect(first.state.pendingOperations, <Object>{firstOperation});
      expect(second.state.pendingOperations, isEmpty);
      expect(first.state.header.title, 'Thread');
      expect(second.state.header.title, '第二个会话');
      expect(firstRunner.effects, hasLength(1));
      expect(secondRunner.effects, isEmpty);
    });

    test('dispose 其一不影响另一个', () {
      final firstRunner = _RecordingRunner();
      final secondRunner = _RecordingRunner();
      final first = _store(firstRunner);
      final second = _store(secondRunner);
      addTearDown(second.dispose);

      first.dispose();
      final operation = second.sendMessage(text: 'still works');

      expect(second.isClosed, isFalse);
      expect(second.state.pendingOperations, <Object>{operation});
      expect(
        secondRunner.effects.single,
        isA<AgentConversationSendMessageEffect>(),
      );
    });

    test('四种审批语义各走各的作用域（G5）', () {
      final runner = _RecordingRunner();
      final store = _store(runner);
      addTearDown(store.dispose);

      store.dispatch(
        AgentConversationRegionsRefreshed(
          pendingInteractions: agentPendingInteractionStateFixture(),
        ),
      );

      expect(
        store.state.hasPendingOperationInScope(
          AgentConversationOperationScopes.permission,
        ),
        isFalse,
      );
      expect(
        store.state.hasPendingOperationInScope(
          AgentConversationOperationScopes.question,
        ),
        isFalse,
      );
    });
  });
}

AgentConversationSliceStore _store(AgentConversationSliceEffectRunner runner) {
  return AgentConversationSliceStore(
    initialState: AgentConversationSliceState(
      header: agentHeaderStateFixture(),
      composer: agentComposerStateFixture(),
      pendingInteractions: agentPendingInteractionStateFixture(),
      expansion: agentExpansionStateFixture(),
      history: agentConversationHistoryStateFixture(),
    ),
    effectRunner: runner,
  );
}

final class _RecordingRunner implements AgentConversationSliceEffectRunner {
  final List<AgentConversationSliceEffect> effects =
      <AgentConversationSliceEffect>[];

  @override
  void run(AgentConversationSliceEffect effect) => effects.add(effect);
}

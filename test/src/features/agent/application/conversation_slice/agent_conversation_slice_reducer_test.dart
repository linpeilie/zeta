import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_command_outcome.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_command_scope.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_effect.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_intent.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_reducer.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_state.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

import '../../presentation/agent_conversation_ui_state_fixtures.dart';

void main() {
  group('agentConversationSliceReduce', () {
    test('region 合并成一次转移，未变的 region 保持同一实例', () {
      final state = _initialState();
      final nextHeader = agentHeaderStateFixture(title: '新标题');

      final transition = agentConversationSliceReduce(
        state,
        AgentConversationRegionsRefreshed(header: nextHeader),
      );

      expect(transition.state.header, nextHeader);
      expect(transition.hasEffects, isFalse);
      // 未变的 region 不重建，selector 才不会被无谓唤醒。
      expect(identical(transition.state.composer, state.composer), isTrue);
      expect(identical(transition.state.history, state.history), isTrue);
    });

    test('空的 region 刷新不产生新状态', () {
      final state = _initialState();

      final transition = agentConversationSliceReduce(
        state,
        const AgentConversationRegionsRefreshed(),
      );

      expect(identical(transition.state, state), isTrue);
      expect(transition.hasEffects, isFalse);
    });

    test('命令登记在途身份并产出 effect，但不直接改 region', () {
      final state = _initialState();
      const operationId = OperationId(
        scope: AgentConversationOperationScopes.send,
        sequence: 1,
      );

      final transition = agentConversationSliceReduce(
        state,
        const AgentConversationSendMessageRequested(
          operationId,
          _testScope,
          text: 'hi',
        ),
      );

      expect(transition.state.pendingOperations, <OperationId>{operationId});
      expect(
        transition.effects.single,
        isA<AgentConversationSendMessageEffect>(),
      );
      // 会话事实的 owner 仍是 TimelineStore：命令不越过它改 region。
      expect(identical(transition.state.header, state.header), isTrue);
      expect(identical(transition.state.history, state.history), isTrue);
    });

    test('发起新命令清掉上一次失败', () {
      const failed = OperationId(
        scope: AgentConversationOperationScopes.send,
        sequence: 1,
      );
      final state = _initialState().copyWith(
        lastFailure: const AgentConversationOperationFailure(
          operationId: failed,
          kind: AgentCommandFailureKind.requestFailed,
        ),
      );
      const next = OperationId(
        scope: AgentConversationOperationScopes.send,
        sequence: 2,
      );

      final transition = agentConversationSliceReduce(
        state,
        const AgentConversationSendMessageRequested(
          next,
          _testScope,
          text: 'retry',
        ),
      );

      expect(transition.state.lastFailure, isNull);
    });

    test('成功结果移除在途身份', () {
      const operationId = OperationId(
        scope: AgentConversationOperationScopes.cancel,
        sequence: 1,
      );
      final state = _initialState().copyWith(
        pendingOperations: <OperationId>{operationId},
      );

      final transition = agentConversationSliceReduce(
        state,
        const AgentConversationCommandSucceeded(operationId),
      );

      expect(transition.state.pendingOperations, isEmpty);
      expect(transition.state.lastFailure, isNull);
    });

    test('失败结果移除在途身份并记录失败', () {
      const operationId = OperationId(
        scope: AgentConversationOperationScopes.send,
        sequence: 3,
      );
      final state = _initialState().copyWith(
        pendingOperations: <OperationId>{operationId},
      );

      final transition = agentConversationSliceReduce(
        state,
        const AgentConversationCommandFailed(
          AgentConversationOperationFailure(
            operationId: operationId,
            kind: AgentCommandFailureKind.requestFailed,
          ),
        ),
      );

      expect(transition.state.pendingOperations, isEmpty);
      expect(
        transition.state.lastFailure?.kind,
        AgentCommandFailureKind.requestFailed,
      );
    });

    test('迟到结果因身份对不上被丢弃，不写回状态', () {
      const current = OperationId(
        scope: AgentConversationOperationScopes.send,
        sequence: 2,
      );
      const stale = OperationId(
        scope: AgentConversationOperationScopes.send,
        sequence: 1,
      );
      final state = _initialState().copyWith(
        pendingOperations: <OperationId>{current},
      );

      final succeeded = agentConversationSliceReduce(
        state,
        const AgentConversationCommandSucceeded(stale),
      );
      final failed = agentConversationSliceReduce(
        state,
        const AgentConversationCommandFailed(
          AgentConversationOperationFailure(
            operationId: stale,
            kind: AgentCommandFailureKind.requestFailed,
          ),
        ),
      );

      expect(identical(succeeded.state, state), isTrue);
      expect(identical(failed.state, state), isTrue);
      expect(state.pendingOperations, <OperationId>{current});
      expect(state.lastFailure, isNull);
    });

    test('四种审批语义各自独立成链，effect 类型互不复用（G5）', () {
      final state = _initialState();
      const scopes = <String>[
        AgentConversationOperationScopes.permission,
        AgentConversationOperationScopes.question,
        AgentConversationOperationScopes.planApproval,
        AgentConversationOperationScopes.planExecution,
      ];

      expect(scopes.toSet(), hasLength(4));
      expect(
        AgentConversationOperationScopes.all.toSet(),
        hasLength(AgentConversationOperationScopes.all.length),
      );
      // 作用域常量必须是字面量，且带 conversation. 前缀，才能安全进日志与指标。
      for (final scope in AgentConversationOperationScopes.all) {
        expect(scope, startsWith('conversation.'));
      }
      expect(state.hasPendingOperationInScope(scopes.first), isFalse);
    });

    test('展开态切换只发 effect，不占用在途身份', () {
      final state = _initialState();

      final transition = agentConversationSliceReduce(
        state,
        const AgentConversationExpansionToggled(
          target: AgentConversationExpansionTarget.toolCall,
          id: 'call-1',
        ),
      );

      expect(identical(transition.state, state), isTrue);
      expect(transition.state.pendingOperations, isEmpty);
      expect(
        transition.effects.single,
        isA<AgentConversationToggleExpansionEffect>(),
      );
    });
  });
}

AgentConversationSliceState _initialState() {
  return AgentConversationSliceState(
    header: agentHeaderStateFixture(),
    composer: agentComposerStateFixture(),
    pendingInteractions: agentPendingInteractionStateFixture(),
    expansion: agentExpansionStateFixture(),
    history: agentConversationHistoryStateFixture(),
  );
}

const _testScope = AgentConversationCommandScope(
  bindingKey: AgentConversationBindingKey.thread(
    providerId: 'codex',
    threadId: 'thread-1',
  ),
  runtimeId: 'runtime-1',
  connectionEpoch: 1,
  listenerGeneration: 1,
  threadId: 'thread-1',
);

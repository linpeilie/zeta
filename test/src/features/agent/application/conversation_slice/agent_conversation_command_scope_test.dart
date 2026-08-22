import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_command_scope.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

const _threadKey = AgentConversationBindingKey.thread(
  providerId: 'codex',
  threadId: 'thread-1',
);
const _otherThreadKey = AgentConversationBindingKey.thread(
  providerId: 'codex',
  threadId: 'thread-2',
);
const _draftKey = AgentConversationBindingKey.draft(
  providerId: 'codex',
  entryId: 'entry-1',
);

void main() {
  group('AgentConversationCommandScope', () {
    const bound = AgentConversationCommandScope(
      bindingKey: _threadKey,
      runtimeId: 'runtime-1',
      connectionEpoch: 1,
      listenerGeneration: 3,
      threadId: 'thread-1',
    );

    test('同一个世界：两次校验都通过', () {
      expect(bound.matchesForExecution(bound), isTrue);
      expect(bound.matchesForCommit(bound), isTrue);
    });

    test('runtime 换代：两次校验都拒绝', () {
      const restarted = AgentConversationCommandScope(
        bindingKey: _threadKey,
        runtimeId: 'runtime-1',
        connectionEpoch: 2,
        listenerGeneration: 4,
        threadId: 'thread-1',
      );

      expect(bound.matchesForExecution(restarted), isFalse);
      expect(bound.matchesForCommit(restarted), isFalse);
    });

    test('换了 runtime 实例：拒绝', () {
      const swapped = AgentConversationCommandScope(
        bindingKey: _threadKey,
        runtimeId: 'runtime-2',
        connectionEpoch: 1,
        listenerGeneration: 3,
        threadId: 'thread-1',
      );

      expect(bound.matchesForCommit(swapped), isFalse);
    });

    test('换了 Binding：拒绝', () {
      const otherEntry = AgentConversationCommandScope(
        bindingKey: _otherThreadKey,
        runtimeId: 'runtime-1',
        connectionEpoch: 1,
        listenerGeneration: 3,
        threadId: 'thread-2',
      );

      expect(bound.matchesForCommit(otherEntry), isFalse);
    });

    test('listener 代数变化：执行前拒绝，回写前放行', () {
      const rebound = AgentConversationCommandScope(
        bindingKey: _threadKey,
        runtimeId: 'runtime-1',
        connectionEpoch: 1,
        listenerGeneration: 4,
        threadId: 'thread-1',
      );

      // 命令自己可能重挂 listener；据此判失效会把正常流程判成 staleTarget。
      expect(bound.matchesForExecution(rebound), isFalse);
      expect(bound.matchesForCommit(rebound), isTrue);
    });

    test('草稿首发：晋升成 thread 仍是同一个世界', () {
      const draft = AgentConversationCommandScope(bindingKey: _draftKey);
      const promoted = AgentConversationCommandScope(
        bindingKey: _threadKey,
        runtimeId: 'runtime-1',
        connectionEpoch: 1,
        listenerGeneration: 2,
        threadId: 'thread-1',
      );

      expect(draft.matchesForExecution(promoted), isTrue);
      expect(draft.matchesForCommit(promoted), isTrue);
    });

    test('thread 不能被改绑成另一个 thread', () {
      const bound2 = AgentConversationCommandScope(bindingKey: _threadKey);
      const other = AgentConversationCommandScope(bindingKey: _otherThreadKey);

      expect(bound2.matchesForCommit(other), isFalse);
    });

    test('失败后 runtime 被拆掉：不改判成 staleTarget', () {
      const tornDown = AgentConversationCommandScope(bindingKey: _threadKey);

      // "现在没有世界" 不等于 "换了个世界"，否则命令自己造成的失败会被
      // 改写成 staleTarget，真实失败原因就丢了。
      expect(bound.matchesForCommit(tornDown), isTrue);
    });
  });
}

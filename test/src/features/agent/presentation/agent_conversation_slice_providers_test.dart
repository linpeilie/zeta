import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_command_scope.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_effect.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_intent.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_state.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_store.dart';
import 'package:zeta/src/features/agent/presentation/conversation_slice/agent_conversation_slice_providers.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'agent_conversation_ui_state_fixtures.dart';

/// 两个 workspace entry 的 Binding 身份。
const _firstKey = AgentConversationBindingKey.thread(
  providerId: 'codex',
  threadId: 'thread-1',
);
const _secondKey = AgentConversationBindingKey.thread(
  providerId: 'codex',
  threadId: 'thread-2',
);
const _draftKey = AgentConversationBindingKey.draft(
  providerId: 'codex',
  entryId: 'entry-1',
);

void main() {
  group('Agent conversation slice providers', () {
    test('默认关闭：任何 key 都没有 store', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(agentConversationSliceEnabledProvider(_firstKey)),
        isFalse,
      );
      expect(
        () => container.read(agentConversationSliceProvider(_firstKey)),
        throwsA(
          predicate<Object>(
            (error) => error.toString().contains('No conversation slice store'),
          ),
        ),
      );
    });

    test('开关按 workspace entry 生效，同一容器里可以只开一个', () {
      final store = _store('会话一');
      addTearDown(store.dispose);
      final container = _container(
        <AgentConversationBindingKey, AgentConversationSliceStore>{
          _firstKey: store,
        },
      );

      expect(
        container.read(agentConversationSliceEnabledProvider(_firstKey)),
        isTrue,
      );
      expect(
        container.read(agentConversationSliceEnabledProvider(_secondKey)),
        isFalse,
      );
    });

    test('同一个容器里两个 entry 完全隔离', () {
      final first = _store('会话一');
      final second = _store('会话二');
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      final container = _container(
        <AgentConversationBindingKey, AgentConversationSliceStore>{
          _firstKey: first,
          _secondKey: second,
        },
      );

      expect(
        container.read(agentConversationHeaderProvider(_firstKey)).title,
        '会话一',
      );
      expect(
        container.read(agentConversationHeaderProvider(_secondKey)).title,
        '会话二',
      );

      // 只推第一个会话，第二个必须纹丝不动。
      first.refreshRegions(
        AgentConversationRegionsRefreshed(
          header: agentHeaderStateFixture(title: '会话一更新了'),
        ),
      );

      expect(
        container.read(agentConversationHeaderProvider(_firstKey)).title,
        '会话一更新了',
      );
      expect(
        container.read(agentConversationHeaderProvider(_secondKey)).title,
        '会话二',
      );
    });

    test('draft 与 thread 是不同的 key，不会互相串', () {
      final draft = _store('草稿');
      final thread = _store('会话');
      addTearDown(draft.dispose);
      addTearDown(thread.dispose);
      final container = _container(
        <AgentConversationBindingKey, AgentConversationSliceStore>{
          _draftKey: draft,
          _firstKey: thread,
        },
      );

      expect(
        container.read(agentConversationHeaderProvider(_draftKey)).title,
        '草稿',
      );
      expect(
        container.read(agentConversationHeaderProvider(_firstKey)).title,
        '会话',
      );
    });

    test('store 变化经 Notifier 反映到 selector', () {
      final store = _store();
      addTearDown(store.dispose);
      final container = _container(
        <AgentConversationBindingKey, AgentConversationSliceStore>{
          _firstKey: store,
        },
      );

      expect(
        container.read(agentConversationHeaderProvider(_firstKey)).title,
        'Thread',
      );

      store.refreshRegions(
        AgentConversationRegionsRefreshed(
          header: agentHeaderStateFixture(title: '新标题'),
        ),
      );

      expect(
        container.read(agentConversationHeaderProvider(_firstKey)).title,
        '新标题',
      );
    });

    test('只变 header 时，其余 region selector 不重新计算', () {
      final store = _store();
      addTearDown(store.dispose);
      final container = _container(
        <AgentConversationBindingKey, AgentConversationSliceStore>{
          _firstKey: store,
        },
      );

      var composerBuilds = 0;
      final probe = Provider<int>((ref) {
        ref.watch(agentConversationComposerProvider(_firstKey));
        return composerBuilds += 1;
      });

      container.read(probe);
      expect(composerBuilds, 1);

      store.refreshRegions(
        AgentConversationRegionsRefreshed(
          header: agentHeaderStateFixture(title: '只改头栏'),
        ),
      );
      container.read(probe);

      // composer 引用没变，selector 不应把它重算一遍。
      expect(composerBuilds, 1);
      expect(
        container.read(agentConversationHeaderProvider(_firstKey)).title,
        '只改头栏',
      );
    });

    test('容器 dispose 只摘监听，不释放 store', () {
      final store = _store();
      addTearDown(store.dispose);
      final container = _container(
        <AgentConversationBindingKey, AgentConversationSliceStore>{
          _firstKey: store,
        },
      );
      container.read(agentConversationSliceProvider(_firstKey));

      container.dispose();

      // store 的生命周期跟随 workspace entry 的 binding lease。
      expect(store.isClosed, isFalse);
      store.refreshRegions(
        AgentConversationRegionsRefreshed(
          header: agentHeaderStateFixture(title: '仍然可用'),
        ),
      );
      expect(store.state.header.title, '仍然可用');
    });

    test('invalidate 一个 key 不影响另一个 key 的监听', () {
      final first = _store('会话一');
      final second = _store('会话二');
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      final container = _container(
        <AgentConversationBindingKey, AgentConversationSliceStore>{
          _firstKey: first,
          _secondKey: second,
        },
      );
      container.read(agentConversationSliceProvider(_firstKey));
      container.read(agentConversationSliceProvider(_secondKey));

      container.invalidate(agentConversationSliceProvider(_firstKey));

      second.refreshRegions(
        AgentConversationRegionsRefreshed(
          header: agentHeaderStateFixture(title: '第二个仍在更新'),
        ),
      );
      expect(
        container.read(agentConversationHeaderProvider(_secondKey)).title,
        '第二个仍在更新',
      );
    });
  });
}

ProviderContainer _container(
  Map<AgentConversationBindingKey, AgentConversationSliceStore> stores,
) {
  final container = ProviderContainer(
    overrides: [
      agentConversationSliceStoreResolverProvider.overrideWith(
        () => AgentConversationSliceStoreResolverNotifier((key) => stores[key]),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

AgentConversationSliceStore _store([String title = 'Thread']) {
  return AgentConversationSliceStore(
    initialState: AgentConversationSliceState(
      header: agentHeaderStateFixture(title: title),
      composer: agentComposerStateFixture(),
      pendingInteractions: agentPendingInteractionStateFixture(),
      expansion: agentExpansionStateFixture(),
      history: agentConversationHistoryStateFixture(),
    ),
    effectRunner: _NoopRunner(),
    scopeSnapshot: () =>
        const AgentConversationCommandScope(bindingKey: _firstKey),
  );
}

final class _NoopRunner implements AgentConversationSliceEffectRunner {
  @override
  void run(AgentConversationSliceEffect effect) {}
}

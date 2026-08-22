import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_effect.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_intent.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_providers.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_state.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_store.dart';

import '../../presentation/agent_conversation_ui_state_fixtures.dart';

void main() {
  group('Agent conversation slice providers', () {
    test('未覆盖 store 时 fail-closed，不静默降级', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Riverpod 3 会把 provider 内抛出的异常包成 ProviderException，
      // 这里断言"确实炸了且原因是缺覆盖"，而不是给个空实现静默降级。
      expect(
        () => container.read(agentConversationSliceProvider),
        throwsA(
          predicate<Object>(
            (error) => error.toString().contains('must be overridden'),
          ),
        ),
      );
    });

    test('切片开关默认关闭，按 workspace entry 覆盖', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(agentConversationSliceEnabledProvider), isFalse);

      final enabled = ProviderContainer(
        overrides: [
          agentConversationSliceEnabledProvider.overrideWithValue(true),
        ],
      );
      addTearDown(enabled.dispose);
      expect(enabled.read(agentConversationSliceEnabledProvider), isTrue);
    });

    test('store 变化经 Notifier 反映到 selector', () {
      final store = _store();
      addTearDown(store.dispose);
      final container = _container(store);

      expect(container.read(agentConversationHeaderProvider).title, 'Thread');

      store.refreshRegions(
        AgentConversationRegionsRefreshed(
          header: agentHeaderStateFixture(title: '新标题'),
        ),
      );

      expect(container.read(agentConversationHeaderProvider).title, '新标题');
    });

    test('只变 header 时，其余 region selector 不重新计算', () {
      final store = _store();
      addTearDown(store.dispose);
      final container = _container(store);

      var composerBuilds = 0;
      final probe = Provider<int>((ref) {
        ref.watch(agentConversationComposerProvider);
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
      expect(container.read(agentConversationHeaderProvider).title, '只改头栏');
    });

    test('两个容器各自持有独立 store，互不串扰', () {
      final firstStore = _store();
      final secondStore = _store();
      addTearDown(firstStore.dispose);
      addTearDown(secondStore.dispose);
      final first = _container(firstStore);
      final second = _container(secondStore);

      firstStore.refreshRegions(
        AgentConversationRegionsRefreshed(
          header: agentHeaderStateFixture(title: '会话一'),
        ),
      );

      expect(first.read(agentConversationHeaderProvider).title, '会话一');
      expect(second.read(agentConversationHeaderProvider).title, 'Thread');
    });

    test('容器 dispose 只摘监听，不释放 store', () {
      final store = _store();
      addTearDown(store.dispose);
      final container = _container(store);
      container.read(agentConversationSliceProvider);

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
  });
}

ProviderContainer _container(AgentConversationSliceStore store) {
  final container = ProviderContainer(
    overrides: [
      agentConversationSliceEnabledProvider.overrideWithValue(true),
      agentConversationSliceStoreProvider.overrideWithValue(store),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

AgentConversationSliceStore _store() {
  return AgentConversationSliceStore(
    initialState: AgentConversationSliceState(
      header: agentHeaderStateFixture(),
      composer: agentComposerStateFixture(),
      pendingInteractions: agentPendingInteractionStateFixture(),
      expansion: agentExpansionStateFixture(),
      history: agentConversationHistoryStateFixture(),
    ),
    effectRunner: _NoopRunner(),
  );
}

final class _NoopRunner implements AgentConversationSliceEffectRunner {
  @override
  void run(AgentConversationSliceEffect effect) {}
}

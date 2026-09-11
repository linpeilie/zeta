import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_runtime_controller.dart';
import 'package:zeta/src/features/agent/presentation/agent_pane.dart';
import 'package:zeta/src/features/agent/presentation/agent_pane_presentation_store.dart';

import '../../../testing/conversation_test_scope.dart';
import 'harness/agent_pane_test_harness.dart';

void main() {
  group('AgentPanePresentationStore', () {
    test('cacheFor 对同一身份返回同一实例', () {
      final store = AgentPanePresentationStore();
      final identity = Object();
      final first = store.cacheFor(identity);

      expect(store.cacheFor(identity), same(first));
    });

    test('closeEntry 释放 Markdown 缓存，再次 cacheFor 得到新实例', () {
      final store = AgentPanePresentationStore();
      final identity = Object();
      final first = store.cacheFor(identity);
      first.markdownCache.acquire(messageId: 'm1', data: '# Hi').release();
      final planController = first.planRevisionDrafts.controllerFor('plan-1');
      planController.text = 'revise';

      store.closeEntry(identity);
      store.closeEntry(identity);

      expect(
        () => first.markdownCache.acquire(messageId: 'm1', data: '# Hi'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'AgentMarkdownCache 已释放。',
          ),
        ),
      );
      expect(
        first.planRevisionDrafts.controllerFor('plan-1'),
        isNot(same(planController)),
      );

      final second = store.cacheFor(identity);
      expect(second, isNot(same(first)));
      expect(second.markdownCache, isNot(same(first.markdownCache)));
      second.markdownCache.acquire(messageId: 'm1', data: '# Hi').release();
      expect(second.markdownCache.debugCreatedControllerCount, 1);
      expect(second.markdownCache.debugControllerHitCount, 0);
    });
  });

  group('AgentPane presentation cache', () {
    testWidgets('pane 重建后仍命中同一 Markdown 缓存', (tester) async {
      final paneKey = GlobalKey();
      final provider = AgentPaneFakeProvider();
      final viewModel = createAgentPaneViewModel(
        provider,
        initialThread: agentPaneThread(
          id: 'thread-md-cache',
          title: 'Markdown cache',
        ),
      );
      addTearDown(provider.dispose);
      addTearDown(viewModel.dispose);
      final sliceStores = _sliceStoresFor(viewModel);

      await tester.pumpWidget(
        AgentPaneTestApp(
          viewModel: viewModel,
          agentPaneKey: paneKey,
          sliceStores: sliceStores,
        ),
      );
      await viewModel.initialization;
      await pumpAgentPaneUi(tester);

      final firstCache = AgentPane.debugMarkdownCache(paneKey);
      final createdBefore = firstCache.debugCreatedControllerCount;
      firstCache
          .acquire(messageId: 'w3-md-cache-probe', data: '# Hello')
          .release();
      expect(firstCache.debugCreatedControllerCount, createdBefore + 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        AgentPaneTestApp(
          viewModel: viewModel,
          agentPaneKey: paneKey,
          sliceStores: sliceStores,
        ),
      );
      await pumpAgentPaneUi(tester);

      final secondCache = AgentPane.debugMarkdownCache(paneKey);
      expect(secondCache, same(firstCache));
      final hitsAfterRemount = secondCache.debugControllerHitCount;
      final createdAfterRemount = secondCache.debugCreatedControllerCount;
      secondCache
          .acquire(messageId: 'w3-md-cache-probe', data: '# Hello')
          .release();
      expect(secondCache.debugCreatedControllerCount, createdAfterRemount);
      expect(secondCache.debugControllerHitCount, hitsAfterRemount + 1);
    });

    testWidgets('controller 换代不销毁旧会话缓存', (tester) async {
      final paneKey = GlobalKey();
      final first = _createPaneFixture('thread-md-cache-a');
      final second = _createPaneFixture('thread-md-cache-b');
      final sliceStores =
          <AgentConversationBindingKey, AgentConversationSliceNotifier>{
            ...first.sliceStores,
            ...second.sliceStores,
          };

      await tester.pumpWidget(
        AgentPaneTestApp(
          viewModel: first.viewModel,
          agentPaneKey: paneKey,
          sliceStores: sliceStores,
        ),
      );
      await first.viewModel.initialization;
      await pumpAgentPaneUi(tester);

      final firstCache = AgentPane.debugMarkdownCache(paneKey);
      firstCache.acquire(messageId: 'm1', data: '# First').release();

      await tester.pumpWidget(
        AgentPaneTestApp(
          viewModel: second.viewModel,
          agentPaneKey: paneKey,
          sliceStores: sliceStores,
        ),
      );
      await second.viewModel.initialization;
      await pumpAgentPaneUi(tester);

      final secondCache = AgentPane.debugMarkdownCache(paneKey);
      expect(secondCache, isNot(same(firstCache)));
      firstCache.acquire(messageId: 'm1', data: '# First').release();
      expect(firstCache.debugControllerHitCount, 1);
      firstCache.acquire(messageId: 'm2', data: '# Still alive').release();

      await tester.pumpWidget(
        AgentPaneTestApp(
          viewModel: first.viewModel,
          agentPaneKey: paneKey,
          sliceStores: sliceStores,
        ),
      );
      await pumpAgentPaneUi(tester);

      expect(AgentPane.debugMarkdownCache(paneKey), same(firstCache));
    });
  });
}

({
  AgentConversationRuntimeController viewModel,
  Map<AgentConversationBindingKey, AgentConversationSliceNotifier> sliceStores,
})
_createPaneFixture(String threadId) {
  final provider = AgentPaneFakeProvider();
  addTearDown(provider.dispose);
  final viewModel = createAgentPaneViewModel(
    provider,
    initialThread: agentPaneThread(id: threadId, title: threadId),
  );
  addTearDown(viewModel.dispose);
  return (viewModel: viewModel, sliceStores: _sliceStoresFor(viewModel));
}

Map<AgentConversationBindingKey, AgentConversationSliceNotifier>
_sliceStoresFor(AgentConversationRuntimeController viewModel) {
  final owner = connectedConversationTestOwner(
    regions: viewModel,
    commands: viewModel,
  );
  return <AgentConversationBindingKey, AgentConversationSliceNotifier>{
    viewModel.conversationBinding.key: owner,
  };
}

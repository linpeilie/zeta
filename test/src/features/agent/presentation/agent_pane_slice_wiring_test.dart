import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_intent.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_store.dart';
import 'package:zeta/src/features/agent/presentation/conversation_slice/agent_conversation_slice_binding.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'agent_conversation_ui_state_fixtures.dart';
import 'harness/agent_pane_test_harness.dart';

/// Phase 2 E 步验收：AgentPane 通过 selector 订阅切片。
///
/// 两条路径给出的是**同一批 region 对象**，所以这里主要证明三件事：
/// 渲染等价、按 entry 生效、切片确实是数据来源（撤掉 store 就回退）。
void main() {
  group('AgentPane 切片接线', () {
    testWidgets('切片开启时渲染与旧路径一致', (tester) async {
      final provider = AgentPaneFakeProvider();
      final viewModel = createAgentPaneViewModel(
        provider,
        initialThread: agentPaneThread(id: 'thread-1', title: '会话一'),
      );
      addTearDown(viewModel.dispose);
      final binding = AgentConversationSliceBinding(viewModel: viewModel);
      addTearDown(binding.dispose);

      await tester.pumpWidget(
        AgentPaneTestApp(
          viewModel: viewModel,
          sliceStores:
              <AgentConversationBindingKey, AgentConversationSliceStore>{
                viewModel.conversationBinding.key: binding.store,
              },
        ),
      );
      await pumpAgentPaneUi(tester);

      expect(find.text('会话一'), findsWidgets);
    });

    testWidgets('未注册 store 的 entry 走旧路径，仍然渲染', (tester) async {
      final provider = AgentPaneFakeProvider();
      final viewModel = createAgentPaneViewModel(
        provider,
        initialThread: agentPaneThread(id: 'thread-1', title: '会话一'),
      );
      addTearDown(viewModel.dispose);

      // sliceStores 为空 = 切片对这个 entry 关闭。
      await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
      await pumpAgentPaneUi(tester);

      expect(find.text('会话一'), findsWidgets);
    });

    testWidgets('切片确实是数据来源：只推 store 也会渲染出来', (tester) async {
      final provider = AgentPaneFakeProvider();
      final viewModel = createAgentPaneViewModel(
        provider,
        initialThread: agentPaneThread(id: 'thread-1', title: '会话一'),
      );
      addTearDown(viewModel.dispose);
      final binding = AgentConversationSliceBinding(viewModel: viewModel);
      addTearDown(binding.dispose);

      await tester.pumpWidget(
        AgentPaneTestApp(
          viewModel: viewModel,
          sliceStores:
              <AgentConversationBindingKey, AgentConversationSliceStore>{
                viewModel.conversationBinding.key: binding.store,
              },
        ),
      );
      await pumpAgentPaneUi(tester);

      // **只**往切片 store 里推，不碰 ViewModel：走旧路径的话这个标题不会出现，
      // 因此这条断言能区分"真的接上了 selector"和"看起来接上了"。
      binding.store.refreshRegions(
        AgentConversationRegionsRefreshed(
          header: agentHeaderStateFixture(title: '只存在于切片里的标题'),
        ),
      );
      await pumpAgentPaneUi(tester);

      expect(find.text('只存在于切片里的标题'), findsWidgets);
    });
  });
}

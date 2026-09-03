import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_intent.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_store.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'agent_conversation_ui_state_fixtures.dart';
import 'harness/agent_pane_test_harness.dart';

/// Conversation 单一路径验收：AgentPane 只通过 selector 订阅切片。
///
/// 这里主要证明三件事：渲染正确、每个 entry 都必建 store、切片确实是唯一数据来源。
void main() {
  group('AgentPane 切片单一路径接线', () {
    testWidgets('显式注入的切片 store 正常渲染', (tester) async {
      final provider = AgentPaneFakeProvider();
      final viewModel = createAgentPaneViewModel(
        provider,
        initialThread: agentPaneThread(id: 'thread-1', title: '会话一'),
      );
      addTearDown(viewModel.dispose);
      final store = AgentConversationSliceStore.connected(
        regions: viewModel.runtime,
        commands: viewModel.runtime,
      );
      addTearDown(store.dispose);

      await tester.pumpWidget(
        AgentPaneTestApp(
          viewModel: viewModel,
          sliceStores:
              <AgentConversationBindingKey, AgentConversationSliceStore>{
                viewModel.conversationBinding.key: store,
              },
        ),
      );
      await pumpAgentPaneUi(tester);

      expect(find.text('会话一'), findsWidgets);
    });

    testWidgets('Harness 未注入 store 时仍强制创建 store', (tester) async {
      final provider = AgentPaneFakeProvider();
      final viewModel = createAgentPaneViewModel(
        provider,
        initialThread: agentPaneThread(id: 'thread-1', title: '会话一'),
      );
      addTearDown(viewModel.dispose);

      // sliceStores 为空时 Harness 创建必选 store，不存在关闭或回退语义。
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
      final store = AgentConversationSliceStore.connected(
        regions: viewModel.runtime,
        commands: viewModel.runtime,
      );
      addTearDown(store.dispose);

      await tester.pumpWidget(
        AgentPaneTestApp(
          viewModel: viewModel,
          sliceStores:
              <AgentConversationBindingKey, AgentConversationSliceStore>{
                viewModel.conversationBinding.key: store,
              },
        ),
      );
      await pumpAgentPaneUi(tester);

      // **只**往切片 store 里推，不碰 ViewModel，证明 Widget 唯一读取 selector。
      store.refreshRegions(
        AgentConversationRegionsRefreshed(
          header: agentHeaderStateFixture(title: '只存在于切片里的标题'),
        ),
      );
      await pumpAgentPaneUi(tester);

      expect(find.text('只存在于切片里的标题'), findsWidgets);
    });

    testWidgets('深层组件也走 selector：只推 store 的 pending 会渲染出来', (tester) async {
      final viewModel = createAgentPaneViewModel(
        AgentPaneFakeProvider(),
        initialThread: agentPaneThread(id: 'thread-1', title: '会话一'),
      );
      addTearDown(viewModel.dispose);
      final store = AgentConversationSliceStore.connected(
        regions: viewModel.runtime,
        commands: viewModel.runtime,
      );
      addTearDown(store.dispose);

      await tester.pumpWidget(
        AgentPaneTestApp(
          viewModel: viewModel,
          sliceStores:
              <AgentConversationBindingKey, AgentConversationSliceStore>{
                viewModel.conversationBinding.key: store,
              },
        ),
      );
      await viewModel.initialization;
      await pumpAgentPaneUi(tester);
      expect(
        find.byKey(const ValueKey<String>('agent-pending-permission-perm-1')),
        findsNothing,
      );

      // pending dock 在 `agent_pane_sections.dart` 深处，只往切片推以固定唯一读取面。
      store.refreshRegions(
        AgentConversationRegionsRefreshed(
          pendingInteractions: agentPendingInteractionStateFixture(
            permissions: const <AgentPermissionRequest>[
              AgentPermissionRequest(
                id: 'perm-1',
                title: '允许执行命令',
                kind: AgentPermissionKind.commandExecution,
              ),
            ],
          ),
        ),
      );
      await pumpAgentPaneUi(tester);

      expect(
        find.byKey(const ValueKey<String>('agent-pending-permission-perm-1')),
        findsOneWidget,
      );
    });
  });
}

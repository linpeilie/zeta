import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_view_model.dart';
import 'package:zeta/src/ui/core/ide_button.dart';

import 'harness/agent_pane_test_harness.dart';

/// 本地执行交接卡的请求 id 由 `sessionId` + `turnId` 拼出。
const String _handoffId = 'plan-execution:session-1:turn-1';

void main() {
  group('AgentPane plan document card', () {
    testWidgets('本地交接卡在流内渲染，修改按钮随输入启用', (tester) async {
      final provider = AgentPaneModeFakeProvider(
        models: agentPaneModelConfigList,
      );
      final viewModel = createAgentPaneViewModel(provider);
      addTearDown(provider.dispose);
      addTearDown(viewModel.dispose);
      await viewModel.loadModels();
      await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
      await pumpAgentPaneUi(tester);

      await _completePlanTurn(tester, viewModel, provider);

      final execute = find.byKey(
        const ValueKey('agent-plan-execute-$_handoffId'),
      );
      final revise = find.byKey(
        const ValueKey('agent-plan-revise-$_handoffId'),
      );
      final input = find.byKey(
        const ValueKey('agent-plan-revision-input-$_handoffId'),
      );
      await pumpUntilFinder(tester, execute);

      // 交互卡取代折叠「计划」卡，同一份正文不会渲染两次。
      expect(
        find.byKey(const ValueKey('agent-plan-card-plan-final')),
        findsNothing,
      );
      expect(find.text('Implement the change'), findsOneWidget);
      // 模型可在卡内直接切换；主 Composer 此时已隐藏，选择器只剩卡内这一个。
      expect(
        find.byKey(const ValueKey('agent-model-selector')),
        findsOneWidget,
      );

      // 空输入时「修改」不可点。
      expect(tester.widget<IdeButton>(revise).onPressed, isNull);

      await tester.enterText(input, '把第二步拆成两步');
      await pumpAgentPaneUi(tester);
      expect(tester.widget<IdeButton>(revise).onPressed, isNotNull);

      await tester.tap(revise);
      await pumpLiveAgentUi(tester);

      // 「修改」回到 Plan 模式并把修改意见作为新回合发送。
      expect(viewModel.planExecutionRequest, isNull);
      expect(viewModel.selectedConversationMode, AgentConversationModeId.plan);
      expect(provider.sentMessages, contains('把第二步拆成两步'));

      provider.emitEvent(
        const AgentTurnCompletedEvent(sessionId: 'session-1', turnId: 'turn-2'),
      );
      await pumpLiveAgentUi(tester);
    });

    testWidgets('放弃关闭交互卡，计划消息退回折叠卡并恢复 Composer', (tester) async {
      final provider = AgentPaneModeFakeProvider(
        models: agentPaneModelConfigList,
      );
      final viewModel = createAgentPaneViewModel(provider);
      addTearDown(provider.dispose);
      addTearDown(viewModel.dispose);
      await viewModel.loadModels();
      await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
      await pumpAgentPaneUi(tester);

      await _completePlanTurn(tester, viewModel, provider);

      final abandon = find.byKey(
        const ValueKey('agent-plan-abandon-$_handoffId'),
      );
      await pumpUntilFinder(tester, abandon);
      expect(find.byKey(const ValueKey('agent-message-input')), findsNothing);

      await tester.tap(abandon);
      await pumpAgentPaneUi(tester);

      expect(viewModel.planExecutionRequest, isNull);
      expect(
        find.byKey(const ValueKey('agent-plan-execute-$_handoffId')),
        findsNothing,
      );
      // 放弃后计划正文退回默认折叠的「计划」消息卡。
      expect(
        find.byKey(const ValueKey('agent-plan-card-plan-final')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('agent-message-input')), findsOneWidget);
      // 本地交接不向 Provider 回写任何审批结果。
      expect(provider.planDecisions, isEmpty);
    });

    testWidgets('审批卡的修改把意见随 rejected 决定回传 Provider', (tester) async {
      final provider = AgentPaneFakeProvider();
      final viewModel = createAgentPaneViewModel(
        provider,
        initialThread: agentPaneThread(
          id: 'thread-approval',
          title: 'Approval thread',
        ),
      );
      addTearDown(provider.dispose);
      addTearDown(viewModel.dispose);
      await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
      await viewModel.loadModels();
      await viewModel.initialization;
      await viewModel.sendMessage('plan this change');
      await pumpLiveAgentUi(tester);

      provider.emitEvent(
        const AgentPlanApprovalRequestedEvent(
          AgentPlanApprovalRequest(
            id: 'plan-1',
            title: 'Refactor tabs',
            markdown: '1. Inspect\n2. Update',
            sessionId: 'thread-approval',
          ),
        ),
      );
      await pumpAgentPaneUi(tester);

      final revise = find.byKey(const ValueKey('agent-plan-revise-plan-1'));
      expect(tester.widget<IdeButton>(revise).onPressed, isNull);

      await tester.enterText(
        find.byKey(const ValueKey('agent-plan-revision-input-plan-1')),
        '先补一个回归测试',
      );
      await pumpAgentPaneUi(tester);
      await tester.tap(revise);
      await pumpAgentPaneUi(tester);

      // 审批是阻塞请求，修改意见只能随决定回传，不能另发一条消息。
      final decision = provider.planDecisions.single;
      expect(decision.kind, AgentPlanApprovalDecisionKind.rejected);
      expect(decision.reason, '先补一个回归测试');
      expect(provider.sentMessages, hasLength(1));

      provider.emitEvent(
        const AgentTurnCompletedEvent(
          sessionId: 'thread-approval',
          turnId: 'turn-1',
        ),
      );
      await pumpLiveAgentUi(tester);
    });
  });
}

/// 跑完一个 Plan 回合，使本地执行交接卡出现在对话流末尾。
Future<void> _completePlanTurn(
  WidgetTester tester,
  AgentConversationViewModel viewModel,
  AgentPaneModeFakeProvider provider,
) async {
  viewModel.selectConversationMode(AgentConversationModeId.plan);
  await viewModel.sendMessage('plan this change');
  provider.emitEvent(
    const AgentMessageDeltaEvent(
      messageId: 'plan-final',
      delta: '# Final plan\n\n- Implement the change',
      role: AgentMessageRole.agent,
      kind: AgentMessageKind.plan,
      status: AgentMessageStatus.completed,
      sessionId: 'session-1',
      turnId: 'turn-1',
    ),
  );
  provider.emitEvent(
    const AgentTurnCompletedEvent(sessionId: 'session-1', turnId: 'turn-1'),
  );
  await pumpAgentPaneUi(tester);
}

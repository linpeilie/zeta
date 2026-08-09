import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_plan_execution_handoff_controller.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  group('AgentPlanExecutionHandoffController', () {
    test('offers trimmed provider plan for a completed Plan turn', () {
      final controller = AgentPlanExecutionHandoffController();

      final request = controller.offerCompletedPlan(
        sessionId: 'thread-1',
        turnId: 'turn-1',
        status: AgentHistoryTurnStatus.completed,
        modeId: AgentConversationModeId.plan,
        planMarkdown: '  # Plan\n\n- Step one  ',
        planMessageId: 'message-plan',
      );

      expect(request, isNotNull);
      expect(request!.id, 'plan-execution:thread-1:turn-1');
      expect(request.markdown, '# Plan\n\n- Step one');
      // UI 据此在对话流中把这条 plan 消息升级为交互卡。
      expect(request.messageId, 'message-plan');
      expect(controller.pendingRequest, same(request));
    });

    test('builds a numbered fallback from structured plan entries', () {
      final controller = AgentPlanExecutionHandoffController();

      final request = controller.offerCompletedPlan(
        sessionId: 'thread-1',
        turnId: 'turn-1',
        status: AgentHistoryTurnStatus.completed,
        modeId: AgentConversationModeId.plan,
        planMarkdown: null,
        planMessageId: 'message-plan',
        planEntries: const <AgentPlanEntry>[
          AgentPlanEntry(content: ' Inspect the code '),
          AgentPlanEntry(content: ''),
          AgentPlanEntry(content: 'Run tests'),
        ],
      );

      expect(
        request?.markdown,
        '## Execution plan\n\n1. Inspect the code\n2. Run tests',
      );
      // 正文是合成的，没有对应 plan 消息，不能让 UI 误升级别的消息。
      expect(request?.messageId, isNull);
    });

    test('rejects non-Plan, unsuccessful, and empty completions', () {
      final controller = AgentPlanExecutionHandoffController();

      expect(
        controller.offerCompletedPlan(
          sessionId: 'thread-1',
          turnId: 'turn-default',
          status: AgentHistoryTurnStatus.completed,
          modeId: AgentConversationModeId.defaultMode,
          planMarkdown: '# Plan',
        ),
        isNull,
      );
      expect(
        controller.offerCompletedPlan(
          sessionId: 'thread-1',
          turnId: 'turn-failed',
          status: AgentHistoryTurnStatus.failed,
          modeId: AgentConversationModeId.plan,
          planMarkdown: '# Plan',
        ),
        isNull,
      );
      expect(
        controller.offerCompletedPlan(
          sessionId: 'thread-1',
          turnId: 'turn-empty',
          status: AgentHistoryTurnStatus.completed,
          modeId: AgentConversationModeId.plan,
          planMarkdown: '  ',
        ),
        isNull,
      );
      expect(controller.pendingRequest, isNull);
    });

    test('does not resolve a stale request', () {
      final controller = AgentPlanExecutionHandoffController();
      final first = controller.offerCompletedPlan(
        sessionId: 'thread-1',
        turnId: 'turn-1',
        status: AgentHistoryTurnStatus.completed,
        modeId: AgentConversationModeId.plan,
        planMarkdown: '# First',
      )!;
      final second = controller.offerCompletedPlan(
        sessionId: 'thread-1',
        turnId: 'turn-2',
        status: AgentHistoryTurnStatus.completed,
        modeId: AgentConversationModeId.plan,
        planMarkdown: '# Second',
      )!;

      expect(controller.resolve(first), isFalse);
      expect(controller.pendingRequest, same(second));
      expect(controller.resolve(second), isTrue);
      expect(controller.pendingRequest, isNull);
    });
  });
}

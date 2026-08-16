import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_plan_execution_handoff_controller.dart';
import 'package:zeta/src/features/agent/application/agent_provider_runtime_identity.dart';
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

    test('hasStagedProviderPlan is true only for the staged turn', () {
      final controller = AgentPlanExecutionHandoffController();
      expect(
        controller.hasStagedProviderPlan(
          sessionId: 'thread-1',
          turnId: 'turn-1',
        ),
        isFalse,
      );
      expect(
        controller.stageProviderApprovedPlan(
          request: const AgentPlanApprovalRequest(
            id: 'approval-1',
            title: 'Review plan',
            markdown: '# Provider plan',
            sessionId: 'thread-1',
            turnId: 'turn-1',
          ),
          executionPermission: null,
          permissionRuntimeIdentity: null,
        ),
        isTrue,
      );
      expect(
        controller.hasStagedProviderPlan(
          sessionId: 'thread-1',
          turnId: 'turn-1',
        ),
        isTrue,
      );
      expect(
        controller.hasStagedProviderPlan(
          sessionId: 'thread-1',
          turnId: 'turn-2',
        ),
        isFalse,
      );
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

    test(
      'waits for successful terminal after Provider approval and freezes permission',
      () {
        final controller = AgentPlanExecutionHandoffController();
        const runtimeIdentity = AgentProviderRuntimeIdentity(
          providerId: 'provider-1',
          generation: 3,
        );
        const approval = AgentPlanApprovalRequest(
          id: 'approval-1',
          title: 'Review plan',
          markdown: '# Approved plan',
          sessionId: 'thread-1',
          turnId: 'turn-1',
          continuation: AgentPlanApprovalContinuation.localExecutionHandoff,
        );

        expect(
          controller.stageProviderApprovedPlan(
            request: approval,
            executionPermission: const AgentPermissionSelection(
              optionId: 'ask',
            ),
            permissionRuntimeIdentity: runtimeIdentity,
          ),
          isTrue,
        );
        expect(controller.pendingRequest, isNull);

        final request = controller.offerCompletedPlan(
          sessionId: 'thread-1',
          turnId: 'turn-1',
          status: AgentHistoryTurnStatus.completed,
          modeId: AgentConversationModeId.defaultMode,
          planMarkdown: null,
        );

        expect(request, isNotNull);
        expect(request!.markdown, '# Approved plan');
        expect(request.title, 'Review plan');
        final seed = controller.permissionSeedFor(request);
        expect(seed?.selection?.optionId, 'ask');
        expect(seed?.runtimeIdentity, runtimeIdentity);
        expect(seed?.threadId, 'thread-1');

        final interrupted = AgentPlanExecutionHandoffController()
          ..stageProviderApprovedPlan(
            request: approval,
            executionPermission: const AgentPermissionSelection(
              optionId: 'ask',
            ),
            permissionRuntimeIdentity: runtimeIdentity,
          );
        expect(
          interrupted
              .offerCompletedPlan(
                sessionId: 'thread-1',
                turnId: 'turn-1',
                status: AgentHistoryTurnStatus.interrupted,
                modeId: AgentConversationModeId.defaultMode,
                planMarkdown: null,
              )
              ?.markdown,
          '# Approved plan',
        );
      },
    );

    test('drops a Provider-approved candidate on unsuccessful terminal', () {
      final controller = AgentPlanExecutionHandoffController();
      controller.stageProviderApprovedPlan(
        request: const AgentPlanApprovalRequest(
          id: 'approval-1',
          title: 'Review plan',
          markdown: '# Approved plan',
          sessionId: 'thread-1',
          turnId: 'turn-1',
          continuation: AgentPlanApprovalContinuation.localExecutionHandoff,
        ),
        executionPermission: null,
        permissionRuntimeIdentity: null,
      );

      expect(
        controller.offerCompletedPlan(
          sessionId: 'thread-1',
          turnId: 'turn-1',
          status: AgentHistoryTurnStatus.failed,
          modeId: AgentConversationModeId.defaultMode,
          planMarkdown: null,
        ),
        isNull,
      );
      expect(controller.pendingRequest, isNull);
    });

    test(
      'reconciles Plan permission, falls back conservatively, and allows local override',
      () {
        final controller = AgentPlanExecutionHandoffController();
        const runtimeIdentity = AgentProviderRuntimeIdentity(
          providerId: 'provider-1',
          generation: 3,
        );
        final offered = controller.offerCompletedPlan(
          sessionId: 'thread-1',
          turnId: 'turn-1',
          status: AgentHistoryTurnStatus.completed,
          modeId: AgentConversationModeId.plan,
          planMarkdown: '# Plan',
          executionPermission: const AgentPermissionSelection(
            optionId: 'custom-safe',
          ),
          permissionRuntimeIdentity: runtimeIdentity,
        )!;
        const options = <AgentPermissionOption>[
          AgentPermissionOption(id: 'ask', label: 'Ask'),
          AgentPermissionOption(id: 'custom-safe', label: 'Custom safe'),
          AgentPermissionOption(
            id: 'blocked',
            label: 'Blocked',
            allowed: false,
          ),
        ];

        final restored = controller.reconcileExecutionPermission(
          request: offered,
          supportsPermissionSelection: true,
          options: options,
          catalogDefault: const AgentPermissionSelection(optionId: 'ask'),
          currentRuntimeIdentity: runtimeIdentity,
        )!;
        expect(restored.executionPermission?.label, 'Custom safe');
        expect(
          restored.executionPermission?.origin,
          AgentPlanExecutionPermissionOrigin.beforePlan,
        );

        final fallback = controller.reconcileExecutionPermission(
          request: restored,
          supportsPermissionSelection: true,
          options: options,
          catalogDefault: const AgentPermissionSelection(optionId: 'ask'),
          currentRuntimeIdentity: const AgentProviderRuntimeIdentity(
            providerId: 'provider-1',
            generation: 4,
          ),
        )!;
        expect(fallback.executionPermission?.label, 'Ask');
        expect(
          fallback.executionPermission?.origin,
          AgentPlanExecutionPermissionOrigin.catalogDefault,
        );

        final overridden = controller.selectExecutionPermission(
          request: fallback,
          option: options[1],
          currentRuntimeIdentity: const AgentProviderRuntimeIdentity(
            providerId: 'provider-1',
            generation: 4,
          ),
        )!;
        expect(
          overridden.executionPermission?.origin,
          AgentPlanExecutionPermissionOrigin.userOverride,
        );
        expect(
          overridden.executionPermission?.toRequestSnapshot().source,
          AgentPermissionRequestSource.localWorkflowOverride,
        );
      },
    );

    test(
      'blocks selectable permission when catalog has no allowed default',
      () {
        final controller = AgentPlanExecutionHandoffController();
        final offered = controller.offerCompletedPlan(
          sessionId: 'thread-1',
          turnId: 'turn-1',
          status: AgentHistoryTurnStatus.completed,
          modeId: AgentConversationModeId.plan,
          planMarkdown: '# Plan',
        )!;

        final blocked = controller.reconcileExecutionPermission(
          request: offered,
          supportsPermissionSelection: true,
          options: const <AgentPermissionOption>[],
          catalogDefault: null,
          currentRuntimeIdentity: null,
        );

        expect(blocked?.executionPermission, isNull);
        expect(controller.pendingRequest, isNotNull);
      },
    );

    test('uses provider fallback when permission selection is unsupported', () {
      final controller = AgentPlanExecutionHandoffController();
      final offered = controller.offerCompletedPlan(
        sessionId: 'thread-1',
        turnId: 'turn-1',
        status: AgentHistoryTurnStatus.completed,
        modeId: AgentConversationModeId.plan,
        planMarkdown: '# Plan',
      )!;

      final reconciled = controller.reconcileExecutionPermission(
        request: offered,
        supportsPermissionSelection: false,
        options: const <AgentPermissionOption>[],
        catalogDefault: null,
        currentRuntimeIdentity: null,
      );

      expect(
        reconciled?.executionPermission?.origin,
        AgentPlanExecutionPermissionOrigin.providerFallback,
      );
      expect(
        reconciled?.executionPermission?.toRequestSnapshot().source,
        AgentPermissionRequestSource.providerFallback,
      );
    });

    test('discards planningOnly seed and card selection', () {
      final controller = AgentPlanExecutionHandoffController();
      const runtimeIdentity = AgentProviderRuntimeIdentity(
        providerId: 'provider-1',
        generation: 1,
      );
      final offered = controller.offerCompletedPlan(
        sessionId: 'thread-1',
        turnId: 'turn-1',
        status: AgentHistoryTurnStatus.completed,
        modeId: AgentConversationModeId.plan,
        planMarkdown: '# Plan',
        executionPermission: const AgentPermissionSelection(optionId: 'plan'),
        permissionRuntimeIdentity: runtimeIdentity,
      )!;
      const options = <AgentPermissionOption>[
        AgentPermissionOption(id: 'ask', label: 'Ask'),
        AgentPermissionOption(id: 'plan', label: 'Plan', planningOnly: true),
      ];

      final restored = controller.reconcileExecutionPermission(
        request: offered,
        supportsPermissionSelection: true,
        options: options,
        catalogDefault: const AgentPermissionSelection(optionId: 'ask'),
        currentRuntimeIdentity: runtimeIdentity,
      )!;
      expect(restored.executionPermission?.label, 'Ask');
      expect(
        restored.executionPermission?.origin,
        AgentPlanExecutionPermissionOrigin.catalogDefault,
      );

      expect(
        controller.selectExecutionPermission(
          request: restored,
          option: options[1],
          currentRuntimeIdentity: runtimeIdentity,
        ),
        isNull,
      );
      expect(controller.pendingRequest?.executionPermission?.label, 'Ask');
    });

    test(
      'falls back to first executable option when catalog default is planningOnly',
      () {
        final controller = AgentPlanExecutionHandoffController();
        final offered = controller.offerCompletedPlan(
          sessionId: 'thread-1',
          turnId: 'turn-1',
          status: AgentHistoryTurnStatus.completed,
          modeId: AgentConversationModeId.plan,
          planMarkdown: '# Plan',
        )!;
        const options = <AgentPermissionOption>[
          AgentPermissionOption(id: 'plan', label: 'Plan', planningOnly: true),
          AgentPermissionOption(id: 'ask', label: 'Ask'),
        ];

        final reconciled = controller.reconcileExecutionPermission(
          request: offered,
          supportsPermissionSelection: true,
          options: options,
          catalogDefault: const AgentPermissionSelection(optionId: 'plan'),
          currentRuntimeIdentity: null,
        );

        expect(reconciled?.executionPermission?.label, 'Ask');
        expect(
          reconciled?.executionPermission?.origin,
          AgentPlanExecutionPermissionOrigin.catalogDefault,
        );
      },
    );

    test('blocks execute when every allowed option is planningOnly', () {
      final controller = AgentPlanExecutionHandoffController();
      final offered = controller.offerCompletedPlan(
        sessionId: 'thread-1',
        turnId: 'turn-1',
        status: AgentHistoryTurnStatus.completed,
        modeId: AgentConversationModeId.plan,
        planMarkdown: '# Plan',
      )!;

      final blocked = controller.reconcileExecutionPermission(
        request: offered,
        supportsPermissionSelection: true,
        options: const <AgentPermissionOption>[
          AgentPermissionOption(id: 'plan', label: 'Plan', planningOnly: true),
        ],
        catalogDefault: const AgentPermissionSelection(optionId: 'plan'),
        currentRuntimeIdentity: null,
      );

      expect(blocked?.executionPermission, isNull);
    });
  });
}

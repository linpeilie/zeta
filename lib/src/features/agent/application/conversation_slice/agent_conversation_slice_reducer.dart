import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_effect.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_intent.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_state.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

/// 命令作用域常量。
///
/// 只允许写死的字面量：`OperationId` 会进日志与指标，拼入运行期数据就等于泄露。
abstract final class AgentConversationOperationScopes {
  static const String send = 'conversation.send';
  static const String cancel = 'conversation.cancel';
  static const String editLastMessage = 'conversation.editLastMessage';
  static const String retryOpen = 'conversation.retryOpen';
  static const String permission = 'conversation.permission';
  static const String question = 'conversation.question';
  static const String planApproval = 'conversation.planApproval';
  static const String planExecution = 'conversation.planExecution';
  static const String guardianOverride = 'conversation.guardianOverride';
  static const String threadMutation = 'conversation.threadMutation';
  static const String catalog = 'conversation.catalog';

  /// 全部作用域，供守卫与测试遍历。
  static const List<String> all = <String>[
    send,
    cancel,
    editLastMessage,
    retryOpen,
    permission,
    question,
    planApproval,
    planExecution,
    guardianOverride,
    threadMutation,
    catalog,
  ];
}

/// Agent Conversation 切片的 reducer。
///
/// **纯同步、无副作用**（G3）：不碰时钟、不发请求、不铸造 id。命令意图携带的
/// `OperationId` 由 store 在 dispatch 前生成。
///
/// 切片对会话事实是**只读投影**：命令不直接改 region 状态，只登记在途身份并
/// 产出 effect；真实变化经 `AgentConversationRegionsRefreshed` 回流。这样同一
/// 份事实始终只有一个 owner（迁移门禁第 1、9 条）。
Transition<AgentConversationSliceState, AgentConversationSliceEffect>
agentConversationSliceReduce(
  AgentConversationSliceState state,
  AgentConversationSliceIntent intent,
) {
  switch (intent) {
    // -----------------------------------------------------------------------
    // ingress
    // -----------------------------------------------------------------------
    case AgentConversationRegionsRefreshed():
      if (intent.isEmpty) {
        return Transition<
          AgentConversationSliceState,
          AgentConversationSliceEffect
        >.none(state);
      }
      final next = state.copyWith(
        header: intent.header,
        composer: intent.composer,
        pendingInteractions: intent.pendingInteractions,
        expansion: intent.expansion,
        history: intent.history,
      );
      return Transition<
        AgentConversationSliceState,
        AgentConversationSliceEffect
      >.stateOnly(next);

    // -----------------------------------------------------------------------
    // command
    // -----------------------------------------------------------------------
    case AgentConversationSendMessageRequested():
      return _command(
        state,
        intent.operationId,
        AgentConversationSendMessageEffect(
          intent.operationId,
          text: intent.text,
          localImagePaths: intent.localImagePaths,
          mentions: intent.mentions,
          skills: intent.skills,
        ),
      );

    case AgentConversationActiveTurnCancelRequested():
      return _command(
        state,
        intent.operationId,
        AgentConversationCancelTurnEffect(intent.operationId),
      );

    case AgentConversationLastUserMessageEditRequested():
      return _command(
        state,
        intent.operationId,
        AgentConversationEditLastUserMessageEffect(
          intent.operationId,
          text: intent.text,
        ),
      );

    case AgentConversationThreadOpenRetried():
      return _command(
        state,
        intent.operationId,
        AgentConversationRetryOpenThreadEffect(intent.operationId),
      );

    case AgentConversationPermissionResponded():
      return _command(
        state,
        intent.operationId,
        AgentConversationRespondPermissionEffect(
          intent.operationId,
          request: intent.request,
          approved: intent.approved,
          cancelTurn: intent.cancelTurn,
          commandDecision: intent.commandDecision,
          execpolicyAmendment: intent.execpolicyAmendment,
        ),
      );

    case AgentConversationQuestionResponded():
      return _command(
        state,
        intent.operationId,
        AgentConversationRespondQuestionEffect(
          intent.operationId,
          request: intent.request,
          answers: intent.answers,
        ),
      );

    case AgentConversationPlanApprovalResponded():
      return _command(
        state,
        intent.operationId,
        AgentConversationRespondPlanApprovalEffect(
          intent.operationId,
          request: intent.request,
          decision: intent.decision,
          reason: intent.reason,
        ),
      );

    case AgentConversationPlanExecutionStarted():
      return _command(
        state,
        intent.operationId,
        AgentConversationPlanExecutionEffect(
          intent.operationId,
          request: intent.request,
        ),
      );

    case AgentConversationPlanExecutionRevised():
      return _command(
        state,
        intent.operationId,
        AgentConversationPlanExecutionEffect(
          intent.operationId,
          request: intent.request,
          revisionFeedback: intent.feedback,
        ),
      );

    case AgentConversationGuardianDeniedActionApproved():
      return _command(
        state,
        intent.operationId,
        AgentConversationApproveGuardianDeniedActionEffect(intent.operationId),
      );

    case AgentConversationThreadMutationRequested():
      return _command(
        state,
        intent.operationId,
        AgentConversationThreadMutationEffect(
          intent.operationId,
          kind: intent.kind,
          name: intent.name,
        ),
      );

    case AgentConversationCatalogLoadRequested():
      return _command(
        state,
        intent.operationId,
        AgentConversationLoadCatalogEffect(
          intent.operationId,
          kind: intent.kind,
          forceRefresh: intent.forceRefresh,
        ),
      );

    // -----------------------------------------------------------------------
    // 同步命令：只发 effect，不占用在途身份
    // -----------------------------------------------------------------------
    case AgentConversationExpansionToggled():
      return Transition<
        AgentConversationSliceState,
        AgentConversationSliceEffect
      >(state, <AgentConversationSliceEffect>[
        AgentConversationToggleExpansionEffect(
          target: intent.target,
          id: intent.id,
        ),
      ]);

    case AgentConversationPlanExecutionDismissed():
      return Transition<
        AgentConversationSliceState,
        AgentConversationSliceEffect
      >(state, <AgentConversationSliceEffect>[
        AgentConversationDismissPlanExecutionEffect(intent.request),
      ]);

    // -----------------------------------------------------------------------
    // result：迟到结果先比对身份
    // -----------------------------------------------------------------------
    case AgentConversationCommandSucceeded():
      if (!state.pendingOperations.contains(intent.operationId)) {
        return Transition<
          AgentConversationSliceState,
          AgentConversationSliceEffect
        >.none(state);
      }
      return Transition<
        AgentConversationSliceState,
        AgentConversationSliceEffect
      >.stateOnly(
        state.copyWith(
          pendingOperations: _without(
            state.pendingOperations,
            intent.operationId,
          ),
        ),
      );

    case AgentConversationCommandFailed():
      if (!state.pendingOperations.contains(intent.operationId)) {
        return Transition<
          AgentConversationSliceState,
          AgentConversationSliceEffect
        >.none(state);
      }
      return Transition<
        AgentConversationSliceState,
        AgentConversationSliceEffect
      >.stateOnly(
        state.copyWith(
          pendingOperations: _without(
            state.pendingOperations,
            intent.operationId,
          ),
          lastFailure: intent.failure,
        ),
      );
  }
}

/// 登记在途身份 + 清掉上一次失败 + 产出 effect。
Transition<AgentConversationSliceState, AgentConversationSliceEffect> _command(
  AgentConversationSliceState state,
  OperationId operationId,
  AgentConversationCommandEffect effect,
) {
  final next = state.copyWith(
    pendingOperations: <OperationId>{...state.pendingOperations, operationId},
    clearLastFailure: true,
  );
  return Transition<AgentConversationSliceState, AgentConversationSliceEffect>(
    next,
    <AgentConversationSliceEffect>[effect],
  );
}

Set<OperationId> _without(Set<OperationId> operations, OperationId removed) {
  return Set<OperationId>.unmodifiable(
    operations.where((operation) => operation != removed),
  );
}

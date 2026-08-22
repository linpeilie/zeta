import 'package:flutter/foundation.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_effect.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_intent.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_reducer.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_state.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

/// 执行切片副作用的端口。
///
/// 实现住在 presentation 组合层（调用现有 application port）；切片本身只描述
/// 要做什么，不知道怎么做。
abstract interface class AgentConversationSliceEffectRunner {
  /// 执行一个副作用。
  ///
  /// 命令类副作用完成后必须调用 [AgentConversationSliceStore.completeCommand]
  /// 或 [AgentConversationSliceStore.failCommand] 回写结果。
  void run(AgentConversationSliceEffect effect);
}

/// 切片诊断计数，用于回归测试与帧预算断言。
@immutable
final class AgentConversationSliceDiagnostics {
  const AgentConversationSliceDiagnostics({
    required this.dispatchCount,
    required this.publishCount,
    required this.effectCount,
    required this.staleResultCount,
  });

  /// 收到的 intent 数量。
  final int dispatchCount;

  /// 实际对外发布的状态变化次数（状态未变不发布）。
  final int publishCount;

  /// 交给 runner 的副作用数量。
  final int effectCount;

  /// 因身份对不上而被丢弃的迟到结果数量。
  final int staleResultCount;
}

/// 单个 Agent Conversation 的薄 store。
///
/// 职责只有四件事：
///
/// 1. 为命令意图铸造 [OperationId]（reducer 因此保持纯同步）；
/// 2. 调 reducer，把新状态发布出去（状态相等则不发布）；
/// 3. 把 effect 交给 runner；
/// 4. 关闭后拒绝一切写入。
///
/// 它**不拥有**任何会话事实：region 状态由 ingress 意图带进来，owner 仍是
/// `AgentConversationTimelineStore` 与既有 controller。
final class AgentConversationSliceStore extends ChangeNotifier
    implements ValueListenable<AgentConversationSliceState> {
  AgentConversationSliceStore({
    required AgentConversationSliceState initialState,
    required this._effectRunner,
    OperationIdGenerator Function(String scope)? operationIdGeneratorFactory,
  }) : _state = initialState,
       _generatorFactory =
           operationIdGeneratorFactory ??
           ((scope) => OperationIdGenerator(scope: scope));

  final AgentConversationSliceEffectRunner _effectRunner;
  final OperationIdGenerator Function(String scope) _generatorFactory;
  final Map<String, OperationIdGenerator> _generators =
      <String, OperationIdGenerator>{};

  AgentConversationSliceState _state;
  bool _closed = false;
  int _dispatchCount = 0;
  int _publishCount = 0;
  int _effectCount = 0;
  int _staleResultCount = 0;

  @override
  AgentConversationSliceState get value => _state;

  /// 当前切片状态。
  AgentConversationSliceState get state => _state;

  /// store 是否已关闭。
  bool get isClosed => _closed;

  AgentConversationSliceDiagnostics get diagnostics =>
      AgentConversationSliceDiagnostics(
        dispatchCount: _dispatchCount,
        publishCount: _publishCount,
        effectCount: _effectCount,
        staleResultCount: _staleResultCount,
      );

  /// 分发一个已经带好身份的意图。
  ///
  /// UI 一般不直接调用这个方法，而是用下面的命令入口——它们负责铸造身份。
  void dispatch(AgentConversationSliceIntent intent) {
    if (_closed) {
      return;
    }
    _dispatchCount += 1;
    final before = _state;
    final transition = agentConversationSliceReduce(before, intent);

    if (!identical(transition.state, before) && transition.state != before) {
      _state = transition.state;
      _publishCount += 1;
      notifyListeners();
    } else if (_isStaleResult(before, intent)) {
      _staleResultCount += 1;
    }

    for (final effect in transition.effects) {
      _effectCount += 1;
      _effectRunner.run(effect);
    }
  }

  // -------------------------------------------------------------------------
  // ingress
  // -------------------------------------------------------------------------

  /// 把同一帧变化的 region 合并成一次转移。
  void refreshRegions(AgentConversationRegionsRefreshed intent) =>
      dispatch(intent);

  // -------------------------------------------------------------------------
  // 命令入口：铸造身份 → dispatch
  // -------------------------------------------------------------------------

  OperationId _nextOperationId(String scope) {
    final generator = _generators.putIfAbsent(
      scope,
      () => _generatorFactory(scope),
    );
    return generator.next();
  }

  OperationId sendMessage({
    required String text,
    List<String> localImagePaths = const <String>[],
    List<({String name, String path})> mentions =
        const <({String name, String path})>[],
    List<AgentSkillRef> skills = const <AgentSkillRef>[],
  }) {
    final operationId = _nextOperationId(AgentConversationOperationScopes.send);
    dispatch(
      AgentConversationSendMessageRequested(
        operationId,
        text: text,
        localImagePaths: localImagePaths,
        mentions: mentions,
        skills: skills,
      ),
    );
    return operationId;
  }

  OperationId cancelActiveTurn() {
    final operationId = _nextOperationId(
      AgentConversationOperationScopes.cancel,
    );
    dispatch(AgentConversationActiveTurnCancelRequested(operationId));
    return operationId;
  }

  OperationId editLastUserMessage(String text) {
    final operationId = _nextOperationId(
      AgentConversationOperationScopes.editLastMessage,
    );
    dispatch(
      AgentConversationLastUserMessageEditRequested(operationId, text: text),
    );
    return operationId;
  }

  OperationId retryOpenThread() {
    final operationId = _nextOperationId(
      AgentConversationOperationScopes.retryOpen,
    );
    dispatch(AgentConversationThreadOpenRetried(operationId));
    return operationId;
  }

  /// 权限决定。**独立链路**：不复用提问 / Plan 的任何已授权状态（G5）。
  OperationId respondToPermission(
    AgentPermissionRequest request, {
    required bool approved,
    bool cancelTurn = false,
    AgentCommandApprovalDecisionKind? commandDecision,
    List<String> execpolicyAmendment = const <String>[],
  }) {
    final operationId = _nextOperationId(
      AgentConversationOperationScopes.permission,
    );
    dispatch(
      AgentConversationPermissionResponded(
        operationId,
        request: request,
        approved: approved,
        cancelTurn: cancelTurn,
        commandDecision: commandDecision,
        execpolicyAmendment: execpolicyAmendment,
      ),
    );
    return operationId;
  }

  /// 提问回答。**独立链路**。
  OperationId respondToQuestion(
    AgentQuestionRequest request, {
    Map<String, List<String>> answers = const <String, List<String>>{},
  }) {
    final operationId = _nextOperationId(
      AgentConversationOperationScopes.question,
    );
    dispatch(
      AgentConversationQuestionResponded(
        operationId,
        request: request,
        answers: answers,
      ),
    );
    return operationId;
  }

  /// Plan 审批。**独立链路**。
  OperationId respondToPlanApproval(
    AgentPlanApprovalRequest request,
    AgentPlanApprovalDecisionKind decision, {
    String? reason,
  }) {
    final operationId = _nextOperationId(
      AgentConversationOperationScopes.planApproval,
    );
    dispatch(
      AgentConversationPlanApprovalResponded(
        operationId,
        request: request,
        decision: decision,
        reason: reason,
      ),
    );
    return operationId;
  }

  /// Plan 本地执行交接。**独立链路**。
  OperationId startPlanExecution(AgentPlanExecutionRequest request) {
    final operationId = _nextOperationId(
      AgentConversationOperationScopes.planExecution,
    );
    dispatch(
      AgentConversationPlanExecutionStarted(operationId, request: request),
    );
    return operationId;
  }

  OperationId revisePlanExecution(
    AgentPlanExecutionRequest request, {
    required String feedback,
  }) {
    final operationId = _nextOperationId(
      AgentConversationOperationScopes.planExecution,
    );
    dispatch(
      AgentConversationPlanExecutionRevised(
        operationId,
        request: request,
        feedback: feedback,
      ),
    );
    return operationId;
  }

  void dismissPlanExecution(AgentPlanExecutionRequest request) =>
      dispatch(AgentConversationPlanExecutionDismissed(request));

  OperationId approveGuardianDeniedAction() {
    final operationId = _nextOperationId(
      AgentConversationOperationScopes.guardianOverride,
    );
    dispatch(AgentConversationGuardianDeniedActionApproved(operationId));
    return operationId;
  }

  OperationId mutateThread(
    AgentConversationThreadMutationKind kind, {
    String? name,
  }) {
    final operationId = _nextOperationId(
      AgentConversationOperationScopes.threadMutation,
    );
    dispatch(
      AgentConversationThreadMutationRequested(
        operationId,
        kind: kind,
        name: name,
      ),
    );
    return operationId;
  }

  OperationId loadCatalog(
    AgentConversationCatalogKind kind, {
    bool forceRefresh = false,
  }) {
    final operationId = _nextOperationId(
      AgentConversationOperationScopes.catalog,
    );
    dispatch(
      AgentConversationCatalogLoadRequested(
        operationId,
        kind: kind,
        forceRefresh: forceRefresh,
      ),
    );
    return operationId;
  }

  void toggleExpansion(AgentConversationExpansionTarget target, String id) =>
      dispatch(AgentConversationExpansionToggled(target: target, id: id));

  // -------------------------------------------------------------------------
  // result 回写
  // -------------------------------------------------------------------------

  /// 命令成功。身份对不上（例如已被新一次操作取代）时静默丢弃。
  void completeCommand(OperationId operationId) =>
      dispatch(AgentConversationCommandSucceeded(operationId));

  /// 命令失败。
  void failCommand(OperationId operationId, String message) => dispatch(
    AgentConversationCommandFailed(
      AgentConversationOperationFailure(
        operationId: operationId,
        message: message,
      ),
    ),
  );

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }

  bool _isStaleResult(
    AgentConversationSliceState before,
    AgentConversationSliceIntent intent,
  ) {
    return switch (intent) {
      AgentConversationCommandSucceeded(:final operationId) ||
      AgentConversationCommandFailed(
        :final operationId,
      ) => !before.pendingOperations.contains(operationId),
      _ => false,
    };
  }
}

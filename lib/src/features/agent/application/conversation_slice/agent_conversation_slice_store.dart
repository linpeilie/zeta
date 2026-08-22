import 'package:meta/meta.dart';
import 'package:zeta/src/features/agent/application/agent_command_outcome.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_command_scope.dart';
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
final class AgentConversationSliceStore {
  AgentConversationSliceStore({
    required AgentConversationSliceState initialState,
    required this._effectRunner,
    required this._scopeSnapshot,
    OperationIdGenerator Function(String scope)? operationIdGeneratorFactory,
  }) : _state = initialState,
       _generatorFactory =
           operationIdGeneratorFactory ??
           ((scope) => OperationIdGenerator(scope: scope));

  final AgentConversationSliceEffectRunner _effectRunner;

  /// 拍下"此刻的 Binding / runtime / thread"。
  ///
  /// 由组合层注入：store 在 application 层，读不到 runtime。
  final AgentConversationCommandScope Function() _scopeSnapshot;
  final OperationIdGenerator Function(String scope) _generatorFactory;
  final Map<String, OperationIdGenerator> _generators =
      <String, OperationIdGenerator>{};

  /// 监听器列表。
  ///
  /// 这里刻意**不用 `ChangeNotifier`**：application 层禁止 import Flutter
  /// （目标架构 §12.5）。语义与 `ChangeNotifier` 对齐——通知期间允许增删监听，
  /// 因此遍历前先复制一份快照。
  final List<void Function()> _listeners = <void Function()>[];

  AgentConversationSliceState _state;
  bool _closed = false;
  int _dispatchCount = 0;
  int _publishCount = 0;
  int _effectCount = 0;
  int _staleResultCount = 0;

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
      _notifyListeners();
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

  /// 命令身份 = 操作 id + 发起时的作用域快照。两者在同一时刻拍下。
  ({OperationId operationId, AgentConversationCommandScope scope}) _identity(
    String scope,
  ) {
    return (operationId: _nextOperationId(scope), scope: _scopeSnapshot());
  }

  OperationId sendMessage({
    required String text,
    List<String> localImagePaths = const <String>[],
    List<({String name, String path})> mentions =
        const <({String name, String path})>[],
    List<AgentSkillRef> skills = const <AgentSkillRef>[],
  }) {
    final identity = _identity(AgentConversationOperationScopes.send);
    dispatch(
      AgentConversationSendMessageRequested(
        identity.operationId,
        identity.scope,
        text: text,
        localImagePaths: localImagePaths,
        mentions: mentions,
        skills: skills,
      ),
    );
    return identity.operationId;
  }

  OperationId cancelActiveTurn() {
    final identity = _identity(AgentConversationOperationScopes.cancel);
    dispatch(
      AgentConversationActiveTurnCancelRequested(
        identity.operationId,
        identity.scope,
      ),
    );
    return identity.operationId;
  }

  OperationId editLastUserMessage(String text) {
    final identity = _identity(
      AgentConversationOperationScopes.editLastMessage,
    );
    dispatch(
      AgentConversationLastUserMessageEditRequested(
        identity.operationId,
        identity.scope,
        text: text,
      ),
    );
    return identity.operationId;
  }

  OperationId retryOpenThread() {
    final identity = _identity(AgentConversationOperationScopes.retryOpen);
    dispatch(
      AgentConversationThreadOpenRetried(identity.operationId, identity.scope),
    );
    return identity.operationId;
  }

  /// 权限决定。**独立链路**：不复用提问 / Plan 的任何已授权状态（G5）。
  OperationId respondToPermission(
    AgentPermissionRequest request, {
    required bool approved,
    bool cancelTurn = false,
    AgentCommandApprovalDecisionKind? commandDecision,
    List<String> execpolicyAmendment = const <String>[],
  }) {
    final identity = _identity(AgentConversationOperationScopes.permission);
    dispatch(
      AgentConversationPermissionResponded(
        identity.operationId,
        identity.scope,
        request: request,
        approved: approved,
        cancelTurn: cancelTurn,
        commandDecision: commandDecision,
        execpolicyAmendment: execpolicyAmendment,
      ),
    );
    return identity.operationId;
  }

  /// 提问回答。**独立链路**。
  OperationId respondToQuestion(
    AgentQuestionRequest request, {
    Map<String, List<String>> answers = const <String, List<String>>{},
  }) {
    final identity = _identity(AgentConversationOperationScopes.question);
    dispatch(
      AgentConversationQuestionResponded(
        identity.operationId,
        identity.scope,
        request: request,
        answers: answers,
      ),
    );
    return identity.operationId;
  }

  /// Plan 审批。**独立链路**。
  OperationId respondToPlanApproval(
    AgentPlanApprovalRequest request,
    AgentPlanApprovalDecisionKind decision, {
    String? reason,
  }) {
    final identity = _identity(AgentConversationOperationScopes.planApproval);
    dispatch(
      AgentConversationPlanApprovalResponded(
        identity.operationId,
        identity.scope,
        request: request,
        decision: decision,
        reason: reason,
      ),
    );
    return identity.operationId;
  }

  /// Plan 本地执行交接。**独立链路**。
  OperationId startPlanExecution(AgentPlanExecutionRequest request) {
    final identity = _identity(AgentConversationOperationScopes.planExecution);
    dispatch(
      AgentConversationPlanExecutionStarted(
        identity.operationId,
        identity.scope,
        request: request,
      ),
    );
    return identity.operationId;
  }

  OperationId revisePlanExecution(
    AgentPlanExecutionRequest request, {
    required String feedback,
  }) {
    final identity = _identity(AgentConversationOperationScopes.planExecution);
    dispatch(
      AgentConversationPlanExecutionRevised(
        identity.operationId,
        identity.scope,
        request: request,
        feedback: feedback,
      ),
    );
    return identity.operationId;
  }

  void dismissPlanExecution(AgentPlanExecutionRequest request) =>
      dispatch(AgentConversationPlanExecutionDismissed(request));

  OperationId approveGuardianDeniedAction() {
    final identity = _identity(
      AgentConversationOperationScopes.guardianOverride,
    );
    dispatch(
      AgentConversationGuardianDeniedActionApproved(
        identity.operationId,
        identity.scope,
      ),
    );
    return identity.operationId;
  }

  OperationId mutateThread(
    AgentConversationThreadMutationKind kind, {
    String? name,
  }) {
    final identity = _identity(AgentConversationOperationScopes.threadMutation);
    dispatch(
      AgentConversationThreadMutationRequested(
        identity.operationId,
        identity.scope,
        kind: kind,
        name: name,
      ),
    );
    return identity.operationId;
  }

  OperationId loadCatalog(
    AgentConversationCatalogKind kind, {
    bool forceRefresh = false,
  }) {
    final identity = _identity(AgentConversationOperationScopes.catalog);
    dispatch(
      AgentConversationCatalogLoadRequested(
        identity.operationId,
        identity.scope,
        kind: kind,
        forceRefresh: forceRefresh,
      ),
    );
    return identity.operationId;
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
  ///
  /// 只收**分类**：调用方不得把原始错误文本传进来当 UI 文案。
  void failCommand(OperationId operationId, AgentCommandFailureKind kind) =>
      dispatch(
        AgentConversationCommandFailed(
          AgentConversationOperationFailure(
            operationId: operationId,
            kind: kind,
          ),
        ),
      );

  /// 订阅状态变化。
  void addListener(void Function() listener) {
    if (_closed) {
      return;
    }
    _listeners.add(listener);
  }

  /// 取消订阅；未注册过的监听器会被忽略。
  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners() {
    // 通知期间可能有监听器增删，先复制快照再遍历。
    for (final listener in List<void Function()>.of(_listeners)) {
      listener();
    }
  }

  void dispose() {
    _closed = true;
    _listeners.clear();
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

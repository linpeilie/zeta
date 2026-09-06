import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:flutter_riverpod/misc.dart' show KeepAliveLink;
import 'agent_conversation_owner_key.dart';
import 'agent_conversation_session_dependencies.dart';
import 'package:zeta/src/features/agent/application/agent_command_outcome.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_command_effect_runner.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_command_scope.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_intent.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_ports.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_reducer.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_state.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

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

final agentConversationSliceOwnerProvider = NotifierProvider.autoDispose
    .family<
      AgentConversationSliceNotifier,
      AgentConversationSliceState,
      AgentConversationOwnerKey
    >(AgentConversationSliceNotifier.new, name: 'agentConversationSliceOwner');

/// entry 生命周期内唯一的轻量 region 与命令账本 owner。
final class AgentConversationSliceNotifier
    extends Notifier<AgentConversationSliceState>
    implements AgentConversationResultSink {
  AgentConversationSliceNotifier(this.ownerKey);
  final AgentConversationOwnerKey ownerKey;
  AgentConversationSliceEffectRunner? _effectRunner;
  AgentConversationRegionSource? _regions;
  AgentConversationCommandScope Function()? _scopeSnapshot;
  OperationIdGenerator Function(String)? _generatorFactory;
  void Function(AgentConversationOwnerKey)? _onProjectionUnobserved;
  final Map<String, OperationIdGenerator> _generators = {};
  KeepAliveLink? _projectionRetention;
  bool _observed = true;
  int _observationRevision = 0;

  @override
  AgentConversationSliceState build() {
    _projectionRetention = ref.keepAlive();
    final deps = ref.read(
      agentConversationSessionDependenciesProvider(ownerKey),
    );
    if (deps.ownerKey != ownerKey) {
      throw StateError('Mismatched conversation owner');
    }
    _regions = deps.regions;
    _scopeSnapshot = deps.scopeSnapshot;
    _generatorFactory =
        deps.operationIdGeneratorFactory ??
        ((scope) => OperationIdGenerator(scope: scope));
    _onProjectionUnobserved = deps.onProjectionUnobserved;
    _effectRunner =
        deps.runnerFactory?.call(this) ??
        AgentConversationCommandEffectRunner(
          commands: deps.executor,
          sink: this,
          scopeSnapshot: deps.scopeSnapshot,
        );
    final initial = AgentConversationSliceState(
      header: deps.regions.headerState,
      composer: deps.regions.composerState,
      pendingInteractions: deps.regions.pendingInteractionState,
      expansion: deps.regions.expansionState,
      history: deps.regions.historyState,
    );
    deps.regions.addUiUpdateListener(_onUiUpdate);
    ref.onCancel(() {
      _observed = false;
      _scheduleReclamation();
    });
    ref.onResume(() {
      _observed = true;
      _observationRevision++;
    });
    ref.onDispose(() {
      _closeResources();
      _onProjectionUnobserved = null;
    });
    return initial;
  }

  AgentConversationSliceState get current => state;
  bool get isProjectionObserved => _observed;
  bool _closed = false;
  int _dispatchCount = 0;
  int _publishCount = 0;
  int _effectCount = 0;
  int _staleResultCount = 0;

  /// 当前切片状态。

  /// store 是否已关闭。
  @override
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
    final before = state;
    final transition = agentConversationSliceReduce(before, intent);

    if (!identical(transition.state, before) && transition.state != before) {
      state = transition.state;
      _publishCount += 1;
    } else if (_isStaleResult(before, intent)) {
      _staleResultCount += 1;
    }

    for (final effect in transition.effects) {
      _effectCount += 1;
      _effectRunner?.run(effect);
    }
  }

  // -------------------------------------------------------------------------
  // ingress
  // -------------------------------------------------------------------------

  /// 把同一帧变化的 region 合并成一次转移。
  void refreshRegions(AgentConversationRegionsRefreshed intent) =>
      dispatch(intent);

  /// scheduler 批处理输出：一次 request 更新所有涉及的 region。
  void _onUiUpdate(AgentUiUpdateRequest request) {
    if (_closed || request.isEmpty) {
      return;
    }
    final regions = _regions;
    if (regions == null) {
      return;
    }
    final intent = AgentConversationRegionsRefreshed(
      header: request.regions.contains(AgentUiRegion.header)
          ? regions.headerState
          : null,
      composer: request.regions.contains(AgentUiRegion.composer)
          ? regions.composerState
          : null,
      pendingInteractions:
          request.regions.contains(AgentUiRegion.pendingInteraction)
          ? regions.pendingInteractionState
          : null,
      expansion: request.regions.contains(AgentUiRegion.expansion)
          ? regions.expansionState
          : null,
      history: request.regions.contains(AgentUiRegion.history)
          ? regions.historyState
          : null,
    );
    if (intent.isEmpty) {
      return;
    }
    refreshRegions(intent);
  }

  // -------------------------------------------------------------------------
  // 命令入口：铸造身份 → dispatch
  // -------------------------------------------------------------------------

  OperationId _nextOperationId(String scope) {
    final generator = _generators.putIfAbsent(
      scope,
      () => _generatorFactory!(scope),
    );
    return generator.next();
  }

  /// 命令身份 = 操作 id + 发起时的作用域快照。两者在同一时刻拍下。
  ({OperationId operationId, AgentConversationCommandScope scope}) _identity(
    String scope,
  ) {
    if (_closed) throw StateError('Conversation command ingress is closed');
    return (operationId: _nextOperationId(scope), scope: _scopeSnapshot!());
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
  @override
  void completeCommand(OperationId operationId) =>
      dispatch(AgentConversationCommandSucceeded(operationId));

  /// 命令失败。
  ///
  /// 只收**分类**：调用方不得把原始错误文本传进来当 UI 文案。
  @override
  void failCommand(OperationId operationId, AgentCommandFailureKind kind) =>
      dispatch(
        AgentConversationCommandFailed(
          AgentConversationOperationFailure(
            operationId: operationId,
            kind: kind,
          ),
        ),
      );

  /// 封闭唯一命令入口；当前账本不对外提供 Future，清空即结算所有在途身份。
  void closeCommandIngress() {
    if (_closed) return;
    _closeResources();
    state = AgentConversationSliceState.closedProjection();
    _scheduleReclamation();
  }

  void closeForEntryRelease() => closeCommandIngress();

  /// 只在应用确认 lease 已释放且无观察者后撤销保活；不释放业务资源。
  void releaseClosedProjectionRetention() {
    if (!_closed || _observed) {
      throw StateError('Cannot reclaim a live or observed conversation');
    }
    _projectionRetention?.close();
    _projectionRetention = null;
  }

  void _closeResources() {
    if (_closed) return;
    _closed = true;
    _regions?.removeUiUpdateListener(_onUiUpdate);
    _regions = null;
    _effectRunner?.close();
    _effectRunner = null;
    _scopeSnapshot = null;
    _generatorFactory = null;
    _generators.clear();
  }

  void _scheduleReclamation() {
    final revision = ++_observationRevision;
    scheduleMicrotask(() {
      if (_closed && !_observed && revision == _observationRevision) {
        _onProjectionUnobserved?.call(ownerKey);
      }
    });
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

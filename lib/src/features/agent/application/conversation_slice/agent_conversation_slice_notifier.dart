import 'agent_conversation_actions.dart';
import 'agent_conversation_command_payload.dart';
import 'agent_conversation_command_result.dart';
import 'agent_conversation_command_result_sink.dart';
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
    implements AgentConversationActions, AgentConversationCommandResultSink {
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

  /// 当前 owner 是否已关闭。
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

    if (intent is AgentConversationCommandRequested &&
        transition.effects.isEmpty) {
      throw StateError('Command did not produce an effect');
    }
    for (final effect in transition.effects) {
      _effectCount += 1;
      final runner = _effectRunner;
      if (runner == null) throw StateError('Conversation runner is closed');
      runner.run(effect);
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

  final Map<OperationId, Completer<AgentConversationCommandResult>> _waiters =
      {};
  final Map<OperationId, AgentConversationCommandEnvelope> _inFlight = {};
  // 四类 admission 表只隔离重复提交，不合并任何审批决定或授权状态。
  final Set<String> _permissionAdmissions = {};
  final Set<String> _questionAdmissions = {};
  final Set<String> _planApprovalAdmissions = {};
  final Set<String> _planExecutionAdmissions = {};

  (Set<String>, String)? _admission(AgentConversationCommandPayload payload) =>
      switch (payload) {
        AgentRespondPermissionCommand(:final request) => (
          _permissionAdmissions,
          request.id,
        ),
        AgentRespondQuestionCommand(:final request) => (
          _questionAdmissions,
          request.id,
        ),
        AgentRespondPlanApprovalCommand(:final request) => (
          _planApprovalAdmissions,
          request.id,
        ),
        AgentStartPlanExecutionCommand(:final request) ||
        AgentRevisePlanExecutionCommand(:final request) ||
        AgentDismissPlanExecutionCommand(
          :final request,
        ) => (_planExecutionAdmissions, request.id),
        _ => null,
      };

  Future<AgentConversationCommandResult> _submit(
    AgentConversationCommandPayload Function() freeze,
  ) {
    if (_closed) return Future.value(_staleResult);
    late final AgentConversationCommandEnvelope command;
    late final AgentConversationCommandPayload payload;
    try {
      payload = freeze();
      final admission = _admission(payload);
      if (admission != null && admission.$1.contains(admission.$2)) {
        return Future.value(
          const AgentConversationCommandResult.regular(
            AgentCommandOutcome.ignored(
              AgentCommandIgnoreReason.alreadyPending,
            ),
          ),
        );
      }
      final generator = _generators.putIfAbsent(
        payload.fixedScope,
        () => _generatorFactory!(payload.fixedScope),
      );
      command = AgentConversationCommandEnvelope(
        id: generator.next(),
        scope: _scopeSnapshot!(),
        ownerLifetimeToken: ownerKey.lifetimeToken,
        payload: payload,
      );
      admission?.$1.add(admission.$2);
    } on Object {
      return Future.value(
        const AgentConversationCommandResult.regular(
          AgentCommandOutcome.failed(AgentCommandFailureKind.requestFailed),
        ),
      );
    }
    final waiter = Completer<AgentConversationCommandResult>();
    _waiters[command.id] = waiter;
    _inFlight[command.id] = command;
    try {
      dispatch(AgentConversationCommandRequested(command));
    } on Object {
      settle(
        command.id,
        const AgentConversationCommandResult.regular(
          AgentCommandOutcome.failed(AgentCommandFailureKind.requestFailed),
        ),
      );
    }
    return waiter.future;
  }

  @override
  Future<AgentCommandOutcome> sendMessage(
    String text, {
    List<String> localImagePaths = const [],
    List<({String name, String path})> mentions = const [],
    List<AgentSkillRef> skills = const [],
    AgentPermissionRequestSnapshot? permissionSnapshotOverride,
  }) => _submit(
    () => AgentSendMessageCommand(
      text: text,
      localImagePaths: localImagePaths,
      mentions: mentions,
      skills: skills,
      permissionSnapshotOverride: permissionSnapshotOverride,
    ),
  ).then((result) => result.outcome);
  @override
  Future<AgentCommandOutcome> cancelActiveTurn() => _submit(
    () => AgentCancelActiveTurnCommand(),
  ).then((result) => result.outcome);
  @override
  Future<AgentCommandOutcome> editLastUserMessageAndRetry(String newText) =>
      _submit(
        () => AgentEditLastUserMessageCommand(newText: newText),
      ).then((result) => result.outcome);
  @override
  Future<AgentCommandOutcome> retryOpenThread() => _submit(
    () => AgentRetryOpenThreadCommand(),
  ).then((result) => result.outcome);
  @override
  Future<AgentCommandOutcome> respondToPermission(
    AgentPermissionRequest request, {
    required bool approved,
    bool cancelTurn = false,
    AgentCommandApprovalDecisionKind? commandDecision,
    List<String> execpolicyAmendment = const [],
  }) => _submit(
    () => AgentRespondPermissionCommand(
      request: request,
      approved: approved,
      cancelTurn: cancelTurn,
      commandDecision: commandDecision,
      execpolicyAmendment: execpolicyAmendment,
    ),
  ).then((result) => result.outcome);
  @override
  Future<AgentCommandOutcome> respondToQuestion(
    AgentQuestionRequest request, {
    Map<String, List<String>> answers = const {},
  }) => _submit(
    () => AgentRespondQuestionCommand(request: request, answers: answers),
  ).then((result) => result.outcome);
  @override
  Future<AgentCommandOutcome> respondToPlanApproval(
    AgentPlanApprovalRequest request,
    AgentPlanApprovalDecisionKind kind, {
    String? reason,
  }) => _submit(
    () => AgentRespondPlanApprovalCommand(
      request: request,
      kind: kind,
      reason: reason,
    ),
  ).then((result) => result.outcome);
  @override
  Future<AgentCommandOutcome> startPlanExecution(
    AgentPlanExecutionRequest request,
  ) => _submit(
    () => AgentStartPlanExecutionCommand(request: request),
  ).then((result) => result.outcome);
  @override
  Future<AgentCommandOutcome> revisePlanExecution(
    AgentPlanExecutionRequest request, {
    String? revisionMessage,
  }) => _submit(
    () => AgentRevisePlanExecutionCommand(
      request: request,
      revisionMessage: revisionMessage,
    ),
  ).then((result) => result.outcome);
  @override
  Future<AgentCommandOutcome> dismissPlanExecution(
    AgentPlanExecutionRequest request,
  ) => _submit(
    () => AgentDismissPlanExecutionCommand(request: request),
  ).then((result) => result.outcome);
  @override
  Future<AgentCommandOutcome> selectPlanExecutionPermissionOption(
    AgentPlanExecutionRequest request,
    AgentPermissionOption option,
  ) => _submit(
    () => AgentSelectPlanExecutionPermissionCommand(
      request: request,
      option: option,
    ),
  ).then((result) => result.outcome);
  @override
  Future<AgentCommandOutcome> approveGuardianDeniedAction() => _submit(
    () => AgentApproveGuardianDeniedActionCommand(),
  ).then((result) => result.outcome);
  @override
  Future<AgentForkCommandOutcome> forkCurrentThread() =>
      _submit(() => AgentForkCurrentThreadCommand()).then(
        (result) =>
            result.fork ??
            AgentForkCommandOutcome.fromRegularFailure(result.outcome),
      );
  @override
  Future<AgentCommandOutcome> renameCurrentThread(String name) => _submit(
    () => AgentRenameCurrentThreadCommand(name: name),
  ).then((result) => result.outcome);
  @override
  Future<AgentCommandOutcome> archiveCurrentThread() => _submit(
    () => AgentArchiveCurrentThreadCommand(),
  ).then((result) => result.outcome);
  @override
  Future<AgentCommandOutcome> compactCurrentThread() => _submit(
    () => AgentCompactCurrentThreadCommand(),
  ).then((result) => result.outcome);
  @override
  Future<AgentCommandOutcome> toggleToolCall(String toolCallId) => _submit(
    () => AgentToggleExpansionCommand(
      target: AgentConversationExpansionTarget.toolCall,
      id: toolCallId,
    ),
  ).then((result) => result.outcome);
  @override
  Future<AgentCommandOutcome> togglePlanMessage(String messageId) => _submit(
    () => AgentToggleExpansionCommand(
      target: AgentConversationExpansionTarget.planMessage,
      id: messageId,
    ),
  ).then((result) => result.outcome);
  @override
  Future<AgentCommandOutcome> toggleActivePlan(String turnId) => _submit(
    () => AgentToggleExpansionCommand(
      target: AgentConversationExpansionTarget.activePlan,
      id: turnId,
    ),
  ).then((result) => result.outcome);
  @override
  Future<AgentCommandOutcome> toggleCommandGroup(String commandGroupId) =>
      _submit(
        () => AgentToggleExpansionCommand(
          target: AgentConversationExpansionTarget.commandGroup,
          id: commandGroupId,
        ),
      ).then((result) => result.outcome);
  @override
  Future<AgentCommandOutcome> toggleFileEditItem(String fileEditItemId) =>
      _submit(
        () => AgentToggleExpansionCommand(
          target: AgentConversationExpansionTarget.fileEditItem,
          id: fileEditItemId,
        ),
      ).then((result) => result.outcome);
  @override
  Future<AgentCommandOutcome> loadModels({bool forceRefresh = false}) =>
      _submit(
        () => AgentLoadModelsCommand(forceRefresh: forceRefresh),
      ).then((result) => result.outcome);
  @override
  Future<AgentCommandOutcome> ensureSkillsCatalog() => _submit(
    () => AgentEnsureSkillsCatalogCommand(),
  ).then((result) => result.outcome);
  @override
  Future<AgentCommandOutcome> retryConversationModes() => _submit(
    () => AgentRetryConversationModesCommand(),
  ).then((result) => result.outcome);
  @override
  Future<AgentCommandOutcome> selectConversationMode(
    AgentConversationModeId modeId,
  ) => _submit(
    () => AgentSelectConversationModeCommand(modeId: modeId),
  ).then((result) => result.outcome);
  @override
  Future<AgentCommandOutcome> selectModel(String modelId) => _submit(
    () => AgentSelectModelCommand(modelId: modelId),
  ).then((result) => result.outcome);
  @override
  Future<AgentCommandOutcome> selectReasoningEffort(String? effort) => _submit(
    () => AgentSelectReasoningEffortCommand(effort: effort),
  ).then((result) => result.outcome);
  @override
  Future<AgentCommandOutcome> selectFastEnabled(bool enabled) => _submit(
    () => AgentSelectFastEnabledCommand(enabled: enabled),
  ).then((result) => result.outcome);
  @override
  Future<AgentCommandOutcome> resolveModelCompatibilityConflict() => _submit(
    () => AgentResolveModelCompatibilityCommand(),
  ).then((result) => result.outcome);
  @override
  Future<AgentCommandOutcome> retryModelConfigurationSave() => _submit(
    () => AgentRetryModelSaveCommand(),
  ).then((result) => result.outcome);
  @override
  Future<AgentCommandOutcome> clearModelConfigurationTransientState() =>
      _submit(
        () => AgentClearModelTransientStateCommand(),
      ).then((result) => result.outcome);
  @override
  Future<AgentCommandOutcome> selectPermissionOption(
    AgentPermissionOption option,
  ) => _submit(
    () => AgentSelectPermissionOptionCommand(option: option),
  ).then((result) => result.outcome);
  @override
  Future<AgentCommandOutcome> retryPermissionPreferencePersistence() => _submit(
    () => AgentRetryPermissionPersistenceCommand(),
  ).then((result) => result.outcome);
  @override
  Future<AgentCommandOutcome> selectSessionConfigOption(
    String configId,
    Object value,
  ) => _submit(
    () =>
        AgentSelectSessionConfigOptionCommand(configId: configId, value: value),
  ).then((result) => result.outcome);
  @override
  Future<AgentCommandOutcome> switchActiveProvider(String providerId) =>
      _submit(
        () => AgentSwitchProviderCommand(providerId: providerId),
      ).then((result) => result.outcome);

  @override
  bool isOpenOperation(OperationId id, Object ownerLifetimeToken) =>
      !_closed &&
      identical(ownerLifetimeToken, ownerKey.lifetimeToken) &&
      _inFlight.containsKey(id);

  @override
  void settle(OperationId id, AgentConversationCommandResult result) {
    final waiter = _waiters.remove(id);
    final command = _inFlight.remove(id);
    if (waiter == null || command == null) {
      _staleResultCount++;
      return;
    }
    final admission = _admission(command.payload);
    admission?.$1.remove(admission.$2);
    final safeResult = result.withoutDiagnostic();
    try {
      if (!_closed) {
        dispatch(AgentConversationOperationSettled(id, safeResult.failureKind));
      }
    } finally {
      if (!waiter.isCompleted) waiter.complete(safeResult);
    }
  }

  static const _staleResult = AgentConversationCommandResult.regular(
    AgentCommandOutcome.failed(AgentCommandFailureKind.staleTarget),
  );

  /// 封闭命令入口，立即结算 UI 等待者；已发 I/O 由资源生命周期负责。
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
    for (final waiter in _waiters.values) {
      if (!waiter.isCompleted) waiter.complete(_staleResult);
    }
    _waiters.clear();
    _inFlight.clear();
    _permissionAdmissions.clear();
    _questionAdmissions.clear();
    _planApprovalAdmissions.clear();
    _planExecutionAdmissions.clear();
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
    return intent is AgentConversationOperationSettled &&
        !before.pendingOperations.contains(intent.id);
  }
}

import 'dart:async';
import 'dart:collection';
import '../agent_command_outcome.dart';
import 'agent_conversation_command_payload.dart';
import 'agent_conversation_command_result.dart';
import 'agent_conversation_command_result_sink.dart';
import 'agent_conversation_command_scope.dart';
import 'agent_conversation_slice_ports.dart';
import 'agent_conversation_slice_effect.dart';

/// 执行器不拥有状态，只按冻结的 lifetime/scope 校验并回流一次结果。
final class AgentConversationCommandEffectRunner
    implements AgentConversationSliceEffectRunner {
  AgentConversationCommandEffectRunner({
    required this._commands,
    required this._sink,
    required this._scopeSnapshot,
  });
  AgentConversationCommandPort? _commands;
  AgentConversationCommandResultSink? _sink;
  AgentConversationCommandScope Function()? _scopeSnapshot;
  final Queue<AgentConversationCommandEnvelope> _permissionQueue = Queue();
  bool _permissionBusy = false;
  bool _closed = false;

  bool _canExecute(AgentConversationCommandEnvelope e) =>
      !_closed &&
      _sink!.isOpenOperation(e.id, e.ownerLifetimeToken) &&
      e.scope.matchesForExecution(_scopeSnapshot!());
  bool _canCommit(AgentConversationCommandEnvelope e) =>
      !_closed &&
      _sink!.isOpenOperation(e.id, e.ownerLifetimeToken) &&
      e.scope.matchesForCommit(_scopeSnapshot!());
  static const _stale = AgentConversationCommandResult.regular(
    AgentCommandOutcome.failed(AgentCommandFailureKind.staleTarget),
  );

  @override
  void run(AgentConversationSliceEffect effect) {
    if (_closed) return;
    final e = (effect as AgentConversationExecuteCommandEffect).command;
    if (e.payload is AgentSelectPermissionOptionCommand ||
        e.payload is AgentRetryPermissionPersistenceCommand) {
      _permissionQueue.add(e);
      _startPermission();
    } else if (e.payload.isSynchronous) {
      if (!_canExecute(e)) {
        _sink?.settle(e.id, _stale);
        return;
      }
      AgentConversationCommandResult result;
      try {
        result = AgentConversationCommandResult.regular(_invokeSync(e.payload));
      } on UnsupportedError {
        result = _failure(AgentCommandFailureKind.unsupported);
      } on Object {
        result = _failure(AgentCommandFailureKind.requestFailed);
      }
      _sink?.settle(
        e.id,
        _canCommit(e)
            ? result.withoutDiagnostic()
            : result.asStaleKeepingCreatedSession(),
      );
    } else {
      unawaited(_runAsync(e));
    }
  }

  void _startPermission() {
    if (_closed || _permissionBusy || _permissionQueue.isEmpty) return;
    _permissionBusy = true;
    final command = _permissionQueue.removeFirst();
    unawaited(
      _runAsync(command).whenComplete(() {
        _permissionBusy = false;
        _startPermission();
      }),
    );
  }

  Future<void> _runAsync(AgentConversationCommandEnvelope e) async {
    var result = _stale;
    try {
      if (_canExecute(e)) {
        try {
          result = await _invokeAsync(e.payload);
        } on UnsupportedError {
          result = _failure(AgentCommandFailureKind.unsupported);
        } on Object {
          result = _failure(AgentCommandFailureKind.requestFailed);
        }
        if (!_canCommit(e)) {
          result = result.asStaleKeepingCreatedSession();
        }
      }
    } on Object {
      // Scope source failures must also settle the caller; retain a known fork.
      final createdSession = result.fork?.createdSession;
      result = createdSession == null
          ? _failure(AgentCommandFailureKind.requestFailed)
          : AgentConversationCommandResult.fork(
              AgentForkCommandOutcome.failed(
                AgentCommandFailureKind.requestFailed,
                createdSession: createdSession,
              ),
            );
    }
    _sink?.settle(e.id, result.withoutDiagnostic());
  }

  AgentConversationCommandResult _failure(AgentCommandFailureKind kind) =>
      AgentConversationCommandResult.regular(AgentCommandOutcome.failed(kind));

  AgentCommandOutcome _invokeSync(AgentConversationCommandPayload p) {
    final executor = _commands!;
    return switch (p) {
      AgentToggleExpansionCommand(:final target, :final id) => switch (target) {
        AgentConversationExpansionTarget.toolCall => executor.toggleToolCall(
          id,
        ),
        AgentConversationExpansionTarget.planMessage =>
          executor.togglePlanMessage(id),
        AgentConversationExpansionTarget.activePlan =>
          executor.toggleActivePlan(id),
        AgentConversationExpansionTarget.commandGroup =>
          executor.toggleCommandGroup(id),
        AgentConversationExpansionTarget.fileEditItem =>
          executor.toggleFileEditItem(id),
      },
      AgentDismissPlanExecutionCommand() => executor.dismissPlanExecution(
        p.request,
      ),
      AgentSelectPlanExecutionPermissionCommand() =>
        executor.selectPlanExecutionPermissionOption(p.request, p.option),
      AgentSelectConversationModeCommand() => executor.selectConversationMode(
        p.modeId,
      ),
      AgentClearModelTransientStateCommand() =>
        executor.clearModelConfigurationTransientState(),
      _ => throw StateError('Expected synchronous conversation command'),
    };
  }

  Future<AgentConversationCommandResult> _invokeAsync(
    AgentConversationCommandPayload p,
  ) async {
    final executor = _commands!;
    if (p is AgentForkCurrentThreadCommand) {
      return AgentConversationCommandResult.fork(
        await executor.forkCurrentThread(),
      );
    }
    final outcome = await switch (p) {
      AgentSendMessageCommand() => executor.sendMessage(
        p.text,
        localImagePaths: p.localImagePaths,
        mentions: p.mentions,
        skills: p.skills,
        permissionSnapshotOverride: p.permissionSnapshotOverride,
      ),
      AgentCancelActiveTurnCommand() => executor.cancelActiveTurn(),
      AgentEditLastUserMessageCommand() => executor.editLastUserMessageAndRetry(
        p.newText,
      ),
      AgentRetryOpenThreadCommand() => executor.retryOpenThread(),
      AgentRespondPermissionCommand() => executor.respondToPermission(
        p.request,
        approved: p.approved,
        cancelTurn: p.cancelTurn,
        commandDecision: p.commandDecision,
        execpolicyAmendment: p.execpolicyAmendment,
      ),
      AgentRespondQuestionCommand() => executor.respondToQuestion(
        p.request,
        answers: p.answers,
      ),
      AgentRespondPlanApprovalCommand() => executor.respondToPlanApproval(
        p.request,
        p.kind,
        reason: p.reason,
      ),
      AgentStartPlanExecutionCommand() => executor.startPlanExecution(
        p.request,
      ),
      AgentRevisePlanExecutionCommand() => executor.revisePlanExecution(
        p.request,
        revisionMessage: p.revisionMessage,
      ),
      AgentApproveGuardianDeniedActionCommand() =>
        executor.approveGuardianDeniedAction(),
      AgentRenameCurrentThreadCommand() => executor.renameCurrentThread(p.name),
      AgentArchiveCurrentThreadCommand() => executor.archiveCurrentThread(),
      AgentCompactCurrentThreadCommand() => executor.compactCurrentThread(),
      AgentLoadModelsCommand() => executor.loadModels(
        forceRefresh: p.forceRefresh,
      ),
      AgentEnsureSkillsCatalogCommand() => executor.ensureSkillsCatalog(),
      AgentRetryConversationModesCommand() => executor.retryConversationModes(),
      AgentSelectModelCommand() => executor.selectModel(p.modelId),
      AgentSelectReasoningEffortCommand() => executor.selectReasoningEffort(
        p.effort,
      ),
      AgentSelectFastEnabledCommand() => executor.selectFastEnabled(p.enabled),
      AgentResolveModelCompatibilityCommand() =>
        executor.resolveModelCompatibilityConflict(),
      AgentRetryModelSaveCommand() => executor.retryModelConfigurationSave(),
      AgentSelectPermissionOptionCommand() => executor.selectPermissionOption(
        p.option,
      ),
      AgentRetryPermissionPersistenceCommand() =>
        executor.retryPermissionPreferencePersistence(),
      AgentSelectSessionConfigOptionCommand() =>
        executor.selectSessionConfigOption(p.configId, p.value),
      AgentSwitchProviderCommand() => executor.switchActiveProvider(
        p.providerId,
      ),
      _ => throw StateError('Expected asynchronous conversation command'),
    };
    return AgentConversationCommandResult.regular(outcome);
  }

  @override
  void close() {
    _closed = true;
    _permissionQueue.clear();
    _commands = null;
    _sink = null;
    _scopeSnapshot = null;
  }
}

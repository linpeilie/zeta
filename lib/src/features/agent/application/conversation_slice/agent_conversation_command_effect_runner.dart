import 'dart:async';

import 'package:zeta/src/features/agent/application/agent_command_outcome.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_command_scope.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_effect.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_intent.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_ports.dart';

/// 经窄命令端口执行切片副作用。
///
/// 每个命令副作用都必须回报成败，否则在途身份会永远留在切片里。
/// 执行前与结果回写前各做一次作用域校验（G3 / 目标架构 §6.2）。
final class AgentConversationCommandEffectRunner
    implements AgentConversationSliceEffectRunner {
  AgentConversationCommandEffectRunner({
    required AgentConversationCommandPort commands,
    required AgentConversationResultSink sink,
    required AgentConversationCommandScope Function() scopeSnapshot,
  }) : _commands = commands, // ignore: prefer_initializing_formals
       _sink = sink, // ignore: prefer_initializing_formals
       _scopeSnapshot = scopeSnapshot; // ignore: prefer_initializing_formals

  AgentConversationCommandPort? _commands;
  AgentConversationResultSink? _sink;
  AgentConversationCommandScope Function()? _scopeSnapshot;
  bool _closed = false;

  @override
  void close() {
    _closed = true;
    _commands = null;
    _sink = null;
    _scopeSnapshot = null;
  }

  @override
  void run(AgentConversationSliceEffect effect) {
    if (_closed) return;
    final commands = _commands!;
    switch (effect) {
      case AgentConversationToggleExpansionEffect():
        switch (effect.target) {
          case AgentConversationExpansionTarget.toolCall:
            commands.toggleToolCall(effect.id);
          case AgentConversationExpansionTarget.planMessage:
            commands.togglePlanMessage(effect.id);
          case AgentConversationExpansionTarget.activePlan:
            commands.toggleActivePlan(effect.id);
          case AgentConversationExpansionTarget.commandGroup:
            commands.toggleCommandGroup(effect.id);
          case AgentConversationExpansionTarget.fileEditItem:
            commands.toggleFileEditItem(effect.id);
        }
      case AgentConversationDismissPlanExecutionEffect():
        commands.dismissPlanExecution(effect.request);
      case AgentConversationCommandEffect():
        _runCommand(effect);
    }
  }

  void _runCommand(AgentConversationCommandEffect effect) {
    unawaited(_awaitCommand(effect, () => _invoke(effect)));
  }

  /// 只接受 port **显式给出**的结果。
  ///
  /// 这里刻意不再用"Future 正常结束"推断成功：Agent 的命令 port 会吞异常、提前
  /// return、或用 `null` 表示失败，靠 try/catch 判定会把真实失败记成成功。
  Future<void> _awaitCommand(
    AgentConversationCommandEffect effect,
    Future<AgentCommandOutcome> Function() invoke,
  ) async {
    if (_closed) return;
    final operationId = effect.operationId;

    // 校验一：执行前。世界已经换代就不要再打这一枪。
    if (!effect.scope.matchesForExecution(_scopeSnapshot!())) {
      _sink?.failCommand(operationId, AgentCommandFailureKind.staleTarget);
      return;
    }

    AgentCommandOutcome outcome;
    try {
      outcome = await invoke();
    } on Object catch (error) {
      // port 直接抛出的异常仍要归类，诊断只进日志不进 UI。
      outcome = AgentCommandOutcome.failed(
        AgentCommandFailureKind.requestFailed,
        diagnostic: error.toString(),
      );
    }

    if (_closed) return;

    // 校验二：结果回写前。await 期间 Provider 可能重启、Binding 可能换代，
    // 那样这个结果属于另一个世界，不能写进当前切片。
    if (!effect.scope.matchesForCommit(_scopeSnapshot!())) {
      _sink?.failCommand(operationId, AgentCommandFailureKind.staleTarget);
      return;
    }

    switch (outcome) {
      // 被忽略的命令（空输入、状态不允许）没有可展示的错误，按完成收口。
      case AgentCommandSucceeded() || AgentCommandIgnored():
        _sink?.completeCommand(operationId);
      case AgentCommandFailed(:final kind):
        _sink?.failCommand(operationId, kind);
    }
  }

  Future<AgentCommandOutcome> _invoke(AgentConversationCommandEffect effect) {
    final commands = _commands!;
    return switch (effect) {
      AgentConversationSendMessageEffect() => commands.sendMessage(
        effect.text,
        localImagePaths: effect.localImagePaths,
        mentions: effect.mentions,
        skills: effect.skills,
      ),
      AgentConversationCancelTurnEffect() => commands.cancelActiveTurn(),
      AgentConversationEditLastUserMessageEffect() =>
        commands.editLastUserMessageAndRetry(effect.text),
      AgentConversationRetryOpenThreadEffect() => commands.retryOpenThread(),
      // 四种审批语义各自独立调用，绝不互相复用已授权状态（G5）。
      AgentConversationRespondPermissionEffect() =>
        commands.respondToPermission(
          effect.request,
          approved: effect.approved,
          cancelTurn: effect.cancelTurn,
          commandDecision: effect.commandDecision,
          execpolicyAmendment: effect.execpolicyAmendment,
        ),
      AgentConversationRespondQuestionEffect() => commands.respondToQuestion(
        effect.request,
        answers: effect.answers,
      ),
      AgentConversationRespondPlanApprovalEffect() =>
        commands.respondToPlanApproval(
          effect.request,
          effect.decision,
          reason: effect.reason,
        ),
      AgentConversationPlanExecutionEffect() =>
        switch (effect.revisionFeedback) {
          final String feedback => commands.revisePlanExecution(
            effect.request,
            revisionMessage: feedback,
          ),
          null => commands.startPlanExecution(effect.request),
        },
      AgentConversationApproveGuardianDeniedActionEffect() =>
        commands.approveGuardianDeniedAction(),
      AgentConversationThreadMutationEffect() => switch (effect.kind) {
        // fork 用 `null` 表示失败，这里显式翻译，不让它冒充成功。
        AgentConversationThreadMutationKind.fork =>
          commands.forkCurrentThread().then<AgentCommandOutcome>(
            (session) => session == null
                ? const AgentCommandOutcome.failed(
                    AgentCommandFailureKind.requestFailed,
                  )
                : const AgentCommandOutcome.succeeded(),
          ),
        AgentConversationThreadMutationKind.rename =>
          commands.renameCurrentThread(effect.name ?? ''),
        AgentConversationThreadMutationKind.archive =>
          commands.archiveCurrentThread(),
        AgentConversationThreadMutationKind.compact =>
          commands.compactCurrentThread(),
      },
      AgentConversationLoadCatalogEffect() => switch (effect.kind) {
        AgentConversationCatalogKind.models => commands.loadModels(
          forceRefresh: effect.forceRefresh,
        ),
        AgentConversationCatalogKind.skills => commands.ensureSkillsCatalog(),
        AgentConversationCatalogKind.conversationModes =>
          commands.retryConversationModes(),
      },
    };
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:zeta/src/features/agent/application/agent_command_outcome.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_command_scope.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_effect.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_intent.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_state.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_store.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_view_model.dart';

/// 把切片接到现有 `AgentConversationViewModel` 上的组合对象。
///
/// 它做两件事，两件都是**单向**的：
///
/// - **ingress**：订阅 ViewModel 的五个 region listenable，把同一帧的变化合并成
///   一次 `AgentConversationRegionsRefreshed`；
/// - **egress**：切片产出的 effect 描述交给 ViewModel 的现有 application port
///   执行，完成后经 result intent 回写。
///
/// 因此**不存在双写 owner**：会话事实的唯一 owner 仍是 TimelineStore 与既有
/// controller，切片只是它们的只读投影 + 命令入口（迁移门禁第 1、9 条）。
final class AgentConversationSliceBinding {
  AgentConversationSliceBinding({
    required AgentConversationViewModel viewModel,
    void Function(void Function())? scheduleFlush,
    AgentConversationCommandScope Function()? scopeSnapshot,
  }) : _viewModel = viewModel,
       _scheduleFlush = scheduleFlush ?? scheduleMicrotask,
       _scopeSnapshot = scopeSnapshot ?? viewModel.currentCommandScope {
    _store = AgentConversationSliceStore(
      initialState: AgentConversationSliceState(
        header: viewModel.headerState,
        composer: viewModel.composerState,
        pendingInteractions: viewModel.pendingInteractionState,
        expansion: viewModel.expansionState,
        history: viewModel.historyState,
      ),
      effectRunner: _AgentConversationViewModelEffectRunner(
        viewModel: viewModel,
        store: () => _store,
        scopeSnapshot: () => _scopeSnapshot(),
      ),
      scopeSnapshot: _scopeSnapshot,
    );

    viewModel.headerStateListenable.addListener(_onHeaderChanged);
    viewModel.composerStateListenable.addListener(_onComposerChanged);
    viewModel.pendingInteractionStateListenable.addListener(_onPendingChanged);
    viewModel.expansionStateListenable.addListener(_onExpansionChanged);
    viewModel.historyStateListenable.addListener(_onHistoryChanged);
  }

  final AgentConversationViewModel _viewModel;
  final void Function(void Function()) _scheduleFlush;

  /// 当前作用域读取器；测试可注入以模拟 runtime 换代。
  final AgentConversationCommandScope Function() _scopeSnapshot;

  late final AgentConversationSliceStore _store;

  bool _headerDirty = false;
  bool _composerDirty = false;
  bool _pendingDirty = false;
  bool _expansionDirty = false;
  bool _historyDirty = false;
  bool _flushScheduled = false;
  bool _disposed = false;
  int _flushCount = 0;

  /// 本会话的切片 store。
  AgentConversationSliceStore get store => _store;

  /// 合并刷新的次数，用于帧预算回归。
  @visibleForTesting
  int get flushCount => _flushCount;

  void _onHeaderChanged() => _markDirty(() => _headerDirty = true);

  void _onComposerChanged() => _markDirty(() => _composerDirty = true);

  void _onPendingChanged() => _markDirty(() => _pendingDirty = true);

  void _onExpansionChanged() => _markDirty(() => _expansionDirty = true);

  void _onHistoryChanged() => _markDirty(() => _historyDirty = true);

  void _markDirty(void Function() mark) {
    if (_disposed) {
      return;
    }
    mark();
    if (_flushScheduled) {
      return;
    }
    _flushScheduled = true;
    _scheduleFlush(_flush);
  }

  /// 把攒下的 region 变化合并成一次切片转移。
  ///
  /// 同一帧内五个 region 都变，也只产生**一次** publish——这是 Phase 0 帧预算
  /// 的要求，不能让每个 region 各推一次。
  void _flush() {
    _flushScheduled = false;
    if (_disposed) {
      return;
    }
    _flushCount += 1;
    final intent = AgentConversationRegionsRefreshed(
      header: _headerDirty ? _viewModel.headerState : null,
      composer: _composerDirty ? _viewModel.composerState : null,
      pendingInteractions: _pendingDirty
          ? _viewModel.pendingInteractionState
          : null,
      expansion: _expansionDirty ? _viewModel.expansionState : null,
      history: _historyDirty ? _viewModel.historyState : null,
    );
    _headerDirty = false;
    _composerDirty = false;
    _pendingDirty = false;
    _expansionDirty = false;
    _historyDirty = false;
    _store.refreshRegions(intent);
  }

  /// 立即合并一次（测试与首帧对齐用）。
  @visibleForTesting
  void flushNow() => _flush();

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _viewModel.headerStateListenable.removeListener(_onHeaderChanged);
    _viewModel.composerStateListenable.removeListener(_onComposerChanged);
    _viewModel.pendingInteractionStateListenable.removeListener(
      _onPendingChanged,
    );
    _viewModel.expansionStateListenable.removeListener(_onExpansionChanged);
    _viewModel.historyStateListenable.removeListener(_onHistoryChanged);
    _store.dispose();
  }
}

/// 用现有 ViewModel port 执行切片副作用。
///
/// 每个命令副作用都必须回报成败，否则在途身份会永远留在切片里。
final class _AgentConversationViewModelEffectRunner
    implements AgentConversationSliceEffectRunner {
  _AgentConversationViewModelEffectRunner({
    required this._viewModel,
    required this._store,
    required this._scopeSnapshot,
  });

  final AgentConversationViewModel _viewModel;
  final AgentConversationSliceStore Function() _store;
  final AgentConversationCommandScope Function() _scopeSnapshot;

  @override
  void run(AgentConversationSliceEffect effect) {
    switch (effect) {
      case AgentConversationToggleExpansionEffect():
        switch (effect.target) {
          case AgentConversationExpansionTarget.toolCall:
            _viewModel.toggleToolCall(effect.id);
          case AgentConversationExpansionTarget.planMessage:
            _viewModel.togglePlanMessage(effect.id);
          case AgentConversationExpansionTarget.activePlan:
            _viewModel.toggleActivePlan(effect.id);
          case AgentConversationExpansionTarget.commandGroup:
            _viewModel.toggleCommandGroup(effect.id);
          case AgentConversationExpansionTarget.fileEditItem:
            _viewModel.toggleFileEditItem(effect.id);
        }
      case AgentConversationDismissPlanExecutionEffect():
        _viewModel.dismissPlanExecution(effect.request);
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
    final operationId = effect.operationId;

    // 校验一：执行前。世界已经换代就不要再打这一枪。
    if (!effect.scope.matchesForExecution(_scopeSnapshot())) {
      _store().failCommand(operationId, AgentCommandFailureKind.staleTarget);
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

    // 校验二：结果回写前。await 期间 Provider 可能重启、Binding 可能换代，
    // 那样这个结果属于另一个世界，不能写进当前切片。
    if (!effect.scope.matchesForCommit(_scopeSnapshot())) {
      _store().failCommand(operationId, AgentCommandFailureKind.staleTarget);
      return;
    }

    switch (outcome) {
      // 被忽略的命令（空输入、状态不允许）没有可展示的错误，按完成收口。
      case AgentCommandSucceeded() || AgentCommandIgnored():
        _store().completeCommand(operationId);
      case AgentCommandFailed(:final kind):
        _store().failCommand(operationId, kind);
    }
  }

  Future<AgentCommandOutcome> _invoke(AgentConversationCommandEffect effect) {
    return switch (effect) {
      AgentConversationSendMessageEffect() => _viewModel.sendMessage(
        effect.text,
        localImagePaths: effect.localImagePaths,
        mentions: effect.mentions,
        skills: effect.skills,
      ),
      AgentConversationCancelTurnEffect() => _viewModel.cancelActiveTurn(),
      AgentConversationEditLastUserMessageEffect() =>
        _viewModel.editLastUserMessageAndRetry(effect.text),
      AgentConversationRetryOpenThreadEffect() => _viewModel.retryOpenThread(),
      // 四种审批语义各自独立调用，绝不互相复用已授权状态（G5）。
      AgentConversationRespondPermissionEffect() =>
        _viewModel.respondToPermission(
          effect.request,
          approved: effect.approved,
          cancelTurn: effect.cancelTurn,
          commandDecision: effect.commandDecision,
          execpolicyAmendment: effect.execpolicyAmendment,
        ),
      AgentConversationRespondQuestionEffect() => _viewModel.respondToQuestion(
        effect.request,
        answers: effect.answers,
      ),
      AgentConversationRespondPlanApprovalEffect() =>
        _viewModel.respondToPlanApproval(
          effect.request,
          effect.decision,
          reason: effect.reason,
        ),
      AgentConversationPlanExecutionEffect() =>
        switch (effect.revisionFeedback) {
          final String feedback => _viewModel.revisePlanExecution(
            effect.request,
            revisionMessage: feedback,
          ),
          null => _viewModel.startPlanExecution(effect.request),
        },
      AgentConversationApproveGuardianDeniedActionEffect() =>
        _viewModel.approveGuardianDeniedAction(),
      AgentConversationThreadMutationEffect() => switch (effect.kind) {
        // fork 用 `null` 表示失败，这里显式翻译，不让它冒充成功。
        AgentConversationThreadMutationKind.fork =>
          _viewModel.forkCurrentThread().then<AgentCommandOutcome>(
            (session) => session == null
                ? const AgentCommandOutcome.failed(
                    AgentCommandFailureKind.requestFailed,
                  )
                : const AgentCommandOutcome.succeeded(),
          ),
        AgentConversationThreadMutationKind.rename =>
          _viewModel.renameCurrentThread(effect.name ?? ''),
        AgentConversationThreadMutationKind.archive =>
          _viewModel.archiveCurrentThread(),
        AgentConversationThreadMutationKind.compact =>
          _viewModel.compactCurrentThread(),
      },
      AgentConversationLoadCatalogEffect() => switch (effect.kind) {
        AgentConversationCatalogKind.models => _viewModel.loadModels(
          forceRefresh: effect.forceRefresh,
        ),
        AgentConversationCatalogKind.skills => _viewModel.ensureSkillsCatalog(),
        AgentConversationCatalogKind.conversationModes =>
          _viewModel.retryConversationModes(),
      },
    };
  }
}

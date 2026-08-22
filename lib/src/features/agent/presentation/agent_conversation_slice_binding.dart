import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_effect.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_intent.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_state.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_store.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_view_model.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

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
  }) : _viewModel = viewModel,
       _scheduleFlush = scheduleFlush ?? scheduleMicrotask {
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
      ),
    );

    viewModel.headerStateListenable.addListener(_onHeaderChanged);
    viewModel.composerStateListenable.addListener(_onComposerChanged);
    viewModel.pendingInteractionStateListenable.addListener(_onPendingChanged);
    viewModel.expansionStateListenable.addListener(_onExpansionChanged);
    viewModel.historyStateListenable.addListener(_onHistoryChanged);
  }

  final AgentConversationViewModel _viewModel;
  final void Function(void Function()) _scheduleFlush;

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
  });

  final AgentConversationViewModel _viewModel;
  final AgentConversationSliceStore Function() _store;

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
    unawaited(_awaitCommand(effect.operationId, () => _invoke(effect)));
  }

  Future<void> _awaitCommand(
    OperationId operationId,
    Future<void> Function() invoke,
  ) async {
    try {
      await invoke();
      _store().completeCommand(operationId);
    } on Object catch (error) {
      // 失败文案沿用 port 已经产出的中立描述；不带原文、prompt 或路径（G7）。
      _store().failCommand(operationId, error.toString());
    }
  }

  Future<void> _invoke(AgentConversationCommandEffect effect) {
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
        AgentConversationThreadMutationKind.fork =>
          _viewModel.forkCurrentThread(),
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

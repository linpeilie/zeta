part of '../agent_pane.dart';

/// 对话时间线与 Composer 的统一布局壳。
///
/// Footer 始终是同一棵带稳定 Key 的子树；空会话时靠近 Canvas 视觉中心，
/// 首个 turn 出现后落到底部。时间线只按 Composer 与阻塞交互的实际高度让位；
/// 紧凑浮层独立叠放，避免其窄卡片制造整行空白。
class _AgentConversationLayout extends StatefulWidget {
  const _AgentConversationLayout({
    required this.hasConversation,
    required this.reduceMotion,
    required this.timeline,
    required this.floatingPanel,
    required this.footer,
  });

  final bool hasConversation;
  final bool reduceMotion;
  final Widget timeline;
  final Widget floatingPanel;
  final Widget footer;

  @override
  State<_AgentConversationLayout> createState() =>
      _AgentConversationLayoutState();
}

class _AgentConversationLayoutState extends State<_AgentConversationLayout> {
  static const Alignment _newConversationAlignment = Alignment(0, -0.12);

  final GlobalKey _footerMeasureKey = GlobalKey(
    debugLabel: 'agent-conversation-footer-measure',
  );
  double _footerHeight = 0;
  bool _measurementScheduled = false;

  @override
  Widget build(BuildContext context) {
    _scheduleFooterMeasurement();
    final duration = widget.reduceMotion
        ? Duration.zero
        : IdeMotion.durationSlow;
    final targetAlignment = widget.hasConversation
        ? Alignment.bottomCenter
        : _newConversationAlignment;

    return Stack(
      key: const ValueKey('agent-conversation-layout'),
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          ignoring: !widget.hasConversation,
          child: AnimatedOpacity(
            key: const ValueKey('agent-conversation-timeline'),
            opacity: widget.hasConversation ? 1 : 0,
            duration: duration,
            curve: IdeMotion.curveDefault,
            child: AnimatedPadding(
              duration: duration,
              curve: IdeMotion.curveDefault,
              padding: EdgeInsets.only(
                bottom: widget.hasConversation ? _footerHeight : 0,
              ),
              child: widget.timeline,
            ),
          ),
        ),
        AnimatedAlign(
          key: const ValueKey('agent-composer-alignment'),
          alignment: targetAlignment,
          duration: duration,
          curve: IdeMotion.curveDefault,
          child: NotificationListener<SizeChangedLayoutNotification>(
            onNotification: (_) {
              _scheduleFooterMeasurement();
              return false;
            },
            child: SizeChangedLayoutNotifier(
              child: SizedBox(
                key: _footerMeasureKey,
                width: double.infinity,
                child: widget.footer,
              ),
            ),
          ),
        ),
        AnimatedPositioned(
          key: const ValueKey('agent-floating-panel-position'),
          left: 0,
          right: 0,
          bottom: widget.hasConversation ? _footerHeight : 0,
          duration: duration,
          curve: IdeMotion.curveDefault,
          child: widget.floatingPanel,
        ),
      ],
    );
  }

  void _scheduleFooterMeasurement() {
    if (_measurementScheduled) {
      return;
    }
    _measurementScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurementScheduled = false;
      if (!mounted) {
        return;
      }
      final renderObject = _footerMeasureKey.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) {
        return;
      }
      final nextHeight = renderObject.size.height;
      if ((nextHeight - _footerHeight).abs() < 0.5) {
        return;
      }
      setState(() {
        _footerHeight = nextHeight;
      });
    });
  }
}

/// 共享 920px 内容轴的可滚动对话区（CustomScrollView + turn 级虚拟化）。
class _AgentConversationTimeline extends StatelessWidget {
  const _AgentConversationTimeline({
    required this.viewModel,
    required this.scrollController,
    required this.pagePadding,
    required this.onLoadOlder,
    required this.buildTurnSection,
  });

  final AgentConversationViewModel viewModel;
  final ScrollController scrollController;
  final EdgeInsets pagePadding;
  final VoidCallback onLoadOlder;
  final _TurnSectionBuilder buildTurnSection;

  @override
  Widget build(BuildContext context) {
    return _AgentContentAlign(
      child: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[
          viewModel.historyVersionListenable,
          viewModel.liveTurnListenable,
        ]),
        builder: (context, _) {
          final standby = viewModel.standbyTurnState;
          final standbySnapshot = standby != null && standby.entries.isNotEmpty
              ? standby.snapshot()
              : null;
          final historyTurns = viewModel.visibleHistoryTurns;
          final liveTurnState = viewModel.liveTurnState;
          final liveSnapshot = liveTurnState?.snapshot();
          final items = projectAgentTimelineViewportItems(
            hasOlderTurns: viewModel.hasOlderTurns,
            standbyTurn: standbySnapshot,
            visibleHistoryTurns: historyTurns,
            liveTurn: liveSnapshot,
          );
          final turnsById = <String, AgentConversationTurnGroup>{
            for (final turn in <AgentConversationTurnGroup>[
              ?standbySnapshot,
              ...historyTurns,
              ?liveSnapshot,
            ])
              turn.id: turn,
          };

          return CustomScrollView(
            key: const ValueKey('agent-message-list'),
            controller: scrollController,
            // 默认 cacheExtent 保留少量视口外 turn，兼顾滚动流畅与虚拟化收益。
            slivers: [
              // 保留 pagePadding；内容最大宽由外层 _AgentContentAlign 约束。
              SliverPadding(
                padding: pagePadding,
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final item = items[index];
                      return KeyedSubtree(
                        key: ValueKey<String>(
                          agentTimelineViewportItemKey(item),
                        ),
                        child: _buildViewportItem(
                          item: item,
                          turnsById: turnsById,
                          liveTurnState: liveTurnState,
                        ),
                      );
                    },
                    childCount: items.length,
                    findChildIndexCallback: (Key key) {
                      if (key is! ValueKey<String>) {
                        return null;
                      }
                      final value = key.value;
                      const prefix = 'timeline-viewport-';
                      if (!value.startsWith(prefix)) {
                        return null;
                      }
                      final id = value.substring(prefix.length);
                      final index = items.indexWhere((item) => item.id == id);
                      return index >= 0 ? index : null;
                    },
                    // turn 内展开态由 viewModel 持有；允许回收视口外 turn。
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: true,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildViewportItem({
    required AgentTimelineViewportItem item,
    required Map<String, AgentConversationTurnGroup> turnsById,
    required AgentConversationTurnState? liveTurnState,
  }) {
    switch (item) {
      case AgentLoadOlderViewportItem():
        return _AgentLoadOlderTurnsButton(
          onPressed: onLoadOlder,
          loading: false,
        );
      case AgentTurnViewportItem(:final turnId, :final isLive):
        if (isLive) {
          final state = liveTurnState;
          if (state == null) {
            return const SizedBox.shrink();
          }
          return ListenableBuilder(
            listenable: state,
            builder: (context, _) {
              return KeyedSubtree(
                key: const ValueKey('agent-live-turn-section'),
                child: buildTurnSection(state.snapshot()),
              );
            },
          );
        }
        final turn = turnsById[turnId];
        if (turn == null) {
          return const SizedBox.shrink();
        }
        return buildTurnSection(turn);
    }
  }
}

/// 固定在 Composer 上方的待处理交互区。
///
/// 权限、用户提问、Provider 计划审批和本地执行交接都从独立 pending 状态读取。
/// [panelHeight] 由 AgentPane width-bucket 的约束旁路提供，不进入 bucket 身份。
class _AgentPendingInteractionSection extends StatelessWidget {
  const _AgentPendingInteractionSection({
    required this.viewModel,
    required this.panelHeight,
    required this.pagePadding,
    required this.onPlanRevisionRequested,
  });

  final AgentConversationViewModel viewModel;
  final double panelHeight;
  final EdgeInsets pagePadding;
  final VoidCallback onPlanRevisionRequested;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        viewModel.historyVersionListenable,
        viewModel.composerVersionListenable,
        viewModel.pendingInteractionVersionListenable,
      ]),
      builder: (context, _) => _buildDock(context),
    );
  }

  Widget _buildDock(BuildContext context) {
    final permissionRequests = viewModel.permissionRequests;
    final questionRequests = viewModel.questionRequests;
    final planApprovalRequests = viewModel.planApprovalRequests;
    final planExecutionRequest = viewModel.planExecutionRequest;
    if (viewModel.isReadOnly ||
        (permissionRequests.isEmpty &&
            questionRequests.isEmpty &&
            planApprovalRequests.isEmpty &&
            planExecutionRequest == null)) {
      return const SizedBox.shrink();
    }

    final maxHeight = panelHeight.isFinite
        ? math.min<double>(360, panelHeight * 0.35)
        : 360.0;
    return _AgentContentAlign(
      child: Padding(
        padding: pagePadding.copyWith(top: IdeSpacing.space8, bottom: 0),
        child: ConstrainedBox(
          key: const ValueKey('agent-pending-interaction-dock'),
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            key: const ValueKey('agent-pending-interaction-scroll'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (var index = 0; index < permissionRequests.length; index++)
                  Padding(
                    key: ValueKey(
                      'agent-pending-permission-'
                      '${permissionRequests[index].id}',
                    ),
                    padding: EdgeInsets.only(
                      bottom:
                          index < permissionRequests.length - 1 ||
                              questionRequests.isNotEmpty ||
                              planApprovalRequests.isNotEmpty ||
                              planExecutionRequest != null
                          ? IdeSpacing.space8
                          : 0,
                    ),
                    child: _buildPermissionCard(permissionRequests[index]),
                  ),
                for (var index = 0; index < questionRequests.length; index++)
                  Padding(
                    key: ValueKey(
                      'agent-pending-question-'
                      '${questionRequests[index].id}',
                    ),
                    padding: EdgeInsets.only(
                      bottom:
                          index < questionRequests.length - 1 ||
                              planApprovalRequests.isNotEmpty ||
                              planExecutionRequest != null
                          ? IdeSpacing.space8
                          : 0,
                    ),
                    child: _AgentQuestionCard(
                      request: questionRequests[index],
                      onRespond: (answers) => viewModel.respondToQuestion(
                        questionRequests[index],
                        answers: answers,
                      ),
                    ),
                  ),
                for (
                  var index = 0;
                  index < planApprovalRequests.length;
                  index++
                )
                  Padding(
                    key: ValueKey(
                      'agent-pending-plan-'
                      '${planApprovalRequests[index].id}',
                    ),
                    padding: EdgeInsets.only(
                      bottom:
                          index < planApprovalRequests.length - 1 ||
                              planExecutionRequest != null
                          ? IdeSpacing.space8
                          : 0,
                    ),
                    child: _AgentPlanApprovalCard(
                      request: planApprovalRequests[index],
                      onRespond: (kind) => viewModel.respondToPlanApproval(
                        planApprovalRequests[index],
                        kind,
                      ),
                    ),
                  ),
                if (planExecutionRequest case final request?)
                  _AgentPlanExecutionCard(
                    key: ValueKey<String>(
                      'agent-pending-plan-execution-${request.id}',
                    ),
                    request: request,
                    onDismiss: () => viewModel.dismissPlanExecution(request),
                    onRevise: () {
                      viewModel.revisePlanExecution(request);
                      onPlanRevisionRequested();
                    },
                    onStart: () =>
                        unawaited(viewModel.startPlanExecution(request)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionCard(AgentPermissionRequest request) {
    return _AgentPermissionCard(
      request: request,
      autoReview: viewModel.autoReviewForTurn(request.turnId),
      onApproveGuardian: viewModel.latestDeniedAutoReview != null
          ? viewModel.approveGuardianDeniedAction
          : null,
      onRespond:
          ({
            required bool approved,
            bool cancelTurn = false,
            AgentCommandApprovalDecisionKind? commandDecision,
            List<String> execpolicyAmendment = const <String>[],
          }) => viewModel.respondToPermission(
            request,
            approved: approved,
            cancelTurn: cancelTurn,
            commandDecision: commandDecision,
            execpolicyAmendment: execpolicyAmendment,
          ),
    );
  }
}

class _AgentTurnSection extends StatelessWidget {
  const _AgentTurnSection({
    required this.turn,
    required this.viewModel,
    super.key,
  });

  final AgentConversationTurnGroup turn;
  final AgentConversationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final renderBlocks = buildAgentTimelineRenderBlocks(
      turnId: turn.id,
      entries: turn.entries,
    );
    final isLiveRunning =
        !turn.isStandby && turn.status == AgentHistoryTurnStatus.running;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final block in renderBlocks)
          KeyedSubtree(
            key: ValueKey<String>('turn-block-${turn.id}-${block.id}'),
            child: _buildBlock(block),
          ),
        // 对话流内进行中状态（与 header 同源；Grok/Codex 通用）。
        if (isLiveRunning) _AgentLiveActivityStatus(viewModel: viewModel),
        // 每个非 standby turn 末尾展示耗时与本 turn token 用量。
        if (!turn.isStandby) _AgentTurnFooter(turn: turn),
      ],
    );
  }

  Widget _buildBlock(AgentTimelineRenderBlock block) {
    return switch (block) {
      AgentTimelineEntryRenderBlock(:final entry) => _buildTimelineEntry(entry),
      AgentTimelineCommandGroupRenderBlock(:final group) =>
        _AgentCommandGroupCard(group: group, viewModel: viewModel),
      AgentTimelineFileEditGroupRenderBlock(:final group) =>
        _AgentFileEditGroupCard(group: group, viewModel: viewModel),
    };
  }

  Widget _buildTimelineEntry(AgentTimelineEntry entry) {
    final isLiveTurn = viewModel.liveTurnState?.id == turn.id;
    return switch (entry) {
      AgentMessageTimelineEntry(:final message) => _AgentMessageEntry(
        message: message,
        // 历史与 live 的普通 Markdown 正文均不折叠；plan / 完成汇总等特殊卡自有样式。
        collapseHeavyContent: false,
        useStreamingMarkdown: isLiveTurn,
        viewModel: viewModel,
      ),
      AgentToolTimelineEntry(:final toolCall) => _AgentToolCallCard(
        toolCall: toolCall,
        viewModel: viewModel,
      ),
      // pending 交互只在 Composer 上方的 dock 渲染，避免时间线出现重复卡片。
      AgentPermissionTimelineEntry() => const SizedBox.shrink(),
      AgentQuestionTimelineEntry() => const SizedBox.shrink(),
      AgentPlanApprovalTimelineEntry() => const SizedBox.shrink(),
      // 正常路径会在 grouping 中转成文件编辑组；此处仅作兜底。
      AgentTurnDiffTimelineEntry() => const SizedBox.shrink(),
      AgentHistoryEventTimelineEntry(:final event) => _AgentHistoryEventCard(
        event: event,
      ),
    };
  }
}

class _AgentComposerSection extends StatelessWidget {
  const _AgentComposerSection({
    required this.viewModel,
    required this.inputController,
    required this.composerFocusNode,
    required this.canSendListenable,
    required this.draftImagePaths,
    required this.onAttachImages,
    required this.onRemoveImage,
    required this.onSend,
    required this.onInsertMention,
    required this.pagePadding,
    super.key,
  });

  final AgentConversationViewModel viewModel;
  final TextEditingController inputController;
  final FocusNode composerFocusNode;
  final ValueListenable<bool> canSendListenable;
  final List<String> draftImagePaths;
  final VoidCallback onAttachImages;
  final ValueChanged<String> onRemoveImage;
  final VoidCallback onSend;
  final ValueChanged<WorkspaceNode> onInsertMention;
  final EdgeInsets pagePadding;

  @override
  Widget build(BuildContext context) {
    return _AgentContentAlign(
      child: Padding(
        padding: pagePadding.copyWith(top: IdeSpacing.space8),
        child: ListenableBuilder(
          listenable: viewModel.composerVersionListenable,
          builder: (context, _) {
            return ValueListenableBuilder<bool>(
              valueListenable: canSendListenable,
              builder: (context, canSend, _) {
                return _AgentComposer(
                  controller: inputController,
                  focusNode: composerFocusNode,
                  canSubmit: canSend && viewModel.canSubmitMessage,
                  isTurnRunning: viewModel.isTurnRunning,
                  threadOpenPhase: viewModel.threadOpenPhase,
                  currentWindowTokenUsage:
                      viewModel.currentThreadLastTokenUsage,
                  draftImagePaths: draftImagePaths,
                  onAttachImages: onAttachImages,
                  onRemoveImage: onRemoveImage,
                  onSend: onSend,
                  onCancel: viewModel.cancelActiveTurn,
                  showImageAttachment: viewModel.canAttachImages,
                  showResourceMention: viewModel.canMentionResources,
                  conversationModeStatus: _modeSelectorStatus(
                    viewModel.conversationModeLoadStatus,
                  ),
                  conversationModeOptions: viewModel.conversationModeOptions,
                  selectedConversationMode: viewModel.selectedConversationMode,
                  conversationModeAppliesToNextTurn:
                      viewModel.conversationModeAppliesToNextTurn,
                  conversationModeStatusMessage:
                      viewModel.conversationModeStatusMessage,
                  conversationModeContextId:
                      viewModel.conversationModeContextId,
                  onSelectConversationMode: viewModel.selectConversationMode,
                  showModelSelection: viewModel.showModelSelection,
                  modelConfigState: viewModel.modelConfigUiState,
                  showPermissionPolicy: viewModel.showPermissionPolicy,
                  permissionPolicyLabel: viewModel.permissionPolicyLabel,
                  permissionPresets: AgentPermissionSelection.presets,
                  selectedPermissionPresetId:
                      viewModel.permissionSelection.matchedPresetId,
                  sessionConfigOptions: viewModel.sessionConfigOptions,
                  onSelectModel: viewModel.selectModel,
                  onSelectReasoningEffort: viewModel.selectReasoningEffort,
                  onSelectFastEnabled: viewModel.selectFastEnabled,
                  onResolveModelCompatibility:
                      viewModel.resolveModelCompatibilityConflict,
                  onRetryModelConfiguration:
                      viewModel.retryModelConfigurationSave,
                  onCloseModelConfiguration:
                      viewModel.clearModelConfigurationTransientState,
                  onSelectPermissionPreset: viewModel.selectPermissionPreset,
                  onSelectSessionConfigOption:
                      viewModel.selectSessionConfigOption,
                  mentionCandidates: viewModel.mentionCandidateFiles,
                  onInsertMention: onInsertMention,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

AgentModeSelectorStatus _modeSelectorStatus(
  AgentConversationModeLoadStatus status,
) {
  return switch (status) {
    AgentConversationModeLoadStatus.unavailable =>
      AgentModeSelectorStatus.unavailable,
    AgentConversationModeLoadStatus.loading => AgentModeSelectorStatus.loading,
    AgentConversationModeLoadStatus.ready => AgentModeSelectorStatus.ready,
    AgentConversationModeLoadStatus.error => AgentModeSelectorStatus.error,
  };
}

class _AgentContentAlign extends StatelessWidget {
  const _AgentContentAlign({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: IdeMetrics.contentMaxWidth),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}

class _AgentLoadOlderTurnsButton extends StatelessWidget {
  const _AgentLoadOlderTurnsButton({
    required this.onPressed,
    required this.loading,
  });

  final VoidCallback onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final textStyles = IdeTextStyles.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: sf.GhostButton(
          key: const ValueKey('agent-load-older-turns-button'),
          onPressed: loading ? null : onPressed,
          size: sf.ButtonSize.small,
          leading: loading
              ? const IdeLoadingIndicator(width: 16, height: 10, barHeight: 3)
              : const Icon(Icons.history_rounded, size: 15),
          child: Text(
            loading ? 'Loading older turns' : 'Load older turns',
            style: textStyles.bodySmall,
          ),
        ),
      ),
    );
  }
}

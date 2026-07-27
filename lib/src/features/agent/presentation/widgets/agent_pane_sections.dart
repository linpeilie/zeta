part of '../agent_pane.dart';

/// 对话时间线与 Composer 的统一布局壳。
///
/// Footer 始终是同一棵带稳定 Key 的子树；空会话时靠近 Canvas 视觉中心，
/// 首个 turn 出现后落到底部。时间线只按 Composer 与阻塞交互的实际高度让位；
/// 紧凑浮层独立叠放，避免其窄卡片制造整行空白。
enum _AgentConversationSlot { timeline, floatingPanel, footer }

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

class _AgentConversationLayoutState extends State<_AgentConversationLayout>
    with SingleTickerProviderStateMixin {
  static const Alignment _newConversationAlignment = Alignment(0, -0.12);

  late final AnimationController _footerPositionProgress;

  double get _targetProgress => widget.hasConversation ? 1 : 0;

  @override
  void initState() {
    super.initState();
    _footerPositionProgress = AnimationController(
      vsync: this,
      duration: IdeMotion.durationSlow,
      value: _targetProgress,
    );
  }

  @override
  void didUpdateWidget(covariant _AgentConversationLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reduceMotion) {
      _footerPositionProgress
        ..stop()
        ..value = _targetProgress;
      return;
    }
    if (oldWidget.hasConversation != widget.hasConversation) {
      _footerPositionProgress.animateTo(
        _targetProgress,
        duration: IdeMotion.durationSlow,
        curve: IdeMotion.curveDefault,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomMultiChildLayout(
      key: const ValueKey('agent-conversation-layout'),
      delegate: _AgentConversationLayoutDelegate(
        hasConversation: widget.hasConversation,
        footerPositionProgress: _footerPositionProgress,
        newConversationAlignment: _newConversationAlignment,
      ),
      children: [
        LayoutId(
          id: _AgentConversationSlot.timeline,
          child: IgnorePointer(
            ignoring: !widget.hasConversation,
            child: FadeTransition(
              key: const ValueKey('agent-conversation-timeline'),
              opacity: _footerPositionProgress,
              child: widget.timeline,
            ),
          ),
        ),
        LayoutId(
          id: _AgentConversationSlot.floatingPanel,
          child: KeyedSubtree(
            key: const ValueKey('agent-floating-panel-position'),
            child: widget.floatingPanel,
          ),
        ),
        LayoutId(
          id: _AgentConversationSlot.footer,
          child: KeyedSubtree(
            key: const ValueKey('agent-composer-alignment'),
            child: SizedBox(
              key: const ValueKey('agent-conversation-footer'),
              width: double.infinity,
              child: widget.footer,
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _footerPositionProgress.dispose();
    super.dispose();
  }
}

/// 同一轮 layout 内先测 Footer，再为 Timeline 与浮动计划分配真实剩余空间。
class _AgentConversationLayoutDelegate extends MultiChildLayoutDelegate {
  _AgentConversationLayoutDelegate({
    required this.hasConversation,
    required this.footerPositionProgress,
    required this.newConversationAlignment,
  }) : super(relayout: footerPositionProgress);

  final bool hasConversation;
  final Animation<double> footerPositionProgress;
  final Alignment newConversationAlignment;

  @override
  void performLayout(Size size) {
    final footerSize = hasChild(_AgentConversationSlot.footer)
        ? layoutChild(
            _AgentConversationSlot.footer,
            BoxConstraints(
              minWidth: size.width,
              maxWidth: size.width,
              maxHeight: size.height,
            ),
          )
        : Size.zero;
    final footerHeight = footerSize.height.clamp(0.0, size.height).toDouble();
    final bottomFooterTop = math.max(0.0, size.height - footerHeight);
    final centeredFooterTop =
        bottomFooterTop * ((newConversationAlignment.y + 1) / 2);
    final progress = footerPositionProgress.value.clamp(0.0, 1.0).toDouble();
    final footerTop =
        centeredFooterTop + ((bottomFooterTop - centeredFooterTop) * progress);

    if (hasChild(_AgentConversationSlot.timeline)) {
      final timelineHeight = hasConversation ? bottomFooterTop : size.height;
      layoutChild(
        _AgentConversationSlot.timeline,
        BoxConstraints.tightFor(width: size.width, height: timelineHeight),
      );
      positionChild(_AgentConversationSlot.timeline, Offset.zero);
    }

    if (hasChild(_AgentConversationSlot.floatingPanel)) {
      final floatingPanelSize = layoutChild(
        _AgentConversationSlot.floatingPanel,
        BoxConstraints(
          minWidth: size.width,
          maxWidth: size.width,
          maxHeight: math.max(0.0, footerTop),
        ),
      );
      positionChild(
        _AgentConversationSlot.floatingPanel,
        Offset(0, math.max(0.0, footerTop - floatingPanelSize.height)),
      );
    }

    if (hasChild(_AgentConversationSlot.footer)) {
      positionChild(_AgentConversationSlot.footer, Offset(0, footerTop));
    }
  }

  @override
  bool shouldRelayout(covariant _AgentConversationLayoutDelegate oldDelegate) {
    return hasConversation != oldDelegate.hasConversation ||
        footerPositionProgress != oldDelegate.footerPositionProgress ||
        newConversationAlignment != oldDelegate.newConversationAlignment;
  }
}

/// 共享 920px 内容轴的可滚动对话区（CustomScrollView + block 级虚拟化）。
class _AgentConversationTimeline extends StatelessWidget {
  const _AgentConversationTimeline({
    required this.viewModel,
    required this.scrollController,
    required this.pagePadding,
    required this.projectionCache,
    required this.virtualListController,
    required this.scrollCoordinator,
    required this.scrollChromeTick,
    required this.onLastItemIdChanged,
    required this.onScrollToEndPressed,
    required this.useAnchoredDynamicSliver,
  });

  final AgentConversationViewModel viewModel;
  final ScrollController scrollController;
  final EdgeInsets pagePadding;
  final AgentTimelineProjectionCache projectionCache;
  final IdeVirtualListController virtualListController;
  final IdeVirtualScrollCoordinator scrollCoordinator;
  final ValueListenable<int> scrollChromeTick;
  final ValueChanged<String?> onLastItemIdChanged;
  final Future<void> Function() onScrollToEndPressed;
  final bool useAnchoredDynamicSliver;

  static const AgentTimelineExtentDescriptorFactory _descriptorFactory =
      AgentTimelineExtentDescriptorFactory();

  @override
  Widget build(BuildContext context) {
    return _AgentContentAlign(
      child: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[
          viewModel.historyVersionListenable,
          viewModel.liveTurnListenable,
          viewModel.expansionVersionListenable,
          ?viewModel.liveTurnState,
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
            standbyTurn: standbySnapshot,
            visibleHistoryTurns: historyTurns,
            liveTurn: liveSnapshot,
            resolveBlocks: projectionCache.resolve,
          );
          // 仅保留当前可见 turn 的投影缓存，避免历史窗口滑动后无限增长。
          projectionCache.retainOnly(<String>{
            if (standbySnapshot != null) standbySnapshot.id,
            for (final turn in historyTurns) turn.id,
            if (liveSnapshot != null) liveSnapshot.id,
          });

          onLastItemIdChanged(items.isEmpty ? null : items.last.id);

          final media = MediaQuery.of(context);
          final layoutContext = AgentTimelineLayoutContext(
            crossAxisExtent: media.size.width - pagePadding.horizontal,
            devicePixelRatio: media.devicePixelRatio,
            textScale: media.textScaler.scale(1),
            localeKey: Localizations.localeOf(context).toString(),
          );

          if (useAnchoredDynamicSliver) {
            virtualListController.setItems(
              _descriptorFactory.describeAll(
                items,
                expansion: (
                  isCommandGroupExpanded: viewModel.isCommandGroupExpanded,
                  isFileEditItemExpanded: viewModel.isFileEditItemExpanded,
                ),
                layoutContext: layoutContext,
              ),
              epoch: layoutContext.toEpoch(),
            );
          }

          final delegate = SliverChildBuilderDelegate(
            (context, index) {
              final item = items[index];
              return KeyedSubtree(
                key: ValueKey<String>(agentTimelineViewportItemKey(item)),
                child: _buildViewportItem(item),
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
          );

          final scrollView = CustomScrollView(
            key: const ValueKey('agent-message-list'),
            controller: scrollController,
            // 默认 cacheExtent 保留少量视口外 block，兼顾滚动流畅与虚拟化收益。
            slivers: [
              // 保留 pagePadding；内容最大宽由外层 _AgentContentAlign 约束。
              SliverPadding(
                padding: pagePadding,
                sliver: useAnchoredDynamicSliver
                    ? IdeAnchoredDynamicSliverList(
                        controller: virtualListController,
                        delegate: delegate,
                      )
                    : SliverList(delegate: delegate),
              ),
            ],
          );

          if (!useAnchoredDynamicSliver) {
            return scrollView;
          }

          return NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              return dispatchUserScrollToCoordinator(
                coordinator: scrollCoordinator,
                notification: notification,
                controller: scrollController,
              );
            },
            child: ListenableBuilder(
              listenable: scrollChromeTick,
              builder: (context, _) {
                final showButton = _shouldShowScrollToEndButton();
                return IdeVirtualScrollShell(
                  controller: scrollController,
                  semanticLabel: 'Agent 对话滚动条',
                  showScrollToEndButton: showButton,
                  hasNewContent: showButton && viewModel.liveTurnState != null,
                  onScrollToEnd: () {
                    unawaited(onScrollToEndPressed());
                  },
                  child: scrollView,
                );
              },
            ),
          );
        },
      ),
    );
  }

  bool _shouldShowScrollToEndButton() {
    if (!scrollController.hasClients) {
      return scrollCoordinator.mode == IdeVirtualScrollMode.free;
    }
    final position = scrollController.position;
    return scrollCoordinator.shouldShowScrollToEndButton(
      IdeVirtualScrollMetricsSnapshot(
        pixels: position.pixels,
        maxScrollExtent: position.maxScrollExtent,
        viewportDimension: position.viewportDimension,
      ),
    );
  }

  Widget _buildViewportItem(AgentTimelineViewportItem item) {
    switch (item) {
      case AgentBlockViewportItem(:final turn, :final block):
        return _AgentTimelineBlockSection(
          turn: turn,
          block: block,
          viewModel: viewModel,
        );
      case AgentLiveActivityViewportItem():
        return KeyedSubtree(
          key: const ValueKey('agent-live-turn-section'),
          child: _AgentLiveActivityStatus(viewModel: viewModel),
        );
      case AgentTurnFooterViewportItem(:final turn):
        return _AgentTurnFooter(turn: turn);
    }
  }
}

/// 单个 Sliver item 只渲染一个 projection block。
///
/// resize 时 Sliver 只会重新布局视口和 cache extent 内的 block，不再为一个长
/// turn 的全部 Markdown、命令和 diff 子树计算总高度。
class _AgentTimelineBlockSection extends StatelessWidget {
  const _AgentTimelineBlockSection({
    required this.turn,
    required this.block,
    required this.viewModel,
  });

  final AgentConversationTurnGroup turn;
  final AgentTimelineRenderBlock block;
  final AgentConversationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: ValueKey<String>('turn-block-${turn.id}-${block.id}'),
      child: switch (block) {
        AgentTimelineEntryRenderBlock(:final entry) => _buildTimelineEntry(
          entry,
        ),
        AgentTimelineCommandGroupRenderBlock(:final group) =>
          _AgentCommandGroupCard(group: group, viewModel: viewModel),
        AgentTimelineFileEditGroupRenderBlock(:final group) =>
          _AgentFileEditGroupCard(group: group, viewModel: viewModel),
      },
    );
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
  const _AgentContentAlign({
    required this.child,
    this.shrinkWrapHeight = false,
  });

  final Widget child;
  final bool shrinkWrapHeight;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      heightFactor: shrinkWrapHeight ? 1 : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: IdeMetrics.contentMaxWidth),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}

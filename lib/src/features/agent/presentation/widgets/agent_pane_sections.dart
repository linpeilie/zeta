part of '../agent_pane.dart';

/// 对话时间线与 Composer 的统一布局壳。
///
/// Footer 始终是同一棵带稳定 Key 的子树；空会话时靠近 Canvas 视觉中心，
/// 首个 turn 出现或正在加载历史时落到底部。时间线只按 Composer 与阻塞交互的
/// 实际高度让位；紧凑 Plan 浮层独立叠放（两侧仍可见对话流）。末项不被遮挡
/// 靠时间线内部的底部滚动 inset（见 [floatingPanelExtent]），而非缩短 viewport。
enum _AgentConversationSlot { timeline, floatingPanel, footer }

class _AgentConversationLayout extends StatefulWidget {
  const _AgentConversationLayout({
    required this.pinFooterToBottom,
    required this.reduceMotion,
    required this.timeline,
    required this.floatingPanel,
    required this.footer,
  });

  /// 为 true 时 Composer 贴底（已有对话 / 加载历史）；否则空草稿居中。
  final bool pinFooterToBottom;
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

  double get _targetProgress => widget.pinFooterToBottom ? 1 : 0;

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
    if (oldWidget.pinFooterToBottom == widget.pinFooterToBottom) {
      if (widget.reduceMotion &&
          _footerPositionProgress.value != _targetProgress) {
        _footerPositionProgress
          ..stop()
          ..value = _targetProgress;
      }
      return;
    }
    // 贴底（有对话 / 加载历史）瞬时到位；回到空草稿居中时可动画。
    // 加载态若仍走居中→底部动画，会出现输入框悬空的中间帧。
    if (widget.reduceMotion || widget.pinFooterToBottom) {
      _footerPositionProgress
        ..stop()
        ..value = _targetProgress;
      return;
    }
    _footerPositionProgress.animateTo(
      _targetProgress,
      duration: IdeMotion.durationSlow,
      curve: IdeMotion.curveDefault,
    );
  }

  @override
  Widget build(BuildContext context) {
    return CustomMultiChildLayout(
      key: const ValueKey('agent-conversation-layout'),
      delegate: _AgentConversationLayoutDelegate(
        pinFooterToBottom: widget.pinFooterToBottom,
        footerPositionProgress: _footerPositionProgress,
        newConversationAlignment: _newConversationAlignment,
      ),
      children: [
        LayoutId(
          id: _AgentConversationSlot.timeline,
          child: IgnorePointer(
            // 空草稿时时间线透明且不接收手势；加载态与有对话时需要可见/可测。
            ignoring: !widget.pinFooterToBottom,
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
    required this.pinFooterToBottom,
    required this.footerPositionProgress,
    required this.newConversationAlignment,
  }) : super(relayout: footerPositionProgress);

  final bool pinFooterToBottom;
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
      // 贴底时时间线高度只让位 footer；Plan 浮层叠在上方，两侧仍透出对话流。
      final timelineHeight = pinFooterToBottom ? bottomFooterTop : size.height;
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
    return pinFooterToBottom != oldDelegate.pinFooterToBottom ||
        footerPositionProgress != oldDelegate.footerPositionProgress ||
        newConversationAlignment != oldDelegate.newConversationAlignment;
  }
}

/// Thread 历史加载中的对话区占位：Agent 图标 + 进度环 + 文案。
///
/// 输入框由布局壳固定在底部；本组件只填充原时间线区域。
class _AgentThreadHistoryLoading extends StatelessWidget {
  const _AgentThreadHistoryLoading({
    required this.providerId,
    required this.providerKind,
    required this.providerName,
  });

  final String providerId;
  final AgentProviderKind providerKind;
  final String providerName;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return Semantics(
      label: 'Loading thread history',
      child: Center(
        key: const ValueKey('agent-thread-history-loading'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: IdeSpacing.space24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    IdeBusySpinner(
                      key: const ValueKey(
                        'agent-thread-history-loading-spinner',
                      ),
                      size: 72,
                      strokeWidth: 2.2,
                      color: colors.accent.withValues(alpha: 0.55),
                      backgroundColor: colors.border.withValues(alpha: 0.28),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surfaceElevated,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: colors.borderSubtle.withValues(alpha: 0.9),
                        ),
                      ),
                      child: SizedBox(
                        width: 52,
                        height: 52,
                        child: Center(
                          child: AgentProviderIcon(
                            key: ValueKey<String>(
                              'agent-thread-history-loading-icon-$providerId',
                            ),
                            providerId: providerId,
                            kind: providerKind,
                            size: 26,
                            color: colors.textSecondary,
                            semanticLabel: providerName,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: IdeSpacing.space16),
              Text(
                '正在加载会话…',
                key: const ValueKey('agent-thread-history-loading-label'),
                textAlign: TextAlign.center,
                style: textStyles.bodyMedium.copyWith(
                  color: colors.textPrimary.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: IdeSpacing.space6),
              Text(
                providerName,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textStyles.caption.copyWith(
                  color: colors.textSecondary.withValues(alpha: 0.78),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 共享 920px 内容轴的可滚动对话区（CustomScrollView + block 级虚拟化）。
class _AgentConversationTimeline extends StatelessWidget {
  const _AgentConversationTimeline({
    required this.viewModel,
    required this.isActive,
    required this.scrollController,
    required this.pagePadding,
    required this.floatingPanelExtent,
    required this.projectionCache,
    required this.descriptorFactory,
    required this.markdownCache,
    required this.planRevisionDrafts,
    required this.virtualListController,
    required this.scrollCoordinator,
    required this.scrollChromeTick,
    required this.onLastItemIdChanged,
    required this.onScrollToEndPressed,
  });

  final AgentConversationViewModel viewModel;

  /// 前台才订阅 live 流式 listenable。
  final bool isActive;
  final ScrollController scrollController;
  final EdgeInsets pagePadding;

  /// Plan 进度浮层实测高度；写入滚动底部 inset，使末项可滑到浮层上方。
  final ValueListenable<double> floatingPanelExtent;
  final AgentTimelineProjectionCache projectionCache;
  final AgentTimelineExtentDescriptorFactory descriptorFactory;
  final AgentMarkdownCache markdownCache;

  /// 计划卡修改输入的草稿宿主；由 [AgentPane] 持有，跨虚拟列表回收存活。
  final AgentPlanRevisionDraftStore planRevisionDrafts;
  final IdeVirtualListController virtualListController;
  final IdeVirtualScrollCoordinator scrollCoordinator;
  final ValueListenable<int> scrollChromeTick;
  final ValueChanged<String?> onLastItemIdChanged;
  final Future<void> Function() onScrollToEndPressed;

  @override
  Widget build(BuildContext context) {
    // 非前台：不挂 live 高频信号，后台 thread 流式输出不重建此 canvas。
    // pending 状态进入时间线信号：计划卡在流内渲染，pending 变化必须重建。
    final timelineListenable = isActive
        ? Listenable.merge(<Listenable>[
            viewModel.historyStateListenable,
            viewModel.liveTurnListenable,
            viewModel.expansionStateListenable,
            viewModel.pendingInteractionStateListenable,
            floatingPanelExtent,
            ?viewModel.liveTurnState,
          ])
        : Listenable.merge(<Listenable>[
            viewModel.historyStateListenable,
            viewModel.expansionStateListenable,
            viewModel.pendingInteractionStateListenable,
            floatingPanelExtent,
          ]);

    return _AgentContentAlign(
      child: LayoutBuilder(
        builder: (context, constraints) => ListenableBuilder(
          listenable: timelineListenable,
          builder: (context, _) {
            final historyState = viewModel.historyState;
            final standbySnapshot = historyState.standbyTurn;
            final historyTurns = historyState.visibleTurns;
            final liveTurnState = viewModel.liveTurnState;
            final liveSnapshot = liveTurnState?.snapshot();
            final expansionState = viewModel.expansionState;
            final pendingState = viewModel.pendingInteractionState;
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
            // 计划请求消失即释放草稿，避免长会话里控制器无限累积。
            planRevisionDrafts.retainOnly(<String>{
              for (final request in pendingState.planApprovals) request.id,
              if (pendingState.planExecutionHandoff case final handoff?)
                handoff.id,
            });

            onLastItemIdChanged(items.isEmpty ? null : items.last.id);

            final media = MediaQuery.of(context);
            final layoutContext = AgentTimelineLayoutContext(
              // 必须使用 920px 内容轴内的真实局部宽度；窗口宽度会让高度估算和
              // layout epoch 在多面板/窗口 resize 时失真。
              crossAxisExtent: math.max(
                0,
                constraints.maxWidth - pagePadding.horizontal,
              ),
              devicePixelRatio: media.devicePixelRatio,
              textScale: media.textScaler.scale(1),
              localeKey: Localizations.localeOf(context).toString(),
            );

            virtualListController.setItems(
              descriptorFactory.describeAll(
                items,
                expansion: (
                  isCommandGroupExpanded: expansionState.isCommandGroupExpanded,
                  isFileEditItemExpanded: expansionState.isFileEditItemExpanded,
                  isPlanMessageInteractive: (messageId) =>
                      pendingState.planExecutionHandoff?.messageId == messageId,
                ),
                layoutContext: layoutContext,
              ),
              epoch: layoutContext.toEpoch(),
            );

            final itemIndexes = <String, int>{
              for (var index = 0; index < items.length; index++)
                items[index].id: index,
            };
            final delegate = SliverChildBuilderDelegate(
              (context, index) {
                final item = items[index];
                final itemKey = ValueKey<String>(
                  agentTimelineViewportItemKey(item),
                );
                final content = IndexedSemantics(
                  index: index,
                  child: RepaintBoundary(
                    child: _buildViewportItem(item, pendingState),
                  ),
                );
                final keepAliveListenable = _prepareMarkdownWarmEntry(item);
                if (keepAliveListenable == null) {
                  return KeyedSubtree(key: itemKey, child: content);
                }
                return ValueListenableBuilder<bool>(
                  key: itemKey,
                  valueListenable: keepAliveListenable,
                  child: content,
                  builder: (context, keepAlive, child) {
                    return KeepAlive(keepAlive: keepAlive, child: child!);
                  },
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
                return itemIndexes[id];
              },
              // Markdown 在根节点使用显式 KeepAlive；禁止嵌套子树发送 ParentData 通知。
              addAutomaticKeepAlives: false,
              // KeepAlive 必须直接控制 Sliver child 的 ParentData，因此在上方按
              // KeepAlive → IndexedSemantics → RepaintBoundary 的顺序显式包装。
              addRepaintBoundaries: false,
              addSemanticIndexes: false,
            );

            // Plan 浮层叠在时间线之上：viewport 不缩短，只在滚动内容底部加
            // inset，使 stick-to-bottom / 手动滑到底时末项停在浮层上方。
            final listPadding = pagePadding.copyWith(
              bottom: pagePadding.bottom + floatingPanelExtent.value,
            );
            final scrollView = CustomScrollView(
              key: const ValueKey('agent-message-list'),
              controller: scrollController,
              // 默认 cacheExtent 保留少量视口外 block，兼顾滚动流畅与虚拟化收益。
              slivers: [
                // 保留 pagePadding；内容最大宽由外层 _AgentContentAlign 约束。
                // 底部额外 inset = Plan 浮层高度；两侧仍可透出对话流。
                SliverPadding(
                  padding: listPadding,
                  sliver: IdeAnchoredDynamicSliverList(
                    controller: virtualListController,
                    delegate: delegate,
                  ),
                ),
              ],
            );

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
                    hasNewContent:
                        showButton && viewModel.liveTurnState != null,
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

  Widget _buildViewportItem(
    AgentTimelineViewportItem item,
    AgentPendingInteractionState pendingState,
  ) {
    switch (item) {
      case AgentBlockViewportItem(:final turn, :final block):
        return _AgentTimelineBlockSection(
          turn: turn,
          block: block,
          viewModel: viewModel,
          markdownCache: markdownCache,
          planRevisionDrafts: planRevisionDrafts,
          pendingState: pendingState,
        );
      case AgentLiveActivityViewportItem():
        return KeyedSubtree(
          key: const ValueKey('agent-live-turn-section'),
          child: _AgentLiveActivityStatus(
            viewModel: viewModel,
            isActive: isActive,
          ),
        );
      case AgentTurnFooterViewportItem(:final turn):
        return _AgentTurnFooter(turn: turn);
    }
  }

  ValueListenable<bool>? _prepareMarkdownWarmEntry(
    AgentTimelineViewportItem item,
  ) {
    if (item is! AgentBlockViewportItem) {
      return null;
    }
    final block = item.block;
    if (block is! AgentTimelineEntryRenderBlock) {
      return null;
    }
    final entry = block.entry;
    if (entry is! AgentMessageTimelineEntry) {
      return null;
    }
    final message = entry.message;
    if (message.role != AgentMessageRole.agent || message.isPlan) {
      return null;
    }
    return markdownCache.prepareWarmEntry(
      messageId: message.id,
      data: message.text,
      preferIncrementalUpdate: item.isLive,
    );
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
    required this.markdownCache,
    required this.planRevisionDrafts,
    required this.pendingState,
  });

  final AgentConversationTurnGroup turn;
  final AgentTimelineRenderBlock block;
  final AgentConversationViewModel viewModel;
  final AgentMarkdownCache markdownCache;
  final AgentPlanRevisionDraftStore planRevisionDrafts;

  /// 计划卡在流内渲染，需要知道当前是否有待处理的计划请求。
  final AgentPendingInteractionState pendingState;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: ValueKey<String>('turn-block-${turn.id}-${block.id}'),
      child: switch (block) {
        AgentTimelineEntryRenderBlock(:final entry) => _buildTimelineEntry(
          entry,
          markdownCache: markdownCache,
        ),
        AgentTimelineCommandGroupRenderBlock(:final group) =>
          _AgentCommandGroupCard(group: group, viewModel: viewModel),
        AgentTimelineFileEditGroupRenderBlock(:final group) =>
          _AgentFileEditGroupCard(group: group, viewModel: viewModel),
      },
    );
  }

  Widget _buildTimelineEntry(
    AgentTimelineEntry entry, {
    required AgentMarkdownCache markdownCache,
  }) {
    final isLiveTurn = viewModel.liveTurnState?.id == turn.id;
    return switch (entry) {
      AgentMessageTimelineEntry(:final message) => _AgentMessageEntry(
        message: message,
        // 历史与 live 正文均全文渲染，禁止折叠预览。
        useStreamingMarkdown: isLiveTurn,
        viewModel: viewModel,
        markdownCache: markdownCache,
        planRevisionDrafts: planRevisionDrafts,
        planExecutionHandoff: pendingState.planExecutionHandoff,
      ),
      AgentToolTimelineEntry(:final toolCall) => _AgentToolCallCard(
        toolCall: toolCall,
        viewModel: viewModel,
      ),
      // 权限与提问仍在 Composer 上方的 dock 渲染，避免时间线出现重复卡片。
      AgentPermissionTimelineEntry() => const SizedBox.shrink(),
      AgentQuestionTimelineEntry() => const SizedBox.shrink(),
      // 计划文档改在对话流内渲染：仍待审批时才是交互卡，决定后条目即被移除。
      AgentPlanApprovalTimelineEntry(:final request) => _buildPlanApprovalCard(
        request,
      ),
      // 正常路径会在 grouping 中转成文件编辑组；此处仅作兜底。
      AgentTurnDiffTimelineEntry() => const SizedBox.shrink(),
      AgentHistoryEventTimelineEntry(:final event) => _AgentHistoryEventCard(
        event: event,
      ),
    };
  }

  /// Provider 计划审批卡。
  ///
  /// 审批是阻塞请求、回合仍在运行，「修改」只能把意见随 `rejected` 决定回传，
  /// 不能走 `sendMessage`。「执行」仅代表接受方案，不预授权任何操作。
  Widget _buildPlanApprovalCard(AgentPlanApprovalRequest request) {
    return _AgentPlanDocumentCard(
      key: ValueKey<String>('agent-plan-approval-card-${request.id}'),
      requestId: request.id,
      title: request.title,
      subtitle: '接受计划仅确认方案；命令、文件与网络权限仍会单独请求。',
      markdown: request.markdown,
      todos: request.todos,
      phases: request.phases,
      revisionController: planRevisionDrafts.controllerFor(request.id),
      revisionFocusNode: planRevisionDrafts.focusNodeFor(request.id),
      viewModel: viewModel,
      onRevise: (revision) => unawaited(
        viewModel.respondToPlanApproval(
          request,
          AgentPlanApprovalDecisionKind.rejected,
          reason: revision,
        ),
      ),
      onExecute: () => unawaited(
        viewModel.respondToPlanApproval(
          request,
          AgentPlanApprovalDecisionKind.accepted,
        ),
      ),
      onAbandon: () => unawaited(
        viewModel.respondToPlanApproval(
          request,
          AgentPlanApprovalDecisionKind.cancelled,
        ),
      ),
    );
  }
}

/// 固定在 Composer 上方的待处理交互区。
///
/// 权限与用户提问从独立 pending 状态读取；计划文档已改在对话流内渲染。
/// [panelHeight] 由 AgentPane width-bucket 的约束旁路提供，不进入 bucket 身份。
class _AgentPendingInteractionSection extends StatelessWidget {
  const _AgentPendingInteractionSection({
    required this.viewModel,
    required this.panelHeight,
    required this.pagePadding,
  });

  final AgentConversationViewModel viewModel;
  final double panelHeight;
  final EdgeInsets pagePadding;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AgentPendingInteractionState>(
      valueListenable: viewModel.pendingInteractionStateListenable,
      builder: (context, state, _) => _buildDock(context, state),
    );
  }

  Widget _buildDock(BuildContext context, AgentPendingInteractionState state) {
    final permissionRequests = state.permissions;
    final questionRequests = state.questions;
    // 计划审批与执行交接改在对话流内渲染，dock 只承载权限与提问。
    if (state.isReadOnly ||
        (permissionRequests.isEmpty && questionRequests.isEmpty)) {
      return const SizedBox.shrink();
    }

    final maxHeight = panelHeight.isFinite
        ? math.min<double>(360.0, panelHeight * 0.35)
        : 360.0;
    final scrollIdentity = <String>[
      for (final request in permissionRequests) 'permission:${request.id}',
      for (final request in questionRequests) 'question:${request.id}',
    ].join('|');

    final cards = <Widget>[
      for (var index = 0; index < permissionRequests.length; index++)
        Padding(
          key: ValueKey(
            'agent-pending-permission-${permissionRequests[index].id}',
          ),
          padding: EdgeInsets.only(
            bottom:
                index < permissionRequests.length - 1 ||
                    questionRequests.isNotEmpty
                ? IdeSpacing.space8
                : 0,
          ),
          child: _buildPermissionCard(permissionRequests[index], state),
        ),
      for (var index = 0; index < questionRequests.length; index++)
        Padding(
          key: ValueKey('agent-pending-question-${questionRequests[index].id}'),
          padding: EdgeInsets.only(
            bottom: index < questionRequests.length - 1 ? IdeSpacing.space8 : 0,
          ),
          child: _AgentQuestionCard(
            request: questionRequests[index],
            onRespond: (answers) => viewModel.respondToQuestion(
              questionRequests[index],
              answers: answers,
            ),
          ),
        ),
    ];

    return _AgentContentAlign(
      child: Padding(
        padding: pagePadding.copyWith(top: IdeSpacing.space8, bottom: 0),
        child: ConstrainedBox(
          key: const ValueKey('agent-pending-interaction-dock'),
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            key: ValueKey<String>(
              'agent-pending-interaction-scroll-$scrollIdentity',
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: cards,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionCard(
    AgentPermissionRequest request,
    AgentPendingInteractionState state,
  ) {
    return _AgentPermissionCard(
      request: request,
      autoReview: state.autoReviewForTurn(request.turnId),
      onApproveGuardian: state.latestDeniedAutoReview != null
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
    required this.state,
    required this.inputController,
    required this.composerFocusNode,
    required this.canSendListenable,
    required this.draftImagePaths,
    required this.onAttachImages,
    required this.onRemoveImage,
    required this.onSend,
    required this.onOpenMentionPicker,
    required this.onInsertSkill,
    required this.pagePadding,
    this.anchorKey,
    super.key,
  });

  final AgentConversationViewModel viewModel;
  final AgentComposerState state;
  final TextEditingController inputController;
  final FocusNode composerFocusNode;
  final ValueListenable<bool> canSendListenable;
  final List<String> draftImagePaths;
  final VoidCallback onAttachImages;
  final ValueChanged<String> onRemoveImage;
  final VoidCallback onSend;
  final VoidCallback onOpenMentionPicker;
  final VoidCallback onInsertSkill;
  final EdgeInsets pagePadding;

  /// Skill popover 锚定用；挂在 Composer 根节点上。
  final Key? anchorKey;

  @override
  Widget build(BuildContext context) {
    return _AgentContentAlign(
      child: Padding(
        padding: pagePadding.copyWith(top: IdeSpacing.space8),
        child: ValueListenableBuilder<bool>(
          valueListenable: canSendListenable,
          builder: (context, canSend, _) {
            return KeyedSubtree(
              key: anchorKey,
              child: _AgentComposer(
                controller: inputController,
                focusNode: composerFocusNode,
                canSubmit: canSend && state.canSubmitMessage,
                isTurnRunning: state.isTurnRunning,
                threadOpenPhase: state.threadOpenPhase,
                currentWindowTokenUsage: state.contextUsage,
                draftImagePaths: draftImagePaths,
                onAttachImages: onAttachImages,
                onRemoveImage: onRemoveImage,
                onSend: onSend,
                onCancel: viewModel.cancelActiveTurn,
                showImageAttachment: state.canAttachImages,
                showResourceMention: state.canMentionResources,
                showSkillInsert: state.canUseSkills,
                conversationModeStatus: _modeSelectorStatus(
                  state.conversationModeStatus,
                ),
                conversationModeOptions: state.conversationModeOptions,
                selectedConversationMode: state.selectedConversationMode,
                conversationModeAppliesToNextTurn:
                    state.conversationModeAppliesToNextTurn,
                conversationModeContextId: state.conversationModeContextId,
                onSelectConversationMode: viewModel.selectConversationMode,
                showModelSelection: state.showModelSelection,
                modelConfigState: state.modelConfigState,
                showPermissionPolicy: state.showPermissionPolicy,
                permissionPolicyLabel: state.permissionPolicyLabel,
                permissionOptions: state.permissionOptions,
                selectedPermissionOptionId: state.selectedPermissionOptionId,
                permissionApplyScopeHint: state.permissionApplyScopeHint,
                sessionConfigOptions: state.sessionConfigOptions,
                onSelectModel: viewModel.selectModel,
                onSelectReasoningEffort: viewModel.selectReasoningEffort,
                onSelectFastEnabled: viewModel.selectFastEnabled,
                onResolveModelCompatibility:
                    viewModel.resolveModelCompatibilityConflict,
                onRetryModelConfiguration:
                    viewModel.retryModelConfigurationSave,
                onCloseModelConfiguration:
                    viewModel.clearModelConfigurationTransientState,
                onSelectPermissionOption: (option) async {
                  final error = await viewModel.selectPermissionOption(option);
                  if (!context.mounted) {
                    return;
                  }
                  if (error != null && error.isNotEmpty) {
                    showIdeToast(
                      context,
                      message: error,
                      tone: IdeToastTone.error,
                    );
                    return;
                  }
                  final hint = viewModel.takePermissionApplyHint();
                  if (hint != null && hint.isNotEmpty) {
                    showIdeToast(context, message: hint);
                  }
                },
                onSelectSessionConfigOption:
                    viewModel.selectSessionConfigOption,
                onOpenMentionPicker: onOpenMentionPicker,
                onInsertSkill: onInsertSkill,
              ),
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

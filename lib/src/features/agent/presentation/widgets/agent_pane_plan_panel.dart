part of '../agent_pane.dart';

const double _activePlanPanelMaxWidth = 340;
const double _activePlanScrollMaxHeight = 200;

/// 固定在 Composer 上方的当前 turn 结构化计划。
class _AgentActivePlanSection extends StatelessWidget {
  const _AgentActivePlanSection({
    required this.viewModel,
    required this.pagePadding,
    required this.onExtentChanged,
  });

  final AgentConversationViewModel viewModel;
  final EdgeInsets pagePadding;

  /// 向时间线同步浮层实测高度，用于滚动底部 inset（不缩短 viewport）。
  final ValueChanged<double> onExtentChanged;

  @override
  Widget build(BuildContext context) {
    return _FloatingPanelExtentReporter(
      onExtent: onExtentChanged,
      child: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[
          viewModel.liveTurnListenable,
          viewModel.headerStateListenable,
          viewModel.pendingInteractionStateListenable,
          viewModel.expansionStateListenable,
        ]),
        builder: (context, _) {
          final turnState = viewModel.liveTurnState;
          if (turnState == null) {
            return const SizedBox.shrink();
          }
          return ListenableBuilder(
            listenable: turnState,
            builder: (context, _) {
              final entries = turnState.planEntries;
              if (!viewModel.shouldShowActivePlan) {
                return const SizedBox.shrink();
              }
              return _AgentContentAlign(
                // CustomMultiChildLayout 会给浮层一个有界最大高度；这里必须按内容
                // 收缩，否则 Align 会占满 Footer 上方空间并把卡片留在时间线顶部。
                shrinkWrapHeight: true,
                child: Padding(
                  padding: pagePadding.copyWith(
                    top: IdeSpacing.space8,
                    bottom: 0,
                  ),
                  child: Align(
                    alignment: Alignment.topCenter,
                    heightFactor: 1,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _activePlanPanelMaxWidth,
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: _AgentActivePlanCard(
                          key: ValueKey<String>(
                            'agent-active-plan-card-${turnState.id}',
                          ),
                          turnId: turnState.id,
                          entries: entries,
                          expanded: viewModel.expansionState
                              .isActivePlanExpanded(turnState.id),
                          onToggle: () =>
                              viewModel.toggleActivePlan(turnState.id),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// 在 layout 完成后上报子树高度；高度未变时不回调，避免无意义重建。
class _FloatingPanelExtentReporter extends SingleChildRenderObjectWidget {
  const _FloatingPanelExtentReporter({required this.onExtent, super.child});

  final ValueChanged<double> onExtent;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderFloatingPanelExtentReporter(onExtent: onExtent);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderFloatingPanelExtentReporter renderObject,
  ) {
    renderObject.onExtent = onExtent;
  }
}

class _RenderFloatingPanelExtentReporter extends RenderProxyBox {
  _RenderFloatingPanelExtentReporter({required this.onExtent});

  ValueChanged<double> onExtent;
  double? _lastExtent;
  double? _reportedExtent;

  @override
  void performLayout() {
    super.performLayout();
    final extent = size.height;
    if (_lastExtent == extent) {
      return;
    }
    _lastExtent = extent;
    // 避免在 layout 阶段同步改动 listenable；同帧多次 layout 取最终高度。
    scheduleMicrotask(() {
      final pending = _lastExtent;
      if (pending == null || pending == _reportedExtent) {
        return;
      }
      _reportedExtent = pending;
      onExtent(pending);
    });
  }
}

class _AgentActivePlanCard extends StatefulWidget {
  const _AgentActivePlanCard({
    required this.turnId,
    required this.entries,
    required this.expanded,
    required this.onToggle,
    super.key,
  });

  final String turnId;
  final List<AgentPlanEntry> entries;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  State<_AgentActivePlanCard> createState() => _AgentActivePlanCardState();
}

class _AgentActivePlanCardState extends State<_AgentActivePlanCard> {
  final ScrollController _scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final currentIndex = _activePlanCurrentIndex(widget.entries);
    final current = widget.entries[currentIndex];
    final progress = '${currentIndex + 1}/${widget.entries.length}';

    return RepaintBoundary(
      child: PanelCard(
        // 仅降低浮层背景不透明度，保留文字与状态标记的完整对比度。
        color: colors.surfaceElevated.withValues(alpha: 0.8),
        borderColor: colors.border,
        borderRadius: IdeRadius.allMedium,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PaneInteractiveSurface(
              key: ValueKey<String>(
                'agent-active-plan-toggle-${widget.turnId}',
              ),
              onPressed: widget.onToggle,
              padding: const EdgeInsets.fromLTRB(
                IdeSpacing.space12,
                IdeSpacing.space4,
                IdeSpacing.space8,
                IdeSpacing.space4,
              ),
              borderRadius: IdeRadius.allMedium,
              hoverBackgroundColor: colors.hoverSurface,
              semanticLabel: widget.expanded ? '收起当前计划' : '展开当前计划',
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: colors.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: IdeSpacing.space8),
                  Expanded(
                    child: Text(
                      'Plan',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textStyles.titleLarge.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  Semantics(
                    label: '当前计划进度 $progress',
                    child: Container(
                      key: ValueKey<String>(
                        'agent-active-plan-progress-${widget.turnId}',
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: IdeSpacing.space10,
                        vertical: IdeSpacing.space4,
                      ),
                      decoration: BoxDecoration(
                        color: colors.border.withValues(alpha: 0.26),
                        borderRadius: IdeRadius.pill,
                      ),
                      child: Text(
                        progress,
                        style: textStyles.codeSmall.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: IdeSpacing.space4),
                  AnimatedRotation(
                    turns: widget.expanded ? 0.25 : 0,
                    duration: IdeMotion.durationNormal,
                    curve: IdeMotion.curveDefault,
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: colors.textSecondary.withValues(alpha: 0.58),
                    ),
                  ),
                ],
              ),
            ),
            if (!widget.expanded)
              Padding(
                key: ValueKey<String>(
                  'agent-active-plan-summary-${widget.turnId}',
                ),
                padding: const EdgeInsets.fromLTRB(
                  IdeSpacing.space12,
                  0,
                  IdeSpacing.space12,
                  IdeSpacing.space10,
                ),
                child: Semantics(
                  label: '当前步骤：${current.content}',
                  excludeSemantics: true,
                  child: Row(
                    children: [
                      Text(
                        '当前',
                        style: textStyles.bodySmall.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                      const SizedBox(width: IdeSpacing.space8),
                      Expanded(
                        child: _AgentPlanOverflowText(
                          content: current.content,
                          style: textStyles.bodyMedium.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            AnimatedSize(
              duration: IdeMotion.durationSlow,
              curve: IdeMotion.curvePopup,
              alignment: Alignment.topCenter,
              child: widget.expanded
                  ? Column(
                      key: ValueKey<String>(
                        'agent-active-plan-body-${widget.turnId}',
                      ),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(height: 1, color: colors.borderSubtle),
                        ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxHeight: _activePlanScrollMaxHeight,
                          ),
                          child: Scrollbar(
                            controller: _scrollController,
                            child: ListView.builder(
                              key: ValueKey<String>(
                                'agent-active-plan-scroll-${widget.turnId}',
                              ),
                              controller: _scrollController,
                              primary: false,
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(
                                vertical: IdeSpacing.space6,
                              ),
                              itemCount: widget.entries.length,
                              itemBuilder: (context, index) =>
                                  _AgentActivePlanStepRow(
                                    key: ValueKey<String>(
                                      'agent-active-plan-step-'
                                      '${widget.turnId}-$index',
                                    ),
                                    entry: widget.entries[index],
                                  ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}

class _AgentActivePlanStepRow extends StatelessWidget {
  const _AgentActivePlanStepRow({required this.entry, super.key});

  final AgentPlanEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return Semantics(
      label:
          '${_activePlanStatusLabel(entry.normalizedStatus)}：${entry.content}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: IdeSpacing.space12,
          vertical: IdeSpacing.space4,
        ),
        child: Row(
          children: [
            _AgentActivePlanStatusMarker(status: entry.normalizedStatus),
            const SizedBox(width: IdeSpacing.space10),
            Expanded(
              child: _AgentPlanOverflowText(
                content: entry.content,
                style: textStyles.bodyMedium.copyWith(
                  color:
                      entry.normalizedStatus == AgentPlanEntryStatus.completed
                      ? colors.textSecondary
                      : colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 保持单行紧凑布局，并仅在内容实际被截断时提供完整文本 Tooltip。
class _AgentPlanOverflowText extends StatelessWidget {
  const _AgentPlanOverflowText({required this.content, required this.style});

  final String content;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: content, style: style),
          maxLines: 1,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          locale: Localizations.maybeLocaleOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final didOverflow = painter.didExceedMaxLines;
        painter.dispose();

        return IdeTooltip(
          message: content,
          enabled: didOverflow,
          child: Text(
            content,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        );
      },
    );
  }
}

class _AgentActivePlanStatusMarker extends StatelessWidget {
  const _AgentActivePlanStatusMarker({required this.status});

  final AgentPlanEntryStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final color = switch (status) {
      AgentPlanEntryStatus.completed => colors.success,
      AgentPlanEntryStatus.inProgress => colors.accent,
      AgentPlanEntryStatus.pending ||
      AgentPlanEntryStatus.unknown => colors.border,
    };
    final completed = status == AgentPlanEntryStatus.completed;
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: completed ? color : null,
        shape: BoxShape.circle,
        border: completed ? null : Border.all(color: color, width: 1.5),
      ),
    );
  }
}

int _activePlanCurrentIndex(List<AgentPlanEntry> entries) {
  final inProgress = entries.indexWhere(
    (entry) => entry.normalizedStatus == AgentPlanEntryStatus.inProgress,
  );
  if (inProgress != -1) {
    return inProgress;
  }
  final pending = entries.indexWhere(
    (entry) => entry.normalizedStatus == AgentPlanEntryStatus.pending,
  );
  if (pending != -1) {
    return pending;
  }
  final unknown = entries.indexWhere(
    (entry) => entry.normalizedStatus == AgentPlanEntryStatus.unknown,
  );
  return unknown == -1 ? entries.length - 1 : unknown;
}

String _activePlanStatusLabel(AgentPlanEntryStatus status) {
  return switch (status) {
    AgentPlanEntryStatus.completed => '已完成',
    AgentPlanEntryStatus.inProgress => '进行中',
    AgentPlanEntryStatus.pending => '待处理',
    AgentPlanEntryStatus.unknown => '状态未知',
  };
}

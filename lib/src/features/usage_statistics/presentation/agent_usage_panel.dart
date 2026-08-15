import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta/src/features/agent/domain/agent_usage_models.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_provider_icon.dart';
import 'package:zeta/src/features/usage_statistics/application/agent_usage_panel_controller.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_panel_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';
import 'package:zeta/src/features/usage_statistics/presentation/agent_usage_quota_gallery.dart';
import 'package:zeta/src/features/usage_statistics/presentation/usage_statistics_formatters.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_effects.dart';
import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/ide_motion.dart';
import 'package:zeta/src/ui/core/ide_popover.dart';
import 'package:zeta/src/ui/core/ide_skeleton.dart';
import 'package:zeta/src/ui/core/rows/ide_row_divider.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/ide_tabs.dart';
import 'package:zeta/src/ui/core/ide_text_styles.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';
import 'package:zeta/src/ui/core/surfaces/ide_surface.dart';

/// Agent 统计在合并左栏中的显示模式。
enum AgentUsagePanelMode { collapsed, expanded }

/// 不包含 [PanelCard] 外框的 Agent 统计内容。
///
/// 左栏常驻的始终是最多三行的折叠摘要；展开态不再原地撑高，而是以摘要为锚点
/// 向上弹出 Popover 承载完整统计，避免挤压 Projects 列表。
class AgentUsagePanelContent extends StatefulWidget {
  const AgentUsagePanelContent({
    required this.controller,
    required this.mode,
    super.key,
    this.onModeChanged,
  });

  final AgentUsagePanelController controller;
  final AgentUsagePanelMode mode;
  final ValueChanged<AgentUsagePanelMode>? onModeChanged;

  @override
  State<AgentUsagePanelContent> createState() => _AgentUsagePanelContentState();
}

class _AgentUsagePanelContentState extends State<AgentUsagePanelContent> {
  /// 锚点上方空间不足时仍保留的最小弹层高度，避免塌缩成不可读的窄条。
  static const double _minPopoverHeight = 160;

  /// 弹层相对锚点左右各内缩的间距，避免贴死左栏边缘。
  static const double _popoverInset = IdeSpacing.space4;

  IdePopoverHandle<void>? _popover;
  bool _openScheduled = false;

  @override
  void initState() {
    super.initState();
    _syncPopover();
  }

  @override
  void didUpdateWidget(covariant AgentUsagePanelContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.mode != oldWidget.mode) {
      _syncPopover();
    }
  }

  @override
  void dispose() {
    final popover = _popover;
    _popover = null;
    if (popover != null) {
      // 关闭会触发 overlay 重建，而 dispose 期间组件树被锁定，推迟到帧末执行。
      WidgetsBinding.instance.addPostFrameCallback((_) => popover.dismiss());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => _CompactAgentUsage(
        controller: widget.controller,
        expanded: widget.mode == AgentUsagePanelMode.expanded,
        onToggle: widget.onModeChanged == null ? null : _toggleMode,
      ),
    );
  }

  void _toggleMode() {
    widget.onModeChanged?.call(
      widget.mode == AgentUsagePanelMode.expanded
          ? AgentUsagePanelMode.collapsed
          : AgentUsagePanelMode.expanded,
    );
  }

  void _syncPopover() {
    if (widget.mode == AgentUsagePanelMode.expanded) {
      _scheduleOpen();
      return;
    }
    _popover?.dismiss();
  }

  /// 弹层需要锚点已完成布局，因此挂载 overlay 推迟到本帧结束。
  void _scheduleOpen() {
    if (_popover != null || _openScheduled) {
      return;
    }
    _openScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openScheduled = false;
      if (!mounted ||
          _popover != null ||
          widget.mode != AgentUsagePanelMode.expanded) {
        return;
      }
      _openPopover();
    });
  }

  void _openPopover() {
    final anchor = context.findRenderObject();
    if (anchor is! RenderBox || !anchor.hasSize) {
      return;
    }
    final mediaQuery = MediaQuery.of(context);
    final anchorTop = anchor.localToGlobal(Offset.zero).dy;
    final maxHeight = math.max(
      _minPopoverHeight,
      anchorTop -
          mediaQuery.padding.top -
          IdeSpacing.space6 -
          IdeSpacing.space12,
    );
    final width = math.max(1.0, anchor.size.width - _popoverInset * 2);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : IdeMotion.durationFast;
    final handle = showIdePopover<void>(
      context: context,
      // 锚点顶边对齐弹层底边：始终向上弹出，不随空间不足翻转到下方。
      alignment: Alignment.bottomLeft,
      anchorAlignment: Alignment.topLeft,
      widthConstraint: IdePopoverConstraint.flexible,
      heightConstraint: IdePopoverConstraint.flexible,
      // 宽度由 builder 按锚点内缩后固定，这里同步右移相同间距保持左右对称。
      offset: const Offset(_popoverInset, -IdeSpacing.space6),
      // 横向留白由内缩宽度承担，margin 只管纵向，避免再被推离左栏。
      margin: const EdgeInsets.symmetric(vertical: IdeSpacing.space12),
      transitionAlignment: Alignment.bottomLeft,
      allowInvertVertical: false,
      showDuration: duration,
      dismissDuration: duration,
      builder: (_) => _AgentUsagePopover(
        controller: widget.controller,
        width: width,
        maxHeight: maxHeight,
      ),
    );
    _popover = handle;
    unawaited(_awaitPopoverClose(handle));
  }

  /// 点击弹层外部或锚点开合按钮最终都从同一 future 收敛回折叠态。
  Future<void> _awaitPopoverClose(IdePopoverHandle<void> handle) async {
    await handle.future;
    handle.dispose();
    if (!mounted || !identical(_popover, handle)) {
      return;
    }
    _popover = null;
    if (widget.mode == AgentUsagePanelMode.expanded) {
      widget.onModeChanged?.call(AgentUsagePanelMode.collapsed);
    }
  }
}

/// 向上弹出的 Agent 统计弹层：内容超出可用高度时在弹层内滚动。
class _AgentUsagePopover extends StatelessWidget {
  const _AgentUsagePopover({
    required this.controller,
    required this.width,
    required this.maxHeight,
  });

  final AgentUsagePanelController controller;

  /// 锚点宽度左右各内缩后的弹层宽度。
  final double width;

  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: width,
        maxWidth: width,
        maxHeight: maxHeight,
      ),
      child: IdeSurface.popover(
        key: const ValueKey('agent-usage-popover'),
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => _AgentUsagePanelBody(controller: controller),
        ),
      ),
    );
  }
}

class _AgentUsageRefreshButton extends StatelessWidget {
  const _AgentUsageRefreshButton({required this.controller});

  final AgentUsagePanelController controller;

  @override
  Widget build(BuildContext context) {
    return IdeTooltip(
      message: '刷新用量',
      child: sf.IconButton.ghost(
        key: const ValueKey('agent-usage-refresh-button'),
        onPressed: controller.isLoading
            ? null
            : () => unawaited(controller.refresh()),
        size: sf.ButtonSize.small,
        density: sf.ButtonDensity.iconDense,
        icon: const Icon(Icons.refresh_rounded, size: 16),
      ),
    );
  }
}

class _AgentUsageModeButton extends StatelessWidget {
  const _AgentUsageModeButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IdeTooltip(
      message: tooltip,
      child: PaneInteractiveSurface(
        onPressed: onPressed,
        enabled: onPressed != null,
        button: true,
        semanticLabel: tooltip,
        width: IdeMetrics.iconButtonHitSize,
        height: IdeMetrics.iconButtonHitSize,
        padding: EdgeInsets.zero,
        borderRadius: IdeRadius.allSmall,
        child: Icon(icon, size: 16, color: IdeColors.of(context).textSecondary),
      ),
    );
  }
}

/// 折叠摘要同时是弹层锚点：[expanded] 只影响开合按钮的图标与语义。
class _CompactAgentUsage extends StatelessWidget {
  const _CompactAgentUsage({
    required this.controller,
    required this.expanded,
    required this.onToggle,
  });

  final AgentUsagePanelController controller;
  final bool expanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    if (controller.providers.isEmpty) {
      if (controller.isLoading) {
        return _CompactAgentUsageSkeleton(
          expanded: expanded,
          onToggle: onToggle,
        );
      }
      if (controller.errorMessage case final error?) {
        return _CompactAgentUsageMessage(
          message: error,
          warning: true,
          onRetry: () => unawaited(controller.refresh()),
          expanded: expanded,
          onToggle: onToggle,
        );
      }
      return _CompactAgentUsageMessage(
        message: '暂无已启用的 Agent',
        expanded: expanded,
        onToggle: onToggle,
      );
    }

    final selected = controller.selectedProvider!;
    final entry = selected.entry;
    if (entry == null) {
      if (selected.isLoading) {
        return _CompactAgentUsageSkeleton(
          expanded: expanded,
          onToggle: onToggle,
        );
      }
      if (selected.loadError case final error?) {
        return _CompactAgentUsageMessage(
          message: error,
          warning: true,
          onRetry: () => unawaited(controller.refresh()),
          expanded: expanded,
          onToggle: onToggle,
        );
      }
      return _CompactAgentUsageMessage(
        message: '暂无统计',
        expanded: expanded,
        onToggle: onToggle,
      );
    }

    return _CompactAgentUsageSummary(
      entry: entry,
      providerName: selected.provider.providerName,
      expanded: expanded,
      onToggle: onToggle,
    );
  }
}

/// 摘要右上角的弹层开合按钮。
class _AgentUsageToggleButton extends StatelessWidget {
  const _AgentUsageToggleButton({
    required this.expanded,
    required this.onToggle,
  });

  final bool expanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    return _AgentUsageModeButton(
      key: const ValueKey('agent-usage-expand-button'),
      icon: expanded
          ? Icons.keyboard_arrow_down_rounded
          : Icons.keyboard_arrow_up_rounded,
      tooltip: expanded ? '折叠 Agent 统计' : '展开 Agent 统计',
      onPressed: onToggle,
    );
  }
}

class _CompactAgentUsageSummary extends StatelessWidget {
  const _CompactAgentUsageSummary({
    required this.entry,
    required this.providerName,
    required this.expanded,
    required this.onToggle,
  });

  final AgentUsagePanelEntry entry;
  final String providerName;
  final bool expanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final textStyles = IdeTextStyles.of(context);
    final colors = IdeColors.of(context);
    final quotaWindow = entry.compactQuotaWindow;
    final title = entry.hasSubscriptionPlan
        ? formatUsagePlanType(entry.quota?.planType)
        : providerName;
    final tokenTotal = entry.todayTokens == null
        ? '-'
        : formatUsageCount(entry.todayTokens!.effectiveTotal ?? 0);

    return Semantics(
      container: true,
      label: 'Agent 统计摘要',
      child: Padding(
        key: const ValueKey('agent-usage-compact'),
        padding: const EdgeInsets.symmetric(
          horizontal: IdeSpacing.space12,
          vertical: IdeSpacing.space8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              key: const ValueKey('agent-usage-compact-header'),
              children: [
                AgentProviderIcon(providerId: entry.providerId, size: 18),
                const SizedBox(width: IdeSpacing.space8),
                Expanded(
                  child: Text(
                    title,
                    key: const ValueKey('agent-usage-compact-title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textStyles.titleSmall.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: IdeSpacing.space4),
                _AgentUsageToggleButton(expanded: expanded, onToggle: onToggle),
              ],
            ),
            if (quotaWindow != null) ...[
              const SizedBox(height: IdeSpacing.space4),
              _CompactQuotaWindow(window: quotaWindow),
            ],
            const SizedBox(height: IdeSpacing.space4),
            Row(
              key: const ValueKey('agent-usage-compact-tokens'),
              children: [
                Expanded(
                  child: Text(
                    '今日 Token',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textStyles.bodySmall.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: IdeSpacing.space8),
                Text(
                  tokenTotal,
                  key: const ValueKey('agent-usage-compact-token-value'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textStyles.numeric.copyWith(color: colors.textPrimary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactQuotaWindow extends StatelessWidget {
  const _CompactQuotaWindow({required this.window});

  final AgentUsageWindow window;

  @override
  Widget build(BuildContext context) {
    final textStyles = IdeTextStyles.of(context);
    final colors = IdeColors.of(context);
    final used = window.usedPercent.clamp(0, 100);
    final remaining = math.max(0, 100 - used);
    return Row(
      key: const ValueKey('agent-usage-compact-quota'),
      children: [
        Expanded(
          child: Text(
            window.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyles.bodySmall.copyWith(color: colors.textSecondary),
          ),
        ),
        const SizedBox(width: IdeSpacing.space8),
        SizedBox(
          width: 64,
          child: AgentUsageQuotaProgressBar(usedPercent: used.toDouble()),
        ),
        const SizedBox(width: IdeSpacing.space6),
        Text(
          '$remaining%',
          key: const ValueKey('agent-usage-compact-quota-remaining'),
          style: textStyles.caption.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

class _CompactAgentUsageSkeleton extends StatelessWidget {
  const _CompactAgentUsageSkeleton({
    required this.expanded,
    required this.onToggle,
  });

  final bool expanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '正在读取 Agent 用量',
      container: true,
      explicitChildNodes: true,
      child: Padding(
        key: const ValueKey('agent-usage-compact-loading'),
        padding: const EdgeInsets.symmetric(
          horizontal: IdeSpacing.space12,
          vertical: IdeSpacing.space8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: IdeSkeletonLine(width: 136, height: 16),
                  ),
                ),
                const SizedBox(width: IdeSpacing.space4),
                _AgentUsageToggleButton(expanded: expanded, onToggle: onToggle),
              ],
            ),
            const SizedBox(height: IdeSpacing.space4),
            const IdeSkeletonLine(height: 10),
            const SizedBox(height: IdeSpacing.space4),
            const IdeSkeletonLine(width: 96, height: 12),
          ],
        ),
      ),
    );
  }
}

class _CompactAgentUsageMessage extends StatelessWidget {
  const _CompactAgentUsageMessage({
    required this.message,
    required this.expanded,
    required this.onToggle,
    this.warning = false,
    this.onRetry,
  });

  final String message;
  final bool warning;
  final VoidCallback? onRetry;
  final bool expanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return Padding(
      key: ValueKey(
        warning ? 'agent-usage-compact-error' : 'agent-usage-compact',
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: IdeSpacing.space12,
        vertical: IdeSpacing.space8,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textStyles.bodySmall.copyWith(
                color: warning ? colors.warning : colors.textSecondary,
              ),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: IdeSpacing.space4),
            _AgentUsageModeButton(
              key: const ValueKey('agent-usage-retry-button'),
              icon: Icons.refresh_rounded,
              tooltip: '重试读取 Agent 用量',
              onPressed: onRetry,
            ),
          ],
          const SizedBox(width: IdeSpacing.space4),
          _AgentUsageToggleButton(expanded: expanded, onToggle: onToggle),
        ],
      ),
    );
  }
}

class _AgentUsagePanelBody extends StatelessWidget {
  const _AgentUsagePanelBody({required this.controller});

  final AgentUsagePanelController controller;

  @override
  Widget build(BuildContext context) {
    final selected = controller.selectedProvider;
    final Widget content;
    if (controller.providers.isEmpty) {
      if (controller.isLoading) {
        // 冷加载：呼吸 Skeleton 替代顶栏不定进度条与文案。
        content = const _AgentUsageSkeleton(
          key: ValueKey<String>('agent-usage-panel-loading'),
          showProviderTitle: true,
        );
      } else if (controller.errorMessage != null) {
        content = _RetryState(
          message: controller.errorMessage!,
          onRetry: () => unawaited(controller.refresh()),
        );
      } else {
        content = const EmptyState(text: '暂无已启用的 Agent');
      }
    } else {
      final resolvedSelected = selected!;
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (controller.errorMessage case final error?)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                IdeSpacing.space12,
                IdeSpacing.space6,
                IdeSpacing.space12,
                0,
              ),
              child: Text(
                error,
                style: IdeTextStyles.of(
                  context,
                ).caption.copyWith(color: IdeColors.of(context).warning),
              ),
            ),
          if (resolvedSelected.entry != null &&
              resolvedSelected.loadError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                IdeSpacing.space12,
                IdeSpacing.space6,
                IdeSpacing.space12,
                0,
              ),
              child: Text(
                resolvedSelected.loadError!,
                style: IdeTextStyles.of(
                  context,
                ).caption.copyWith(color: IdeColors.of(context).warning),
              ),
            ),
          _SelectedProviderBody(
            state: resolvedSelected,
            controller: controller,
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tabs 与刷新常驻底部，仅正文在弹层可用高度内滚动。
        Flexible(child: SingleChildScrollView(child: content)),
        _AgentUsageTabsToolbar(
          controller: controller,
          selectedProviderId: selected?.provider.providerId,
        ),
      ],
    );
  }
}

class _AgentUsageTabsToolbar extends StatelessWidget {
  const _AgentUsageTabsToolbar({
    required this.controller,
    required this.selectedProviderId,
  });

  final AgentUsagePanelController controller;
  final String? selectedProviderId;

  @override
  Widget build(BuildContext context) {
    final showTabs =
        controller.providers.length > 1 && selectedProviderId != null;
    return Padding(
      key: const ValueKey('agent-usage-tabs-toolbar'),
      padding: const EdgeInsets.fromLTRB(
        IdeSpacing.space8,
        0,
        IdeSpacing.space6,
        IdeSpacing.space8,
      ),
      child: Row(
        children: [
          if (showTabs)
            Expanded(
              child: IdeTabs<String>(
                key: const ValueKey('agent-usage-tabs'),
                value: selectedProviderId!,
                semanticLabel: '选择 Agent 用量',
                scrollContentAlignment: Alignment.center,
                items: [
                  for (final state in controller.providers)
                    IdeTabItem<String>(
                      key: ValueKey<String>(
                        'agent-usage-tab-${state.provider.providerId}',
                      ),
                      value: state.provider.providerId,
                      label: state.provider.providerName,
                      loading: state.isLoading,
                    ),
                ],
                onChanged: controller.selectProvider,
              ),
            )
          else
            const Spacer(),
          if (showTabs) const SizedBox(width: IdeSpacing.space4),
          _AgentUsageRefreshButton(controller: controller),
        ],
      ),
    );
  }
}

class _SelectedProviderBody extends StatelessWidget {
  const _SelectedProviderBody({required this.state, required this.controller});

  final AgentUsagePanelProviderState state;
  final AgentUsagePanelController controller;

  @override
  Widget build(BuildContext context) {
    final entry = state.entry;
    if (entry == null) {
      if (state.isLoading) {
        return _AgentUsageSkeleton(
          key: ValueKey<String>(
            'agent-usage-provider-loading-${state.provider.providerId}',
          ),
          showProviderTitle: controller.providers.length == 1,
        );
      }
      if (state.loadError case final error?) {
        return _RetryState(
          message: error,
          onRetry: () => unawaited(controller.refresh()),
        );
      }
      return const EmptyState(text: '暂无统计');
    }

    return Padding(
      padding: const EdgeInsets.all(IdeSpacing.space12),
      child: _ProviderUsage(
        key: ValueKey<String>(
          'agent-usage-provider-${state.provider.providerId}',
        ),
        entry: entry,
        providerName: state.provider.providerName,
        showProviderName: controller.providers.length == 1,
      ),
    );
  }
}

/// Agent 统计冷加载骨架：套餐区 + 今日 Token 行，布局贴近 [_ProviderUsage]。
class _AgentUsageSkeleton extends StatelessWidget {
  const _AgentUsageSkeleton({required this.showProviderTitle, super.key});

  final bool showProviderTitle;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '正在读取 Agent 用量',
      container: true,
      child: Padding(
        padding: const EdgeInsets.all(IdeSpacing.space12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showProviderTitle) ...[
              const IdeSkeletonLine(width: 120, height: 16),
              const SizedBox(height: IdeSpacing.space12),
            ],
            const IdeSkeletonLine(width: 140, height: 22),
            const SizedBox(height: IdeSpacing.space10),
            const _SkeletonQuotaGallery(),
            const SizedBox(height: IdeSpacing.space12),
            const Row(
              children: [
                IdeSkeletonLine(width: 56, height: 10),
                Spacer(),
                IdeSkeletonLine(width: 64, height: 18),
              ],
            ),
            const SizedBox(height: IdeSpacing.space10),
            const _SkeletonTokenGrid(),
          ],
        ),
      ),
    );
  }
}

class _SkeletonQuotaGallery extends StatelessWidget {
  const _SkeletonQuotaGallery();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: agentUsageQuotaGalleryHeight,
      child: Row(
        children: [
          Expanded(child: _SkeletonQuotaCapsule()),
          SizedBox(width: agentUsageQuotaGalleryGap),
          Expanded(child: _SkeletonQuotaCapsule()),
        ],
      ),
    );
  }
}

class _SkeletonQuotaCapsule extends StatelessWidget {
  const _SkeletonQuotaCapsule();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(IdeSpacing.space8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: IdeSkeletonLine(height: 12)),
              SizedBox(width: IdeSpacing.space8),
              IdeSkeletonLine(width: 28, height: 10),
            ],
          ),
          SizedBox(height: IdeSpacing.space6),
          IdeSkeletonLine(height: 4),
          SizedBox(height: IdeSpacing.space2),
          IdeSkeletonLine(width: 64, height: 10),
        ],
      ),
    );
  }
}

/// [_TokenMetricGrid] 的骨架版本：同一容器化背景 + 2×2 占位块。
class _SkeletonTokenGrid extends StatelessWidget {
  const _SkeletonTokenGrid();

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.hoverSurface,
        borderRadius: IdeRadius.allSmall,
      ),
      child: const Padding(
        padding: EdgeInsets.all(IdeSpacing.space8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: _SkeletonTokenCell()),
                SizedBox(width: IdeSpacing.space8),
                Expanded(child: _SkeletonTokenCell()),
              ],
            ),
            SizedBox(height: IdeSpacing.space8),
            Row(
              children: [
                Expanded(child: _SkeletonTokenCell()),
                SizedBox(width: IdeSpacing.space8),
                Expanded(child: _SkeletonTokenCell()),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonTokenCell extends StatelessWidget {
  const _SkeletonTokenCell();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: IdeSkeletonLine(height: 10)),
        SizedBox(width: IdeSpacing.space6),
        IdeSkeletonLine(width: 28, height: 12),
      ],
    );
  }
}

class _ProviderUsage extends StatelessWidget {
  const _ProviderUsage({
    required this.entry,
    required this.providerName,
    required this.showProviderName,
    super.key,
  });

  final AgentUsagePanelEntry entry;
  final String providerName;
  final bool showProviderName;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final resetCreditCount = entry.quota?.availableResetCreditCount;
    final hasResetCredits = resetCreditCount != null && resetCreditCount > 0;
    final hasQuotaWindows = entry.quota?.windows.isNotEmpty ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showProviderName) ...[
          Text(
            providerName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyles.titleSmall,
          ),
          const SizedBox(height: IdeSpacing.space12),
        ],
        if (hasQuotaWindows || hasResetCredits) ...[
          if (hasQuotaWindows) _PlanSection(quota: entry.quota!),
          if (hasQuotaWindows && hasResetCredits)
            const SizedBox(height: IdeSpacing.space10),
          if (hasResetCredits) _ResetCreditCountRow(count: resetCreditCount),
          const SizedBox(height: IdeSpacing.space12),
          const IdeRowDivider(),
          const SizedBox(height: IdeSpacing.space12),
        ],
        _TokenSection(tokens: entry.todayTokens),
        if (entry.message case final message?) ...[
          const SizedBox(height: IdeSpacing.space12),
          Text(
            message,
            style: textStyles.caption.copyWith(color: colors.textTertiary),
          ),
        ],
      ],
    );
  }
}

class _ResetCreditCountRow extends StatelessWidget {
  const _ResetCreditCountRow({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return Row(
      key: const ValueKey('agent-usage-reset-credit-count'),
      children: [
        Expanded(
          child: Text(
            '可用重置卡',
            style: textStyles.bodySmall.copyWith(color: colors.textSecondary),
          ),
        ),
        const SizedBox(width: IdeSpacing.space8),
        Text(
          '$count 张',
          key: const ValueKey('agent-usage-reset-credit-count-value'),
          style: textStyles.numeric,
        ),
      ],
    );
  }
}

/// 今日 Token 统计：横向 Header（标签 + 总数）叠加 2×2 子项网格。
///
/// Header 保持素色呼应 [_PlanSection] 的套餐名，网格则复用
/// [_QuotaWindowCard] 同款浅灰圆角容器，让上下两个模块读作同一套系统组件。
class _TokenSection extends StatelessWidget {
  const _TokenSection({required this.tokens});

  final UsageTokenBreakdown? tokens;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final tokens = this.tokens;
    final labelStyle = textStyles.caption.copyWith(color: colors.textSecondary);
    return Column(
      key: const ValueKey('agent-usage-token-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('今日 Token', style: labelStyle)),
            const SizedBox(width: IdeSpacing.space8),
            Text(
              tokens == null
                  ? '暂无统计'
                  : formatUsageCount(tokens.effectiveTotal ?? 0),
              key: const ValueKey('agent-usage-today-total'),
              style: textStyles.metricValue.copyWith(
                color: tokens == null
                    ? colors.textSecondary
                    : colors.textPrimary,
              ),
            ),
          ],
        ),
        if (tokens != null) ...[
          const SizedBox(height: IdeSpacing.space10),
          _TokenMetricGrid(tokens: tokens, labelStyle: labelStyle),
        ],
      ],
    );
  }
}

/// 输入 / 缓存输入 / 输出 / 推理四项子指标的 2×2 网格容器。
class _TokenMetricGrid extends StatelessWidget {
  const _TokenMetricGrid({required this.tokens, required this.labelStyle});

  final UsageTokenBreakdown tokens;
  final TextStyle labelStyle;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.hoverSurface,
        borderRadius: IdeRadius.allSmall,
      ),
      child: Padding(
        padding: const EdgeInsets.all(IdeSpacing.space8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: _TokenMetricCell(
                    label: '输入',
                    value: tokens.inputTokens ?? 0,
                    labelStyle: labelStyle,
                  ),
                ),
                const SizedBox(width: IdeSpacing.space8),
                Expanded(
                  child: _TokenMetricCell(
                    label: '缓存输入',
                    value: tokens.cachedInputTokens ?? 0,
                    labelStyle: labelStyle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: IdeSpacing.space8),
            Row(
              children: [
                Expanded(
                  child: _TokenMetricCell(
                    label: '输出',
                    value: tokens.outputTokens ?? 0,
                    labelStyle: labelStyle,
                  ),
                ),
                const SizedBox(width: IdeSpacing.space8),
                Expanded(
                  child: _TokenMetricCell(
                    label: '推理',
                    value: tokens.reasoningTokens ?? 0,
                    labelStyle: labelStyle,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 网格单元格：标签靠左（次级灰）、数值靠右（加粗深色、等宽数字），两端对齐。
class _TokenMetricCell extends StatelessWidget {
  const _TokenMetricCell({
    required this.label,
    required this.value,
    required this.labelStyle,
  });

  final String label;
  final int value;
  final TextStyle labelStyle;

  @override
  Widget build(BuildContext context) {
    final textStyles = IdeTextStyles.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: labelStyle,
          ),
        ),
        const SizedBox(width: IdeSpacing.space6),
        Text(
          formatUsageCount(value),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textStyles.numeric.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _PlanSection extends StatelessWidget {
  const _PlanSection({required this.quota});

  final AgentUsageQuotaSnapshot quota;

  @override
  Widget build(BuildContext context) {
    final textStyles = IdeTextStyles.of(context);
    return Column(
      key: const ValueKey('agent-usage-plan-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          formatUsagePlanType(quota.planType),
          key: const ValueKey('agent-usage-plan-name'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textStyles.titleLarge,
        ),
        const SizedBox(height: IdeSpacing.space10),
        AgentUsageQuotaGallery(windows: quota.windows),
      ],
    );
  }
}

class _RetryState extends StatelessWidget {
  const _RetryState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final textStyles = IdeTextStyles.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(IdeSpacing.space12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: textStyles.bodySmall,
            ),
            const SizedBox(height: IdeSpacing.space8),
            sf.GhostButton(
              key: const ValueKey('agent-usage-retry-button'),
              onPressed: onRetry,
              size: sf.ButtonSize.small,
              density: sf.ButtonDensity.dense,
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta/src/features/agent/domain/agent_usage_models.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_provider_icon.dart';
import 'package:zeta/src/features/usage_statistics/application/agent_usage_panel_controller.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_panel_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';
import 'package:zeta/src/features/usage_statistics/presentation/usage_statistics_formatters.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_effects.dart';
import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/ide_skeleton.dart';
import 'package:zeta/src/ui/core/rows/ide_row_divider.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/ide_tabs.dart';
import 'package:zeta/src/ui/core/ide_text_styles.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';

/// Agent 统计在合并左栏中的显示模式。
enum AgentUsagePanelMode { collapsed, expanded }

/// 不包含 [PanelCard] 外框的 Agent 统计内容。
///
/// 折叠态提供最多三行摘要；展开态以 Provider Tabs 和完整统计内容自然撑高。
class AgentUsagePanelContent extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return switch (mode) {
      AgentUsagePanelMode.collapsed => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => _CompactAgentUsage(
          controller: controller,
          onExpand: onModeChanged == null
              ? null
              : () => onModeChanged!(AgentUsagePanelMode.expanded),
        ),
      ),
      AgentUsagePanelMode.expanded => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => _AgentUsagePanelBody(
          controller: controller,
          onCollapse: onModeChanged == null
              ? null
              : () => onModeChanged!(AgentUsagePanelMode.collapsed),
        ),
      ),
    };
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

class _CompactAgentUsage extends StatelessWidget {
  const _CompactAgentUsage({required this.controller, required this.onExpand});

  final AgentUsagePanelController controller;
  final VoidCallback? onExpand;

  @override
  Widget build(BuildContext context) {
    if (controller.providers.isEmpty) {
      if (controller.isLoading) {
        return const _CompactAgentUsageSkeleton();
      }
      if (controller.errorMessage case final error?) {
        return _CompactAgentUsageMessage(
          message: error,
          warning: true,
          onRetry: () => unawaited(controller.refresh()),
          onExpand: onExpand,
        );
      }
      return _CompactAgentUsageMessage(
        message: '暂无已启用的 Agent',
        onExpand: onExpand,
      );
    }

    final selected = controller.selectedProvider!;
    final entry = selected.entry;
    if (entry == null) {
      if (selected.isLoading) {
        return const _CompactAgentUsageSkeleton();
      }
      if (selected.loadError case final error?) {
        return _CompactAgentUsageMessage(
          message: error,
          warning: true,
          onRetry: () => unawaited(controller.refresh()),
          onExpand: onExpand,
        );
      }
      return _CompactAgentUsageMessage(message: '暂无统计', onExpand: onExpand);
    }

    return _CompactAgentUsageSummary(
      entry: entry,
      providerName: selected.provider.providerName,
      onExpand: onExpand,
    );
  }
}

class _CompactAgentUsageSummary extends StatelessWidget {
  const _CompactAgentUsageSummary({
    required this.entry,
    required this.providerName,
    required this.onExpand,
  });

  final AgentUsagePanelEntry entry;
  final String providerName;
  final VoidCallback? onExpand;

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
                _AgentUsageModeButton(
                  key: const ValueKey('agent-usage-expand-button'),
                  icon: Icons.keyboard_arrow_up_rounded,
                  tooltip: '展开 Agent 统计',
                  onPressed: onExpand,
                ),
              ],
            ),
            if (quotaWindow != null) ...[
              const SizedBox(height: IdeSpacing.space4),
              _CompactQuotaWindow(window: quotaWindow),
            ] else if (entry.hasSubscriptionPlan) ...[
              const SizedBox(height: IdeSpacing.space4),
              Text(
                '额度详情暂不可用',
                key: const ValueKey('agent-usage-compact-quota-unavailable'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textStyles.bodySmall.copyWith(
                  color: colors.textSecondary,
                ),
              ),
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
          child: _QuotaProgressBar(usedPercent: used.toDouble()),
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
  const _CompactAgentUsageSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '正在读取 Agent 用量',
      container: true,
      child: const Padding(
        key: ValueKey('agent-usage-compact-loading'),
        padding: EdgeInsets.symmetric(
          horizontal: IdeSpacing.space12,
          vertical: IdeSpacing.space8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            IdeSkeletonLine(width: 136, height: 16),
            SizedBox(height: IdeSpacing.space4),
            IdeSkeletonLine(height: 10),
            SizedBox(height: IdeSpacing.space4),
            IdeSkeletonLine(width: 96, height: 12),
          ],
        ),
      ),
    );
  }
}

class _CompactAgentUsageMessage extends StatelessWidget {
  const _CompactAgentUsageMessage({
    required this.message,
    required this.onExpand,
    this.warning = false,
    this.onRetry,
  });

  final String message;
  final bool warning;
  final VoidCallback? onRetry;
  final VoidCallback? onExpand;

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
          _AgentUsageModeButton(
            key: const ValueKey('agent-usage-expand-button'),
            icon: Icons.keyboard_arrow_up_rounded,
            tooltip: '展开 Agent 统计',
            onPressed: onExpand,
          ),
        ],
      ),
    );
  }
}

class _AgentUsagePanelBody extends StatelessWidget {
  const _AgentUsagePanelBody({required this.controller, this.onCollapse});

  final AgentUsagePanelController controller;
  final VoidCallback? onCollapse;

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
        _AgentUsageTabsToolbar(
          controller: controller,
          selectedProviderId: selected?.provider.providerId,
          onCollapse: onCollapse,
        ),
        content,
      ],
    );
  }
}

class _AgentUsageTabsToolbar extends StatelessWidget {
  const _AgentUsageTabsToolbar({
    required this.controller,
    required this.selectedProviderId,
    required this.onCollapse,
  });

  final AgentUsagePanelController controller;
  final String? selectedProviderId;
  final VoidCallback? onCollapse;

  @override
  Widget build(BuildContext context) {
    final showTabs =
        controller.providers.length > 1 && selectedProviderId != null;
    return Padding(
      key: const ValueKey('agent-usage-tabs-toolbar'),
      padding: const EdgeInsets.fromLTRB(
        IdeSpacing.space8,
        IdeSpacing.space8,
        IdeSpacing.space6,
        0,
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
          if (onCollapse != null) ...[
            _AgentUsageModeButton(
              key: const ValueKey('agent-usage-collapse-button'),
              icon: Icons.keyboard_arrow_down_rounded,
              tooltip: '折叠 Agent 统计',
              onPressed: onCollapse,
            ),
            const SizedBox(width: IdeSpacing.space2),
          ],
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
            const IdeSkeletonLine(width: 40, height: 10),
            const SizedBox(height: IdeSpacing.space4),
            const IdeSkeletonLine(width: 140, height: 22),
            const SizedBox(height: IdeSpacing.space2),
            const IdeSkeletonLine(width: 88, height: 10),
            const SizedBox(height: IdeSpacing.space10),
            const _SkeletonQuotaWindow(),
            const SizedBox(height: IdeSpacing.space8),
            const _SkeletonQuotaWindow(),
            const SizedBox(height: IdeSpacing.space12),
            const IdeSkeletonLine(width: 56, height: 10),
            const SizedBox(height: IdeSpacing.space4),
            const IdeSkeletonLine(width: 96, height: 24),
            const SizedBox(height: IdeSpacing.space10),
            for (var i = 0; i < 4; i++) ...[
              if (i > 0) const SizedBox(height: IdeSpacing.space2),
              const _SkeletonMetricRow(),
            ],
          ],
        ),
      ),
    );
  }
}

class _SkeletonQuotaWindow extends StatelessWidget {
  const _SkeletonQuotaWindow();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: IdeSkeletonLine(height: 12)),
            SizedBox(width: IdeSpacing.space8),
            IdeSkeletonLine(width: 56, height: 10),
          ],
        ),
        SizedBox(height: IdeSpacing.space4),
        IdeSkeletonLine(height: 6),
      ],
    );
  }
}

class _SkeletonMetricRow extends StatelessWidget {
  const _SkeletonMetricRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: IdeSpacing.space2),
      child: Row(
        children: [
          Expanded(child: IdeSkeletonLine(height: 12)),
          SizedBox(width: IdeSpacing.space8),
          IdeSkeletonLine(width: 40, height: 12),
        ],
      ),
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
        if (entry.hasSubscriptionPlan || hasResetCredits) ...[
          if (entry.hasSubscriptionPlan) _PlanSection(quota: entry.quota!),
          if (entry.hasSubscriptionPlan && hasResetCredits)
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

class _TokenSection extends StatelessWidget {
  const _TokenSection({required this.tokens});

  final UsageTokenBreakdown? tokens;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final tokens = this.tokens;
    return Column(
      key: const ValueKey('agent-usage-token-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('今日 Token', style: textStyles.caption),
        const SizedBox(height: IdeSpacing.space4),
        Text(
          tokens == null
              ? '暂无统计'
              : formatUsageCount(tokens.effectiveTotal ?? 0),
          key: const ValueKey('agent-usage-today-total'),
          style: textStyles.metricValue.copyWith(
            color: tokens == null ? colors.textSecondary : colors.textPrimary,
          ),
        ),
        if (tokens != null) ...[
          const SizedBox(height: IdeSpacing.space10),
          _MetricRow(label: '输入', value: tokens.inputTokens ?? 0),
          _MetricRow(label: '缓存输入', value: tokens.cachedInputTokens ?? 0),
          _MetricRow(label: '输出', value: tokens.outputTokens ?? 0),
          _MetricRow(label: '推理', value: tokens.reasoningTokens ?? 0),
        ],
      ],
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: IdeSpacing.space2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: textStyles.bodySmall.copyWith(color: colors.textSecondary),
            ),
          ),
          Text(formatUsageCount(value), style: textStyles.numeric),
        ],
      ),
    );
  }
}

class _PlanSection extends StatelessWidget {
  const _PlanSection({required this.quota});

  final AgentUsageQuotaSnapshot quota;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return Column(
      key: const ValueKey('agent-usage-plan-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('套餐', style: textStyles.caption),
        const SizedBox(height: IdeSpacing.space4),
        Text(
          formatUsagePlanType(quota.planType),
          key: const ValueKey('agent-usage-plan-name'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textStyles.titleLarge,
        ),
        const SizedBox(height: IdeSpacing.space10),
        if (quota.windows.isEmpty)
          Text(
            '额度详情暂不可用',
            key: const ValueKey('agent-usage-quota-unavailable'),
            style: textStyles.bodySmall.copyWith(color: colors.textSecondary),
          ),
        for (var index = 0; index < quota.windows.length; index++) ...[
          _QuotaWindow(
            key: ValueKey<String>('agent-usage-window-$index'),
            window: quota.windows[index],
          ),
          if (index != quota.windows.length - 1)
            const SizedBox(height: IdeSpacing.space8),
        ],
      ],
    );
  }
}

class _QuotaWindow extends StatelessWidget {
  const _QuotaWindow({required this.window, super.key});

  final AgentUsageWindow window;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final used = window.usedPercent.clamp(0, 100);
    final remaining = math.max(0, 100 - used);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                window.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textStyles.bodySmall,
              ),
            ),
            const SizedBox(width: IdeSpacing.space8),
            Text(
              '$remaining%',
              style: textStyles.caption.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: IdeSpacing.space6),
        _QuotaProgressBar(usedPercent: used.toDouble()),
        if (window.resetsAt case final resetsAt?) ...[
          const SizedBox(height: IdeSpacing.space2),
          Text(
            '重置 ${formatUsageDateTime(resetsAt)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyles.caption.copyWith(color: colors.textTertiary),
          ),
        ],
      ],
    );
  }
}

/// 当前额度窗口的已用进度。
class _QuotaProgressBar extends StatelessWidget {
  const _QuotaProgressBar({required this.usedPercent});

  /// 已用百分比，0~100。
  final double usedPercent;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final used = usedPercent.clamp(0, 100);
    final remaining = 100 - used;
    final fraction = remaining / 100;
    return sf.LinearProgressIndicator(
      value: fraction,
      minHeight: 4,
      color: colors.textSecondary,
      backgroundColor: colors.borderSubtle,
      borderRadius: IdeRadius.allMicro,
      showSparks: false,
      disableAnimation: true,
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

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta/src/features/agent/domain/agent_usage_models.dart';
import 'package:zeta/src/features/usage_statistics/application/agent_usage_panel_controller.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_panel_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';
import 'package:zeta/src/features/usage_statistics/presentation/usage_statistics_formatters.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/ide_tabs.dart';
import 'package:zeta/src/ui/core/ide_text_styles.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';

/// 左侧 Context 槽位中的轻量 Agent 用量面板。
class AgentUsagePanel extends StatelessWidget {
  const AgentUsagePanel({required this.controller, super.key});

  final AgentUsagePanelController controller;

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      key: const ValueKey('context-panel-card'),
      child: Pane(
        title: 'Agent 统计',
        trailing: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => IdeTooltip(
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
          ),
        ),
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => _AgentUsagePanelBody(controller: controller),
        ),
      ),
    );
  }
}

class _AgentUsagePanelBody extends StatelessWidget {
  const _AgentUsagePanelBody({required this.controller});

  final AgentUsagePanelController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.providers.isEmpty) {
      if (controller.isLoading) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: const [
            _AgentUsageTopLoadingBar(
              key: ValueKey<String>('agent-usage-panel-loading'),
            ),
            Expanded(child: Center(child: Text('正在读取 Agent 用量…'))),
          ],
        );
      }
      if (controller.errorMessage != null) {
        return _RetryState(
          message: controller.errorMessage!,
          onRetry: () => unawaited(controller.refresh()),
        );
      }
      return const EmptyState(text: '暂无已启用的 Agent');
    }

    final selected = controller.selectedProvider!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 加载中在面板顶部展示不定进度线性条（含刷新保留旧内容的场景）。
        if (controller.isLoading)
          _AgentUsageTopLoadingBar(
            key: ValueKey<String>(
              selected.entry != null && selected.isLoading
                  ? 'agent-usage-provider-refreshing-'
                        '${selected.provider.providerId}'
                  : 'agent-usage-panel-loading',
            ),
          ),
        if (controller.providers.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              IdeSpacing.space8,
              IdeSpacing.space8,
              IdeSpacing.space8,
              0,
            ),
            child: IdeTabs<String>(
              key: const ValueKey('agent-usage-tabs'),
              value: selected.provider.providerId,
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
          ),
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
        if (selected.entry != null && selected.loadError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              IdeSpacing.space12,
              IdeSpacing.space6,
              IdeSpacing.space12,
              0,
            ),
            child: Text(
              selected.loadError!,
              style: IdeTextStyles.of(
                context,
              ).caption.copyWith(color: IdeColors.of(context).warning),
            ),
          ),
        Expanded(
          child: _SelectedProviderBody(state: selected, controller: controller),
        ),
      ],
    );
  }
}

/// Agent 统计面板顶部不定进度条，使用 shadcn [sf.LinearProgressIndicator]。
class _AgentUsageTopLoadingBar extends StatelessWidget {
  const _AgentUsageTopLoadingBar({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    return sf.LinearProgressIndicator(
      minHeight: 2,
      color: colors.accent,
      backgroundColor: colors.borderSubtle,
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
        return _ProviderLoadingState(provider: state.provider);
      }
      if (state.loadError case final error?) {
        return _RetryState(
          message: error,
          onRetry: () => unawaited(controller.refresh()),
        );
      }
      return const EmptyState(text: '暂无统计');
    }

    return SingleChildScrollView(
      key: PageStorageKey<String>(
        'agent-usage-scroll-${state.provider.providerId}',
      ),
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

class _ProviderLoadingState extends StatelessWidget {
  const _ProviderLoadingState({required this.provider});

  final AgentUsagePanelProvider provider;

  @override
  Widget build(BuildContext context) {
    // 顶部已由 [_AgentUsageTopLoadingBar] 展示线性进度，正文仅保留说明文案。
    return Center(
      key: ValueKey<String>(
        'agent-usage-provider-loading-${provider.providerId}',
      ),
      child: Text(
        '正在读取 ${provider.providerName} 用量…',
        textAlign: TextAlign.center,
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
        if (entry.hasSubscriptionPlan) ...[
          _PlanSection(quota: entry.quota!),
          const SizedBox(height: IdeSpacing.space12),
          Divider(height: 1, color: colors.borderSubtle),
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
          Text(formatUsageCount(value), style: textStyles.codeSmall),
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
        if (quota.limitName case final limitName?) ...[
          const SizedBox(height: IdeSpacing.space2),
          Text(
            limitName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyles.caption.copyWith(color: colors.textSecondary),
          ),
        ],
        if (quota.windows.isNotEmpty) ...[
          const SizedBox(height: IdeSpacing.space10),
          for (var index = 0; index < quota.windows.length; index++) ...[
            _QuotaWindow(
              key: ValueKey<String>('agent-usage-window-$index'),
              window: quota.windows[index],
            ),
            if (index != quota.windows.length - 1)
              const SizedBox(height: IdeSpacing.space8),
          ],
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
              '剩余 $remaining%',
              style: textStyles.caption.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: IdeSpacing.space4),
        // 深色段表示剩余额度，与「剩余 n%」文案一致。
        sf.Progress(progress: remaining.toDouble(), min: 0, max: 100),
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

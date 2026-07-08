part of '../agent_pane.dart';

/// thread 详情头部：左侧标题 + 运行图标，右侧当前 thread 累计 token 用量。
class _AgentHeader extends StatelessWidget {
  const _AgentHeader({required this.viewModel});

  final AgentConversationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = IdeColors.of(context);
    final tokenUsage = viewModel.currentThreadTokenUsage;
    final tokenLabel = _tokenUsageLabel(tokenUsage);
    final tokenTooltip = _tokenUsageTooltip(tokenUsage);
    final threadOpenStatusText = _threadOpenStatusText(viewModel);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      viewModel.currentThreadTitle,
                      key: const ValueKey('agent-header-title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (viewModel.showRunningIndicator) ...[
                    const SizedBox(width: 6),
                    Icon(
                      Icons.autorenew_rounded,
                      key: const ValueKey('agent-header-running-icon'),
                      size: 15,
                      color: colors.accent,
                    ),
                  ],
                ],
              ),
              if (threadOpenStatusText != null) ...[
                const SizedBox(height: 3),
                Text(
                  threadOpenStatusText,
                  key: const ValueKey('agent-thread-open-status'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color:
                        viewModel.threadOpenPhase ==
                            AgentThreadOpenPhase.openFailed
                        ? colors.warning
                        : colors.mutedText.withValues(alpha: 0.82),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (tokenLabel != null) ...[
          const SizedBox(width: 8),
          Tooltip(
            message: tokenTooltip,
            child: Row(
              key: const ValueKey('agent-header-token'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.bolt_outlined,
                  size: 12,
                  color: colors.mutedText.withValues(alpha: 0.65),
                ),
                const SizedBox(width: 3),
                Text(
                  tokenLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: colors.mutedText.withValues(alpha: 0.78),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

part of '../agent_pane.dart';

/// thread 详情头部：左侧标题 + 运行图标，右侧 token 用量与压缩/分叉操作。
class _AgentHeader extends StatelessWidget {
  const _AgentHeader({required this.viewModel});

  final AgentConversationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final tokenUsage = viewModel.currentThreadTokenUsage;
    final tokenLabel = _tokenUsageLabel(tokenUsage);
    final tokenTooltip = _tokenUsageTooltip(tokenUsage);
    final threadOpenStatusText = _threadOpenStatusText(viewModel);
    final offerCompact = viewModel.shouldOfferContextCompact;
    final canFork =
        viewModel.sessionId != null &&
        viewModel.canSubmitMessage &&
        !viewModel.isTurnRunning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
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
                          style: textStyles.titleLarge.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      if (viewModel.threadStatusCapsuleLabel
                          case final label?) ...[
                        const SizedBox(width: IdeSpacing.space6),
                        IdeChip(
                          key: const ValueKey('agent-header-status-capsule'),
                          label: label,
                          leadingIcon: viewModel.threadWaitingOnApproval
                              ? Icons.verified_user_outlined
                              : viewModel.threadWaitingOnUserInput
                              ? Icons.edit_note_rounded
                              : Icons.error_outline_rounded,
                          trailingIcon: null,
                          semanticLabel: label,
                        ),
                      ] else if (viewModel.showRunningIndicator) ...[
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
                      key: ValueKey(
                        viewModel.threadOpenPhase ==
                                    AgentThreadOpenPhase.idle &&
                                viewModel.systemNoticeLabel != null
                            ? 'agent-system-notice'
                            : 'agent-thread-open-status',
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textStyles.bodySmall.copyWith(
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
            if (canFork) ...[
              const SizedBox(width: IdeSpacing.space4),
              IdeTooltip(
                message: '分叉当前会话',
                child: ShadIconButton.ghost(
                  key: const ValueKey('agent-header-fork'),
                  onPressed: () {
                    unawaited(viewModel.forkCurrentThread());
                  },
                  width: 28,
                  height: 28,
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.call_split_rounded,
                    size: 15,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
            if (tokenLabel != null) ...[
              const SizedBox(width: IdeSpacing.space8),
              IdeTooltip(
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
                      style: textStyles.caption.copyWith(
                        color: colors.mutedText.withValues(alpha: 0.78),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        if (offerCompact || viewModel.isCompacting) ...[
          const SizedBox(height: IdeSpacing.space8),
          _AgentCompactBanner(viewModel: viewModel),
        ],
      ],
    );
  }
}

/// 上下文接近上限时的压缩提示条。
class _AgentCompactBanner extends StatelessWidget {
  const _AgentCompactBanner({required this.viewModel});

  final AgentConversationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final compacting = viewModel.isCompacting;
    return DecoratedBox(
      key: const ValueKey('agent-compact-banner'),
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: 0.12),
        borderRadius: IdeRadius.allSmall,
        border: Border.all(color: colors.warning.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: IdeSpacing.space10,
          vertical: IdeSpacing.space8,
        ),
        child: Row(
          children: [
            Icon(Icons.compress_rounded, size: 16, color: colors.warning),
            const SizedBox(width: IdeSpacing.space8),
            Expanded(
              child: Text(
                compacting ? '正在压缩上下文…' : '上下文占用较高，可压缩以继续对话',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textStyles.bodySmall.copyWith(color: colors.textPrimary),
              ),
            ),
            const SizedBox(width: IdeSpacing.space8),
            ShadButton.outline(
              key: const ValueKey('agent-compact-button'),
              size: ShadButtonSize.sm,
              onPressed: compacting || viewModel.isTurnRunning
                  ? null
                  : () {
                      unawaited(viewModel.compactCurrentThread());
                    },
              child: Text(compacting ? '压缩中' : '压缩上下文'),
            ),
          ],
        ),
      ),
    );
  }
}

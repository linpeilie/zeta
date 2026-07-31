part of '../agent_pane.dart';

/// thread 详情头部：左侧标题 + 运行图标，右侧 token、分叉与更多菜单。
class _AgentHeader extends StatelessWidget {
  const _AgentHeader({
    required this.viewModel,
    required this.state,
    required this.isActive,
  });

  final AgentConversationViewModel viewModel;
  final AgentHeaderState state;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    // 与上下文面板「总 Token」同源：会话累计用量，而非最近一次上下文窗口占用。
    final tokenUsage = state.tokenUsage;
    final tokenLabel = _threadTotalTokenUsageLabel(tokenUsage);
    final tokenTooltip = _tokenUsageTooltip(tokenUsage);
    final threadOpenStatusText = _threadOpenStatusText(state);
    final offerCompact = state.shouldOfferContextCompact;
    final canFork = state.canFork;
    Widget runningStatus(DateTime now) {
      return Text(
        _headerRunningStatusText(state, now),
        key: const ValueKey('agent-header-running-status'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textStyles.caption.copyWith(
          color: colors.mutedText.withValues(alpha: 0.86),
          fontWeight: FontWeight.w500,
        ),
      );
    }

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
                          state.title,
                          key: const ValueKey('agent-header-title'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textStyles.titleLarge.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      if (state.statusCapsuleLabel case final label?) ...[
                        const SizedBox(width: IdeSpacing.space6),
                        IdeTab(
                          key: const ValueKey('agent-header-status-capsule'),
                          label: label,
                          leadingIcon: state.waitingOnApproval
                              ? Icons.verified_user_outlined
                              : state.waitingOnUserInput
                              ? Icons.edit_note_rounded
                              : Icons.error_outline_rounded,
                          trailingIcon: null,
                          semanticLabel: label,
                        ),
                      ] else if (state.showRunningIndicator) ...[
                        const SizedBox(width: 6),
                        const IdeBusySpinner(
                          key: ValueKey('agent-header-running-icon'),
                          size: 14,
                          strokeWidth: 2,
                          semanticsLabel: 'Thread running',
                        ),
                        const SizedBox(width: IdeSpacing.space6),
                        Flexible(
                          child: isActive
                              ? ListenableBuilder(
                                  listenable: viewModel.elapsedClockListenable,
                                  builder: (context, _) =>
                                      runningStatus(viewModel.elapsedNow),
                                )
                              : runningStatus(DateTime.now()),
                        ),
                      ],
                    ],
                  ),
                  if (threadOpenStatusText != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      threadOpenStatusText,
                      key: ValueKey(
                        state.threadOpenPhase == AgentThreadOpenPhase.idle &&
                                state.systemNoticeLabel != null
                            ? 'agent-system-notice'
                            : 'agent-thread-open-status',
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textStyles.bodySmall.copyWith(
                        color:
                            state.threadOpenPhase ==
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
                child: sf.IconButton.ghost(
                  key: const ValueKey('agent-header-fork'),
                  onPressed: () {
                    unawaited(viewModel.forkCurrentThread());
                  },
                  size: sf.ButtonSize.small,
                  density: sf.ButtonDensity.iconDense,
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
            const SizedBox(width: IdeSpacing.space4),
            _AgentHeaderMoreButton(viewModel: viewModel, state: state),
          ],
        ),
        if (offerCompact || state.isCompacting) ...[
          const SizedBox(height: IdeSpacing.space8),
          _AgentCompactBanner(viewModel: viewModel, state: state),
        ],
      ],
    );
  }
}

/// 标题栏右侧「更多」菜单：重命名 / 归档 / 上下文。
class _AgentHeaderMoreButton extends StatefulWidget {
  const _AgentHeaderMoreButton({required this.viewModel, required this.state});

  final AgentConversationViewModel viewModel;
  final AgentHeaderState state;

  @override
  State<_AgentHeaderMoreButton> createState() => _AgentHeaderMoreButtonState();
}

class _AgentHeaderMoreButtonState extends State<_AgentHeaderMoreButton> {
  IdePopoverHandle<void>? _popoverEntry;
  bool _menuOpen = false;

  @override
  void dispose() {
    _popoverEntry?.dismiss();
    _popoverEntry = null;
    super.dispose();
  }

  void _toggleMenu() {
    if (_menuOpen) {
      _dismissMenu();
      return;
    }
    _showMenu();
  }

  void _showMenu() {
    if (_popoverEntry != null) {
      return;
    }
    setState(() {
      _menuOpen = true;
    });
    final canRename = widget.state.canRename;
    final canArchive = widget.state.canArchive;
    final entry = showIdePopover<void>(
      context: context,
      alignment: Alignment.topRight,
      anchorAlignment: Alignment.bottomRight,
      offset: const Offset(0, 4),
      modal: false,
      builder: (context) {
        return ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 100, maxWidth: 120),
          child: IdeContextMenu(
            actions: [
              if (canRename)
                IdeContextMenuAction(
                  key: const ValueKey('agent-header-menu-rename'),
                  label: '重命名',
                  leadingIcon: Icons.drive_file_rename_outline_rounded,
                  onPressed: () {
                    unawaited(_showRenameDialog());
                  },
                ),
              if (canArchive)
                IdeContextMenuAction(
                  key: const ValueKey('agent-header-menu-archive'),
                  label: '归档',
                  leadingIcon: Icons.archive_outlined,
                  onPressed: () {
                    unawaited(widget.viewModel.archiveCurrentThread());
                  },
                ),
              IdeContextMenuAction(
                key: const ValueKey('agent-header-menu-context'),
                label: '上下文',
                leadingIcon: Icons.account_tree_outlined,
                onPressed: () {
                  widget.viewModel.toggleContextPanel();
                },
              ),
            ],
          ),
        );
      },
    );
    _popoverEntry = entry;
    entry.future.whenComplete(() {
      if (!mounted) {
        return;
      }
      setState(() {
        if (identical(_popoverEntry, entry)) {
          _popoverEntry = null;
        }
        _menuOpen = false;
      });
    });
  }

  void _dismissMenu() {
    final entry = _popoverEntry;
    if (entry == null) {
      return;
    }
    _popoverEntry = null;
    setState(() {
      _menuOpen = false;
    });
    entry.dismiss();
  }

  Future<void> _showRenameDialog() async {
    final controller = TextEditingController(text: widget.state.title);
    final name = await showIdeDialog<String>(
      context: context,
      builder: (dialogContext) {
        return IdeDialog(
          key: const ValueKey('agent-header-rename-dialog'),
          title: const Text('重命名'),
          content: SizedBox(
            width: 320,
            child: sf.TextField(
              controller: controller,
              autofocus: true,
              onSubmitted: (value) {
                Navigator.of(dialogContext).pop(value.trim());
              },
            ),
          ),
          actions: [
            IdeDialogAction.cancel(
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            IdeDialogAction.confirm(
              onPressed: () {
                Navigator.of(dialogContext).pop(controller.text.trim());
              },
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (!mounted || name == null || name.isEmpty) {
      return;
    }
    await widget.viewModel.renameCurrentThread(name);
  }

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    return IdeTooltip(
      message: '更多',
      child: sf.IconButton.ghost(
        key: const ValueKey('agent-header-more'),
        onPressed: _toggleMenu,
        size: sf.ButtonSize.small,
        density: sf.ButtonDensity.iconDense,
        icon: Icon(
          Icons.more_horiz_rounded,
          size: 15,
          color: _menuOpen ? colors.textPrimary : colors.textSecondary,
        ),
      ),
    );
  }
}

/// 上下文接近上限时的压缩提示条。
class _AgentCompactBanner extends StatelessWidget {
  const _AgentCompactBanner({required this.viewModel, required this.state});

  final AgentConversationViewModel viewModel;
  final AgentHeaderState state;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final compacting = state.isCompacting;
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
            sf.OutlineButton(
              key: const ValueKey('agent-compact-button'),
              size: sf.ButtonSize.small,
              onPressed: compacting || state.isTurnRunning
                  ? null
                  : () {
                      unawaited(viewModel.compactCurrentThread());
                    },
              child: Text(
                compacting ? '压缩中' : '压缩上下文',
                style: textStyles.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

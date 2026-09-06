import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_actions.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_ui/zeta_ui.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_region_state.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_runtime_controller.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_pane_text.dart';
import 'package:zeta/src/ui/localization/app_localizations_x.dart';

/// thread 详情头部：左侧项目与会话标题，右侧 token、分叉与更多菜单。
class AgentHeader extends StatelessWidget {
  const AgentHeader({
    required this.controller,
    required this.actions,
    required this.state,
    required this.onToggleContextPanel,
    super.key,
  });

  final AgentConversationRuntimeController controller;
  final AgentConversationActions actions;
  final AgentHeaderState state;
  final VoidCallback onToggleContextPanel;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    // 与上下文面板「总 Token」同源：会话累计用量，而非最近一次上下文窗口占用。
    final tokenUsage = state.tokenUsage;
    final l10n = context.l10n;
    final tokenLabel = threadTotalTokenUsageLabel(tokenUsage, l10n);
    final tokenTooltip = tokenUsageTooltip(tokenUsage, l10n);
    final openStatusText = threadOpenStatusText(state, l10n);
    final projectName = controller.projectName;

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
                      if (projectName case final name?) ...[
                        Flexible(
                          fit: FlexFit.loose,
                          child: IdeTooltip(
                            message: controller.projectPath ?? name,
                            child: Semantics(
                              label: context.l10n.agentProjectName(name),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 180,
                                ),
                                child: Row(
                                  key: const ValueKey(
                                    'agent-header-project-name',
                                  ),
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.folder_outlined,
                                      size: 13,
                                      color: colors.textSecondary,
                                    ),
                                    const SizedBox(width: IdeSpacing.space4),
                                    Flexible(
                                      child: Text(
                                        name,
                                        key: const ValueKey(
                                          'agent-header-project-name-text',
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: textStyles.caption.copyWith(
                                          color: colors.textSecondary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: IdeSpacing.space6,
                          ),
                          child: Icon(
                            Icons.chevron_right_rounded,
                            key: ValueKey('agent-header-project-separator'),
                            size: 14,
                            color: colors.textTertiary,
                          ),
                        ),
                      ],
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
                      if (state.isPlanMode) ...[
                        const SizedBox(width: IdeSpacing.space6),
                        IdeTab(
                          key: const ValueKey('agent-header-plan-mode'),
                          label: 'Plan',
                          leadingIcon: Icons.fact_check_outlined,
                          trailingIcon: null,
                          semanticLabel: context.l10n.agentReadonlyPlanMode,
                        ),
                      ],
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
                      ],
                    ],
                  ),
                  if (openStatusText != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      openStatusText,
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
                            : colors.textSecondary.withValues(alpha: 0.82),
                      ),
                    ),
                  ],
                ],
              ),
            ),
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
                      color: colors.textSecondary.withValues(alpha: 0.65),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      tokenLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textStyles.caption.copyWith(
                        color: colors.textSecondary.withValues(alpha: 0.78),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(width: IdeSpacing.space4),
            _AgentHeaderMoreButton(
              controller: controller,
              actions: actions,
              state: state,
              onToggleContextPanel: onToggleContextPanel,
            ),
          ],
        ),
      ],
    );
  }
}

/// 标题栏右侧「更多」菜单：分叉 / 重命名 / 归档 / 上下文。
class _AgentHeaderMoreButton extends StatefulWidget {
  const _AgentHeaderMoreButton({
    required this.controller,
    required this.actions,
    required this.state,
    required this.onToggleContextPanel,
  });

  final AgentConversationRuntimeController controller;
  final AgentConversationActions actions;
  final AgentHeaderState state;
  final VoidCallback onToggleContextPanel;

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
    final capturedActions = widget.actions;
    final canRename = widget.state.canRename;
    final canArchive = widget.state.canArchive;
    final canFork = widget.state.canFork;
    // 后续项按序构建；第一个可见项上方加分隔符，与「上下文」分开。
    final contextFollowing = <IdeContextMenuAction>[
      if (canRename)
        IdeContextMenuAction(
          key: const ValueKey('agent-header-menu-rename'),
          label: context.l10n.agentRename,
          leadingIcon: Icons.drive_file_rename_outline_rounded,
          onPressed: () {
            unawaited(_showRenameDialog(capturedActions));
          },
        ),
      if (canFork)
        IdeContextMenuAction(
          key: const ValueKey('agent-header-menu-fork'),
          label: context.l10n.agentForkSession,
          leadingIcon: Icons.call_split_rounded,
          onPressed: () {
            unawaited(capturedActions.forkCurrentThread());
          },
        ),
      if (canArchive)
        IdeContextMenuAction(
          key: const ValueKey('agent-header-menu-archive'),
          label: context.l10n.agentArchive,
          leadingIcon: Icons.archive_outlined,
          onPressed: () {
            unawaited(capturedActions.archiveCurrentThread());
          },
        ),
    ];
    final actions = <IdeContextMenuAction>[
      IdeContextMenuAction(
        key: const ValueKey('agent-header-menu-context'),
        label: context.l10n.agentContext,
        leadingIcon: Icons.account_tree_outlined,
        onPressed: () {
          widget.onToggleContextPanel();
        },
      ),
      for (var index = 0; index < contextFollowing.length; index++)
        index == 0
            ? contextFollowing[index].withDividerAbove(true)
            : contextFollowing[index],
    ];
    final entry = showIdePopover<void>(
      context: context,
      alignment: Alignment.topRight,
      anchorAlignment: Alignment.bottomRight,
      offset: const Offset(0, 4),
      modal: false,
      builder: (context) {
        return ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 140, maxWidth: 160),
          child: IdeContextMenu(actions: actions),
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

  Future<void> _showRenameDialog(
    AgentConversationActions capturedActions,
  ) async {
    final controller = TextEditingController(text: widget.state.title);
    final name = await showIdeDialog<String>(
      context: context,
      builder: (dialogContext) {
        return IdeDialog(
          key: const ValueKey('agent-header-rename-dialog'),
          title: Text(context.l10n.agentRename),
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
              label: context.l10n.commonCancel,
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            IdeDialogAction.confirm(
              label: context.l10n.commonConfirm,
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
    await capturedActions.renameCurrentThread(name);
  }

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    return IdeTooltip(
      message: context.l10n.agentMore,
      // G8：IdeIconButton 没有 iconDense，也不能按菜单开合改图标色；
      // 头栏更多按钮继续用 small+iconDense，避免被撑到 compact 24px。
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

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'ide_colors.dart';
import 'ide_spacing.dart';
import 'ide_text_styles.dart';
import 'pane_widgets.dart';

@immutable
class IdeContextMenuAction {
  const IdeContextMenuAction({
    required this.label,
    required this.onPressed,
    this.key,
    this.leadingIcon,
    this.enabled = true,
    this.destructive = false,
    this.semanticLabel,
    this.dividerAbove = false,
  });

  final Key? key;
  final String label;
  final IconData? leadingIcon;
  final bool enabled;
  final bool destructive;
  final String? semanticLabel;
  final bool dividerAbove;
  final VoidCallback onPressed;
}

/// 统一 IDE 上下文菜单容器与菜单项样式。
class IdeContextMenu extends StatelessWidget {
  const IdeContextMenu({required this.actions, super.key, this.minWidth = 156});

  final List<IdeContextMenuAction> actions;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final brightness = Theme.of(context).brightness;
    return RepaintBoundary(
      child: PanelCard(
        color: colors.surfaceOverlay,
        borderRadius: BorderRadius.circular(IdeSpacing.space8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: brightness == Brightness.dark ? 0.12 : 0.06,
            ),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        child: Padding(
          padding: IdeSpacing.all4,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: minWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < actions.length; index++) ...[
                  if (actions[index].dividerAbove && index != 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: IdeSpacing.space4,
                      ),
                      child: Divider(
                        height: 1,
                        thickness: 1,
                        color: colors.borderSubtle,
                      ),
                    ),
                  _ContextMenuActionButton(action: actions[index]),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ContextMenuActionButton extends StatelessWidget {
  const _ContextMenuActionButton({required this.action});

  final IdeContextMenuAction action;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final foreground = !action.enabled
        ? colors.textTertiary
        : action.destructive
        ? colors.error
        : colors.textPrimary;

    return PaneInteractiveSurface(
      key: action.key,
      onPressed: action.enabled ? action.onPressed : null,
      enabled: action.enabled,
      height: 32,
      button: true,
      semanticLabel: action.semanticLabel,
      padding: const EdgeInsets.symmetric(horizontal: IdeSpacing.space12),
      borderRadius: BorderRadius.circular(idePanelRadius),
      child: Row(
        children: [
          if (action.leadingIcon != null) ...[
            Icon(action.leadingIcon, size: 14, color: foreground),
            const SizedBox(width: IdeSpacing.space8),
          ],
          Expanded(
            child: Text(
              action.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textStyles.bodyMedium.copyWith(
                color: foreground,
                height: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

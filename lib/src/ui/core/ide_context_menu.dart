import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'ide_colors.dart';
import 'ide_effects.dart';
import 'ide_spacing.dart';
import 'ide_text_styles.dart';
import 'surfaces/ide_surface.dart';

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

  /// 返回 [dividerAbove] 置为 [value] 的新菜单项（其余字段不变）。
  IdeContextMenuAction withDividerAbove(bool value) {
    return IdeContextMenuAction(
      key: key,
      label: label,
      leadingIcon: leadingIcon,
      enabled: enabled,
      destructive: destructive,
      semanticLabel: semanticLabel,
      dividerAbove: value,
      onPressed: onPressed,
    );
  }
}

/// 统一 IDE 上下文菜单容器与菜单项样式。
class IdeContextMenu extends StatelessWidget {
  const IdeContextMenu({
    required this.actions,
    super.key,
    this.minWidth = 156,
    this.closeOnActivate = true,
  });

  final List<IdeContextMenuAction> actions;
  final double minWidth;
  final bool closeOnActivate;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final shadcnTheme = sf.Theme.of(context);
    final menuTheme = shadcnTheme.copyWith(
      colorScheme: () => shadcnTheme.colorScheme.copyWith(
        accent: () => colors.hoverSurface,
        border: () => colors.borderSubtle,
      ),
    );
    return RepaintBoundary(
      child: IdeSurface.popover(
        padding: IdeSpacing.all4,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: minWidth),
          child: sf.Theme(
            data: menuTheme,
            child: sf.ComponentTheme(
              data: sf.MenuButtonTheme(
                decoration: (context, states, value) {
                  final color = states.contains(WidgetState.disabled)
                      ? Colors.transparent
                      : states.contains(WidgetState.pressed)
                      ? colors.pressedSurface
                      : states.contains(WidgetState.hovered) ||
                            states.contains(WidgetState.focused) ||
                            states.contains(WidgetState.selected)
                      ? colors.hoverSurface
                      : Colors.transparent;
                  return BoxDecoration(
                    color: color,
                    borderRadius: IdeRadius.allSmall,
                  );
                },
                padding: (context, states, value) =>
                    const EdgeInsets.symmetric(horizontal: IdeSpacing.space12),
                margin: (context, states, value) => EdgeInsets.zero,
              ),
              child: sf.MenuGroup(
                direction: Axis.vertical,
                onDismissed: () {
                  sf.closeOverlay(context);
                },
                builder: (context, children) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: children,
                ),
                children: _buildMenuItems(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<sf.MenuItem> _buildMenuItems() {
    return <sf.MenuItem>[
      for (var index = 0; index < actions.length; index++) ...[
        if (actions[index].dividerAbove && index != 0) const sf.MenuDivider(),
        _ContextMenuActionButton(
          key: actions[index].key,
          action: actions[index],
          closeOnActivate: closeOnActivate,
        ),
      ],
    ];
  }
}

class _ContextMenuActionButton extends StatelessWidget implements sf.MenuItem {
  const _ContextMenuActionButton({
    super.key,
    required this.action,
    required this.closeOnActivate,
  });

  final IdeContextMenuAction action;
  final bool closeOnActivate;

  @override
  bool get hasLeading => action.leadingIcon != null;

  @override
  sf.OverlayController? get overlayController => null;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final foreground = !action.enabled
        ? colors.textTertiary
        : action.destructive
        ? colors.error
        : colors.textPrimary;

    return Semantics(
      button: true,
      enabled: action.enabled,
      label: action.semanticLabel,
      excludeSemantics: action.semanticLabel != null,
      child: SizedBox(
        height: 32,
        child: sf.MenuButton(
          enabled: action.enabled,
          autoClose: false,
          leading: action.leadingIcon == null
              ? null
              : Icon(action.leadingIcon, size: 14, color: foreground),
          onPressed: action.enabled
              ? (context) {
                  if (!closeOnActivate) {
                    action.onPressed();
                    return;
                  }
                  sf.closeOverlay(context).whenComplete(action.onPressed);
                }
              : null,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
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
        ),
      ),
    );
  }
}

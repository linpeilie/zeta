import 'dart:async';

import 'package:app_ui/app_ui.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

/// Immutable context-menu action with caller-supplied copy.
@immutable
class IdeContextMenuAction {
  /// Creates an action.
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

  /// Stable widget key.
  final Key? key;

  /// Visible action copy.
  final String label;

  /// Optional leading glyph.
  final IconData? leadingIcon;

  /// Whether activation is enabled.
  final bool enabled;

  /// Whether the action is destructive.
  final bool destructive;

  /// Optional accessible name.
  final String? semanticLabel;

  /// Whether a divider precedes this action.
  final bool dividerAbove;

  /// Activation callback.
  final VoidCallback onPressed;

  /// Returns a copy with [dividerAbove] replaced by [value].
  IdeContextMenuAction withDividerAbove({required bool value}) {
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

/// A token-backed vertical context menu.
class IdeContextMenu extends StatelessWidget {
  /// Creates a context menu.
  const IdeContextMenu({
    required this.actions,
    this.minWidth = 156,
    this.closeOnActivate = true,
    super.key,
  });

  /// Menu actions.
  final List<IdeContextMenuAction> actions;

  /// Minimum menu width.
  final double minWidth;

  /// Whether activation closes the containing shadcn overlay.
  final bool closeOnActivate;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: PanelCard(
        color: context.appColors.popoverSurface,
        borderRadius: context.appRadii.allLarge,
        boxShadow: context.appEffects.overlayShadow(
          Theme.of(context).brightness,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: minWidth),
          child: Padding(
            padding: EdgeInsets.all(context.appSpacing.xxs),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (
                  var index = 0;
                  index < actions.length;
                  index++
                ) ...<Widget>[
                  if (index > 0 && actions[index].dividerAbove)
                    Divider(color: context.appColors.borderSubtle, height: 1),
                  _ContextMenuActionButton(
                    action: actions[index],
                    closeOnActivate: closeOnActivate,
                  ),
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
  const _ContextMenuActionButton({
    required this.action,
    required this.closeOnActivate,
  });

  final IdeContextMenuAction action;
  final bool closeOnActivate;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final foreground = !action.enabled
        ? colors.textTertiary
        : action.destructive
        ? colors.error
        : colors.textPrimary;
    return PaneInteractiveSurface(
      enabled: action.enabled,
      semanticLabel: action.semanticLabel ?? action.label,
      height: 32,
      padding: EdgeInsets.symmetric(horizontal: context.appSpacing.sm),
      onPressed: () {
        if (!closeOnActivate) {
          action.onPressed();
          return;
        }
        unawaited(sf.closeOverlay<void>(context));
        action.onPressed();
      },
      child: Row(
        children: <Widget>[
          if (action.leadingIcon case final icon?) ...<Widget>[
            Icon(icon, size: 14, color: foreground),
            SizedBox(width: context.appSpacing.xs),
          ],
          Expanded(
            child: Text(
              action.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.appTypography.bodyMedium.copyWith(
                color: foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

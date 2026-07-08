import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'ide_colors.dart';
import 'ide_motion.dart';
import 'ide_spacing.dart';
import 'pane_widgets.dart';

@immutable
class IdeRailAction {
  const IdeRailAction({
    required this.icon,
    required this.tooltip,
    required this.semanticLabel,
    required this.active,
    required this.onPressed,
    this.key,
    this.enabled = true,
  });

  final Key? key;
  final IconData icon;
  final String tooltip;
  final String semanticLabel;
  final bool active;
  final bool enabled;
  final VoidCallback onPressed;
}

/// 统一 IDE 左右活动栏。
class IdeActivityRail extends StatelessWidget {
  const IdeActivityRail({
    required this.leadingActions,
    super.key,
    this.trailingActions = const <IdeRailAction>[],
    this.backgroundColor,
  });

  final List<IdeRailAction> leadingActions;
  final List<IdeRailAction> trailingActions;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    return PanelCard(
      color: backgroundColor ?? colors.surface,
      showBorder: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: IdeSpacing.space2 / 2),
        child: Column(
          children: [
            for (final action in leadingActions)
              _RailActionButton(action: action),
            if (trailingActions.isNotEmpty) const Spacer(),
            for (final action in trailingActions)
              _RailActionButton(action: action),
          ],
        ),
      ),
    );
  }
}

class _RailActionButton extends StatelessWidget {
  const _RailActionButton({required this.action});

  final IdeRailAction action;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final iconColor = !action.enabled
        ? colors.textTertiary
        : action.active
        ? colors.accentForeground
        : colors.textSecondary;

    return IdeTooltip(
      message: action.tooltip,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          PaneInteractiveSurface(
            key: action.key,
            onPressed: action.enabled ? action.onPressed : null,
            selected: action.active,
            enabled: action.enabled,
            width: 32,
            height: 32,
            padding: EdgeInsets.zero,
            borderRadius: BorderRadius.circular(idePanelRadius),
            backgroundColor: Colors.transparent,
            selectedBackgroundColor: colors.primaryMuted,
            semanticLabel: action.semanticLabel,
            child: Icon(action.icon, size: 19, color: iconColor),
          ),
          Positioned(
            left: -2,
            child: AnimatedContainer(
              duration: IdeMotion.durationNormal,
              curve: IdeMotion.curveDefault,
              width: 3,
              height: action.active ? 16 : 0,
              decoration: BoxDecoration(
                color: colors.accent,
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

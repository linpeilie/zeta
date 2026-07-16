import 'package:flutter/material.dart';

import 'ide_colors.dart';
import 'ide_effects.dart';
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
    this.focusNode,
  });

  final Key? key;
  final IconData icon;
  final String tooltip;
  final String semanticLabel;
  final bool active;
  final bool enabled;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
}

/// 统一 IDE 左右活动栏。
class IdeActivityRail extends StatelessWidget {
  const IdeActivityRail({
    required this.leadingActions,
    super.key,
    this.trailingActions = const <IdeRailAction>[],
    this.indicatorSide = IdeActivityRailIndicatorSide.left,
  });

  final List<IdeRailAction> leadingActions;
  final List<IdeRailAction> trailingActions;

  /// 选中态指示条位置：左侧栏靠右、右侧栏靠左，贴近内容区。
  final IdeActivityRailIndicatorSide indicatorSide;

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      color: Colors.transparent,
      showBorder: false,
      boxShadow: const [],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: IdeSpacing.space2 / 2),
        child: Column(
          children: [
            for (final action in leadingActions)
              _RailActionButton(action: action, indicatorSide: indicatorSide),
            if (trailingActions.isNotEmpty) const Spacer(),
            for (final action in trailingActions)
              _RailActionButton(action: action, indicatorSide: indicatorSide),
          ],
        ),
      ),
    );
  }
}

/// 活动栏选中指示条相对按钮的水平位置。
enum IdeActivityRailIndicatorSide { left, right }

class _RailActionButton extends StatelessWidget {
  const _RailActionButton({required this.action, required this.indicatorSide});

  final IdeRailAction action;
  final IdeActivityRailIndicatorSide indicatorSide;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final iconColor = !action.enabled
        ? colors.textTertiary
        : action.active
        ? colors.accentForeground
        : colors.textSecondary;
    final indicatorOnLeft = indicatorSide == IdeActivityRailIndicatorSide.left;

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
            focusNode: action.focusNode,
            width: 32,
            height: 32,
            padding: EdgeInsets.zero,
            borderRadius: IdeRadius.allSmall,
            backgroundColor: Colors.transparent,
            selectedBackgroundColor: colors.selectedSurface,
            semanticLabel: action.semanticLabel,
            child: Icon(action.icon, size: 19, color: iconColor),
          ),
          Positioned(
            left: indicatorOnLeft ? -2 : null,
            right: indicatorOnLeft ? null : -2,
            child: AnimatedContainer(
              duration: IdeMotion.durationNormal,
              curve: IdeMotion.curveDefault,
              width: 3,
              height: action.active ? 16 : 0,
              decoration: BoxDecoration(
                color: colors.accent,
                borderRadius: BorderRadius.horizontal(
                  left: indicatorOnLeft
                      ? Radius.zero
                      : const Radius.circular(2),
                  right: indicatorOnLeft
                      ? const Radius.circular(2)
                      : Radius.zero,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

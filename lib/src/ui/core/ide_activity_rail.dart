import 'package:flutter/material.dart';

import 'ide_colors.dart';
import 'ide_effects.dart';
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
///
/// 选中态仅通过中性 [IdeColors.selectedSurface] 底与
/// [IdeColors.accentForeground] 图标色表达，不再绘制侧边指示条。
class IdeActivityRail extends StatelessWidget {
  const IdeActivityRail({
    required this.leadingActions,
    super.key,
    this.trailingActions = const <IdeRailAction>[],
  });

  final List<IdeRailAction> leadingActions;
  final List<IdeRailAction> trailingActions;

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
      child: PaneInteractiveSurface(
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
    );
  }
}

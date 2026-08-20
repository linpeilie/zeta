import 'package:app_ui/app_ui.dart';

/// Immutable description of one [IdeActivityRail] action.
@immutable
class IdeRailAction {
  /// Creates a rail action.
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

  /// Stable widget key.
  final Key? key;

  /// Action icon.
  final IconData icon;

  /// Hover tooltip copy.
  final String tooltip;

  /// Accessible action name.
  final String semanticLabel;

  /// Whether the destination is active.
  final bool active;

  /// Whether activation is enabled.
  final bool enabled;

  /// Activation callback.
  final VoidCallback onPressed;

  /// Optional externally owned focus node.
  final FocusNode? focusNode;
}

/// A vertical desktop destination rail.
class IdeActivityRail extends StatelessWidget {
  /// Creates an activity rail.
  const IdeActivityRail({
    required this.leadingActions,
    this.trailingActions = const <IdeRailAction>[],
    super.key,
  });

  /// Actions anchored to the leading edge.
  final List<IdeRailAction> leadingActions;

  /// Actions anchored to the trailing edge.
  final List<IdeRailAction> trailingActions;

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      color: Colors.transparent,
      showBorder: false,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: context.appSpacing.xxxs / 2),
        child: Column(
          children: <Widget>[
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
    final colors = context.appColors;
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
        borderRadius: context.appRadii.allSmall,
        backgroundColor: Colors.transparent,
        selectedBackgroundColor: colors.selectedSurface,
        semanticLabel: action.semanticLabel,
        child: Icon(
          action.icon,
          size: context.appMetrics.activityRailIconSize,
          color: iconColor,
        ),
      ),
    );
  }
}

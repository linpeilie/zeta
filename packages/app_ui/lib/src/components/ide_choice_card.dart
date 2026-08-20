import 'package:app_ui/app_ui.dart';

/// An icon-and-label choice card for small mutually exclusive groups.
class IdeChoiceCard extends StatelessWidget {
  /// Creates a choice card.
  const IdeChoiceCard({
    required this.label,
    required this.icon,
    this.selected = false,
    this.enabled = true,
    this.onPressed,
    this.semanticLabel,
    super.key,
  });

  /// Visible choice copy.
  final String label;

  /// Choice icon.
  final IconData icon;

  /// Whether the choice is selected.
  final bool selected;

  /// Whether the choice is enabled.
  final bool enabled;

  /// Activation callback.
  final VoidCallback? onPressed;

  /// Optional accessible name.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final iconColor = !enabled
        ? colors.textTertiary
        : selected
        ? colors.accent
        : colors.textSecondary;
    final labelColor = !enabled
        ? colors.textTertiary
        : selected
        ? colors.accent
        : colors.textPrimary;
    return PaneInteractiveSurface(
      onPressed: enabled ? onPressed : null,
      enabled: enabled,
      selected: selected,
      semanticLabel: semanticLabel ?? label,
      alignment: Alignment.topLeft,
      padding: EdgeInsets.all(context.appSpacing.sm),
      borderRadius: context.appRadii.allMedium,
      borderColor: colors.border,
      selectedBorderColor: colors.accent,
      selectedBackgroundColor: colors.selectedSurface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: iconColor),
          SizedBox(height: context.appSpacing.sm),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.appTypography.bodyMedium.copyWith(
              color: labelColor,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:app_ui/app_ui.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

/// Visual variants for [IdeChip].
enum IdeChipVariant {
  /// Neutral filled chip.
  secondary,

  /// Outlined chip.
  outline,

  /// Primary filled chip.
  primary,

  /// Low-emphasis chip.
  ghost,

  /// Destructive chip.
  destructive,
}

/// A compact label, filter, or removable tag backed by shadcn.
class IdeChip extends StatelessWidget {
  /// Creates a compact chip.
  const IdeChip({
    required this.label,
    this.leadingIcon,
    this.trailingIcon,
    this.onPressed,
    this.onDeleted,
    this.selected = false,
    this.enabled = true,
    this.variant = IdeChipVariant.secondary,
    this.semanticLabel,
    super.key,
  });

  /// Visible chip label.
  final String label;

  /// Optional leading glyph.
  final IconData? leadingIcon;

  /// Optional trailing glyph, superseded by [onDeleted].
  final IconData? trailingIcon;

  /// Whole-chip activation callback.
  final VoidCallback? onPressed;

  /// Optional delete callback.
  final VoidCallback? onDeleted;

  /// Whether the chip is selected.
  final bool selected;

  /// Whether chip actions are enabled.
  final bool enabled;

  /// Unselected visual style.
  final IdeChipVariant variant;

  /// Optional accessible name.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final metrics = context.appMetrics;
    final foreground = _foreground(colors);
    final labelStyle = context.appTypography.bodySmall.copyWith(
      color: foreground,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
      height: 1.1,
    );
    final chip = sf.ComponentTheme(
      data: sf.ChipTheme(
        padding: EdgeInsets.symmetric(
          horizontal: context.appSpacing.xs,
          vertical: context.appSpacing.xxs,
        ),
      ),
      child: sf.Chip(
        style: _style(),
        onPressed: enabled ? onPressed : null,
        leading: leadingIcon == null
            ? null
            : Icon(leadingIcon, size: 12, color: foreground),
        trailing: _trailing(colors, foreground),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: labelStyle,
        ),
      ),
    );

    final isInteractive = onPressed != null || onDeleted != null;
    final content = isInteractive
        ? ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: metrics.minimumInteractiveTarget,
              minHeight: metrics.minimumInteractiveTarget,
            ),
            child: chip,
          )
        : chip;

    return Semantics(
      button: onPressed != null,
      enabled: enabled && isInteractive,
      selected: selected,
      label: semanticLabel ?? label,
      excludeSemantics: onDeleted == null,
      child: Opacity(opacity: enabled ? 1 : 0.48, child: content),
    );
  }

  Widget? _trailing(AppColors colors, Color foreground) {
    if (onDeleted != null) {
      return sf.ChipButton(
        onPressed: enabled ? onDeleted : null,
        child: Icon(
          Icons.close,
          size: 12,
          color: enabled ? colors.textSecondary : colors.textTertiary,
        ),
      );
    }
    return trailingIcon == null
        ? null
        : Icon(trailingIcon, size: 12, color: foreground);
  }

  Color _foreground(AppColors colors) {
    if (!enabled) return colors.textTertiary;
    if (selected || variant == IdeChipVariant.primary) return colors.onAccent;
    if (variant == IdeChipVariant.destructive) return Colors.white;
    return colors.textSecondary;
  }

  sf.AbstractButtonStyle _style() {
    if (selected) {
      return const sf.ButtonStyle.primary(
        size: sf.ButtonSize.small,
        density: sf.ButtonDensity.dense,
      );
    }
    return switch (variant) {
      IdeChipVariant.secondary => const sf.ButtonStyle.secondary(
        size: sf.ButtonSize.small,
        density: sf.ButtonDensity.dense,
      ),
      IdeChipVariant.outline => const sf.ButtonStyle.outline(
        size: sf.ButtonSize.small,
        density: sf.ButtonDensity.dense,
      ),
      IdeChipVariant.primary => const sf.ButtonStyle.primary(
        size: sf.ButtonSize.small,
        density: sf.ButtonDensity.dense,
      ),
      IdeChipVariant.ghost => const sf.ButtonStyle.ghost(
        size: sf.ButtonSize.small,
        density: sf.ButtonDensity.dense,
      ),
      IdeChipVariant.destructive => const sf.ButtonStyle.destructive(
        size: sf.ButtonSize.small,
        density: sf.ButtonDensity.dense,
      ),
    };
  }
}

import 'dart:math' as math;

import 'package:app_ui/app_ui.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

/// Visual variants for [IdeButton].
enum IdeButtonVariant {
  /// Neutral outlined action.
  outline,

  /// Neutral filled action.
  secondary,

  /// Primary brand action.
  primary,

  /// Low-emphasis action.
  ghost,

  /// Destructive filled action.
  destructive,

  /// Brand-colored outlined action.
  accentOutline,

  /// Error-colored outlined action.
  dangerOutline,
}

/// A dense, semantic desktop button backed by shadcn.
class IdeButton extends StatelessWidget {
  /// Creates a compact button.
  const IdeButton({
    required this.label,
    this.onPressed,
    this.leading,
    this.leadingIcon,
    this.trailingIcon,
    this.enabled = true,
    this.variant = IdeButtonVariant.outline,
    this.controlSize = AppControlSize.compact,
    this.height,
    this.width,
    this.maxLines = 1,
    this.semanticLabel,
    super.key,
  });

  /// Creates a regular-density toolbar button.
  const IdeButton.toolbar({
    required this.label,
    this.onPressed,
    this.leading,
    this.leadingIcon,
    this.trailingIcon,
    this.enabled = true,
    this.variant = IdeButtonVariant.outline,
    this.width,
    this.maxLines = 1,
    this.semanticLabel,
    super.key,
  }) : controlSize = AppControlSize.regular,
       height = null;

  /// Visible button label.
  final String label;

  /// Invoked when the enabled button is activated.
  final VoidCallback? onPressed;

  /// Custom leading content, taking precedence over [leadingIcon].
  final Widget? leading;

  /// Optional leading glyph.
  final IconData? leadingIcon;

  /// Optional trailing glyph.
  final IconData? trailingIcon;

  /// Whether interaction is enabled.
  final bool enabled;

  /// Visual style.
  final IdeButtonVariant variant;

  /// Control density.
  final AppControlSize controlSize;

  /// Optional explicit outer height, clamped to the AA target floor.
  final double? height;

  /// Optional explicit width.
  final double? width;

  /// Maximum label line count.
  final int maxLines;

  /// Optional accessible name overriding [label].
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final metrics = context.appMetrics;
    final typography = context.appTypography;
    final isEnabled = enabled && onPressed != null;
    final foreground = _foreground(colors, isEnabled: isEnabled);
    final labelStyle = typography.bodySmall.copyWith(color: foreground);
    final padding = EdgeInsets.symmetric(
      horizontal: context.appSpacing.xs,
      vertical: metrics.controlPaddingYFor(controlSize),
    );
    final button = sf.Button(
      onPressed: isEnabled ? onPressed : null,
      enabled: isEnabled,
      style: _style(padding),
      alignment: Alignment.centerLeft,
      leading:
          leading ??
          (leadingIcon == null
              ? null
              : IdeIconBox(
                  leadingIcon,
                  style: labelStyle,
                  color: foreground,
                )),
      trailing: trailingIcon == null
          ? null
          : IdeIconBox(
              trailingIcon,
              style: labelStyle,
              color: foreground,
            ),
      child: Text(
        label,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: labelStyle,
      ),
    );
    final minimumHeight = metrics.controlMinHeightFor(controlSize);
    final constrained = ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: minimumHeight,
        minWidth: metrics.minimumInteractiveTarget,
      ),
      child: button,
    );
    final content = height == null && width == null
        ? constrained
        : SizedBox(
            height: height == null
                ? null
                : math.max(height!, metrics.minimumInteractiveTarget),
            width: width,
            child: button,
          );

    return Semantics(
      button: true,
      enabled: isEnabled,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      child: content,
    );
  }

  Color _foreground(AppColors colors, {required bool isEnabled}) {
    if (!isEnabled) return colors.textTertiary;
    return switch (variant) {
      IdeButtonVariant.primary => colors.onAccent,
      IdeButtonVariant.destructive => Colors.white,
      IdeButtonVariant.accentOutline => colors.accent,
      IdeButtonVariant.dangerOutline => colors.error,
      IdeButtonVariant.outline ||
      IdeButtonVariant.secondary ||
      IdeButtonVariant.ghost => colors.textPrimary,
    };
  }

  sf.AbstractButtonStyle _style(EdgeInsets padding) {
    final base = switch (variant) {
      IdeButtonVariant.outline ||
      IdeButtonVariant.accentOutline ||
      IdeButtonVariant.dangerOutline => const sf.ButtonStyle.outline(
        density: sf.ButtonDensity.dense,
      ),
      IdeButtonVariant.secondary => const sf.ButtonStyle.secondary(
        density: sf.ButtonDensity.dense,
      ),
      IdeButtonVariant.primary => const sf.ButtonStyle.primary(
        density: sf.ButtonDensity.dense,
      ),
      IdeButtonVariant.ghost => const sf.ButtonStyle.ghost(
        density: sf.ButtonDensity.dense,
      ),
      IdeButtonVariant.destructive => const sf.ButtonStyle.destructive(
        density: sf.ButtonDensity.dense,
      ),
    };
    return base.copyWith(padding: (context, states, value) => padding);
  }
}

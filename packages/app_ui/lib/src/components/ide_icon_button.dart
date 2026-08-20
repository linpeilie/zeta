import 'dart:math' as math;

import 'package:app_ui/app_ui.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

/// A square icon-only button with a required accessible name.
class IdeIconButton extends StatelessWidget {
  /// Creates an icon-only button.
  const IdeIconButton({
    required this.icon,
    required this.semanticLabel,
    this.onPressed,
    this.enabled = true,
    this.variant = IdeButtonVariant.outline,
    this.controlSize = AppControlSize.compact,
    super.key,
  });

  /// Icon glyph.
  final IconData icon;

  /// Accessible name for the icon-only action.
  final String semanticLabel;

  /// Invoked when the enabled button is activated.
  final VoidCallback? onPressed;

  /// Whether interaction is enabled.
  final bool enabled;

  /// Visual style.
  final IdeButtonVariant variant;

  /// Control density.
  final AppControlSize controlSize;

  @override
  Widget build(BuildContext context) {
    final metrics = context.appMetrics;
    final colors = context.appColors;
    final isEnabled = enabled && onPressed != null;
    final foreground = _foreground(colors, isEnabled: isEnabled);
    final padding = metrics.controlPaddingYFor(controlSize);
    final minimumSide = math.max(
      metrics.controlMinHeightFor(controlSize),
      metrics.minimumInteractiveTarget,
    );

    return Semantics(
      button: true,
      enabled: isEnabled,
      label: semanticLabel,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: minimumSide,
          minHeight: minimumSide,
        ),
        child: sf.Button(
          onPressed: isEnabled ? onPressed : null,
          enabled: isEnabled,
          style: _style(EdgeInsets.all(padding)),
          alignment: Alignment.center,
          child: IdeIconBox(
            icon,
            style: context.appTypography.bodySmall,
            color: foreground,
          ),
        ),
      ),
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
      IdeButtonVariant.ghost => colors.textSecondary,
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

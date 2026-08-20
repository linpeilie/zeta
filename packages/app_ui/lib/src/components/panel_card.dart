import 'package:app_ui/app_ui.dart';

/// A token-backed content card with optional border and overlay shadow.
class PanelCard extends StatelessWidget {
  /// Creates a panel card.
  const PanelCard({
    required this.child,
    this.color,
    this.showBorder = true,
    this.borderColor,
    this.borderRadius,
    this.boxShadow,
    this.clipBehavior = Clip.antiAlias,
    super.key,
  });

  /// Card content.
  final Widget child;

  /// Optional surface color.
  final Color? color;

  /// Whether to draw a one-pixel border.
  final bool showBorder;

  /// Optional border color.
  final Color? borderColor;

  /// Optional radius overriding the panel tier.
  final BorderRadiusGeometry? borderRadius;

  /// Optional shadow, reserved for detached overlays.
  final List<BoxShadow>? boxShadow;

  /// Content clipping behavior.
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final radii = context.appRadii;
    final resolvedRadius = borderRadius ?? radii.allLarge;
    final resolvedColor = color ?? context.appColors.paneSurface;
    final resolvedBorder = borderColor ?? context.appColors.borderSubtle;
    final shadows = boxShadow ?? const <BoxShadow>[];
    final isPanelTier = radii.isPanelTier(resolvedRadius);
    return Container(
      clipBehavior: clipBehavior,
      decoration: isPanelTier
          ? ShapeDecoration(
              color: resolvedColor,
              shape: radii.panel(),
              shadows: shadows,
            )
          : BoxDecoration(
              color: resolvedColor,
              borderRadius: resolvedRadius,
              boxShadow: shadows,
            ),
      foregroundDecoration: showBorder
          ? isPanelTier
                ? ShapeDecoration(
                    shape: radii.panel(
                      side: BorderSide(color: resolvedBorder),
                    ),
                  )
                : BoxDecoration(
                    border: Border.all(color: resolvedBorder),
                    borderRadius: resolvedRadius,
                  )
          : null,
      child: child,
    );
  }
}

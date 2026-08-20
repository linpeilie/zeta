import 'package:app_ui/app_ui.dart';

/// Visual elevation level for an [IdeSurface].
enum IdeSurfaceLevel {
  /// Central content canvas.
  canvas,

  /// Navigation or inspector pane.
  pane,

  /// Transparent row surface.
  row,

  /// Floating overlay surface.
  popover,
}

/// Applies the shared canvas, pane, row, or popover decoration.
class IdeSurface extends StatelessWidget {
  /// Creates a surface at [level].
  const IdeSurface({
    required this.level,
    required this.child,
    this.padding,
    this.borderRadius,
    this.showBorder,
    this.clipBehavior = Clip.antiAlias,
    super.key,
  });

  /// Creates a canvas surface.
  const IdeSurface.canvas({
    required Widget child,
    Key? key,
    EdgeInsetsGeometry? padding,
    bool? showBorder,
  }) : this(
         key: key,
         level: IdeSurfaceLevel.canvas,
         padding: padding,
         showBorder: showBorder,
         child: child,
       );

  /// Creates a pane surface.
  const IdeSurface.pane({
    required Widget child,
    Key? key,
    EdgeInsetsGeometry? padding,
    bool? showBorder,
  }) : this(
         key: key,
         level: IdeSurfaceLevel.pane,
         padding: padding,
         showBorder: showBorder,
         child: child,
       );

  /// Creates a transparent row surface.
  const IdeSurface.row({
    required Widget child,
    Key? key,
    EdgeInsetsGeometry? padding,
  }) : this(
         key: key,
         level: IdeSurfaceLevel.row,
         padding: padding,
         child: child,
       );

  /// Creates a floating popover surface.
  const IdeSurface.popover({
    required Widget child,
    Key? key,
    EdgeInsetsGeometry? padding,
  }) : this(
         key: key,
         level: IdeSurfaceLevel.popover,
         padding: padding,
         child: child,
       );

  /// Visual elevation level.
  final IdeSurfaceLevel level;

  /// Surface content.
  final Widget child;

  /// Optional content inset.
  final EdgeInsetsGeometry? padding;

  /// Optional radius override.
  final BorderRadiusGeometry? borderRadius;

  /// Optional border override.
  final bool? showBorder;

  /// Content clipping behavior.
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final effects = context.appEffects;
    final radii = context.appRadii;
    final brightness = Theme.of(context).brightness;
    final background = switch (level) {
      IdeSurfaceLevel.canvas => colors.canvasSurface,
      IdeSurfaceLevel.pane => colors.paneSurface,
      IdeSurfaceLevel.row => Colors.transparent,
      IdeSurfaceLevel.popover => colors.popoverSurface,
    };
    final resolvedRadius =
        borderRadius ??
        switch (level) {
          IdeSurfaceLevel.canvas || IdeSurfaceLevel.row => BorderRadius.zero,
          IdeSurfaceLevel.pane || IdeSurfaceLevel.popover => radii.allLarge,
        };
    final resolvedShowBorder =
        showBorder ??
        (level == IdeSurfaceLevel.pane || level == IdeSurfaceLevel.popover);
    final isPanelTier = radii.isPanelTier(resolvedRadius);
    final shadows = level == IdeSurfaceLevel.popover
        ? effects.overlayShadow(brightness)
        : const <BoxShadow>[];

    return Container(
      clipBehavior: clipBehavior,
      padding: padding,
      decoration: isPanelTier
          ? ShapeDecoration(
              color: background,
              shape: radii.panel(),
              shadows: shadows,
            )
          : BoxDecoration(
              color: background,
              borderRadius: resolvedRadius,
              boxShadow: shadows,
            ),
      foregroundDecoration: resolvedShowBorder
          ? isPanelTier
                ? ShapeDecoration(
                    shape: radii.panel(
                      side: BorderSide(color: colors.border),
                    ),
                  )
                : BoxDecoration(
                    border: Border.all(color: colors.border),
                    borderRadius: resolvedRadius,
                  )
          : null,
      child: child,
    );
  }
}

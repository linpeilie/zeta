import 'dart:math' as math;

import 'package:app_ui/app_ui.dart';

/// A square icon box whose side follows the active control text line box.
class IdeIconBox extends StatelessWidget {
  /// Creates a box containing an [IconData].
  const IdeIconBox(
    this.icon, {
    this.style,
    this.size,
    this.color,
    super.key,
  }) : child = null;

  /// Creates a box containing an arbitrary centered widget.
  const IdeIconBox.custom({
    required Widget this.child,
    this.style,
    super.key,
  }) : icon = null,
       size = null,
       color = null;

  /// Icon glyph to render.
  final IconData? icon;

  /// Custom content used by [IdeIconBox.custom].
  final Widget? child;

  /// Text style whose line box determines the square side.
  final TextStyle? style;

  /// Optional glyph size, clamped to the square side.
  final double? size;

  /// Optional glyph color.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedStyle = style ?? context.appTypography.bodySmall;
    final side = context.appMetrics.controlIconBoxFor(resolvedStyle);
    return SizedBox.square(
      dimension: side,
      child: Center(
        child:
            child ??
            Icon(icon, size: math.min(size ?? side, side), color: color),
      ),
    );
  }
}

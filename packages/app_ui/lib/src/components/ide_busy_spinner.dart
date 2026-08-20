import 'package:app_ui/app_ui.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

/// A compact circular busy or determinate progress indicator.
class IdeBusySpinner extends StatelessWidget {
  /// Creates a busy spinner.
  const IdeBusySpinner({
    required this.semanticsLabel,
    this.size = 14,
    this.strokeWidth = 2,
    this.color,
    this.backgroundColor,
    this.value,
    super.key,
  });

  /// Indicator side.
  final double size;

  /// Stroke width.
  final double strokeWidth;

  /// Optional foreground color.
  final Color? color;

  /// Optional track color.
  final Color? backgroundColor;

  /// Optional determinate value from zero to one.
  final double? value;

  /// Live-region progress announcement.
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      liveRegion: true,
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: size,
          child: sf.CircularProgressIndicator(
            value: value,
            size: size,
            strokeWidth: strokeWidth,
            color: color ?? context.appColors.accent,
            backgroundColor: backgroundColor ?? Colors.transparent,
            animated:
                value == null &&
                !(MediaQuery.maybeOf(context)?.disableAnimations ?? false),
          ),
        ),
      ),
    );
  }
}

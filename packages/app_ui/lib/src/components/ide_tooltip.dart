import 'package:app_ui/app_ui.dart';

/// A compact tooltip whose copy is supplied by the caller.
class IdeTooltip extends StatelessWidget {
  /// Creates a tooltip.
  const IdeTooltip({
    required this.message,
    required this.child,
    this.waitDuration,
    this.enabled = true,
    super.key,
  });

  /// Tooltip copy.
  final String message;

  /// Anchored content.
  final Widget child;

  /// Optional hover delay.
  final Duration? waitDuration;

  /// Whether the tooltip is active.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled || message.trim().isEmpty) return child;
    return Tooltip(
      message: message,
      waitDuration: waitDuration ?? const Duration(milliseconds: 500),
      decoration: BoxDecoration(
        color: context.appColors.surfaceOverlay,
        borderRadius: context.appRadii.allMicro,
      ),
      textStyle: context.appTypography.bodySmall.copyWith(
        color: context.appColors.textPrimary,
        fontWeight: FontWeight.w500,
        height: 1.15,
      ),
      child: child,
    );
  }
}

import 'package:app_ui/app_ui.dart';

/// A compact caller-colored status label.
class StateLabel extends StatelessWidget {
  /// Creates a status label.
  const StateLabel({required this.text, required this.color, super.key});

  /// Label copy.
  final String text;

  /// Semantic status color.
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        minHeight: context.appMetrics.minimumInteractiveTarget,
      ),
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(horizontal: context.appSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: context.appRadii.allMicro,
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: context.appTypography.bodySmall.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

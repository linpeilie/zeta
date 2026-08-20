import 'package:app_ui/app_ui.dart';

/// A centered empty-state message supplied by the caller.
class EmptyState extends StatelessWidget {
  /// Creates an empty state.
  const EmptyState({required this.text, super.key});

  /// Empty-state copy.
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(context.appSpacing.md),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: context.appTypography.bodySmall.copyWith(
            color: context.appColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

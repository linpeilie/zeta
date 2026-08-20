import 'package:app_ui/app_ui.dart';

/// A floating action that returns a freely scrolled virtual list to its end.
class IdeScrollToEndButton extends StatelessWidget {
  /// Creates a scroll-to-end button.
  const IdeScrollToEndButton({
    required this.onPressed,
    required this.semanticLabel,
    required this.newContentLabel,
    required this.backToBottomLabel,
    this.hasNewContent = false,
    super.key,
  }) : assert(semanticLabel != '', 'semanticLabel must not be empty'),
       assert(newContentLabel != '', 'newContentLabel must not be empty'),
       assert(backToBottomLabel != '', 'backToBottomLabel must not be empty');

  /// Requests follow-end mode and reveals the final item.
  final VoidCallback onPressed;

  /// Localized accessible action name.
  final String semanticLabel;

  /// Localized visible label when new content is available.
  final String newContentLabel;

  /// Localized visible label when no unread content is pending.
  final String backToBottomLabel;

  /// Whether streaming content arrived while the user was browsing freely.
  final bool hasNewContent;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final spacing = context.appSpacing;
    return PaneInteractiveSurface(
      onPressed: onPressed,
      semanticLabel: semanticLabel,
      borderRadius: context.appRadii.allMedium,
      backgroundColor: colors.surfaceElevated,
      hoverBackgroundColor: colors.hoverSurface,
      pressedBackgroundColor: colors.pressedSurface,
      borderColor: colors.borderSubtle,
      padding: EdgeInsets.symmetric(
        horizontal: spacing.sm,
        vertical: spacing.xs,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.arrow_downward_rounded,
            size: context.appTypography.bodySmall.fontSize,
            color: hasNewContent ? colors.accent : colors.textSecondary,
          ),
          SizedBox(width: spacing.s6),
          Text(
            hasNewContent ? newContentLabel : backToBottomLabel,
            style: context.appTypography.bodySmall.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:app_ui/app_ui.dart';

/// Semantic tones for [IdeStatusCard].
enum IdeStatusCardTone {
  /// Neutral information.
  neutral,

  /// Informational state.
  info,

  /// Warning state.
  warning,

  /// Error state.
  error,

  /// Success state.
  success,
}

/// A compact semantic status card with caller-supplied copy and content.
class IdeStatusCard extends StatelessWidget {
  /// Creates a status card.
  const IdeStatusCard({
    required this.tone,
    required this.title,
    this.leading,
    this.body,
    this.footer,
    this.margin,
    this.padding,
    super.key,
  });

  /// Semantic tone.
  final IdeStatusCardTone tone;

  /// Title copy.
  final String title;

  /// Optional leading content.
  final Widget? leading;

  /// Optional body.
  final Widget? body;

  /// Optional footer.
  final Widget? footer;

  /// Optional outer margin.
  final EdgeInsetsGeometry? margin;

  /// Optional inner padding.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final accent = switch (tone) {
      IdeStatusCardTone.neutral => colors.textTertiary,
      IdeStatusCardTone.info => colors.info,
      IdeStatusCardTone.warning => colors.warning,
      IdeStatusCardTone.error => colors.error,
      IdeStatusCardTone.success => colors.success,
    };
    final icon = switch (tone) {
      IdeStatusCardTone.neutral || IdeStatusCardTone.info => Icons.info_outline,
      IdeStatusCardTone.warning => Icons.warning_amber,
      IdeStatusCardTone.error => Icons.error_outline,
      IdeStatusCardTone.success => Icons.check_circle_outline,
    };
    final neutral = tone == IdeStatusCardTone.neutral;
    return Padding(
      padding: margin ?? EdgeInsets.only(bottom: context.appSpacing.sm),
      child: PanelCard(
        color: neutral ? colors.controlSurface : accent.withValues(alpha: 0.08),
        borderColor: neutral
            ? colors.borderSubtle
            : accent.withValues(
                alpha: tone == IdeStatusCardTone.warning ? 0.35 : 0.26,
              ),
        borderRadius: context.appRadii.allMedium,
        child: Padding(
          padding: padding ?? context.appSpacing.cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  leading ?? Icon(icon, size: 16, color: accent),
                  SizedBox(width: context.appSpacing.xs),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.appTypography.titleSmall,
                    ),
                  ),
                ],
              ),
              if (body case final body?)
                Padding(
                  padding: EdgeInsets.only(top: context.appSpacing.s6),
                  child: body,
                ),
              if (footer case final footer?)
                Padding(
                  padding: EdgeInsets.only(top: context.appSpacing.s10),
                  child: footer,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

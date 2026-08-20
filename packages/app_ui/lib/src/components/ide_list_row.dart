import 'package:app_ui/app_ui.dart';

/// A dense list row with unified selection, interaction, and truncation.
class IdeListRow extends StatelessWidget {
  /// Creates a list row.
  const IdeListRow({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.selected = false,
    this.enabled = true,
    this.onPressed,
    this.showDivider = true,
    this.dividerIndent = 0,
    this.semanticLabel,
    super.key,
  });

  /// Primary row label.
  final String title;

  /// Optional secondary row label.
  final String? subtitle;

  /// Optional leading content.
  final Widget? leading;

  /// Optional trailing content.
  final Widget? trailing;

  /// Whether this row is selected.
  final bool selected;

  /// Whether this row can be activated.
  final bool enabled;

  /// Optional activation callback.
  final VoidCallback? onPressed;

  /// Whether to draw a bottom divider.
  final bool showDivider;

  /// Leading divider inset in the current text direction.
  final double dividerIndent;

  /// Optional accessible name. Defaults to [title].
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final metrics = context.appMetrics;
    final spacing = context.appSpacing;
    final typography = context.appTypography;
    final foreground = !enabled
        ? colors.textTertiary
        : selected
        ? colors.textPrimary
        : colors.textSecondary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: metrics.listRowHeight),
          child: PaneInteractiveSurface(
            onPressed: onPressed,
            selected: selected,
            enabled: enabled,
            button: onPressed != null,
            semanticLabel: semanticLabel ?? title,
            padding: spacing.rowPadding,
            child: Row(
              children: <Widget>[
                if (leading case final leadingWidget?) ...<Widget>[
                  IconTheme(
                    data: IconThemeData(size: 15, color: foreground),
                    child: leadingWidget,
                  ),
                  SizedBox(width: spacing.xs),
                ],
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: typography.rowTitle.copyWith(
                          color: enabled
                              ? colors.textPrimary
                              : colors.textTertiary,
                        ),
                      ),
                      if (subtitle case final subtitleText?)
                        Text(
                          subtitleText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: typography.meta.copyWith(color: foreground),
                        ),
                    ],
                  ),
                ),
                if (trailing case final trailingWidget?) ...<Widget>[
                  SizedBox(width: spacing.xs),
                  IconTheme.merge(
                    data: IconThemeData(
                      color: enabled ? null : colors.textTertiary,
                    ),
                    child: DefaultTextStyle.merge(
                      style: TextStyle(
                        color: enabled ? null : colors.textTertiary,
                      ),
                      child: trailingWidget,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (showDivider) IdeRowDivider(indent: dividerIndent),
      ],
    );
  }
}

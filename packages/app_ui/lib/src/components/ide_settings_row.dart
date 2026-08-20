import 'package:app_ui/app_ui.dart';

/// Aligns a settings description with its control on desktop layouts.
class IdeSettingsRow extends StatelessWidget {
  /// Creates a settings row.
  const IdeSettingsRow({
    required this.label,
    required this.control,
    this.description,
    this.showDivider = true,
    this.padding,
    super.key,
  });

  /// Setting name.
  final String label;

  /// Optional supporting description.
  final String? description;

  /// Interactive setting control.
  final Widget control;

  /// Whether to draw a bottom divider.
  final bool showDivider;

  /// Optional row inset. Defaults to [AppSpacing.settingsRowPadding].
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final metrics = context.appMetrics;
    final spacing = context.appSpacing;
    final typography = context.appTypography;
    final resolvedPadding = padding ?? spacing.settingsRowPadding;
    final dividerIndent = resolvedPadding
        .resolve(Directionality.of(context))
        .left;

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < metrics.stackedRowBreakpoint;
        final labelContent = Column(
          key: const ValueKey<String>('ide-settings-row-label'),
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(label, style: typography.titleSmall),
            if (description case final descriptionText?) ...<Widget>[
              SizedBox(height: spacing.xxs),
              Text(
                descriptionText,
                style: typography.meta.copyWith(height: 1.25),
              ),
            ],
          ],
        );

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: metrics.settingsRowMinHeight,
              ),
              child: Padding(
                padding: resolvedPadding,
                child: stacked
                    ? Column(
                        key: const ValueKey<String>(
                          'ide-settings-row-stacked',
                        ),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          labelContent,
                          SizedBox(height: spacing.xs),
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: control,
                          ),
                        ],
                      )
                    : Row(
                        key: const ValueKey<String>(
                          'ide-settings-row-inline',
                        ),
                        children: <Widget>[
                          Expanded(child: labelContent),
                          SizedBox(width: spacing.md),
                          Flexible(child: control),
                        ],
                      ),
              ),
            ),
            if (showDivider) IdeRowDivider(indent: dividerIndent),
          ],
        );
      },
    );
  }
}

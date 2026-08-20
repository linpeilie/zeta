import 'package:app_ui/app_ui.dart';

/// A shared-width header or data row for dense desktop tables.
class IdeDataRow extends StatelessWidget {
  /// Creates a data row.
  const IdeDataRow({
    required this.values,
    required this.flexes,
    this.header = false,
    this.onPressed,
    this.showDivider = true,
    this.semanticLabel,
    this.numericColumns = const <int>{},
    this.identifierColumns = const <int>{},
    super.key,
  }) : assert(
         values.length == flexes.length,
         'values and flexes must have identical lengths',
       );

  /// Single-line values in column order.
  final List<String> values;

  /// Flex values matching [values].
  final List<int> flexes;

  /// Columns rendered as right-aligned tabular numbers.
  final Set<int> numericColumns;

  /// Columns rendered as machine identifiers.
  final Set<int> identifierColumns;

  /// Whether this row is a table header.
  final bool header;

  /// Optional row activation callback.
  final VoidCallback? onPressed;

  /// Whether to draw a bottom divider.
  final bool showDivider;

  /// Optional accessible name for an interactive row.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final metrics = context.appMetrics;
    final spacing = context.appSpacing;
    final typography = context.appTypography;
    final textStyle = header
        ? typography.toolbarLabel.copyWith(color: colors.textSecondary)
        : typography.bodySmall.copyWith(color: colors.textPrimary);
    final numericStyle = header
        ? textStyle
        : typography.numeric.copyWith(color: colors.textPrimary);
    final identifierStyle = header
        ? textStyle
        : typography.identifier.copyWith(color: colors.textPrimary);

    TextStyle styleFor(int index) {
      if (numericColumns.contains(index)) return numericStyle;
      if (identifierColumns.contains(index)) return identifierStyle;
      return textStyle;
    }

    final interactive = onPressed != null;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: header ? colors.surfaceElevated : Colors.transparent,
        border: showDivider
            ? Border(bottom: BorderSide(color: colors.borderSubtle))
            : null,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: metrics.compactRowHeight),
        child: PaneInteractiveSurface(
          onPressed: onPressed,
          button: interactive,
          semanticLabel: interactive ? semanticLabel : null,
          padding: EdgeInsets.symmetric(
            horizontal: spacing.xs,
            vertical: spacing.s6,
          ),
          borderRadius: BorderRadius.zero,
          child: Row(
            children: <Widget>[
              for (var index = 0; index < values.length; index++)
                Expanded(
                  flex: flexes[index],
                  child: Padding(
                    padding: EdgeInsetsDirectional.only(
                      end: index < values.length - 1 ? spacing.xs : 0,
                    ),
                    child: Text(
                      values[index],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: numericColumns.contains(index)
                          ? TextAlign.end
                          : TextAlign.start,
                      style: styleFor(index),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

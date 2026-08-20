import 'package:app_ui/app_ui.dart';

/// Typography semantics for an [IdeKeyValueRow] value.
enum IdeKeyValueTone {
  /// Human-readable prose.
  text,

  /// Stable machine identifier.
  identifier,

  /// Secondary technical text such as a path or command.
  code,

  /// A tabular number or version.
  numeric,
}

/// A dense read-only technical key/value row.
class IdeKeyValueRow extends StatelessWidget {
  /// Creates a key/value row.
  const IdeKeyValueRow({
    required this.label,
    required this.value,
    this.tone = IdeKeyValueTone.text,
    this.valueColor,
    this.trailing,
    this.selectable = false,
    this.maxLines = 2,
    super.key,
  });

  /// Fixed-width field name.
  final String label;

  /// Read-only field value.
  final String value;

  /// Semantic typography used for [value].
  final IdeKeyValueTone tone;

  /// Optional value color override.
  final Color? valueColor;

  /// Optional operation placed after the value.
  final Widget? trailing;

  /// Whether the value can be selected and copied.
  final bool selectable;

  /// Maximum visible value lines.
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final metrics = context.appMetrics;
    final spacing = context.appSpacing;
    final typography = context.appTypography;
    final baseStyle = switch (tone) {
      IdeKeyValueTone.text => typography.bodySmall,
      IdeKeyValueTone.identifier => typography.identifier,
      IdeKeyValueTone.code => typography.codeSmall,
      IdeKeyValueTone.numeric => typography.numeric,
    };
    final valueStyle = valueColor == null
        ? baseStyle
        : baseStyle.copyWith(color: valueColor);

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: metrics.compactRowHeight),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: spacing.s6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: metrics.keyValueLabelWidth,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: typography.titleSmall.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
            SizedBox(width: spacing.xs),
            Expanded(
              child: selectable
                  ? SelectableText(
                      value,
                      maxLines: maxLines,
                      style: valueStyle,
                    )
                  : Text(
                      value,
                      maxLines: maxLines,
                      overflow: TextOverflow.ellipsis,
                      style: valueStyle,
                    ),
            ),
            if (trailing case final trailingWidget?) ...<Widget>[
              SizedBox(width: spacing.xxs),
              trailingWidget,
            ],
          ],
        ),
      ),
    );
  }
}

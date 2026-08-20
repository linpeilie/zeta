import 'package:app_ui/app_ui.dart';

/// Organizes page content under a semantic section heading.
class IdeSection extends StatelessWidget {
  /// Creates a workbench section.
  const IdeSection({
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    super.key,
  });

  /// Section title.
  final String title;

  /// Optional supporting description.
  final String? subtitle;

  /// Optional trailing operation.
  final Widget? trailing;

  /// Section content.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final metrics = context.appMetrics;
    final spacing = context.appSpacing;
    final typography = context.appTypography;
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Semantics(
          header: true,
          child: Text(title, style: typography.sectionTitle),
        ),
        if (subtitle case final subtitleText?)
          Text(
            subtitleText,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: typography.meta.copyWith(color: colors.textSecondary),
          ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LayoutBuilder(
          builder: (context, constraints) {
            final trailingWidget = trailing;
            if (trailingWidget == null) return heading;
            if (constraints.maxWidth < metrics.stackedRowBreakpoint) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  heading,
                  SizedBox(height: spacing.xs),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: trailingWidget,
                  ),
                ],
              );
            }
            return Row(
              children: <Widget>[
                Expanded(child: heading),
                SizedBox(width: spacing.xs),
                Flexible(child: trailingWidget),
              ],
            );
          },
        ),
        SizedBox(height: spacing.xs),
        child,
      ],
    );
  }
}

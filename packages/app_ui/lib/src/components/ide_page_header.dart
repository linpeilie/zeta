import 'package:app_ui/app_ui.dart';

/// A compact workbench page heading with optional actions.
class IdePageHeader extends StatelessWidget {
  /// Creates a page header.
  const IdePageHeader({
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const <Widget>[],
    super.key,
  });

  /// Page title.
  final String title;

  /// Optional page description.
  final String? subtitle;

  /// Optional leading widget.
  final Widget? leading;

  /// Trailing actions in display order.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final metrics = context.appMetrics;
    final spacing = context.appSpacing;
    final typography = context.appTypography;
    return SizedBox(
      height: metrics.pageHeaderHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.borderSubtle)),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: spacing.sm),
          child: Row(
            children: <Widget>[
              if (leading case final leadingWidget?) ...<Widget>[
                leadingWidget,
                SizedBox(width: spacing.xs),
              ],
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: typography.pageTitle,
                      ),
                    ),
                    if (subtitle case final subtitleText?)
                      Text(
                        subtitleText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: typography.meta.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              if (actions.isNotEmpty)
                Flexible(
                  child: SingleChildScrollView(
                    key: const ValueKey<String>('ide-page-header-actions'),
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        for (final action in actions) ...<Widget>[
                          SizedBox(width: spacing.xxs),
                          action,
                        ],
                      ],
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

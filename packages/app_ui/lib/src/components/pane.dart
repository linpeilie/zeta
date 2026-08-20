import 'package:app_ui/app_ui.dart';

/// A full-height desktop pane with an optional compact header.
class Pane extends StatelessWidget {
  /// Creates a pane.
  const Pane({
    required this.child,
    this.title,
    this.subtitle,
    this.trailing,
    this.titleContent,
    super.key,
  });

  /// Optional title copy.
  final String? title;

  /// Optional subtitle copy.
  final String? subtitle;

  /// Optional trailing header action.
  final Widget? trailing;

  /// Optional complete replacement for title and subtitle.
  final Widget? titleContent;

  /// Pane body.
  final Widget child;

  bool get _showHeader =>
      title != null ||
      subtitle != null ||
      trailing != null ||
      titleContent != null;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.appColors.paneSurface,
        borderRadius: context.appRadii.allLarge,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (_showHeader)
            Container(
              height: context.appMetrics.paneHeaderHeight,
              padding: EdgeInsets.only(
                left: context.appSpacing.sm,
                right: context.appSpacing.s6,
              ),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: context.appColors.borderSubtle),
                ),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child:
                        titleContent ??
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            if (title case final title?)
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.appTypography.titleSmall,
                              ),
                            if (subtitle case final subtitle?)
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.appTypography.caption,
                              ),
                          ],
                        ),
                  ),
                  ?trailing,
                ],
              ),
            ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

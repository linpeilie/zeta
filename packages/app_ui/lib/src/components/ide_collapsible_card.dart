import 'package:app_ui/app_ui.dart';

/// A caller-controlled expandable information card.
class IdeCollapsibleCard extends StatelessWidget {
  /// Creates a collapsible card.
  const IdeCollapsibleCard({
    required this.expanded,
    required this.onToggle,
    this.headerKey,
    this.toggleKey,
    this.bodyKey,
    this.title,
    this.titleWidget,
    this.summaryWidget,
    this.leading,
    this.canExpand = true,
    this.margin = EdgeInsets.zero,
    this.padding = EdgeInsets.zero,
    this.summaryPadding,
    this.bodyPadding,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius,
    this.boxShadow,
    this.hoverBackgroundColor,
    this.body,
    this.semanticLabel,
    this.wrapBodyWithRepaintBoundary = true,
    super.key,
  }) : assert(
         title != null || titleWidget != null,
         'Either title or titleWidget must be provided.',
       );

  /// Header key.
  final Key? headerKey;

  /// Toggle-glyph key.
  final Key? toggleKey;

  /// Expanded-body key.
  final Key? bodyKey;

  /// Optional title copy.
  final String? title;

  /// Optional title replacement.
  final Widget? titleWidget;

  /// Optional always-visible summary.
  final Widget? summaryWidget;

  /// Optional leading widget.
  final Widget? leading;

  /// Whether the body is expanded.
  final bool expanded;

  /// Whether activation is available.
  final bool canExpand;

  /// Outer margin.
  final EdgeInsetsGeometry margin;

  /// Inner inset.
  final EdgeInsetsGeometry padding;

  /// Optional summary inset.
  final EdgeInsetsGeometry? summaryPadding;

  /// Optional body inset.
  final EdgeInsetsGeometry? bodyPadding;

  /// Optional card background.
  final Color? backgroundColor;

  /// Optional card border.
  final Color? borderColor;

  /// Optional corner radius.
  final BorderRadiusGeometry? borderRadius;

  /// Optional overlay shadow.
  final List<BoxShadow>? boxShadow;

  /// Optional header hover color.
  final Color? hoverBackgroundColor;

  /// Optional expandable body.
  final Widget? body;

  /// Optional accessible header name.
  final String? semanticLabel;

  /// Whether to isolate body repaint.
  final bool wrapBodyWithRepaintBoundary;

  /// Header activation callback.
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final spacing = context.appSpacing;
    final colors = context.appColors;
    final radius = borderRadius ?? context.appRadii.allSmall;
    final duration = context.appMotion.resolveFor(
      context,
      context.appMotion.normal,
    );
    final header = PaneInteractiveSurface(
      key: headerKey,
      onPressed: canExpand ? onToggle : null,
      button: canExpand,
      semanticLabel: semanticLabel,
      hoverBackgroundColor:
          hoverBackgroundColor ?? colors.border.withValues(alpha: 0.12),
      borderRadius: radius,
      child: Row(
        children: <Widget>[
          SizedBox(
            key: toggleKey,
            width: 16,
            height: 20,
            child: AnimatedRotation(
              turns: expanded ? 0.25 : 0,
              duration: duration,
              curve: context.appMotion.defaultCurve,
              child: Icon(
                Icons.chevron_right,
                size: 14,
                color: canExpand ? colors.textSecondary : colors.textTertiary,
              ),
            ),
          ),
          SizedBox(width: spacing.xxs),
          if (leading case final leading?) ...<Widget>[
            leading,
            SizedBox(width: spacing.s6),
          ],
          Expanded(
            child:
                titleWidget ??
                Text(
                  title ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.appTypography.bodyMedium,
                ),
          ),
        ],
      ),
    );
    Widget child = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        header,
        if (summaryWidget case final summary?)
          Padding(
            padding: summaryPadding ?? EdgeInsets.only(top: spacing.xs),
            child: summary,
          ),
        AnimatedSize(
          duration: context.appMotion.resolveFor(
            context,
            context.appMotion.slow,
          ),
          curve: context.appMotion.popupCurve,
          alignment: Alignment.topCenter,
          child: expanded && body != null
              ? Padding(
                  key: bodyKey,
                  padding: bodyPadding ?? EdgeInsets.only(top: spacing.xs),
                  child: wrapBodyWithRepaintBoundary
                      ? RepaintBoundary(child: body)
                      : body,
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
    if (padding != EdgeInsets.zero) {
      child = Padding(padding: padding, child: child);
    }
    if (backgroundColor != null || borderColor != null || boxShadow != null) {
      child = PanelCard(
        color: backgroundColor,
        showBorder: borderColor != null,
        borderColor: borderColor,
        borderRadius: radius,
        boxShadow: boxShadow,
        child: child,
      );
    }
    return Padding(padding: margin, child: child);
  }
}

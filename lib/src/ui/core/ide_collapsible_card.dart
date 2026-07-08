import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'ide_colors.dart';
import 'ide_motion.dart';
import 'ide_spacing.dart';
import 'ide_text_styles.dart';
import 'pane_widgets.dart';

/// 统一 IDE 内可展开信息卡片的标题、摘要与展开动画。
class IdeCollapsibleCard extends StatelessWidget {
  const IdeCollapsibleCard({
    required this.expanded,
    required this.onToggle,
    super.key,
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
    this.summaryPadding = const EdgeInsets.only(top: IdeSpacing.space8),
    this.bodyPadding = const EdgeInsets.only(top: IdeSpacing.space8),
    this.backgroundColor,
    this.borderColor,
    this.borderRadius,
    this.boxShadow,
    this.hoverBackgroundColor,
    this.body,
    this.semanticLabel,
    this.wrapBodyWithRepaintBoundary = true,
  }) : assert(title != null || titleWidget != null);

  final Key? headerKey;
  final Key? toggleKey;
  final Key? bodyKey;
  final String? title;
  final Widget? titleWidget;
  final Widget? summaryWidget;
  final Widget? leading;
  final bool expanded;
  final bool canExpand;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry summaryPadding;
  final EdgeInsetsGeometry bodyPadding;
  final Color? backgroundColor;
  final Color? borderColor;
  final BorderRadiusGeometry? borderRadius;
  final List<BoxShadow>? boxShadow;
  final Color? hoverBackgroundColor;
  final Widget? body;
  final String? semanticLabel;
  final bool wrapBodyWithRepaintBoundary;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final radius =
        borderRadius ?? const BorderRadius.all(Radius.circular(idePanelRadius));
    final header = PaneInteractiveSurface(
      key: headerKey,
      onPressed: canExpand ? onToggle : null,
      button: canExpand,
      semanticLabel: semanticLabel,
      hoverBackgroundColor:
          hoverBackgroundColor ?? colors.border.withValues(alpha: 0.12),
      borderRadius: radius,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: IdeSpacing.space8),
          ],
          Expanded(
            child:
                titleWidget ??
                Text(
                  title!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.textSecondary.withValues(alpha: 0.9),
                  ),
                ),
          ),
          const SizedBox(width: IdeSpacing.space8),
          SizedBox(
            key: toggleKey,
            width: 20,
            height: 20,
            child: Icon(
              expanded
                  ? Icons.keyboard_arrow_down_rounded
                  : Icons.chevron_right_rounded,
              size: 16,
              color: canExpand
                  ? colors.textSecondary.withValues(alpha: 0.55)
                  : colors.textSecondary.withValues(alpha: 0.25),
            ),
          ),
        ],
      ),
    );

    Widget child = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        header,
        if (summaryWidget != null)
          Padding(padding: summaryPadding, child: summaryWidget!),
        AnimatedSize(
          duration: IdeMotion.durationSlow,
          curve: IdeMotion.curvePopup,
          alignment: Alignment.topCenter,
          child: expanded && body != null
              ? Padding(
                  key: bodyKey,
                  padding: bodyPadding,
                  child: wrapBodyWithRepaintBoundary
                      ? RepaintBoundary(child: body!)
                      : body!,
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

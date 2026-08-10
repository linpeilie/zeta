import 'package:flutter/material.dart';

import 'ide_colors.dart';
import 'ide_effects.dart';
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
    final radius = borderRadius ?? IdeRadius.allSmall;
    final header = PaneInteractiveSurface(
      key: headerKey,
      onPressed: canExpand ? onToggle : null,
      button: canExpand,
      semanticLabel: semanticLabel,
      hoverBackgroundColor:
          hoverBackgroundColor ?? colors.border.withValues(alpha: 0.12),
      borderRadius: radius,
      // 箭头放在**行首**而不是行尾。右对齐的箭头会被 Expanded 的标题推到
      // 画布最右侧，标题和箭头之间几百像素的空白在视觉上读成一条横规——
      // 这正是「每一行都带 > 箭头和长长的横线」的来源。把箭头、图标、标题
      // 挤成一个紧凑簇，一串操作才会读成「过程记录」而不是平铺列表。
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            key: toggleKey,
            width: 16,
            height: 20,
            child: AnimatedRotation(
              turns: expanded ? 0.25 : 0.0,
              duration: IdeMotion.durationNormal,
              curve: IdeMotion.curveDefault,
              child: Icon(
                Icons.chevron_right_rounded,
                size: 14,
                color: canExpand
                    ? colors.textSecondary.withValues(alpha: 0.55)
                    : colors.textSecondary.withValues(alpha: 0.25),
              ),
            ),
          ),
          const SizedBox(width: IdeSpacing.space4),
          if (leading != null) ...[
            leading!,
            const SizedBox(width: IdeSpacing.space6),
          ],
          Expanded(
            child:
                titleWidget ??
                Text(
                  title!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w500,
                    color: colors.textSecondary.withValues(alpha: 0.68),
                  ),
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

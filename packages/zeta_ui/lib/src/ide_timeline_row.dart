import 'package:flutter/material.dart';

import 'ide_colors.dart';
import 'ide_effects.dart';
import 'ide_icon_box.dart';
import 'ide_spacing.dart';
import 'ide_text_styles.dart';
import 'pane_widgets.dart';

/// 时间线中的紧凑信息行。
///
/// 统一提供 leading 图标盒、单行省略标题和尾部 meta 布局。行高完全由文字与
/// 图标盒自然撑开；它不使用列表行的固定高度，适合嵌入折叠卡标题或操作组正文。
class IdeTimelineRow extends StatelessWidget {
  const IdeTimelineRow({
    required this.title,
    super.key,
    this.leading,
    this.prefix,
    this.trailing,
    this.onTap,
    this.semanticLabel,
    this.titleStyle,
  });

  /// 单行标题；组件统一处理省略。
  final String title;

  /// 行首图标或等价的紧凑视觉标记；内部统一套 [IdeIconBox]。
  final Widget? leading;

  /// 标题前的短文本，例如文件动作类型。
  ///
  /// 它不进入图标盒，允许与 [title] 使用不同排版，同时仍共享同一行骨架。
  final Widget? prefix;

  /// 行尾 meta，例如耗时、状态或 diff 统计。
  final Widget? trailing;

  /// 可选点击动作；为空时只渲染信息行，不额外引入交互表面。
  final VoidCallback? onTap;

  /// 覆盖组合内容的无障碍名称。
  final String? semanticLabel;

  /// 覆盖默认标题排版；用于代码路径等确有不同语义的标题。
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final styles = IdeTextStyles.of(context);
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        if (leading case final Widget leadingWidget) ...<Widget>[
          IdeIconBox.custom(child: leadingWidget),
          const SizedBox(width: IdeSpacing.space6),
        ],
        if (prefix case final Widget prefixWidget) ...<Widget>[
          prefixWidget,
          const SizedBox(width: IdeSpacing.space6),
        ],
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                titleStyle ??
                styles.bodyMedium.copyWith(
                  color: colors.textSecondary.withValues(alpha: 0.88),
                ),
          ),
        ),
        if (trailing case final Widget trailingWidget) ...<Widget>[
          const SizedBox(width: IdeSpacing.space8),
          DefaultTextStyle.merge(
            style: styles.caption.copyWith(
              color: colors.textTertiary,
              fontWeight: FontWeight.w500,
            ),
            child: trailingWidget,
          ),
        ],
      ],
    );
    final action = onTap;
    if (action != null) {
      return PaneInteractiveSurface(
        onPressed: action,
        semanticLabel: semanticLabel ?? title,
        expandToConstraints: false,
        padding: EdgeInsets.zero,
        borderRadius: IdeRadius.allSmall,
        child: semanticLabel == null
            ? content
            : ExcludeSemantics(child: content),
      );
    }
    final label = semanticLabel;
    if (label != null) {
      return Semantics(label: label, excludeSemantics: true, child: content);
    }
    return content;
  }
}

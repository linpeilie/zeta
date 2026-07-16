import 'package:flutter/material.dart';

import '../ide_colors.dart';
import '../ide_metrics.dart';
import '../ide_spacing.dart';
import '../ide_text_styles.dart';
import '../pane_widgets.dart';

/// 统一列表行的密度、文本省略和交互状态。
class IdeListRow extends StatelessWidget {
  const IdeListRow({
    required this.title,
    super.key,
    this.subtitle,
    this.leading,
    this.trailing,
    this.selected = false,
    this.enabled = true,
    this.onPressed,
    this.showDivider = true,
    this.semanticLabel,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final bool selected;
  final bool enabled;
  final VoidCallback? onPressed;
  final bool showDivider;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final styles = IdeTextStyles.of(context);
    final foreground = !enabled
        ? colors.textTertiary
        : selected
        ? colors.textPrimary
        : colors.textSecondary;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: showDivider
            ? Border(bottom: BorderSide(color: colors.borderSubtle))
            : null,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: IdeMetrics.listRowHeight),
        child: PaneInteractiveSurface(
          onPressed: onPressed,
          selected: selected,
          enabled: enabled,
          semanticLabel: semanticLabel ?? title,
          padding: IdeSpacing.rowPadding,
          borderRadius: BorderRadius.zero,
          child: Row(
            children: [
              if (leading case final Widget leadingWidget) ...[
                IconTheme(
                  data: IconThemeData(size: 15, color: foreground),
                  child: leadingWidget,
                ),
                const SizedBox(width: IdeSpacing.space8),
              ],
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: styles.rowTitle.copyWith(
                        color: enabled
                            ? colors.textPrimary
                            : colors.textTertiary,
                      ),
                    ),
                    if (subtitle case final String subtitleText)
                      Text(
                        subtitleText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: styles.meta.copyWith(color: foreground),
                      ),
                  ],
                ),
              ),
              if (trailing case final Widget trailingWidget) ...[
                const SizedBox(width: IdeSpacing.space8),
                IconTheme.merge(
                  data: IconThemeData(
                    color: enabled ? null : colors.textTertiary,
                  ),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(
                      color: enabled ? null : colors.textTertiary,
                    ),
                    child: trailingWidget,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

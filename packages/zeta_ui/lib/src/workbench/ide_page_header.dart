import 'package:flutter/widgets.dart';

import '../ide_colors.dart';
import '../ide_metrics.dart';
import '../ide_spacing.dart';
import '../ide_text_styles.dart';

/// 统一页面标题、说明和操作区的紧凑页头。
class IdePageHeader extends StatelessWidget {
  const IdePageHeader({
    required this.title,
    super.key,
    this.subtitle,
    this.leading,
    this.actions = const <Widget>[],
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final styles = IdeTextStyles.of(context);
    return SizedBox(
      height: IdeMetrics.pageHeaderHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.borderSubtle)),
        ),
        child: Padding(
          padding: IdeSpacing.horizontal12,
          child: Row(
            children: [
              if (leading case final Widget leadingWidget) ...[
                leadingWidget,
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
                      style: styles.pageTitle,
                    ),
                    if (subtitle case final String subtitleText)
                      Text(
                        subtitleText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: styles.meta.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              if (actions.isNotEmpty)
                Flexible(
                  child: SingleChildScrollView(
                    key: const ValueKey('ide-page-header-actions'),
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final action in actions) ...[
                          const SizedBox(width: IdeSpacing.space4),
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

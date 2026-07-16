import 'package:flutter/material.dart';

import '../ide_colors.dart';
import '../ide_metrics.dart';
import '../ide_spacing.dart';
import '../ide_text_styles.dart';
import '../pane_widgets.dart';

/// 紧凑指标条中的单个语义指标。
@immutable
class CompactMetricItem {
  const CompactMetricItem({
    required this.label,
    required this.value,
    this.detail,
    this.icon,
    this.tone,
    this.onPressed,
    this.semanticLabel,
  });

  final String label;
  final String value;
  final String? detail;
  final IconData? icon;
  final Color? tone;
  final VoidCallback? onPressed;
  final String? semanticLabel;
}

/// 宽屏均分、较窄窗口横向滚动的紧凑指标条。
class CompactMetricBar extends StatelessWidget {
  const CompactMetricBar({required this.items, super.key});

  final List<CompactMetricItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    final colors = IdeColors.of(context);
    final styles = IdeTextStyles.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final evenlyDistributed =
            constraints.hasBoundedWidth &&
            constraints.maxWidth >= IdeMetrics.metricBarEqualWidthBreakpoint;
        final dividerWidth = (items.length - 1).toDouble();
        final itemWidth = evenlyDistributed
            ? (constraints.maxWidth - dividerWidth) / items.length
            : IdeMetrics.metricBarItemWidth;
        return SingleChildScrollView(
          key: const ValueKey('compact-metric-bar-scroll-view'),
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var index = 0; index < items.length; index++) ...[
                SizedBox(
                  key: ValueKey('compact-metric-item-$index'),
                  width: itemWidth,
                  child: PaneInteractiveSurface(
                    onPressed: items[index].onPressed,
                    semanticLabel:
                        items[index].semanticLabel ?? items[index].label,
                    padding: IdeSpacing.all12,
                    borderRadius: BorderRadius.zero,
                    child: _MetricContent(
                      item: items[index],
                      styles: styles,
                      colors: colors,
                    ),
                  ),
                ),
                if (index < items.length - 1)
                  SizedBox(
                    height: IdeMetrics.metricBarDividerHeight,
                    child: VerticalDivider(
                      width: 1,
                      color: colors.borderSubtle,
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _MetricContent extends StatelessWidget {
  const _MetricContent({
    required this.item,
    required this.styles,
    required this.colors,
  });

  final CompactMetricItem item;
  final IdeTextStyles styles;
  final IdeColors colors;

  @override
  Widget build(BuildContext context) {
    final tone = item.tone ?? colors.accent;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (item.icon case final IconData icon) ...[
              Icon(icon, size: 14, color: tone),
              const SizedBox(width: IdeSpacing.space6),
            ],
            Expanded(
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: styles.toolbarLabel,
              ),
            ),
          ],
        ),
        const SizedBox(height: IdeSpacing.space4),
        Text(
          item.value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: styles.metricValue.copyWith(color: tone),
        ),
        if (item.detail case final String detail) ...[
          const SizedBox(height: IdeSpacing.space2),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: styles.meta,
          ),
        ],
      ],
    );
  }
}
